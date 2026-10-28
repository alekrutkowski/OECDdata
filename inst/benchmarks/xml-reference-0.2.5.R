# Frozen OECDdata 0.2.5 XML implementation for offline benchmarking only.
# Copyright (c) 2026 Alek Rutkowski. MIT license; see LICENSE.
# The original R/xml.R body below is unchanged. Production code never loads
# this file. benchmarks/xml.R loads it in an isolated environment and compiles
# its functions so legacy/native timings both use byte-compiled R code.

.children <- function(node, name) xml2::xml_find_all(node, paste0("./*[local-name()='", name, "']"))
.descendants <- function(node, name) xml2::xml_find_all(node, paste0(".//*[local-name()='", name, "']"))
.first <- function(node, path) xml2::xml_find_first(node, path)
.attr <- function(node, name, default = "") {
  x <- xml2::xml_attr(node, name)
  x[is.na(x)] <- default
  x
}
.text <- function(node, default = "") {
  x <- xml2::xml_text(node, trim = TRUE)
  x[is.na(x)] <- default
  x
}
.localized <- function(node, name = "Name", fallback = "") {
  nodes <- .children(node, name)
  if (!length(nodes)) return(fallback)
  lang <- .attr(nodes, "lang")
  # xml2 exposes xml:lang by its local attribute name.
  preferred <- c(which(lang == .opt("language")), which(lang == "en"), seq_along(nodes))
  .text(nodes[[preferred[[1L]]]], fallback)
}
.annotations <- function(node) {
  items <- .descendants(node, "Annotation")
  if (!length(items)) return(character())
  types <- vapply(items, function(a) .text(.first(a, "./*[local-name()='AnnotationType']")), character(1))
  values <- vapply(items, function(a) {
    title <- .text(.first(a, "./*[local-name()='AnnotationTitle']"))
    if (nzchar(title)) title else .localized(a, "AnnotationText")
  }, character(1))
  stats_setNames(values, types)
}
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
.ref <- function(node) {
  r <- .first(node, ".//*[local-name()='Ref']")
  list(agency = .attr(r, "agencyID"), id = .attr(r, "id"), version = .attr(r, "version"),
    parent = .attr(r, "maintainableParentID"), parent_version = .attr(r, "maintainableParentVersion"))
}
.codes <- function(node) {
  codes <- .children(node, "Code")
  if (!length(codes)) return(data.table::data.table(code = character(), label = character()))
  ans <- data.table::data.table(code = .attr(codes, "id"),
    label = vapply(codes, .localized, character(1)))
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
    refs <- xml2::xml_find_all(node,
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
  flow_node <- .select_node(.descendants(doc, "Dataflow"), ref$agency, ref$id, ref$version, "dataflow")
  flow <- list(agency = .attr(flow_node, "agencyID"), id = .attr(flow_node, "id"),
    version = .attr(flow_node, "version"), name = .localized(flow_node),
    description = .localized(flow_node, "Description"))
  flow$code <- paste(flow$agency, flow$id, flow$version, sep = ",")
  dsref <- .ref(.first(flow_node, "./*[local-name()='Structure']"))
  dsd <- .select_node(.descendants(doc, "DataStructure"), dsref$agency, dsref$id, dsref$version, "DSD")
  elements <- xml2::xml_find_all(dsd,
    "./*[local-name()='DataStructureComponents']/*[local-name()='DimensionList' or local-name()='AttributeList' or local-name()='MeasureList']/*")
  if (!length(elements)) .abort("The selected DSD has no components.", "OECDdata_metadata_error")
  # Build component metadata and dictionaries together without nonlocal assignment.
  parts <- lapply(seq_along(elements), function(i) {
    node <- elements[[i]]
    id <- .attr(node, "id")
    kind <- xml2::xml_name(node)
    pos <- .attr(node, "position", as.character(i))
    if (kind %in% c("Dimension", "MeasureDimension", "TimeDimension") &&
        (!grepl("^[0-9]+$", pos) || !is.finite(as.numeric(pos)) ||
         as.numeric(pos) < 1 || as.numeric(pos) > .Machine$integer.max))
      .abort("The DSD contains an invalid dimension position.", "OECDdata_metadata_error")
    cref <- .ref(.first(node, "./*[local-name()='ConceptIdentity']"))
    concept <- .concept(doc, cref)
    label <- if (is.null(concept)) id else .localized(concept, fallback = id)
    enum <- .first(node, "./*[local-name()='LocalRepresentation']/*[local-name()='Enumeration']")
    if (inherits(enum, "xml_missing") && !is.null(concept))
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
  flows <- .descendants(doc, "Dataflow")
  # Only maintainable definitions, never Dataflow references inside attachments.
  flows <- flows[nzchar(.attr(flows, "agencyID")) & nzchar(.attr(flows, "id"))]
  if (!length(flows)) .abort("No dataflow definitions were returned.", "OECDdata_metadata_error")
  rows <- lapply(flows, function(f) {
    a <- .attr(f, "agencyID"); id <- .attr(f, "id"); v <- .attr(f, "version")
    ann <- .annotations(f)
    data.table::data.table(`Dataset name` = .localized(f, fallback = id),
      Code = paste(a, id, v, sep = ","), Type = "dataset",
      `Last update of data` = .annotation(ann, c("UPDATE_DATA", "LAST_UPDATE")),
      `Last table structure change` = .annotation(ann, c("UPDATE_STRUCTURE")),
      `Data start` = .annotation(ann, c("OBS_PERIOD_OVERALL_OLDEST")),
      `Data end` = .annotation(ann, c("OBS_PERIOD_OVERALL_LATEST")),
      # The Explorer requires an explicit data space.  Omission can produce
      # "The space is invalid" despite a correct agency/dataflow identity.
      Link = paste0("https://data-explorer.oecd.org/vis?lc=",
        curl::curl_escape(.opt("language")),
        "&df[ds]=dsDisseminateFinalDMZ&df[ag]=", curl::curl_escape(a),
        "&df[id]=", curl::curl_escape(id), "&df[vs]=", curl::curl_escape(v)),
      Agency = a, Dataflow = id, Version = v,
      Description = .localized(f, "Description"))
  }) %>% data.table::rbindlist()
  # A current catalogue has one latest version for each agency/dataflow pair.
  rows <- rows[, .SD[.newest(Version)], by = c("Agency", "Dataflow")]
  data.table::set(rows, j = "ShortCode", value = .catalogue_short_codes(rows$Dataflow))
  data.table::set(rows, j = "DataflowPrefix", value = .dataflow_parts(rows$Dataflow)$prefix)
  data.table::setcolorder(rows, c("ShortCode", "Dataset name", "Code", "Agency", "Dataflow",
    "DataflowPrefix", "Version", "Type", "Last update of data", "Last table structure change",
    "Data start", "Data end", "Description", "Link"))
  data.table::setorderv(rows, c("Agency", "Dataflow"))
  rows
}
