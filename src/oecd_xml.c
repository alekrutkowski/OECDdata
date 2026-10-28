/* Bulk, read-only SDMX XML extraction. Copyright (c) 2026 Alek Rutkowski.
 * Package-owned code is MIT licensed. libxml2 retains its own MIT license.
 * No xml2 package pointer representation or other private package ABI is used.
 */
#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Utils.h>
#include <libxml/parser.h>
#include <libxml/tree.h>
#include <libxml/xpath.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#include <wchar.h>
#endif

#define N_INDEX 5
static const char *index_names[N_INDEX] = {
    "Dataflow", "Codelist", "ConceptScheme", "DataStructure", "ContentConstraint"
};

typedef struct {
    xmlDocPtr doc;
    xmlNodePtr *index[N_INDEX];
    R_xlen_t count[N_INDEX];
} Document;

/* Every temporary allocation owned by libxml2 is attached to a call context.
 * R_UnwindProtect frees these on ordinary return, error and user interrupt.
 */
typedef struct {
    SEXP args[5];
    int operation;
    xmlChar *text;
    xmlXPathContextPtr xpath;
    xmlXPathObjectPtr result;
    xmlParserCtxtPtr parser;
    xmlDocPtr pending_doc;
    Document *pending_owner;
    FILE *file;
} Call;

enum {
    OP_READ, OP_FIND, OP_XPATH, OP_ATTR, OP_TEXT, OP_NAME,
    OP_LOCALIZED, OP_REF, OP_ANNOTATIONS, OP_CODES, OP_CATALOGUE
};

static SEXP document_tag(void) { return Rf_install("OECDdata_xml_document"); }
static SEXP node_tag(void) { return Rf_install("OECDdata_xml_node"); }

static void free_document(Document *owner) {
    if (owner == NULL) return;
    for (int i = 0; i < N_INDEX; ++i) free(owner->index[i]);
    if (owner->doc != NULL) xmlFreeDoc(owner->doc);
    free(owner);
}

static void document_finalizer(SEXP pointer) {
    if (TYPEOF(pointer) != EXTPTRSXP ||
        R_ExternalPtrTag(pointer) != document_tag()) return;
    free_document((Document *) R_ExternalPtrAddr(pointer));
    R_ClearExternalPtr(pointer);
}

static void cleanup_call(void *data, Rboolean jump) {
    Call *call = (Call *) data;
    (void) jump;
    if (call->text != NULL) xmlFree(call->text);
    if (call->result != NULL) xmlXPathFreeObject(call->result);
    if (call->xpath != NULL) xmlXPathFreeContext(call->xpath);
    if (call->parser != NULL) xmlFreeParserCtxt(call->parser);
    if (call->file != NULL) fclose(call->file);
    if (call->pending_doc != NULL) xmlFreeDoc(call->pending_doc);
    free_document(call->pending_owner);
}

static const char *string_arg(SEXP value, const char *name) {
    if (TYPEOF(value) != STRSXP || XLENGTH(value) != 1 ||
        STRING_ELT(value, 0) == NA_STRING)
        Rf_error("`%s` must be one non-missing string.", name);
    return Rf_translateCharUTF8(STRING_ELT(value, 0));
}

static int logical_arg(SEXP value, const char *name) {
    if (TYPEOF(value) != LGLSXP || XLENGTH(value) != 1 ||
        LOGICAL(value)[0] == NA_LOGICAL)
        Rf_error("`%s` must be TRUE or FALSE.", name);
    return LOGICAL(value)[0];
}

static SEXP owner_pointer(SEXP handle) {
    if (TYPEOF(handle) != EXTPTRSXP)
        Rf_error("Expected a native OECD XML document or node.");
    SEXP tag = R_ExternalPtrTag(handle);
    SEXP owner = tag == document_tag() ? handle :
        tag == node_tag() ? R_ExternalPtrProtected(handle) : R_NilValue;
    if (TYPEOF(owner) != EXTPTRSXP ||
        R_ExternalPtrTag(owner) != document_tag() ||
        R_ExternalPtrAddr(owner) == NULL)
        Rf_error("Invalid native OECD XML handle (documents cannot be serialized).");
    return owner;
}

