test_that("v2 uses encoded component filters and an exact resolved version", {
  local_oecd(api_version = "v2", base_url = "https://sdmx.oecd.org/public/rest")
  q <- OECDdata:::.query(fixture_structure(), list(ref_area = c("USA", "FRA"),
    GROUP = "00", TIME_PERIOD = c("2024-06", "2024-01", "2024-03")))$url
  expect_match(q, "/rest/v2/data/dataflow/TEST/DEMO/1.0/*?", fixed = TRUE)
  expect_match(q, "c%5BREF_AREA%5D=FRA%2CUSA", fixed = TRUE)
  expect_match(q, "c%5BGROUP%5D=00", fixed = TRUE)
  expect_match(q, "ge%3A2024-01%2Ble%3A2024-06", fixed = TRUE)
  expect_match(q, "attributes=dsd", fixed = TRUE)
  expect_false(grepl("startPeriod=", q, fixed = TRUE))
})

test_that("v1 orders positional keys by the DSD, not by list order", {
  local_oecd(api_version = "v1", base_url = "https://sdmx.oecd.org/public/rest")
  q <- OECDdata:::.query(fixture_structure(), list(GROUP = "00", REF_AREA = c("USA", "FRA"),
    FREQ = "M", TIME_PERIOD = 2020:2024))$url
  expect_match(q, "/data/TEST,DEMO,1.0/M.FRA+USA..00?", fixed = TRUE)
  expect_match(q, "startPeriod=2020&endPeriod=2024", fixed = TRUE)
  expect_match(OECDdata:::.query(fixture_structure(), NULL)$url, "/all?", fixed = TRUE)
})

test_that("query construction rejects ambiguous and malformed filters", {
  s <- fixture_structure()
  expect_error(OECDdata:::.filters(list(), s), "non-empty")
  expect_error(OECDdata:::.filters(list("USA"), s), "names")
  expect_error(OECDdata:::.filters(list(REF_AREA = NA_character_), s), "without NA")
  expect_error(OECDdata:::.filters(list(REF_AREA = "USA", ref_area = "FRA"), s), "unique")
  expect_error(OECDdata:::.filters(list(UNKNOWN = "USA"), s), "Unknown")
  expect_error(OECDdata:::.filters(list(REF_AREA = "USA+FRA"), s), "Reserved")
  expect_error(OECDdata:::.filters(list(REF_AREA = "BOGUS"), s), "Invalid code")
  expect_error(OECDdata:::.filters(list(REF_AREA = c("", "USA")), s), "mix")
  expect_error(OECDdata:::.filters(list(REF_AREA = TRUE), s), "vector")
  expect_error(OECDdata:::.filters(list(REF_AREA = matrix("USA")), s), "vector")
  expect_warning(z <- OECDdata:::.filters(list(REF_AREA = ""), s), "selects all")
  expect_length(z, 0)
})

test_that("time bounds have one granularity and inclusive min/max semantics", {
  expect_identical(OECDdata:::.period(c("2024-Q4", "2022-Q1")), c(start = "2022-Q1", end = "2024-Q4"))
  expect_identical(OECDdata:::.period(c("2024-M12", "2024-M02")), c(start = "2024-02", end = "2024-12"))
  expect_identical(OECDdata:::.period("2024-A1"), c(start = "2024", end = "2024"))
  expect_identical(OECDdata:::.period("2024-02-29"), c(start = "2024-02-29", end = "2024-02-29"))
  expect_error(OECDdata:::.period("2023-02-29"), "Invalid")
  expect_error(OECDdata:::.period("2024-13"), "Invalid")
  expect_error(OECDdata:::.period(c("2024", "2024-01")), "granularity")
  expect_error(OECDdata:::.period("2024-W54"), "Invalid")
})

test_that("the metadata query builder does not download observations", {
  local_fixture_metadata()
  testthat::local_mocked_bindings(.fetch = function(...) stop("Unexpected observation transfer"), .package = "OECDdata")
  q <- oecdQuery("TEST,DEMO", list(REF_AREA = "USA"))
  expect_type(q, "character")
  expect_identical(attr(q, "OECDDatasetCode"), "TEST,DEMO,1.0")
  expect_match(attr(q, "Accept"), "csv", fixed = TRUE)
})

test_that("bare dataflow names resolve only when unique", {
  local_fixture_metadata()
  expect_identical(OECDdata:::.parse_reference("demo")$id, "DEMO")
  expect_identical(OECDdata:::.parse_reference("TEST,DEMO,latest")$version, "+")
  expect_error(OECDdata:::.parse_reference("https://example.org/data"), "not a URL")
  expect_error(OECDdata:::.parse_reference("TEST,DEMO,not-a-version"), "Version")
  expect_error(OECDdata:::.parse_reference("missing"), "Unknown dataflow")
  x <- importDataList(); y <- x[1, ]; y$Agency <- "OTHER"
  y$Code <- "OTHER,DEMO,1.0"
  testthat::local_mocked_bindings(importDataList = function() rbind(x, y), .package = "OECDdata")
  expect_error(OECDdata:::.parse_reference("DEMO"), class = "OECDdata_ambiguous")
})


test_that("literal dots in codes are safe in v2 and rejected in v1 keys", {
  s <- fixture_structure()
  s$labels$GROUP <- data.table::data.table(code = "a.b", label = "Dotted code")
  local_oecd(api_version = "v2")
  expect_match(OECDdata:::.query(s, list(GROUP = "a.b"))$url,
               "c%5BGROUP%5D=a.b", fixed = TRUE)
  local_oecd(api_version = "v1")
  expect_error(OECDdata:::.query(s, list(GROUP = "a.b")), "require")
})


test_that("v2 unrestricted queries have no accidental empty component selector", {
  local_oecd(api_version = "v2")
  s <- fixture_structure()
  q <- OECDdata:::.query(s, NULL)$url
  expect_false(grepl("c%5B", q, fixed = TRUE))
  expect_match(q, "attributes=dsd", fixed = TRUE)
  q2 <- OECDdata:::.query(s, list(TIME_PERIOD = c("2024-01", "2024-02")))$url
  expect_false(grepl("c%5BREF_AREA%5D", q2, fixed = TRUE))
  expect_match(q2, "c%5BTIME_PERIOD%5D=", fixed = TRUE)
})
