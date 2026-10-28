#define R_NO_REMAP
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <R_ext/Visibility.h>

extern SEXP oecd_xml_read(SEXP, SEXP);
extern SEXP oecd_xml_find(SEXP, SEXP, SEXP);
extern SEXP oecd_xml_xpath(SEXP, SEXP, SEXP);
extern SEXP oecd_xml_attr(SEXP, SEXP, SEXP);
extern SEXP oecd_xml_text(SEXP, SEXP);
extern SEXP oecd_xml_name(SEXP);
extern SEXP oecd_xml_localized(SEXP, SEXP, SEXP, SEXP);
extern SEXP oecd_xml_ref(SEXP);
extern SEXP oecd_xml_annotations(SEXP, SEXP);
extern SEXP oecd_xml_codes(SEXP, SEXP);
extern SEXP oecd_xml_catalogue(SEXP, SEXP);

static const R_CallMethodDef call_methods[] = {
    {"oecd_xml_read", (DL_FUNC) &oecd_xml_read, 2},
    {"oecd_xml_find", (DL_FUNC) &oecd_xml_find, 3},
    {"oecd_xml_xpath", (DL_FUNC) &oecd_xml_xpath, 3},
    {"oecd_xml_attr", (DL_FUNC) &oecd_xml_attr, 3},
    {"oecd_xml_text", (DL_FUNC) &oecd_xml_text, 2},
    {"oecd_xml_name", (DL_FUNC) &oecd_xml_name, 1},
    {"oecd_xml_localized", (DL_FUNC) &oecd_xml_localized, 4},
    {"oecd_xml_ref", (DL_FUNC) &oecd_xml_ref, 1},
    {"oecd_xml_annotations", (DL_FUNC) &oecd_xml_annotations, 2},
    {"oecd_xml_codes", (DL_FUNC) &oecd_xml_codes, 2},
    {"oecd_xml_catalogue", (DL_FUNC) &oecd_xml_catalogue, 2},
    {NULL, NULL, 0}
};

void attribute_visible R_init_OECDdata(DllInfo *dll) {
    R_registerRoutines(dll, NULL, call_methods, NULL, NULL);
    R_useDynamicSymbols(dll, FALSE);
    R_forceSymbols(dll, TRUE);
}
