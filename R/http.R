.clock <- function() as.numeric(Sys.time())
.sleep <- function(seconds) if (seconds > 0) Sys.sleep(seconds)

.throttle <- function(kind) {
  now <- .clock()
  window <- .opt("download_window")
  .state$data_requests <- .state$data_requests[.state$data_requests > now - window]
  if (kind == "data" && length(.state$data_requests) >= .opt("max_downloads"))
    .abort(paste0("Session data-download budget reached (", .opt("max_downloads"),
      " per ", window, " seconds). Reuse cached data or wait. Other sessions may share the IP quota."),
      "OECDdata_rate_limit")
  .sleep(max(0, .opt("min_interval") - (now - .state$last_request)))
  .state$last_request <- .clock()
  if (kind == "data") .state$data_requests <- c(.state$data_requests, .clock())
}

.perform <- function(url, dest, accept) {
  h <- curl::new_handle()
  curl::handle_setopt(h, timeout = .opt("timeout"), connecttimeout = .opt("connect_timeout"),
    followlocation = TRUE, maxredirs = 5L, failonerror = FALSE,
    accept_encoding = "gzip, deflate", useragent = "OECDdata/0.3.1 (R SDMX client)")
  curl::handle_setheaders(h, Accept = accept, `Accept-Language` = .opt("language"))
  # libcurl enforces this when a server advertises Content-Length; also check after transfer.
  if (is.finite(.opt("max_bytes"))) curl::handle_setopt(h, maxfilesize_large = .opt("max_bytes"))
  curl::curl_fetch_disk(url, dest, handle = h)
}

.header <- function(headers, key) {
  if (is.null(headers) || !length(headers)) return(NULL)
  text <- if (is.raw(headers)) rawToChar(headers) else paste(headers, collapse = "\r\n")
  lines <- strsplit(text, "\r?\n", perl = TRUE)[[1L]]
  hits <- lines[grepl(paste0("^", key, ":"), lines, ignore.case = TRUE)]
  if (!length(hits)) NULL else trimws(sub("^[^:]+:", "", utils::tail(hits, 1L)))
}
.retry_after <- function(headers) {
  x <- .header(headers, "Retry-After")
  if (is.null(x)) return(NA_real_)
  if (grepl("^[0-9]+$", x)) return(as.numeric(x))
  when <- tryCatch(as.numeric(curl::parse_date(x)), error = function(e) NA_real_)
  if (length(when) != 1L || is.na(when)) NA_real_ else max(0, when - .clock())
}
.snippet <- function(path, n = 2048L) {
  if (!file.exists(path)) return("")
  con <- file(path, "rb"); on.exit(close(con), add = TRUE)
  bytes <- readBin(con, "raw", n = n)
  # Error bodies can contain NUL or invalid UTF-8, neither should hide the HTTP status.
  text <- rawToChar(bytes[bytes != as.raw(0L)])
  iconv(text, from = "UTF-8", to = "UTF-8", sub = "?")
}
.http_error <- function(status, url, body = "", retry_after = NA_real_) {
  hint <- switch(as.character(status),
    `400` = "Check dimension codes, values and the dataset version.",
    `401` = "The public API normally needs no credentials; check the endpoint and network.",
    `403` = "The service denied access. Check OECD access restrictions and network settings.",
    `404` = "Dataset/version not found or no observations match. Check oecdStructure() and filters.",
    `406` = "The server rejected the response format. Check the endpoint/API version.",
    `413` = "Narrow the time range and dimensions. OECD restricts expensive queries on some datasets.",
    `429` = "OECD rate limit reached. Reuse cached results and wait before retrying.",
    "The service did not return a complete successful response.")
  .abort(paste0("OECD HTTP ", status, ": ", hint,
    if (!is.na(retry_after)) paste0(" Retry-After: ", ceiling(retry_after), " seconds."),
    "\nURL: ", url, if (nzchar(body)) paste0("\nResponse: ", body)),
    c(if (status == 429L) "OECDdata_rate_limit", "OECDdata_http_error"),
    status_code = status, url = url, retry_after = retry_after)
}

.validate_body <- function(path, kind, status) {
  if (status == 204L) return(invisible(NULL))
  # No Windows network-share owner lookup: only size is needed here.
  size <- file.info(path, extra_cols = FALSE)$size
  if (is.na(size) || size == 0) .abort("OECD returned an empty HTTP 200 response.", "OECDdata_parse_error")
  if (size > .opt("max_bytes")) .abort("Response exceeds `max_bytes`.", "OECDdata_size_error")
  start <- sub("^\\s+", "", .snippet(path), perl = TRUE)
  if (grepl("<(html|!doctype html)", start, ignore.case = TRUE))
    .abort("OECD returned an HTML page instead of data (possibly a network access block).", "OECDdata_parse_error")
  if (kind == "data" && grepl("^<", start))
    .abort(paste0("Expected SDMX-CSV but received XML: ", start), "OECDdata_parse_error")
  invisible(NULL)
}

