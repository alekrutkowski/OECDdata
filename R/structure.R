#' Import the current OECD dataflow catalogue
#' @export
importDataList <- function() {
  raw <- .read_structure("dataflow", "*", "*", "+", references = "none", detail = "full")
  out <- .parse_catalogue(raw$doc) %>% as.data.frame()
  attr(out, "DownloadTime") <- raw$response$time
  attr(out, "Cached") <- raw$response$cached
  as.OECDDataList(out)
}

#' Inspect the resolved structure of an OECD dataset
#' @export
oecdStructure <- function(OECDDatasetCode) {
  .structure_for(.parse_reference(OECDDatasetCode))
}

.structure_for <- function(ref) {
  # referencepartial requires a literal version on the OECD service. Resolve
  # latest through a small dataflow-only response before asking for its DSD.
  if (ref$version %in% c("+", "latest")) {
    latest <- .read_structure("dataflow", ref$agency, ref$id, ref$version,
      references = "none", detail = "full")
    node <- .select_node(.descendants(latest$doc, "Dataflow"),
      ref$agency, ref$id, ref$version, "dataflow")
    ref <- list(agency = .attr(node, "agencyID"), id = .attr(node, "id"),
      version = .attr(node, "version"))
  }
  raw <- .read_structure("dataflow", ref$agency, ref$id, ref$version)
  out <- .parse_structure(raw$doc, ref)
  attr(out, "DownloadTime") <- raw$response$time
  attr(out, "SourceURL") <- raw$response$url
  out
}

.dimension_labels <- function(code, dataset = NULL, require_codes = TRUE) {
  .scalar_string(code, "OECDDimCode")
  if (grepl("::", code, fixed = TRUE)) {
    parts <- strsplit(paste0(code, "::#"), "::", fixed = TRUE)[[1L]]
    parts <- utils::head(parts, -1L)
    if (length(parts) != 2L || any(!nzchar(parts)))
      .abort("Use 'AGENCY,DATAFLOW,VERSION::DIMENSION'.")
    if (!is.null(dataset) && !identical(dataset, parts[[1L]]) &&
        !identical(oecdDataset(dataset), oecdDataset(parts[[1L]])))
      .abort("Conflicting dataset argument and qualified component reference.")
    dataset <- parts[[1L]]; code <- parts[[2L]]
  }
  if (is.null(dataset)) dataset <- .opt("dataset")
  if (!is.null(dataset)) {
    s <- oecdStructure(dataset)
    components <- data.table::rbindlist(list(s$dimensions, s$attributes), use.names = TRUE)
    at <- which(toupper(components$id) == toupper(code))
    if (length(at) != 1L) .abort(paste0("Unknown or ambiguous component: ", code,
      ". Available: ", paste(components$id, collapse = ", ")))
    actual <- components$id[[at]]
    dictionary <- s$labels[[actual]]
    if (require_codes && is.null(dictionary)) .abort(paste0("Component ", actual,
      " is not backed by an enumerated codelist."), "OECDdata_metadata_error")
    return(list(code = code, label = components$label[[at]], table = dictionary,
      time = attr(s, "DownloadTime"), dataset = s$flow$code))
  }
  # No guessing of dimension order or selection of the first dictionary.
  # A bare component can use a globally unambiguous CL_<COMPONENT> dictionary.
  ref <- if (grepl(",", code, fixed = TRUE)) .parse_reference(code) else
    list(agency = "*", id = if (startsWith(toupper(code), "CL_")) toupper(code) else paste0("CL_", toupper(code)), version = "+")
  raw <- .read_structure("codelist", ref$agency, ref$id, ref$version, "none", "full")
  node <- .select_node(.descendants(raw$doc, "Codelist"), ref$agency, ref$id, ref$version, "codelist")
  list(code = code, label = .localized(node), table = .codes(node), time = raw$response$time, dataset = NULL)
}

#' Import labels for a dimension or attribute
#' @export
importLabels <- function(OECDDimCode, dataset = NULL) {
  x <- .dimension_labels(OECDDimCode, dataset)
  out <- data.table::copy(x$table)
  data.table::setnames(out, c(x$code, paste0(x$code, "_labels")))
  if (.opt("strings_as_factors")) out[, (names(out)) := lapply(.SD, factor)]
  out <- as.data.frame(out)
  class(out) <- c("OECDLabels", "data.frame")
  attr(out, "OECDDimCode") <- x$code
  attr(out, "OECDDatasetCode") <- x$dataset
  attr(out, "DownloadTime") <- x$time
  out
}

#' Import the human-readable name of a dimension
#' @export
importDimLabel <- function(OECDDimCode, dataset = NULL) {
  .dimension_labels(OECDDimCode, dataset, require_codes = FALSE)$label
}

.metabase_one <- function(s, code = s$flow$code) {
  dims <- s$dimensions[kind != "TimeDimension"]$id
  mode <- .opt("availability")
  if (mode == "actual" && (s$availability != "actual" ||
      any(vapply(s$available[dims], is.null, logical(1)))))
    .abort(paste0("Exact marginal availability is unavailable for ", s$flow$code, ". ",
      s$availability_reason, " Use oecdStructure() for the dictionary or explicitly set ",
      "oecdOptions(availability = 'allowed') for permissible, not necessarily observed, codes."),
      "OECDdata_availability_error")
  tables <- lapply(dims, function(d) {
    vals <- if (mode == "actual") s$available[[d]] else s$labels[[d]]$code
    if (is.null(vals)) .abort(paste0("Dimension ", d, " has no enumerable codes."), "OECDdata_metadata_error")
    data.table::data.table(Code = rep(code, length(vals)), Dim_name = rep(d, length(vals)), Dim_val = vals)
  })
  out <- data.table::rbindlist(tables, use.names = TRUE)
  data.table::setattr(out, "Availability", mode)
  out
}

