# Production metadata are parsed from the downloaded file directly in C.
# xml2 documents remain accepted by the internal parsers for fixture editing;
# convert once at the parser boundary, never once per code or catalogue row.
.read_xml <- function(source, is_file = TRUE) .Call(C_oecd_xml_read, source, is_file)
.native_xml <- function(node) {
  if (is.null(node) || inherits(node, "xml_missing")) return(NULL)
  if (inherits(node, c("OECDxml_document", "OECDxml_node"))) return(node)
  if (inherits(node, "xml_node")) return(.read_xml(as.character(node), FALSE))
  .abort("Expected an XML document or node.", "OECDdata_parse_error")
}
.children <- function(node, name) .Call(C_oecd_xml_find, .native_xml(node), name, TRUE)
.descendants <- function(node, name) .Call(C_oecd_xml_find, .native_xml(node), name, FALSE)
.first <- function(node, path) .Call(C_oecd_xml_xpath, .native_xml(node), path, TRUE)
.find_all <- function(node, path) .Call(C_oecd_xml_xpath, .native_xml(node), path, FALSE)
.attr <- function(node, name, default = "") .Call(C_oecd_xml_attr, node, name, default)
.text <- function(node, default = "") .Call(C_oecd_xml_text, node, default)
.localized <- function(node, name = "Name", fallback = "") {
  .Call(C_oecd_xml_localized, .native_xml(node), name, .opt("language"), fallback)
}
.annotations <- function(node) .Call(C_oecd_xml_annotations, .native_xml(node), .opt("language"))
.annotation <- function(x, candidates) {
  idx <- match(candidates, names(x)); idx <- idx[!is.na(idx)]
  if (!length(idx)) NA_character_ else unname(x[[idx[[1L]]]])
}

.newest <- function(versions) {
  if (!length(versions)) return(integer())
  if (any(!grepl("^[0-9]+(\\.[0-9]+)*$", versions)))
    .abort("Non-numeric structure versions are ambiguous; request an exact version.", "OECDdata_metadata_error")
  Reduce(function(i, j) if (utils::compareVersion(versions[[i]], versions[[j]]) >= 0) i else j,
    seq_along(versions), init = 1L)
}
.select_node <- function(nodes, agency = "", id = "", version = "", what = "artefact") {
  if (nzchar(agency) && agency != "*") nodes <- nodes[.attr(nodes, "agencyID") == agency]
  if (nzchar(id) && id != "*") nodes <- nodes[.attr(nodes, "id") == id]
  if (nzchar(version) && !(version %in% c("+", "latest", "*")))
    nodes <- nodes[.attr(nodes, "version") == version]
  if (!length(nodes)) .abort(paste0("Could not resolve ", what, " ", agency, ",", id, ",", version,
    ". The server may have returned incomplete structural metadata."), "OECDdata_metadata_error")
  identities <- unique(paste(.attr(nodes, "agencyID"), .attr(nodes, "id")))
  if (length(identities) != 1L)
    .abort(paste0("Ambiguous ", what, "; supply an agency and identifier."), "OECDdata_ambiguous")
  nodes[[if (length(nodes) > 1L) .newest(.attr(nodes, "version")) else 1L]]
}
.ref <- function(node) .Call(C_oecd_xml_ref, .native_xml(node))
.codes <- function(node) {
  ans <- .Call(C_oecd_xml_codes, .native_xml(node), .opt("language")) %>%
    data.table::as.data.table()
  if (anyDuplicated(ans$code)) .abort("Duplicate identifiers in an OECD codelist.", "OECDdata_metadata_error")
  ans
}
.concept <- function(doc, ref) {
  if (!nzchar(ref$parent)) return(NULL)
  schemes <- .descendants(doc, "ConceptScheme")
  schemes <- schemes[.attr(schemes, "id") == ref$parent]
  if (nzchar(ref$agency)) schemes <- schemes[.attr(schemes, "agencyID") == ref$agency]
  if (nzchar(ref$parent_version)) schemes <- schemes[.attr(schemes, "version") == ref$parent_version]
  if (!length(schemes)) return(NULL)
  scheme <- .select_node(schemes, what = "concept scheme")
  codes <- .children(scheme, "Concept")
  codes <- codes[.attr(codes, "id") == ref$id]
  if (length(codes) == 1L) codes[[1L]] else NULL
}

