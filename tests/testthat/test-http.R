test_that("cache hits preserve download times and need no HTTP call", {
  state <- local_fake_http()
  a <- OECDdata:::.fetch("https://example.invalid/a", "data")
  state$now <- state$now + 10
  b <- OECDdata:::.fetch("https://example.invalid/a", "data")
  expect_identical(state$calls, 1L)
  expect_false(a$cached); expect_true(b$cached)
  expect_identical(a$time, b$time)
  expect_identical(readLines(a$path), "payload")
})

test_that("offline mode ignores expiry but never ignores corruption", {
  state <- local_fake_http()
  a <- OECDdata:::.fetch("https://example.invalid/a", "data")
  state$now <- state$now + 100000
  local_oecd(offline = TRUE)
  expect_true(OECDdata:::.fetch("https://example.invalid/a", "data")$cached)
  expect_identical(state$calls, 1L)
  expect_error(OECDdata:::.fetch("https://example.invalid/missing", "data"), class = "OECDdata_cache_miss")
  writeLines("corrupt", a$path)
  expect_error(OECDdata:::.fetch("https://example.invalid/a", "data"), "corrupt")
})

test_that("expiry, refresh and response-language changes invalidate cache reuse", {
  state <- local_fake_http()
  OECDdata:::.fetch("https://example.invalid/a", "data")
  state$now <- state$now + 4000
  OECDdata:::.fetch("https://example.invalid/a", "data")
  expect_identical(state$calls, 2L)
  local_oecd(refresh = TRUE)
  OECDdata:::.fetch("https://example.invalid/a", "data")
  expect_identical(state$calls, 3L)
  local_oecd(refresh = FALSE, language = "fr")
  OECDdata:::.fetch("https://example.invalid/a", "data")
  expect_identical(state$calls, 4L)
})

test_that("transient failures retry and respect Retry-After", {
  state <- local_fake_http(statuses = c(429L, 200L), headers = c("Retry-After: 5\r\n", ""))
  a <- OECDdata:::.fetch("https://example.invalid/a", "data")
  expect_identical(state$calls, 2L)
  expect_identical(state$waits, 5)
  expect_identical(a$status, 200L)
})

test_that("excessive Retry-After values fail without an early retry", {
  state <- local_fake_http(statuses = 429L, headers = "Retry-After: 3600\r\n")
  expect_error(OECDdata:::.fetch("https://example.invalid/a", "data"), class = "OECDdata_rate_limit")
  expect_identical(state$calls, 1L)
  expect_length(state$waits, 0L)
})

test_that("HTTP dates and numeric Retry-After headers are supported", {
  testthat::local_mocked_bindings(.clock = function() as.numeric(as.POSIXct("2015-10-21 07:27:00", tz = "UTC")),
    .package = "OECDdata")
  expect_equal(OECDdata:::.retry_after("Retry-After: Wed, 21 Oct 2015 07:28:00 GMT\r\n"), 60)
  expect_equal(OECDdata:::.retry_after("Retry-After: 12\r\n"), 12)
  expect_true(is.na(OECDdata:::.retry_after("Not-Retry: 1\r\n")))
})

test_that("404 and other permanent errors are not silently returned as empty data", {
  state <- local_fake_http(statuses = 404L, bodies = "not found")
  error <- tryCatch(OECDdata:::.fetch("https://example.invalid/a", "data"), error = identity)
  expect_s3_class(error, "OECDdata_http_error")
  expect_identical(error$status_code, 404L)
  expect_identical(state$calls, 1L)
  expect_length(list.files(oecdOptions()$cache_dir), 0L)
})

test_that("network failures retry only the configured number of times", {
  state <- local_fake_http(statuses = list(simpleError("connection failed")))
  expect_error(OECDdata:::.fetch("https://example.invalid/a", "data"), class = "OECDdata_network_error")
  expect_identical(state$calls, 3L)
})

test_that("HTML blocks, XML errors and oversized responses never enter the cache", {
  state <- local_fake_http(bodies = "<html>Access denied</html>")
  expect_error(OECDdata:::.fetch("https://example.invalid/a", "data"), "HTML")
  expect_length(list.files(oecdOptions()$cache_dir), 0L)
  path <- tempfile(); withr::defer(unlink(path))
  writeLines("<Error>Bad request</Error>", path)
  expect_error(OECDdata:::.validate_body(path, "data", 200L), "XML")
  local_oecd(max_bytes = 2)
  expect_error(OECDdata:::.validate_body(path, "metadata", 200L), class = "OECDdata_size_error")
})

test_that("clearCache only deletes owned cache entries", {
  state <- local_fake_http()
  OECDdata:::.fetch("https://example.invalid/a", "data")
  foreign <- file.path(oecdOptions()$cache_dir, "leave-me.txt")
  writeLines("user file", foreign)
  expect_equal(clearCache(), 2L)
  expect_true(file.exists(foreign))
})

test_that("invalid parsed payloads can be evicted rather than poisoning cache hits", {
  state <- local_fake_http()
  a <- OECDdata:::.fetch("https://example.invalid/a", "data")
  OECDdata:::.invalidate_response(a)
  expect_false(file.exists(a$path))
  expect_length(list.files(oecdOptions()$cache_dir), 0L)
})

test_that("the local download budget is explicit and separate from metadata", {
  local_oecd(max_downloads = 0L, min_interval = 0)
  state <- OECDdata:::.state
  old <- list(last_request = state$last_request, data_requests = state$data_requests)
  withr::defer({ state$last_request <- old$last_request; state$data_requests <- old$data_requests })
  expect_error(OECDdata:::.throttle("data"), class = "OECDdata_rate_limit")
  expect_no_error(OECDdata:::.throttle("metadata"))
})
