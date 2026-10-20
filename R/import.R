.numeric_measure <- function(x) {
  missing <- is.na(x) | x %in% c("", ":", "NA")
  result <- suppressWarnings(as.numeric(x))
  bad <- !missing & is.na(result) & !(x %in% c("NaN", "nan"))
  if (any(bad)) .abort(paste0("Non-numeric observation value(s): ",
    paste(utils::head(unique(x[bad]), 5L), collapse = ", "),
    ". No values were silently coerced."), "OECDdata_parse_error")
  result[missing] <- NA_real_
  result
}
.empty_data <- function(s) {
  out <- stats_setNames(rep(list(character()), length(s$dimensions$id)), s$dimensions$id) %>%
    data.table::as.data.table()
  out[, value_ := double()]
  out[, flags_ := character()]
  invisible(lapply(s$attributes$id, function(n) data.table::set(out, j = n, value = character())))
  out
}
.parse_data <- function(path, s) {
  out <- withCallingHandlers(data.table::fread(file = path, sep = ",", header = TRUE,
    colClasses = "character", na.strings = NULL, encoding = "UTF-8", data.table = TRUE,
    check.names = FALSE, strip.white = FALSE, fill = FALSE, showProgress = !.opt("quiet")),
    warning = function(w) .abort(paste0("CSV parsing warning treated as an error: ", conditionMessage(w)),
      "OECDdata_parse_error"))
  if (anyDuplicated(names(out))) .abort("The CSV has duplicate column names.", "OECDdata_parse_error")
  if (any(c("value_", "flags_") %in% names(out)))
    .abort("The response uses a reserved output column name (value_ or flags_).", "OECDdata_parse_error")
  need <- c(s$dimensions$id, s$measure)
  if (length(setdiff(need, names(out)))) .abort(paste0("CSV is missing required columns: ",
    paste(setdiff(need, names(out)), collapse = ", ")), "OECDdata_parse_error")
  if ("ACTION" %in% names(out) && any(!(out$ACTION %in% c("A", "I", "R", ""))))
    .abort("CSV contains deletion or unsupported action records; these are not full snapshot observations.",
      "OECDdata_parse_error")
  identities <- function(ref) c(
    paste0(ref$agency, ":", ref$id, "(", ref$version, ")"),
    paste(ref$agency, ref$id, ref$version, sep = ","), ref$id)
  types <- if ("STRUCTURE" %in% names(out)) toupper(out$STRUCTURE) else
    rep("DATAFLOW", nrow(out))
  if (any(!types %in% c("DATAFLOW", "DATASTRUCTURE")))
    .abort("CSV contains an unsupported structure type.", "OECDdata_parse_error")
  if ("STRUCTURE_ID" %in% names(out) && any(
      (types == "DATAFLOW" & !out$STRUCTURE_ID %in% identities(s$flow)) |
      (types == "DATASTRUCTURE" & !out$STRUCTURE_ID %in% identities(s$dsd))))
    .abort("Response identity does not match the requested dataflow/version or DSD.", "OECDdata_parse_error")
  if ("DATAFLOW" %in% names(out) && any(!out$DATAFLOW %in% identities(s$flow)))
    .abort("Response identity does not match the requested dataflow/version.", "OECDdata_parse_error")
  if (any(vapply(s$dimensions$id, function(n) anyNA(out[[n]]) || any(!nzchar(out[[n]])), logical(1))))
    .abort("An observation has a missing dimension identifier.", "OECDdata_parse_error")
  if (nrow(out) && anyDuplicated(out, by = s$dimensions$id))
    .abort("The response has duplicate observation keys; no aggregation was attempted.", "OECDdata_parse_error")
  data.table::set(out, j = s$measure, value = .numeric_measure(out[[s$measure]]))
  data.table::setnames(out, s$measure, "value_")
  status <- if ("OBS_STATUS" %in% names(out)) out$OBS_STATUS else rep("", nrow(out))
  status[is.na(status)] <- ""
  data.table::set(out, j = "flags_", value = status)
  control <- intersect(c("DATAFLOW", "STRUCTURE", "STRUCTURE_ID", "ACTION"), names(out))
  invisible(lapply(control, function(n) data.table::set(out, j = n, value = NULL)))
  data.table::setcolorder(out, c(s$dimensions$id, "value_", "flags_",
    setdiff(names(out), c(s$dimensions$id, "value_", "flags_"))))
  out
}
.finish_data <- function(out, s, requested, response, filters = NULL) {
  if (.opt("strings_as_factors")) out[, (s$dimensions$id) := lapply(.SD, factor), .SDcols = s$dimensions$id]
  if (!.opt("return_data_table")) data.table::setDF(out)
  class(out) <- c("OECDDataset", class(out))
  attr(out, "RequestedDatasetCode") <- requested
  attr(out, "OECDDatasetCode") <- s$flow$code
  attr(out, "DownloadTime") <- response$time
  attr(out, "SourceURL") <- response$url
  attr(out, "Cached") <- response$cached
  attr(out, "Dimensions") <- s$dimensions$id
  attr(out, "OECDAttributes") <- setdiff(names(out), c(s$dimensions$id, "value_", "flags_"))
  attr(out, "Filters") <- filters
  out
}

#' Import a flat OECD dataset
#' @export
importData <- function(OECDDatasetCode, filters = NULL) {
  selection <- .selection(OECDDatasetCode, filters)
  s <- selection$structure
  q <- .query(s, selection$filters)
  response <- .fetch(q$url, "data")
  on.exit(if (response$cleanup) unlink(response$path), add = TRUE)
  out <- if (response$status == 204L) {
    .warn("OECD returned HTTP 204: no observations for this selection.", "OECDdata_empty")
    .empty_data(s)
  } else tryCatch(.parse_data(response$path, s), error = function(e) {
    .invalidate_response(response)
    stop(e)
  })
  .finish_data(out, s, OECDDatasetCode, response, filters)
}

#' Load a small synthetic example without any network access
#' @export
oecdExample <- function() {
  doc <- xml2::read_xml(system.file("extdata", "structure.xml", package = "OECDdata"), options = "NONET")
  s <- .parse_structure(doc, list(agency = "TEST", id = "DEMO", version = "1.0"))
  .parse_data(system.file("extdata", "example.csv", package = "OECDdata"), s) %>%
    .finish_data(s, "TEST,DEMO,1.0", list(time = as.POSIXct("2024-01-01", tz = "UTC"),
      url = "synthetic example bundled with OECDdata", cached = FALSE))
}
