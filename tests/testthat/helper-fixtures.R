fixture_path <- function(name) system.file("extdata", name, package = "OECDdata")
fixture_doc <- function() xml2::read_xml(fixture_path("structure.xml"), options = "NONET")
fixture_structure <- function(code = "TEST,DEMO,1.0", doc = fixture_doc())
  OECDdata:::.parse_structure(doc, OECDdata:::.parse_reference(code))
fixture_csv <- function() data.table::fread(fixture_path("example.csv"), colClasses = "character", na.strings = NULL)
write_csv <- function(x) {
  path <- tempfile(fileext = ".csv")
  data.table::fwrite(x, path, na = "", quote = "auto")
  path
}
local_oecd <- function(..., .env = parent.frame()) {
  old <- oecdOptions(...)
  withr::defer(options(old), envir = .env)
}
local_fixture_metadata <- function(doc = fixture_doc(), .env = parent.frame()) {
  testthat::local_mocked_bindings(.read_structure = function(...) list(doc = doc,
    response = list(time = as.POSIXct("2024-01-01", tz = "UTC"), cached = FALSE,
      url = "https://example.invalid/fixture")), .package = "OECDdata", .env = .env)
  local_oecd(api_version = "v2", quiet = TRUE, open_browser = FALSE, dataset = NULL,
    availability = "actual", strings_as_factors = TRUE, return_data_table = FALSE, .env = .env)
}
local_fake_http <- function(statuses = 200L, bodies = "payload", headers = "",
                            .env = parent.frame()) {
  state <- new.env(parent = emptyenv())
  state$calls <- 0L; state$waits <- numeric(); state$now <- 10000
  testthat::local_mocked_bindings(
    .clock = function() state$now,
    .sleep = function(seconds) { state$waits <- c(state$waits, seconds); state$now <- state$now + seconds },
    .throttle = function(kind) invisible(NULL),
    .perform = function(url, dest, accept) {
      state$calls <- state$calls + 1L
      i <- min(state$calls, length(statuses))
      if (inherits(statuses[[i]], "error")) stop(statuses[[i]])
      writeLines(bodies[[min(i, length(bodies))]], dest, useBytes = TRUE)
      list(status_code = statuses[[i]], headers = headers[[min(i, length(headers))]])
    }, .package = "OECDdata", .env = .env)
  root <- tempfile("oecd-test-cache-")
  withr::defer(unlink(root, recursive = TRUE), envir = .env)
  local_oecd(cache = TRUE, cache_dir = root, offline = FALSE, refresh = FALSE,
    cache_ttl = 3600, metadata_ttl = 86400, retries = 2L, max_retry_wait = 60,
    quiet = TRUE, max_bytes = Inf, .env = .env)
  state
}

# Catalogue-only fixtures test alias collisions without observation transfers.
alias_catalogue <- function() {
  data.frame(Agency = c("TEST", "TEST", "OTHER"),
    Dataflow = c("DSD_DEMO@DF_DEMO", "DSD_OTHER@DF_OTHER", "DSD_DEMO@DF_DEMO"),
    Version = c("1.0", "2.0", "3.0"),
    Code = c("TEST,DSD_DEMO@DF_DEMO,1.0", "TEST,DSD_OTHER@DF_OTHER,2.0",
             "OTHER,DSD_DEMO@DF_DEMO,3.0"),
    `Dataset name` = c("Synthetic demo", "Synthetic other", "Second synthetic demo"),
    Link = rep("https://example.invalid/", 3L), check.names = FALSE)
}
alias_doc <- function() {
  doc <- fixture_doc()
  xml2::xml_set_attr(xml2::xml_find_all(doc,
    ".//*[local-name()='Dataflow' and @id='DEMO']"), "id", "DSD_DEMO@DF_DEMO")
  xml2::xml_set_attr(xml2::xml_find_all(doc,
    ".//*[local-name()='Dataflow']/*[local-name()='Ref' and @id='DEMO']"),
    "id", "DSD_DEMO@DF_DEMO")
  doc
}
