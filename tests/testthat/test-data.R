test_that("native CSV parsing retains values, flags and leading-zero identifiers", {
  s <- fixture_structure()
  x <- OECDdata:::.parse_data(fixture_path("example.csv"), s)
  expect_equal(nrow(x), 12L)
  expect_identical(unique(x$GROUP), "00")
  expect_identical(unique(x$UNIT_MULT), "0")
  expect_equal(x$value_[1:3], c(100, 101.5, 102))
  expect_identical(x$flags_, x$OBS_STATUS)
  expect_false(any(c("ACTION", "STRUCTURE", "STRUCTURE_ID") %in% names(x)))
})

test_that("scientific notation and missing measures are handled explicitly", {
  expect_equal(OECDdata:::.numeric_measure(c("1e3", "-2.5E-2", "0")), c(1000, -0.025, 0))
  expect_true(all(is.na(OECDdata:::.numeric_measure(c("", ":", "NA", NA_character_)))))
  expect_error(OECDdata:::.numeric_measure(c("12 apples", "2")), class = "OECDdata_parse_error")
})

test_that("response identity, observation keys and CSV schema are checked", {
  s <- fixture_structure()
  x <- fixture_csv(); x$STRUCTURE_ID <- "TEST:OTHER(1.0)"
  path <- write_csv(x); withr::defer(unlink(path))
  expect_error(OECDdata:::.parse_data(path, s), "identity")
  x <- fixture_csv(); x <- rbind(x, x[1])
  path2 <- write_csv(x); withr::defer(unlink(path2))
  expect_error(OECDdata:::.parse_data(path2, s), "duplicate observation")
  x <- fixture_csv(); x$REF_AREA <- NULL
  path3 <- write_csv(x); withr::defer(unlink(path3))
  expect_error(OECDdata:::.parse_data(path3, s), "missing required")
  x <- fixture_csv(); x$ACTION[1] <- "D"
  path4 <- write_csv(x); withr::defer(unlink(path4))
  expect_error(OECDdata:::.parse_data(path4, s), "deletion")
})

test_that("explicit HTTP 204 returns a typed empty frame, not an HTTP error", {
  local_fixture_metadata()
  path <- tempfile(); file.create(path); withr::defer(unlink(path))
  testthat::local_mocked_bindings(.fetch = function(...) list(path = path, status = 204L,
    cleanup = FALSE, time = Sys.time(), cached = FALSE, url = "https://example.invalid/no-data"), .package = "OECDdata")
  expect_warning(x <- importData("TEST,DEMO,1.0"), class = "OECDdata_empty")
  expect_equal(nrow(x), 0L)
  expect_type(x$value_, "double")
  expect_true(is.factor(x$REF_AREA))
})

test_that("full import uses the correct parser and preserves download provenance", {
  local_fixture_metadata()
  testthat::local_mocked_bindings(.fetch = function(url, ...) list(path = fixture_path("example.csv"),
    status = 200L, cleanup = FALSE, time = as.POSIXct("2024-02-01", tz = "UTC"), cached = TRUE, url = url),
    .package = "OECDdata")
  x <- importData(OECDDatasetCode = "TEST,DEMO", filters = list(FREQ = "M"))
  expect_equal(nrow(x), 12L)
  expect_true(attr(x, "Cached"))
  expect_identical(attr(x, "RequestedDatasetCode"), "TEST,DEMO")
  expect_identical(attr(x, "OECDDatasetCode"), "TEST,DEMO,1.0")
  expect_identical(attr(x, "Filters"), list(FREQ = "M"))
})


test_that("user fread return-type options cannot break the parser", {
  old <- options(datatable.fread.datatable = FALSE)
  withr::defer(options(old))
  x <- OECDdata:::.parse_data(fixture_path("example.csv"), fixture_structure())
  expect_true(data.table::is.data.table(x))
  expect_equal(nrow(x), 12L)
})