static Document *document_from(SEXP handle) {
    return (Document *) R_ExternalPtrAddr(owner_pointer(handle));
}

static xmlNodePtr node_from(SEXP handle) {
    if (handle == R_NilValue) return NULL;
    Document *owner = document_from(handle);
    if (R_ExternalPtrTag(handle) == document_tag())
        return xmlDocGetRootElement(owner->doc);
    xmlNodePtr node = (xmlNodePtr) R_ExternalPtrAddr(handle);
    if (node == NULL || node->doc != owner->doc)
        Rf_error("Invalid native OECD XML node.");
    return node;
}

static SEXP node_handle(xmlNodePtr node, SEXP owner) {
    if (node == NULL) return R_NilValue;
    SEXP handle = PROTECT(R_MakeExternalPtr(node, node_tag(), owner));
    SEXP klass = PROTECT(Rf_mkString("OECDxml_node"));
    Rf_setAttrib(handle, R_ClassSymbol, klass);
    UNPROTECT(2);
    return handle;
}

static int named(xmlNodePtr node, const char *name) {
    return node != NULL && node->type == XML_ELEMENT_NODE &&
        xmlStrEqual(node->name, (const xmlChar *) name);
}

/* Iterative depth-first traversal avoids C stack growth on nested content. */
static xmlNodePtr next_descendant(xmlNodePtr node, xmlNodePtr root) {
    if (node->children != NULL) return node->children;
    while (node != root) {
        if (node->next != NULL) return node->next;
        node = node->parent;
    }
    return NULL;
}

static xmlNodePtr first_child(xmlNodePtr node, const char *name) {
    if (node == NULL) return NULL;
    for (xmlNodePtr child = node->children; child != NULL; child = child->next)
        if (named(child, name)) return child;
    return NULL;
}

static xmlNodePtr first_descendant(xmlNodePtr node, const char *name) {
    if (node == NULL) return NULL;
    size_t visited = 0;
    for (xmlNodePtr cur = node->children; cur != NULL;
         cur = next_descendant(cur, node)) {
        if (named(cur, name)) return cur;
        if ((++visited & 16383U) == 0) R_CheckUserInterrupt();
    }
    return NULL;
}