# Raw response caching keeps DownloadTime truthful and avoids serializing XML external pointers.
# Each entry has a checksum and its exact request identity. The manifest is committed last.
.fetch <- function(url, kind = c("metadata", "data"), accept = NULL) {
  kind <- match.arg(kind)
  if (is.null(accept)) accept <- if (kind == "data")
    "application/vnd.sdmx.data+csv;version=2;labels=id" else
    "application/vnd.sdmx.structure+xml;version=2.1"
  identity <- list(schema = 1L, url = url, accept = accept, language = .opt("language"))
  caching <- isTRUE(.opt("cache"))
  offline <- isTRUE(.opt("offline"))
  if (offline && !caching) .abort("Offline mode requires caching.", "OECDdata_cache_error")
  root <- if (caching) .cache_directory() else tempdir()
  hash <- digest::digest(identity, algo = "sha256")
  path <- file.path(root, paste0("oecd-", hash, ".body"))
  meta <- file.path(root, paste0("oecd-", hash, ".rds"))
  ttl <- .opt(if (kind == "data") "cache_ttl" else "metadata_ttl")
  if (caching && file.exists(path) && file.exists(meta) && (!isTRUE(.opt("refresh")) || offline)) {
    saved <- tryCatch(suppressWarnings(readRDS(meta)), error = function(e) NULL)
    valid <- is.list(saved) && identical(saved$identity, identity) &&
      is.numeric(saved$time) && length(saved$time) == 1L && is.finite(saved$time) &&
      is.numeric(saved$status) && length(saved$status) == 1L &&
      saved$status %in% c(200L, 204L) &&
      is.character(saved$checksum) && length(saved$checksum) == 1L &&
      !is.na(saved$checksum)
    if (valid && (offline || .clock() - saved$time <= ttl)) {
      valid <- tryCatch(identical(saved$checksum,
        digest::digest(file = path, algo = "sha256")), error = function(e) FALSE)
      if (valid) {
        .validate_body(path, kind, saved$status)
        return(list(path = path, status = saved$status,
          time = as.POSIXct(saved$time, origin = "1970-01-01", tz = "UTC"),
          cached = TRUE, cleanup = FALSE, url = url))
      }
      if (offline) .abort("The cached response is corrupt; reconnect and refresh it.", "OECDdata_cache_error")
    }
  }
  if (offline) .abort(paste0("No usable cached response for: ", url), "OECDdata_cache_miss")
  .say("OECD ", kind, ": ", url)
  dest <- tempfile("oecd-transfer-", tmpdir = root)
  keep <- FALSE
  on.exit(if (!keep) unlink(dest), add = TRUE)
  attempt <- 0L
  repeat {
    .throttle(kind)
    response <- tryCatch(.perform(url, dest, accept), error = function(e) e)
    if (inherits(response, "error")) {
      if (inherits(response, "curl_error_filesize_exceeded"))
        .abort("Response exceeds `max_bytes`.", "OECDdata_size_error", url = url)
      if (attempt >= .opt("retries")) .abort(paste0("OECD transfer failed: ", conditionMessage(response),
        "\nURL: ", url), "OECDdata_network_error", url = url)
      delay <- min(2^attempt, .opt("max_retry_wait"))
    } else {
      status <- as.integer(response$status_code)
      if (status %in% c(200L, 204L)) break
      delay_header <- .retry_after(response$headers)
      transient <- status %in% c(408L, 429L, 500L, 502L, 503L, 504L)
      delay <- if (is.na(delay_header)) 2^attempt else max(2^attempt, delay_header)
      if (!transient || attempt >= .opt("retries") || delay > .opt("max_retry_wait"))
        .http_error(status, url, .snippet(dest), delay_header)
    }
    .say("Retrying in ", delay, " seconds.")
    .sleep(delay)
    attempt <- attempt + 1L
  }
  .validate_body(dest, kind, status)
  downloaded <- .clock()
  if (caching) {
    manifest <- list(identity = identity, time = downloaded, status = status,
      checksum = digest::digest(file = dest, algo = "sha256"))
    pending <- tempfile("oecd-manifest-", tmpdir = root)
    on.exit(unlink(pending), add = TRUE)
    saveRDS(manifest, pending, version = 2)
    # Removing only these known entry files also permits replacement on Windows.
    unlink(c(meta, path))
    if (!file.rename(dest, path) || !file.rename(pending, meta))
      .abort("Could not commit the response cache.", "OECDdata_cache_error")
    dest <- path
  }
  keep <- TRUE
  list(path = dest, status = status,
    time = as.POSIXct(downloaded, origin = "1970-01-01", tz = "UTC"),
    cached = FALSE, cleanup = !caching, url = url)
}

.url <- function(path, query = list()) {
  base <- sub("/+$", "", .opt("base_url"))
  url <- paste0(base, "/", path)
  if (!length(query)) return(url)
  paste0(url, "?", paste0(curl::curl_escape(names(query)), "=",
    curl::curl_escape(vapply(query, as.character, character(1))), collapse = "&"))
}
.segment <- function(x) {
  # SDMX routing syntax belongs in the path, never in an unescaped query string.
  if (x %in% c("*", "+")) x else curl::curl_escape(x)
}
.structure_path <- function(type, agency, id, version) {
  v2 <- identical(.opt("api_version"), "v2")
  values <- c(if (v2) c("v2", "structure"), type,
    if (!v2 && agency == "*") "all" else agency,
    if (!v2 && id == "*") "all" else id,
    if (!v2 && version == "+") "latest" else version)
  paste(vapply(values, .segment, character(1)), collapse = "/")
}
.invalidate_response <- function(response) {
  # A syntactically bad payload must not poison subsequent cache hits.
  if (!isTRUE(response$cleanup) && grepl("^oecd-[a-f0-9]{64}\\.body$", basename(response$path)))
    unlink(c(response$path, sub("\\.body$", ".rds", response$path)))
  invisible(NULL)
}
.read_structure <- function(type, agency, id, version, references = "all", detail = "referencepartial") {
  result <- .fetch(.url(.structure_path(type, agency, id, version),
    list(references = references, detail = detail)))
  on.exit(if (result$cleanup) unlink(result$path), add = TRUE)
  if (result$status == 204L) .abort("No structural metadata were returned.", "OECDdata_metadata_error")
  doc <- tryCatch(.read_xml(result$path),
    error = function(e) {
      .invalidate_response(result)
      .abort(paste0("Invalid structure XML: ", conditionMessage(e)), "OECDdata_parse_error")
    })
  list(doc = doc, response = result)
}