# Actual constraints supply marginal availability, not a guarantee of all cross-products.
.constraint_values <- function(doc, flow, dimensions) {
  constraints <- .descendants(doc, "ContentConstraint")
  constraints <- constraints[tolower(.attr(constraints, "type")) == "actual"]
  constraints <- Filter(function(node) {
    refs <- .find_all(node,
      ".//*[local-name()='ConstraintAttachment']/*[local-name()='Dataflow']/*[local-name()='Ref']")
    if (!length(refs)) return(FALSE)
    if (length(unique(paste(.attr(refs, "agencyID"), .attr(refs, "id"), .attr(refs, "version")))) != 1L)
      return(FALSE)
    any(.attr(refs, "id") == flow$id &
      (.attr(refs, "agencyID") %in% c("", flow$agency)) &
      (.attr(refs, "version") %in% c("", "+", "latest", flow$version)))
  }, as.list(constraints))
  if (!length(constraints)) return(list(values = list(), source = "unavailable", reason =
    "No dataflow-specific Actual content constraint was supplied."))
  if (length(constraints) > 1L) {
    ids <- vapply(constraints, function(x) paste(.attr(x, "agencyID"), .attr(x, "id")), character(1))
    if (length(unique(ids)) > 1L) return(list(values = list(), source = "unavailable", reason =
      "Several distinct Actual constraints require an unsupported intersection."))
    constraints <- constraints[.newest(vapply(constraints, .attr, character(1), name = "version"))]
  }
  regions <- as.list(.descendants(constraints[[1L]], "CubeRegion"))
  if (!length(regions)) return(list(values = list(), source = "unavailable", reason =
    "Actual constraint does not enumerate cube regions."))
  included <- Filter(function(r) .attr(r, "include", "true") %in% c("true", "1"), regions)
  excluded <- Filter(function(r) !(.attr(r, "include", "true") %in% c("true", "1")), regions)
  if (length(excluded))
    return(list(values = list(), source = "unavailable", reason =
      "Excluded cube regions cannot be projected to exact marginal availability safely."))
  members <- .descendants(constraints[[1L]], "KeyValue")
  if (any(!(.attr(members, "include", "true") %in% c("true", "1"))))
    return(list(values = list(), source = "unavailable", reason =
      "Excluded key values cannot be projected to exact marginal availability safely."))
  projection <- lapply(dimensions, function(d) {
    lists <- lapply(included, function(r) {
      kv <- .children(r, "KeyValue"); kv <- kv[.attr(kv, "id") == d]
      if (length(kv) != 1L || length(.descendants(kv[[1L]], "TimeRange"))) return(NULL)
      values <- .text(.children(kv[[1L]], "Value"))
      if (!length(values) || any(!nzchar(values))) NULL else values
    })
    if (!length(lists) || any(vapply(lists, is.null, logical(1)))) return(NULL)
    vals <- unique(unlist(lists, use.names = FALSE))
    vals
  })
  names(projection) <- dimensions
  list(values = projection, source = "actual", reason = "Actual SDMX content constraint")
}