static int space_byte(unsigned char c) {
    return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

static SEXP utf8_chars(const xmlChar *text, int trim) {
    const char *start = text == NULL ? "" : (const char *) text;
    size_t n = strlen(start);
    if (trim) {
        while (n > 0 && space_byte((unsigned char) *start)) { ++start; --n; }
        while (n > 0 && space_byte((unsigned char) start[n - 1])) --n;
    }
    if (n > INT_MAX) Rf_error("XML string exceeds R's string length limit.");
    return Rf_mkCharLenCE(start, (int) n, CE_UTF8);
}

static void clear_text(Call *call) {
    if (call->text != NULL) xmlFree(call->text);
    call->text = NULL;
}

/* Attribute names are local names, including xml:lang. */
static xmlAttrPtr find_attribute(xmlNodePtr node, const char *name) {
    if (node == NULL || node->type != XML_ELEMENT_NODE) return NULL;
    for (xmlAttrPtr a = node->properties; a != NULL; a = a->next)
        if (xmlStrEqual(a->name, (const xmlChar *) name)) return a;
    return NULL;
}

static const xmlChar *attribute_value(Call *call, xmlNodePtr node,
                                      const char *name) {
    clear_text(call);
    xmlAttrPtr a = find_attribute(node, name);
    if (a == NULL) return NULL;
    if (a->children == NULL) return (const xmlChar *) "";
    if (a->children->type == XML_TEXT_NODE && a->children->next == NULL)
        return a->children->content;
    call->text = xmlNodeListGetString(node->doc, a->children, 1);
    if (call->text == NULL) Rf_error("Cannot allocate XML attribute text.");
    return call->text;
}

static SEXP attribute_chars(Call *call, xmlNodePtr node, const char *name,
                            SEXP fallback) {
    const xmlChar *value = attribute_value(call, node, name);
    SEXP answer = value == NULL ? fallback : utf8_chars(value, 0);
    clear_text(call);
    return answer;
}

static int attribute_equal(Call *call, xmlNodePtr node, const char *name,
                           const char *value) {
    const xmlChar *actual = attribute_value(call, node, name);
    int answer = actual != NULL && xmlStrEqual(actual, (const xmlChar *) value);
    clear_text(call);
    return answer;
}

static int attribute_nonempty(Call *call, xmlNodePtr node, const char *name) {
    const xmlChar *value = attribute_value(call, node, name);
    int answer = value != NULL && value[0] != '\0';
    clear_text(call);
    return answer;
}

static SEXP text_chars(Call *call, xmlNodePtr node, SEXP fallback) {
    if (node == NULL) return fallback;
    clear_text(call);
    /* The common SDMX label is one text/CDATA child. Borrow its bytes. */
    if (node->children != NULL && node->children->next == NULL &&
        (node->children->type == XML_TEXT_NODE ||
         node->children->type == XML_CDATA_SECTION_NODE))
        return utf8_chars(node->children->content, 1);
    call->text = xmlNodeGetContent(node);
    if (call->text == NULL) Rf_error("Cannot allocate XML node text.");
    SEXP answer = utf8_chars(call->text, 1);
    clear_text(call);
    return answer;
}

static xmlNodePtr localized_node(Call *call, xmlNodePtr node, const char *name,
                                const char *language) {
    if (node == NULL) return NULL;
    xmlNodePtr first = NULL, english = NULL;
    for (xmlNodePtr child = node->children; child != NULL; child = child->next) {
        if (!named(child, name)) continue;
        if (first == NULL) first = child;
        if (attribute_equal(call, child, "lang", language)) return child;
        if (english == NULL && attribute_equal(call, child, "lang", "en"))
            english = child;
    }
    return english == NULL ? first : english;
}

static SEXP localized_chars(Call *call, xmlNodePtr node, const char *name,
                            const char *language, SEXP fallback) {
    return text_chars(call, localized_node(call, node, name, language), fallback);
}

static SEXP column_list(R_xlen_t rows, int columns, const char **names) {
    SEXP answer = PROTECT(Rf_allocVector(VECSXP, columns));
    SEXP labels = PROTECT(Rf_allocVector(STRSXP, columns));
    for (int i = 0; i < columns; ++i) {
        SET_VECTOR_ELT(answer, i, Rf_allocVector(STRSXP, rows));
        SET_STRING_ELT(labels, i, Rf_mkChar(names[i]));
    }
    Rf_setAttrib(answer, R_NamesSymbol, labels);
    UNPROTECT(2);
    return answer;
}

static int index_number(const char *name) {
    for (int i = 0; i < N_INDEX; ++i)
        if (strcmp(name, index_names[i]) == 0) return i;
    return -1;
}

static void build_index(Document *owner) {
    xmlNodePtr root = xmlDocGetRootElement(owner->doc);
    size_t visited = 0;
    for (xmlNodePtr cur = root->children; cur != NULL;
         cur = next_descendant(cur, root)) {
        if (cur->type == XML_ELEMENT_NODE) {
            int i = index_number((const char *) cur->name);
            if (i >= 0) {
                if (owner->count[i] == R_XLEN_T_MAX)
                    Rf_error("Too many XML structure definitions.");
                ++owner->count[i];
            }
        }
        if ((++visited & 16383U) == 0) R_CheckUserInterrupt();
    }
    for (int i = 0; i < N_INDEX; ++i) {
        if (owner->count[i] == 0) continue;
        if ((uint64_t) owner->count[i] > SIZE_MAX / sizeof(xmlNodePtr))
            Rf_error("XML index exceeds addressable memory.");
        owner->index[i] = (xmlNodePtr *) malloc((size_t) owner->count[i] * sizeof(xmlNodePtr));
        if (owner->index[i] == NULL) Rf_error("Cannot allocate the XML structure index.");
    }
    R_xlen_t used[N_INDEX] = {0};
    for (xmlNodePtr cur = root->children; cur != NULL;
         cur = next_descendant(cur, root)) {
        if (cur->type == XML_ELEMENT_NODE) {
            int i = index_number((const char *) cur->name);
            if (i >= 0) owner->index[i][used[i]++] = cur;
        }
        if ((++visited & 16383U) == 0) R_CheckUserInterrupt();
    }
}

static xmlParserInputPtr deny_entity(void *context, const xmlChar *public_id,
                                      const xmlChar *system_id) {
    (void) context; (void) public_id; (void) system_id;
    return NULL;
}

static int read_input(void *context, char *buffer, int length) {
    Call *call = (Call *) context;
    size_t n = fread(buffer, 1, (size_t) length, call->file);
    return n == 0 && ferror(call->file) ? -1 : (int) n;
}

static int close_input(void *context) {
    Call *call = (Call *) context;
    if (call->file == NULL) return 0;
    int result = fclose(call->file);
    call->file = NULL;
    return result;
}

static SEXP read_document(Call *call) {
    SEXP source = call->args[0];
    int is_file = logical_arg(call->args[1], "is_file");
    const char *text = NULL;
    int length = 0;
    if (TYPEOF(source) == RAWSXP && !is_file) {
        if (XLENGTH(source) > INT_MAX) Rf_error("XML input exceeds libxml2's memory input limit.");
        text = (const char *) RAW(source);
        length = (int) XLENGTH(source);
    } else {
        text = string_arg(source, "source");
        size_t n = strlen(text);
        if (n > INT_MAX) Rf_error("XML input exceeds libxml2's memory input limit.");
        length = (int) n;
    }
    R_CheckUserInterrupt();
    call->parser = xmlNewParserCtxt();
    if (call->parser == NULL) Rf_error("Cannot allocate an XML parser.");
    /* Do not change libxml2 global loaders or error handlers used by xml2. */
    call->parser->sax->resolveEntity = deny_entity;
    int options = XML_PARSE_NONET | XML_PARSE_NOBLANKS |
        XML_PARSE_NOERROR | XML_PARSE_NOWARNING;
#if LIBXML_VERSION >= 21300
    options |= XML_PARSE_NO_XXE;
#endif
    if (is_file) {
        const char *path = Rf_translateChar(STRING_ELT(source, 0));
#ifdef _WIN32
        /* R stores UTF-8 paths on modern Windows; fopen still depends on the
         * process code page. Use the wide API to support all file names. */
        int width = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, NULL, 0);
        if (width == 0) Rf_error("Cannot convert the XML file name to UTF-16.");
        wchar_t *wide = (wchar_t *) R_alloc((size_t) width, sizeof(wchar_t));
        if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, wide, width) == 0)
            Rf_error("Cannot convert the XML file name to UTF-16.");
        call->file = _wfopen(wide, L"rb");
