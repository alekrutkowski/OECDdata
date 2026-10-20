# Dataset identity is not an observation dimension. Shorthands are resolved
# from the configured provider's catalogue, never by a hard-coded alias table.
.identifier <- function(x, name) {
  .scalar_string(x, name)
  if (!grepl("^[A-Za-z0-9_@$.-]+$", x))
    .abort(paste0("Invalid ", name, ": use a literal identifier, not a URL or wildcard."))
  x
}
.version <- function(x) {
  .scalar_string(x, "version")
  if (tolower(x) == "latest") x <- "+"
  if (!(x == "+" || grepl("^[0-9]+(\\.[0-9]+)*$", x)))
    .abort("Version must be a numeric string (for example '1.0'), '+' or 'latest'.")
  x
}
.dataflow_parts <- function(ids) {
  has_prefix <- grepl("@", ids, fixed = TRUE)
  leaf <- sub("^.*@", "", ids)
  list(prefix = ifelse(has_prefix, sub("@.*$", "", ids), NA_character_),
       leaf = leaf, short = sub("^DF_", "", leaf, ignore.case = TRUE))
}
# Suppress an advertised shorthand if any other identity could use that token.
# Counting all literal, terminal and compact tokens avoids an O(n^2) scan.
.catalogue_short_codes <- function(ids) {
  parts <- .dataflow_parts(ids)
  lookup <- lapply(list(ids, parts$leaf, parts$short), function(x)
    data.table::data.table(token = toupper(x), row_id = seq_along(ids))) %>%
    data.table::rbindlist() %>% unique()
  counts <- lookup[, list(n_matches = .N), by = "token"]
  safe <- counts$n_matches[match(toupper(parts$short), counts$token)] == 1L
  ifelse(safe & nzchar(parts$short), parts$short, NA_character_)
}
.dataset_selectors <- function(x) {
  if (is.null(x)) return(list())
  if (!is.list(x) || !length(x))
    .abort("`filters$.dataset` must be a non-empty named list of agency, prefix and/or version.")
  nm <- names(x)
  if (is.null(nm) || anyNA(nm) || any(!nzchar(nm)) || anyDuplicated(tolower(nm)))
    .abort("Dataset selectors must have unique, non-empty names.")
  names(x) <- tolower(nm)
  unknown <- setdiff(names(x), c("agency", "prefix", "version"))
  if (length(unknown)) .abort(paste0("Unknown dataset selector(s): ",
    paste(unknown, collapse = ", "), ". Use agency, prefix and/or version."))
  invisible(lapply(names(x), function(n) {
    if (is.null(x[[n]])) .abort(paste0("Dataset selector ", n, " must be a string, not NULL."))
    if (n == "version") .version(x[[n]]) else .identifier(x[[n]], n)
  }))
  x
}
.parse_reference <- function(code, resolve = TRUE, agency = NULL, prefix = NULL, version = NULL) {
  .scalar_string(code, "OECDDatasetCode")
  if (grepl("[/:?#[:space:]]", code))
    .abort("Use an OECD short code or 'AGENCY,DATAFLOW,VERSION', not a URL or whitespace.")
  if (!is.null(agency)) .identifier(agency, "agency")
  if (!is.null(prefix)) {
    .identifier(prefix, "prefix")
    if (grepl("@", prefix, fixed = TRUE))
      .abort("`prefix` selects the dataflow prefix before '@'; omit the suffix.")
  }
  if (!is.null(version)) version <- .version(version)
  parts <- strsplit(paste0(code, ",#"), ",", fixed = TRUE)[[1L]]
  parts <- utils::head(parts, -1L)
  if (!(length(parts) %in% 1:3) || any(!nzchar(parts[seq_len(min(2L, length(parts)))])))
    .abort("Expected a short code, dataflow ID, 'AGENCY,DATAFLOW' or 'AGENCY,DATAFLOW,VERSION'.")
  if (length(parts) >= 2L) {
    .identifier(parts[[1L]], "agency"); .identifier(parts[[2L]], "dataflow")
    if (!is.null(agency) && toupper(agency) != toupper(parts[[1L]]))
      .abort("Conflicting agency in OECDDatasetCode and dataset selectors.")
    actual_prefix <- .dataflow_parts(parts[[2L]])$prefix
    if (!is.null(prefix) && (is.na(actual_prefix) || toupper(prefix) != toupper(actual_prefix)))
      .abort("Conflicting dataflow prefix in OECDDatasetCode and dataset selectors.")
    specified <- length(parts) == 3L && nzchar(parts[[3L]])
    supplied <- if (specified) .version(parts[[3L]]) else NULL
    if (!is.null(version) && specified && version != supplied)
      .abort("Conflicting version in OECDDatasetCode and dataset selectors.")
    return(list(agency = parts[[1L]], id = parts[[2L]],
      version = if (!is.null(version)) version else if (specified) supplied else "+"))
  }
  .identifier(code, "OECDDatasetCode")
  if (!resolve) return(list(agency = if (is.null(agency)) "*" else agency, id = code,
    version = if (is.null(version)) "+" else version))
  catalogue <- importDataList()
  bits <- .dataflow_parts(catalogue$Dataflow)
  eligible <- rep(TRUE, nrow(catalogue))
  if (!is.null(agency)) eligible <- eligible & toupper(catalogue$Agency) == toupper(agency)
  if (!is.null(prefix)) eligible <- eligible & !is.na(bits$prefix) & toupper(bits$prefix) == toupper(prefix)
  # Exact IDs win over terminal suffixes, which win over DF_-stripped aliases.
  matches <- lapply(list(catalogue$Dataflow, bits$leaf, bits$short), function(x)
    which(eligible & toupper(x) == toupper(code)))
  first <- match(TRUE, lengths(matches) > 0L)
  if (is.na(first)) .abort(paste0("Unknown dataflow or short code: ", code,
    ". No match for the supplied dataset selectors. Search importDataList(); ",
    "legacy OECD.Stat codes are not automatically translated."), "OECDdata_metadata_error")
  idx <- matches[[first]]
  if (length(idx) > 1L) .abort(paste0("Ambiguous dataset code: ", code,
    ". Use a canonical Code, or add agency/prefix selectors. Candidates: ",
    paste(utils::head(catalogue$Code[idx], 20L), collapse = "; "),
    if (length(idx) > 20L) "; ... (all candidates are in condition$candidates)" else ""),
    "OECDdata_ambiguous", candidates = catalogue[idx, , drop = FALSE])
  list(agency = catalogue$Agency[[idx]], id = catalogue$Dataflow[[idx]],
    version = if (is.null(version)) catalogue$Version[[idx]] else version)
}
.split_filters <- function(filters) {
  if (is.null(filters)) return(list(selectors = list(), filters = NULL))
  if (!is.list(filters) || !length(filters))
    .abort("`filters` must be NULL or a non-empty named list.")
  nm <- names(filters)
  if (is.null(nm) || anyNA(nm) || any(!nzchar(nm)) || anyDuplicated(toupper(nm)))
    .abort("All filter entries must have unique, non-empty names.")
  at <- which(tolower(nm) == ".dataset")
  selectors <- if (length(at)) {
    if (is.null(filters[[at]])) .abort("`filters$.dataset` must be a non-empty named list, not NULL.")
    .dataset_selectors(filters[[at]])
  } else list()
  actual <- if (length(at)) filters[-at] else filters
  list(selectors = selectors, filters = if (length(actual)) actual else NULL)
}
.selection <- function(OECDDatasetCode, filters) {
  x <- .split_filters(filters)
  ref <- do.call(.parse_reference, c(list(code = OECDDatasetCode), x$selectors))
  list(structure = .structure_for(ref), filters = x$filters)
}

#' Resolve an OECD dataset to its canonical, versioned reference
#' @export
oecdDataset <- function(OECDDatasetCode, agency = NULL, prefix = NULL, version = NULL) {
  .structure_for(.parse_reference(OECDDatasetCode, agency = agency,
    prefix = prefix, version = version))$flow$code
}