#' Import the dataset/dimension/code inventory
#' @export
importMetabase <- function(OECDDatasetCode = NULL) {
  code <- OECDDatasetCode
  if (is.null(code)) code <- .opt("dataset")
  if (!is.null(code)) {
    if (!is.character(code) || !length(code) || anyNA(code)) .abort("Dataset codes must be non-missing strings.")
    out <- lapply(unique(code), function(x) .metabase_one(oecdStructure(x), x)) %>% data.table::rbindlist()
  } else {
    .say("Retrieving the complete structural inventory. This can be large; prefer importMetabase(dataset).")
    raw <- .read_structure("dataflow", "*", "*", "+", references = "all", detail = "referencepartial")
    cat <- .parse_catalogue(raw$doc)
    out <- lapply(cat$Code, function(x) .metabase_one(.parse_structure(raw$doc,
      .parse_reference(x)), x)) %>% data.table::rbindlist()
  }
  out <- as.data.frame(out)
  attr(out, "Availability") <- .opt("availability")
  out
}

.describe_one <- function(code, import_labels, wide, import_dim_labels) {
  s <- oecdStructure(code)
  out <- .metabase_one(s, code)
  data.table::set(out, j = "Code", value = NULL)
  data.table::set(out, j = code, value = rep(TRUE, nrow(out)))
  if (wide) {
    # data.table interprets commas in character `by` names as separators.
    # Canonical OECD references contain commas, and this column is always TRUE.
    out <- out[, list(Dim_values = paste(Dim_val, collapse = ", ")),
      by = "Dim_name"]
    data.table::set(out, j = code, value = rep(TRUE, nrow(out)))
  }
  if (import_dim_labels) data.table::set(out, j = "Dim_name_label",
    value = s$dimensions$label[match(out$Dim_name, s$dimensions$id)])
  if (import_labels) {
    labels <- lapply(names(s$labels), function(d) {
      t <- data.table::copy(s$labels[[d]])
      data.table::setnames(t, c("Dim_val", "Dim_val_label"))
      t[, Dim_name := d]
    }) %>% data.table::rbindlist()
    if (!ncol(labels)) labels <- data.table::data.table(
      Dim_name = character(), Dim_val = character(), Dim_val_label = character())
    out <- merge(out, labels, by = c("Dim_name", "Dim_val"), all.x = TRUE, sort = FALSE)
  }
  order <- c("Dim_name", if (import_dim_labels) "Dim_name_label",
    if (wide) "Dim_values" else "Dim_val", if (import_labels) "Dim_val_label", code)
  data.table::setcolorder(out, order)
  data.table::setattr(out, "Availability", .opt("availability"))
  out
}

#' Describe dimensions and their values
#' @export
describe <- function(OECDDatasetCode, import_labels = !wide, wide = FALSE, import_dim_labels = TRUE) {
  .scalar_string(OECDDatasetCode, "OECDDatasetCode")
  .flag(import_labels, "import_labels"); .flag(wide, "wide"); .flag(import_dim_labels, "import_dim_labels")
  if (wide && import_labels) .abort("`wide = TRUE` requires `import_labels = FALSE`, as in eurodata.")
  .describe_one(OECDDatasetCode, import_labels, wide, import_dim_labels)
}

#' Compare marginal dimension-code coverage of datasets
#' @export
compare <- function(..., import_labels = TRUE, import_dim_labels = TRUE) {
  .flag(import_labels, "import_labels"); .flag(import_dim_labels, "import_dim_labels")
  args <- list(...)
  if (any(!vapply(args, function(x) is.character(x) && length(x) == 1L && !is.na(x), logical(1))))
    .abort("Supply dataset codes as separate scalar strings.")
  codes <- unique(unlist(args, use.names = FALSE))
  if (length(codes) < 2L) .abort("`compare()` needs at least two different dataset codes.")
  ds <- lapply(codes, .describe_one, import_labels = import_labels, wide = FALSE,
    import_dim_labels = import_dim_labels)
  keys <- c("Dim_name", "Dim_val")
  out <- Reduce(function(a, b) merge(a, b, by = keys, all = TRUE, sort = FALSE),
    lapply(seq_along(ds), function(i) ds[[i]][, c(keys, codes[[i]]), with = FALSE]))
  invisible(lapply(codes, function(code) data.table::set(out,
    j = code, value = !is.na(out[[code]]) & out[[code]])))
  label_cols <- c(if (import_labels) "Dim_val_label", if (import_dim_labels) "Dim_name_label")
  if (length(label_cols)) {
    lab <- lapply(ds, function(x) x[, c(keys, label_cols), with = FALSE]) %>% data.table::rbindlist()
    conflict <- any(lab[, lapply(.SD, function(x) data.table::uniqueN(x[!is.na(x)]) > 1L),
      by = keys, .SDcols = label_cols][, unlist(.SD), .SDcols = label_cols])
    if (conflict) .warn("Some matching dimension/code IDs have different labels across datasets. Labels are joined with ' | '; semantic equivalence is not implied.")
    lab <- lab[, lapply(.SD, function(x) {
      u <- unique(x[!is.na(x)])
      if (!length(u)) NA_character_ else paste(u, collapse = " | ")
    }), by = keys, .SDcols = label_cols]
    out <- merge(out, lab, by = keys, all.x = TRUE, sort = FALSE)
  }
  data.table::setcolorder(out, c("Dim_name", if (import_dim_labels) "Dim_name_label",
    "Dim_val", if (import_labels) "Dim_val_label", codes))
  attr(out, "Availability") <- .opt("availability")
  out
}