#else
        call->file = fopen(path, "rb");
#endif
        if (call->file == NULL) Rf_error("Cannot open XML file: %s", path);
        /* IO callbacks permit only this local file, never URL input loaders. */
        call->pending_doc = xmlCtxtReadIO(call->parser, read_input, close_input,
            call, NULL, NULL, options);
    } else {
        call->pending_doc = xmlCtxtReadMemory(call->parser, text, length,
            NULL, NULL, options);
    }
    if (call->pending_doc == NULL) {
        const xmlError *error = xmlCtxtGetLastError(call->parser);
        Rf_error("Invalid XML: %s", error != NULL && error->message != NULL ?
            error->message : "the document could not be parsed.");
    }
    if (call->pending_doc->intSubset != NULL || call->pending_doc->extSubset != NULL)
        Rf_error("DTD declarations are not supported in OECD structure XML.");
    if (xmlDocGetRootElement(call->pending_doc) == NULL)
        Rf_error("XML document has no root element.");
    xmlFreeParserCtxt(call->parser);
    call->parser = NULL;
    call->pending_owner = (Document *) calloc(1, sizeof(Document));
    if (call->pending_owner == NULL) Rf_error("Cannot allocate an XML document owner.");
    call->pending_owner->doc = call->pending_doc;
    call->pending_doc = NULL;
    build_index(call->pending_owner);
    SEXP answer = PROTECT(R_MakeExternalPtr(call->pending_owner, document_tag(), R_NilValue));
    R_RegisterCFinalizerEx(answer, document_finalizer, TRUE);
    call->pending_owner = NULL;
    SEXP klass = PROTECT(Rf_mkString("OECDxml_document"));
    Rf_setAttrib(answer, R_ClassSymbol, klass);
    UNPROTECT(2);
    return answer;
}

