# No network access, option changes, or filesystem writes at package load time.
.state <- new.env(parent = emptyenv())
.state$last_request <- -Inf
.state$data_requests <- numeric()
.state$cache_dir <- NULL
.state$browser_file_index <- 0L

.defaults <- list(
  api_version = "v2", base_url = "https://sdmx.oecd.org/public/rest",
  language = "en", dataset = NULL, cache = TRUE, cache_dir = NULL,
  cache_ttl = 3600, metadata_ttl = 86400, offline = FALSE, refresh = FALSE,
  timeout = 120, connect_timeout = 20, retries = 3L, max_retry_wait = 60,
  min_interval = 1, max_downloads = 60L, download_window = 3600,
  strings_as_factors = TRUE, return_data_table = FALSE,
  quiet = FALSE, open_browser = interactive(), availability = "actual",
  max_bytes = Inf
)

.opt <- function(name) getOption(paste0("OECDdata.", name), .defaults[[name]])

.abort <- function(message, class = "OECDdata_error", ...) {
  stop(structure(c(list(message = message, call = NULL), list(...)),
                 class = unique(c(class, "OECDdata_error", "error", "condition"))))
}
.warn <- function(message, class = "OECDdata_warning") {
  warning(structure(list(message = message, call = NULL),
                    class = c(class, "warning", "condition")))
}
.say <- function(...) if (!isTRUE(.opt("quiet"))) message(...)
.scalar_string <- function(x, name, empty = FALSE) {
  if (!is.character(x) || length(x) != 1L || is.na(x) || (!empty && !nzchar(x)))
    .abort(paste0("`", name, "` must be one ", if (!empty) "non-empty ", "string."))
  x
}
.flag <- function(x, name) {
  if (!is.logical(x) || length(x) != 1L || is.na(x))
    .abort(paste0("`", name, "` must be TRUE or FALSE."))
  x
}
.validate_option <- function(name, x) {
  if (!(name %in% names(.defaults))) .abort(paste0("Unknown option: ", name))
  if (name %in% c("cache", "offline", "refresh", "strings_as_factors",
                  "return_data_table", "quiet", "open_browser")) .flag(x, name)
  if (name %in% c("cache_ttl", "metadata_ttl", "timeout", "connect_timeout",
                  "retries", "max_retry_wait", "min_interval", "max_downloads",
                  "download_window", "max_bytes")) {
    if (!is.numeric(x) || length(x) != 1L || is.na(x) || x < 0)
      .abort(paste0("`", name, "` must be one non-negative number."))
    if (name %in% c("timeout", "connect_timeout", "download_window", "max_bytes") && x == 0)
      .abort(paste0("`", name, "` must be positive."))
    if (name %in% c("retries", "max_downloads") && (!is.finite(x) || x != floor(x)))
      .abort(paste0("`", name, "` must be a finite non-negative integer."))
    if (name %in% c("timeout", "connect_timeout", "min_interval", "max_retry_wait",
                    "download_window") && !is.finite(x))
      .abort(paste0("`", name, "` must be finite."))
  }
  if (name == "api_version" && !(identical(x, "v2") || identical(x, "v1")))
    .abort("`api_version` must be 'v2' or 'v1'.")
  if (name == "availability" && !(identical(x, "actual") || identical(x, "allowed")))
    .abort("`availability` must be 'actual' or 'allowed'.")
  if (name %in% c("language", "base_url")) .scalar_string(x, name)
  if (name == "base_url" && !grepl("^https://[^?#]+/rest/?$", x))
    .abort("`base_url` must be an HTTPS SDMX endpoint ending in /rest (not /rest/v2).")
  if (name %in% c("dataset", "cache_dir") && !is.null(x)) .scalar_string(x, name)
  invisible(x)
}

#' Read or set OECDdata options
#' @export
oecdOptions <- function(...) {
  args <- list(...)
  if (!length(args)) return(stats_setNames(lapply(names(.defaults), .opt), names(.defaults)))
  if (is.null(names(args)) || anyNA(names(args)) || any(!nzchar(names(args))) || anyDuplicated(names(args)))
    .abort("All options must have unique names.")
  invisible(lapply(names(args), function(n) .validate_option(n, args[[n]])))
  # This explicit configuration setter returns the original namespaced values
  # so callers can restore them with options(old), as with base::options().
  old <- options(stats_setNames(args, paste0("OECDdata.", names(args))))
  invisible(old)
}
# Avoid a dependency on stats for a small names assignment.
stats_setNames <- function(object, nm) { names(object) <- nm; object }

.cache_directory <- function(create = TRUE) {
  root <- .opt("cache_dir")
  if (is.null(root)) {
    if (is.null(.state$cache_dir)) .state$cache_dir <- file.path(tempdir(), "OECDdata-cache")
    root <- .state$cache_dir
  }
  if (create && !dir.exists(root) && !dir.create(root, recursive = TRUE, showWarnings = FALSE))
    .abort(paste0("Cannot create cache directory: ", root), "OECDdata_cache_error")
  root
}

#' Remove only cache files owned by OECDdata
#' @export
clearCache <- function() {
  root <- .cache_directory(FALSE)
  files <- if (dir.exists(root)) list.files(root,
    pattern = "^oecd-[a-f0-9]{64}\\.(body|rds)$", full.names = TRUE) else character()
  status <- if (length(files)) unlink(files) else 0L
  if (status != 0L) .abort("Some cache files could not be removed.", "OECDdata_cache_error")
  invisible(length(files))
}

utils::globalVariables(c(".", ".SD", ".N", "Dim_name", "Dim_val", "Dim_values",
  "Dim_name_label", "Dim_val_label", "Code", "position", "kind", "id",
  "agency", "version", "Version", "label", "value_", "flags_", "TIME_PERIOD"))