.parse_structure <- function(doc, ref) {
  doc <- .native_xml(doc)
  flow_node <- .select_node(.descendants(doc, "Dataflow"), ref$agency, ref$id, ref$version, "dataflow")
  flow <- list(agency = .attr(flow_node, "agencyID"), id = .attr(flow_node, "id"),
    version = .attr(flow_node, "version"), name = .localized(flow_node),
    description = .localized(flow_node, "Description"))
  flow$code <- paste(flow$agency, flow$id, flow$version, sep = ",")
  dsref <- .ref(.first(flow_node, "./*[local-name()='Structure']"))
  dsd <- .select_node(.descendants(doc, "DataStructure"), dsref$agency, dsref$id, dsref$version, "DSD")
  elements <- .find_all(dsd,
    "./*[local-name()='DataStructureComponents']/*[local-name()='DimensionList' or local-name()='AttributeList' or local-name()='MeasureList']/*")
  if (!length(elements)) .abort("The selected DSD has no components.", "OECDdata_metadata_error")
  # Build component metadata and dictionaries together without nonlocal assignment.
  parts <- lapply(seq_along(elements), function(i) {
    node <- elements[[i]]
    id <- .attr(node, "id")
    kind <- .Call(C_oecd_xml_name, node)
    pos <- .attr(node, "position", as.character(i))
    if (kind %in% c("Dimension", "MeasureDimension", "TimeDimension") &&
        (!grepl("^[0-9]+$", pos) || !is.finite(as.numeric(pos)) ||
         as.numeric(pos) < 1 || as.numeric(pos) > .Machine$integer.max))
      .abort("The DSD contains an invalid dimension position.", "OECDdata_metadata_error")
    cref <- .ref(.first(node, "./*[local-name()='ConceptIdentity']"))
    concept <- .concept(doc, cref)
    label <- if (is.null(concept)) id else .localized(concept, fallback = id)
    enum <- .first(node, "./*[local-name()='LocalRepresentation']/*[local-name()='Enumeration']")
    if (is.null(enum) && !is.null(concept))
      enum <- .first(concept, "./*[local-name()='CoreRepresentation']/*[local-name()='Enumeration']")
    er <- .ref(enum)
    dictionary <- if (nzchar(er$id)) {
      cl <- .select_node(.descendants(doc, "Codelist"), er$agency,
        er$id, er$version, "codelist")
      .codes(cl)
    } else NULL
    list(component = data.table::data.table(
      id = id, label = label, kind = kind,
      position = as.integer(pos),
      codelist = if (nzchar(er$id)) paste(er$agency, er$id, er$version, sep = ",")
        else NA_character_), dictionary = dictionary)
  })
  components <- data.table::rbindlist(lapply(parts, `[[`, "component"))
  labels <- lapply(parts, `[[`, "dictionary")
  names(labels) <- components$id
  labels <- labels[!vapply(labels, is.null, logical(1))]
  if (anyDuplicated(components$id)) .abort("The DSD contains duplicate component IDs.", "OECDdata_metadata_error")
  if (any(!nzchar(components$id)) || any(components$id %in%
      c("value_", "flags_", "DATAFLOW", "STRUCTURE", "STRUCTURE_ID", "ACTION")))
    .abort("The DSD contains empty or reserved component IDs.", "OECDdata_metadata_error")
  dimensions <- components[kind %in% c("Dimension", "MeasureDimension", "TimeDimension")][order(position)]
  if (!nrow(dimensions) || anyDuplicated(dimensions$position))
    .abort("The DSD must have dimensions with unique positions.", "OECDdata_metadata_error")
  if (sum(dimensions$kind == "TimeDimension") > 1L)
    .abort("The DSD contains multiple time dimensions.", "OECDdata_metadata_error")
  attrs <- components[kind == "Attribute"]
  measure <- components[kind %in% c("PrimaryMeasure", "Measure")]$id
  if (length(measure) != 1L)
    .abort("Only DSDs with a single observation measure are supported.", "OECDdata_metadata_error")
  keys <- dimensions[kind != "TimeDimension"]$id
  availability <- .constraint_values(doc, flow, keys)
  dsd_ref <- list(agency = .attr(dsd, "agencyID"), id = .attr(dsd, "id"),
    version = .attr(dsd, "version"))
  structure(list(flow = flow, dsd = dsd_ref, dimensions = dimensions, attributes = attrs, measure = measure,
    labels = labels, available = availability$values,
    availability = availability$source, availability_reason = availability$reason), class = "OECDStructure")
}

.parse_catalogue <- function(doc) {
  # All strings are extracted into full-length vectors in a single C call.
  # This avoids an R closure and a one-row data.table for every dataflow.
  rows <- .Call(C_oecd_xml_catalogue, .native_xml(doc), .opt("language")) %>%
    data.table::as.data.table()
  if (!nrow(rows)) .abort("No dataflow definitions were returned.", "OECDdata_metadata_error")
  rows[, `:=`(Code = paste(Agency, Dataflow, Version, sep = ","), Type = "dataset",
    Link = paste0("https://data-explorer.oecd.org/vis?lc=", curl::curl_escape(.opt("language")),
      "&df[ds]=dsDisseminateFinalDMZ&df[ag]=", curl::curl_escape(Agency),
      "&df[id]=", curl::curl_escape(Dataflow), "&df[vs]=", curl::curl_escape(Version)))]
  # A current catalogue has one latest version for each agency/dataflow pair.
  if (any(!grepl("^[0-9]+(\\.[0-9]+)*$", rows$Version)))
    .abort("Non-numeric structure versions are ambiguous; request an exact version.", "OECDdata_metadata_error")
  if (anyDuplicated(rows, by = c("Agency", "Dataflow")))
    rows <- rows[rows[, .I[if (.N == 1L) 1L else .newest(Version)],
      by = c("Agency", "Dataflow")]$V1]
  data.table::set(rows, j = "ShortCode", value = .catalogue_short_codes(rows$Dataflow))
  data.table::set(rows, j = "DataflowPrefix", value = .dataflow_parts(rows$Dataflow)$prefix)
  data.table::setcolorder(rows, c("ShortCode", "Dataset name", "Code", "Agency", "Dataflow",
    "DataflowPrefix", "Version", "Type", "Last update of data", "Last table structure change",
    "Data start", "Data end", "Description", "Link"))
  data.table::setorderv(rows, c("Agency", "Dataflow"))
  rows
}