static SEXP find_nodes(Call *call) {
    SEXP handle = call->args[0];
    xmlNodePtr root = node_from(handle);
    const char *name = string_arg(call->args[1], "name");
    int children_only = logical_arg(call->args[2], "children_only");
    if (root == NULL) return Rf_allocVector(VECSXP, 0);
    SEXP owner = owner_pointer(handle);
    Document *document = (Document *) R_ExternalPtrAddr(owner);
    int index = !children_only && R_ExternalPtrTag(handle) == document_tag() ?
        index_number(name) : -1;
    R_xlen_t n = 0;
    if (index >= 0) n = document->count[index];
    else {
        size_t visited = 0;
        for (xmlNodePtr cur = root->children; cur != NULL;
             cur = children_only ? cur->next : next_descendant(cur, root)) {
            if (named(cur, name)) ++n;
            if ((++visited & 16383U) == 0) R_CheckUserInterrupt();
        }
    }
    SEXP answer = PROTECT(Rf_allocVector(VECSXP, n));
    if (index >= 0) {
        for (R_xlen_t i = 0; i < n; ++i) {
            SET_VECTOR_ELT(answer, i, node_handle(document->index[index][i], owner));
            if ((i & 4095) == 0) R_CheckUserInterrupt();
        }
    } else {
        R_xlen_t i = 0;
        for (xmlNodePtr cur = root->children; cur != NULL;
             cur = children_only ? cur->next : next_descendant(cur, root))
            if (named(cur, name)) {
                SET_VECTOR_ELT(answer, i++, node_handle(cur, owner));
                if ((i & 4095) == 0) R_CheckUserInterrupt();
            }
    }
    UNPROTECT(1);
    return answer;
}

static SEXP xpath_nodes(Call *call) {
    SEXP handle = call->args[0];
    xmlNodePtr node = node_from(handle);
    const char *path = string_arg(call->args[1], "path");
    int first = logical_arg(call->args[2], "first");
    if (node == NULL) return first ? R_NilValue : Rf_allocVector(VECSXP, 0);
    SEXP owner = owner_pointer(handle);
    call->xpath = xmlXPathNewContext(node->doc);
    if (call->xpath == NULL) Rf_error("Cannot allocate an XPath context.");
    call->xpath->node = node;
    call->result = xmlXPathEvalExpression((const xmlChar *) path, call->xpath);
    if (call->result == NULL || call->result->type != XPATH_NODESET)
        Rf_error("Invalid node-selection XPath expression.");
    xmlNodeSetPtr nodes = call->result->nodesetval;
    int n = nodes == NULL ? 0 : nodes->nodeNr;
    if (first) {
        if (n == 0) return R_NilValue;
        if (nodes->nodeTab[0]->type != XML_ELEMENT_NODE)
            Rf_error("Only element nodes are supported by the native XML XPath interface.");
        return node_handle(nodes->nodeTab[0], owner);
    }
    SEXP answer = PROTECT(Rf_allocVector(VECSXP, n));
    for (int i = 0; i < n; ++i) {
        if (nodes->nodeTab[i]->type != XML_ELEMENT_NODE)
            Rf_error("Only element nodes are supported by the native XML XPath interface.");
        SET_VECTOR_ELT(answer, i, node_handle(nodes->nodeTab[i], owner));
        if ((i & 4095) == 0) R_CheckUserInterrupt();
    }
    UNPROTECT(1);
    return answer;
}

