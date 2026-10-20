.period <- function(x) {
  x <- as.character(x)
  if (!length(x) || anyNA(x) || any(!nzchar(x))) .abort("TIME_PERIOD must contain non-missing periods.")
  # Normalize aliases before finding bounds; never compare unpadded month strings.
  x <- sub("^([0-9]{4})-A1$", "\\1", x)
  x <- sub("^([0-9]{4})-M([0-9]{2})$", "\\1-\\2", x)
  kinds <- vapply(x, function(p) {
    if (grepl("^[0-9]{4}$", p)) return("annual")
    if (grepl("^[0-9]{4}-Q[1-4]$", p)) return("quarterly")
    if (grepl("^[0-9]{4}-S[1-2]$", p)) return("semiannual")
    if (grepl("^[0-9]{4}-W(0[1-9]|[1-4][0-9]|5[0-3])$", p)) return("weekly")
    if (grepl("^[0-9]{4}-(0[1-9]|1[0-2])$", p)) return("monthly")
    if (grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", p) &&
        !is.na(suppressWarnings(as.Date(p, format = "%Y-%m-%d"))) &&
        format(as.Date(p, format = "%Y-%m-%d"), "%Y-%m-%d") == p) return("daily")
    .abort(paste0("Invalid or unsupported TIME_PERIOD: ", p,
      ". Use YYYY, YYYY-Q1, YYYY-S1, YYYY-W01, YYYY-MM or YYYY-MM-DD."))
  }, character(1))
  if (length(unique(kinds)) != 1L) .abort("Use one time-period granularity within a filter.")
  c(start = min(x), end = max(x))
}

.filters <- function(filters, s) {
  if (is.null(filters)) return(list())
  if (!is.list(filters) || !length(filters)) .abort("`filters` must be NULL or a non-empty named list.")
  nm <- names(filters)
  if (is.null(nm) || anyNA(nm) || any(!nzchar(nm)) || anyDuplicated(toupper(nm)))
    .abort("All filter dimensions must have unique, non-empty names.")
  dims <- s$dimensions$id
  at <- match(toupper(nm), toupper(dims))
  if (anyNA(at)) .abort(paste0("Unknown filter dimension(s): ", paste(nm[is.na(at)], collapse = ", "),
    ". Available: ", paste(dims, collapse = ", ")))
  names(filters) <- dims[at]
  filters <- lapply(names(filters), function(n) {
    x <- filters[[n]]
    if ((!is.character(x) && !is.numeric(x) && !is.factor(x)) || !is.null(dim(x)) || is.complex(x) || !length(x) || anyNA(x))
      .abort(paste0("Filter ", n, " must be a non-empty character or numeric vector without NA."))
    x <- unique(as.character(x))
    if (identical(x, "")) { .warn(paste0(n, " = '' selects all values.")); return(NULL) }
    if (any(!nzchar(x))) .abort(paste0("Do not mix empty and non-empty codes in ", n, "."))
    if (n %in% s$dimensions[kind == "TimeDimension"]$id) return(.period(x))
    if (any(grepl("[,+*:&?/#=[:space:]]", x)))
      .abort(paste0("Reserved SDMX filter characters in ", n, "; supply individual literal codes."))
    if (.opt("api_version") == "v1" && any(grepl(".", x, fixed = TRUE)))
      .abort("Dimension codes containing dots require api_version = 'v2'.")
    dictionary <- s$labels[[n]]
    if (!is.null(dictionary) && nrow(dictionary)) {
      invalid <- setdiff(x, dictionary$code)
      if (length(invalid)) .abort(paste0("Invalid code(s) for ", n, ": ", paste(invalid, collapse = ", "),
        ". Inspect importLabels('", n, "', dataset = 'AGENCY,DATAFLOW,VERSION')."))
    }
    sort(x)
  }) %>% stats_setNames(names(filters))
  filters[!vapply(filters, is.null, logical(1))]
}

.query <- function(s, filters) {
  f <- .filters(filters, s)
  flow <- s$flow
  v2 <- identical(.opt("api_version"), "v2")
  time_id <- s$dimensions[kind == "TimeDimension"]$id
  time_filter <- if (length(time_id)) f[[time_id[[1L]]]] else NULL
  dims <- s$dimensions[kind != "TimeDimension"]$id
  if (v2) {
    path <- paste(c("v2", "data", "dataflow", vapply(c(flow$agency, flow$id, flow$version),
      .segment, character(1)), "*"), collapse = "/")
    chosen <- intersect(dims, names(f))
    query <- lapply(chosen, function(n) paste(f[[n]], collapse = ","))
    # paste0("c[", character(), "]") is length one on some R versions.
    # Never assign that name to a zero-length query (unfiltered requests).
    if (length(chosen)) names(query) <- paste0("c[", chosen, "]")
    if (!is.null(time_filter)) query[[paste0("c[", time_id[[1L]], "]")]] <-
      paste0("ge:", time_filter[["start"]], "+le:", time_filter[["end"]])
    query <- c(query, list(attributes = "dsd", measures = "all", dimensionAtObservation = "AllDimensions"))
  } else {
    key <- vapply(dims, function(n) paste(curl::curl_escape(as.character(f[[n]])), collapse = "+"), character(1))
    key <- if (all(!nzchar(key))) "all" else paste(key, collapse = ".")
    flow_key <- paste(vapply(c(flow$agency, flow$id, flow$version), .segment, character(1)), collapse = ",")
    path <- paste("data", flow_key, key, sep = "/")
    query <- list(dimensionAtObservation = "AllDimensions")
    if (!is.null(time_filter)) query <- c(query,
      list(startPeriod = time_filter[["start"]], endPeriod = time_filter[["end"]]))
  }
  list(url = .url(path, query), filters = f, structure = s)
}

#' Build an encoded data request without downloading observations
#' @export
oecdQuery <- function(OECDDatasetCode, filters = NULL) {
  selection <- .selection(OECDDatasetCode, filters)
  q <- .query(selection$structure, selection$filters)
  out <- q$url
  attr(out, "Accept") <- "application/vnd.sdmx.data+csv;version=2;labels=id"
  attr(out, "OECDDatasetCode") <- q$structure$flow$code
  attr(out, "RequestedDatasetCode") <- OECDDatasetCode
  out
}