static SEXP node_values(Call *call, int attributes) {
    SEXP nodes = call->args[0];
    int list = TYPEOF(nodes) == VECSXP;
    R_xlen_t n = list ? XLENGTH(nodes) : 1;
    const char *name = attributes ? string_arg(call->args[1], "name") : NULL;
    SEXP fallback_arg = call->args[attributes ? 2 : 1];
    string_arg(fallback_arg, "default");
    SEXP fallback = STRING_ELT(fallback_arg, 0);
    SEXP answer = PROTECT(Rf_allocVector(STRSXP, n));
    for (R_xlen_t i = 0; i < n; ++i) {
        xmlNodePtr node = node_from(list ? VECTOR_ELT(nodes, i) : nodes);
        SET_STRING_ELT(answer, i, attributes ? attribute_chars(call, node, name, fallback) :
            text_chars(call, node, fallback));
        if ((i & 8191) == 0) R_CheckUserInterrupt();
    }
    UNPROTECT(1);
    return answer;
}

static SEXP localized_value(Call *call) {
    xmlNodePtr node = node_from(call->args[0]);
    const char *name = string_arg(call->args[1], "name");
    const char *language = string_arg(call->args[2], "language");
    string_arg(call->args[3], "fallback");
    SEXP answer = PROTECT(Rf_allocVector(STRSXP, 1));
    SET_STRING_ELT(answer, 0, localized_chars(call, node, name, language,
        STRING_ELT(call->args[3], 0)));
    UNPROTECT(1);
    return answer;
}

static SEXP reference_value(Call *call) {
    xmlNodePtr node = first_descendant(node_from(call->args[0]), "Ref");
    static const char *names[] = {"agency", "id", "version", "parent", "parent_version"};
    static const char *attrs[] = {"agencyID", "id", "version", "maintainableParentID",
        "maintainableParentVersion"};
    SEXP answer = PROTECT(column_list(1, 5, names));
    for (int i = 0; i < 5; ++i)
        SET_STRING_ELT(VECTOR_ELT(answer, i), 0, attribute_chars(call, node, attrs[i], R_BlankString));
    UNPROTECT(1);
    return answer;
}

static SEXP annotation_value(Call *call, xmlNodePtr node, const char *language) {
    SEXP title = PROTECT(text_chars(call, first_child(node, "AnnotationTitle"), R_BlankString));
    if (LENGTH(title) != 0) {
        UNPROTECT(1);
        return title;
    }
    SEXP answer = localized_chars(call, node, "AnnotationText", language, R_BlankString);
    UNPROTECT(1);
    return answer;
}

static SEXP annotation_values(Call *call) {
    xmlNodePtr node = node_from(call->args[0]);
    const char *language = string_arg(call->args[1], "language");
    R_xlen_t n = 0;
    if (node != NULL)
        for (xmlNodePtr cur = node->children; cur != NULL; cur = next_descendant(cur, node))
            if (named(cur, "Annotation")) ++n;
    SEXP answer = PROTECT(Rf_allocVector(STRSXP, n));
    SEXP names = PROTECT(Rf_allocVector(STRSXP, n));
    R_xlen_t i = 0;
    if (node != NULL)
        for (xmlNodePtr cur = node->children; cur != NULL; cur = next_descendant(cur, node))
            if (named(cur, "Annotation")) {
                SET_STRING_ELT(names, i, text_chars(call, first_child(cur, "AnnotationType"), R_BlankString));
                SET_STRING_ELT(answer, i, annotation_value(call, cur, language));
                if ((++i & 4095) == 0) R_CheckUserInterrupt();
            }
    if (n != 0) Rf_setAttrib(answer, R_NamesSymbol, names);
    UNPROTECT(2);
    return answer;
}

static SEXP code_values(Call *call) {
    xmlNodePtr node = node_from(call->args[0]);
    const char *language = string_arg(call->args[1], "language");
    R_xlen_t n = 0;
    if (node != NULL)
        for (xmlNodePtr cur = node->children; cur != NULL; cur = cur->next)
            if (named(cur, "Code")) ++n;
    static const char *names[] = {"code", "label"};
    SEXP answer = PROTECT(column_list(n, 2, names));
    SEXP codes = VECTOR_ELT(answer, 0), labels = VECTOR_ELT(answer, 1);
    R_xlen_t i = 0;
    if (node != NULL)
        for (xmlNodePtr cur = node->children; cur != NULL; cur = cur->next)
            if (named(cur, "Code")) {
                SET_STRING_ELT(codes, i, attribute_chars(call, cur, "id", R_BlankString));
                SET_STRING_ELT(labels, i, localized_chars(call, cur, "Name", language, R_BlankString));
                if ((++i & 4095) == 0) R_CheckUserInterrupt();
            }
    UNPROTECT(1);
    return answer;
}

static void catalogue_annotations(Call *call, xmlNodePtr node, const char *language,
                                  SEXP answer, R_xlen_t row) {
    /* Match priority is by requested annotation type, then document order. */
    static const char *types[] = {"UPDATE_DATA", "LAST_UPDATE", "UPDATE_STRUCTURE",
        "OBS_PERIOD_OVERALL_OLDEST", "OBS_PERIOD_OVERALL_LATEST"};
    xmlNodePtr selected[5] = {NULL};
    for (xmlNodePtr cur = node->children; cur != NULL; cur = next_descendant(cur, node)) {
        if (!named(cur, "Annotation")) continue;
        SEXP type = PROTECT(text_chars(call, first_child(cur, "AnnotationType"), R_BlankString));
        for (int j = 0; j < 5; ++j)
            if (selected[j] == NULL && strcmp(CHAR(type), types[j]) == 0) selected[j] = cur;
        UNPROTECT(1);
    }
    xmlNodePtr picked[] = {selected[0] == NULL ? selected[1] : selected[0],
        selected[2], selected[3], selected[4]};
    for (int j = 0; j < 4; ++j)
        SET_STRING_ELT(VECTOR_ELT(answer, 5 + j), row, picked[j] == NULL ? NA_STRING :
            annotation_value(call, picked[j], language));
}

static SEXP catalogue_values(Call *call) {
    SEXP handle = call->args[0];
    xmlNodePtr root = node_from(handle);
    const char *language = string_arg(call->args[1], "language");
    static const char *names[] = {"Dataset name", "Agency", "Dataflow", "Version",
        "Description", "Last update of data", "Last table structure change", "Data start", "Data end"};
    if (root == NULL) return column_list(0, 9, names);
    Document *owner = document_from(handle);
    int indexed = R_ExternalPtrTag(handle) == document_tag();
    R_xlen_t n = 0;
    if (indexed) {
        for (R_xlen_t i = 0; i < owner->count[0]; ++i) {
            xmlNodePtr node = owner->index[0][i];
            if (attribute_nonempty(call, node, "agencyID") && attribute_nonempty(call, node, "id")) ++n;
        }
    } else {
        for (xmlNodePtr node = root->children; node != NULL; node = next_descendant(node, root))
            if (named(node, "Dataflow") && attribute_nonempty(call, node, "agencyID") &&
                attribute_nonempty(call, node, "id")) ++n;
    }
    SEXP answer = PROTECT(column_list(n, 9, names));
    R_xlen_t row = 0, pos = 0;
    xmlNodePtr cur = root->children;
    while (indexed ? pos < owner->count[0] : cur != NULL) {
        xmlNodePtr node;
        if (indexed) node = owner->index[0][pos++];
        else { node = cur; cur = next_descendant(cur, root); }
        if (!named(node, "Dataflow") || !attribute_nonempty(call, node, "agencyID") ||
            !attribute_nonempty(call, node, "id")) continue;
        SET_STRING_ELT(VECTOR_ELT(answer, 1), row, attribute_chars(call, node, "agencyID", R_BlankString));
        SET_STRING_ELT(VECTOR_ELT(answer, 2), row, attribute_chars(call, node, "id", R_BlankString));
        SET_STRING_ELT(VECTOR_ELT(answer, 3), row, attribute_chars(call, node, "version", R_BlankString));
        SET_STRING_ELT(VECTOR_ELT(answer, 0), row, localized_chars(call, node, "Name", language,
            STRING_ELT(VECTOR_ELT(answer, 2), row)));
        SET_STRING_ELT(VECTOR_ELT(answer, 4), row, localized_chars(call, node, "Description", language, R_BlankString));
        catalogue_annotations(call, node, language, answer, row);
        if ((++row & 255) == 0) R_CheckUserInterrupt();
    }
    UNPROTECT(1);
    return answer;
}

static SEXP run_call(void *data) {
    Call *call = (Call *) data;
    switch (call->operation) {
    case OP_READ: return read_document(call);
    case OP_FIND: return find_nodes(call);
    case OP_XPATH: return xpath_nodes(call);
    case OP_ATTR: return node_values(call, 1);
    case OP_TEXT: return node_values(call, 0);
    case OP_NAME: {
        xmlNodePtr node = node_from(call->args[0]);
        SEXP answer = PROTECT(Rf_allocVector(STRSXP, 1));
        SET_STRING_ELT(answer, 0, node == NULL ? R_BlankString : utf8_chars(node->name, 0));
        UNPROTECT(1);
        return answer;
    }
    case OP_LOCALIZED: return localized_value(call);
    case OP_REF: return reference_value(call);
    case OP_ANNOTATIONS: return annotation_values(call);
    case OP_CODES: return code_values(call);
    case OP_CATALOGUE: return catalogue_values(call);
    }
    Rf_error("Unknown native XML operation.");
    return R_NilValue;
}

static SEXP invoke(int operation, SEXP a, SEXP b, SEXP c, SEXP d) {
    Call call = {0};
    call.operation = operation;
    call.args[0] = a; call.args[1] = b; call.args[2] = c; call.args[3] = d;
    return R_UnwindProtect(run_call, &call, cleanup_call, &call, NULL);
}

SEXP oecd_xml_read(SEXP source, SEXP file) { return invoke(OP_READ, source, file, R_NilValue, R_NilValue); }
SEXP oecd_xml_find(SEXP node, SEXP name, SEXP children) { return invoke(OP_FIND, node, name, children, R_NilValue); }
SEXP oecd_xml_xpath(SEXP node, SEXP path, SEXP first) { return invoke(OP_XPATH, node, path, first, R_NilValue); }
SEXP oecd_xml_attr(SEXP node, SEXP name, SEXP fallback) { return invoke(OP_ATTR, node, name, fallback, R_NilValue); }
SEXP oecd_xml_text(SEXP node, SEXP fallback) { return invoke(OP_TEXT, node, fallback, R_NilValue, R_NilValue); }
SEXP oecd_xml_name(SEXP node) { return invoke(OP_NAME, node, R_NilValue, R_NilValue, R_NilValue); }
SEXP oecd_xml_localized(SEXP node, SEXP name, SEXP language, SEXP fallback) { return invoke(OP_LOCALIZED, node, name, language, fallback); }
SEXP oecd_xml_ref(SEXP node) { return invoke(OP_REF, node, R_NilValue, R_NilValue, R_NilValue); }
SEXP oecd_xml_annotations(SEXP node, SEXP language) { return invoke(OP_ANNOTATIONS, node, language, R_NilValue, R_NilValue); }
SEXP oecd_xml_codes(SEXP node, SEXP language) { return invoke(OP_CODES, node, language, R_NilValue, R_NilValue); }
SEXP oecd_xml_catalogue(SEXP node, SEXP language) { return invoke(OP_CATALOGUE, node, language, R_NilValue, R_NilValue); }
