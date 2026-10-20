test_that("dimension names do not require enumerated codes", {
  local_fixture_metadata()
  expect_identical(importDimLabel("TIME_PERIOD", "TEST,DEMO,1.0"), "Time period")
  expect_error(importLabels("TIME_PERIOD", "TEST,DEMO,1.0"), "not backed")
})

test_that("qualified components take precedence over the default dataset", {
  local_fixture_metadata()
  a <- importLabels("REF_AREA", "TEST,DEMO,1.0")
  local_oecd(dataset = "TEST,OTHER,1.0")
  expect_identical(importLabels("TEST,DEMO,1.0::REF_AREA"), a)
  expect_identical(importLabels("TEST,DEMO,1.0::REF_AREA", "TEST,DEMO,1.0"), a)
  expect_error(importLabels("TEST,DEMO,1.0::REF_AREA", "TEST,OTHER,1.0"),
               "Conflicting")
  expect_error(importLabels("TEST,DEMO,1.0::"), "DIMENSION")
})

test_that("cache hits respect the current response size limit", {
  state <- local_fake_http()
  OECDdata:::.fetch("https://example.invalid/size", "data")
  local_oecd(max_bytes = 2)
  expect_error(OECDdata:::.fetch("https://example.invalid/size", "data"),
               class = "OECDdata_size_error")
  local_oecd(offline = TRUE)
  expect_error(OECDdata:::.fetch("https://example.invalid/size", "data"),
               class = "OECDdata_size_error")
  expect_identical(state$calls, 1L)
})

test_that("malformed cache manifests are never returned as valid responses", {
  state <- local_fake_http()
  a <- OECDdata:::.fetch("https://example.invalid/manifest", "data")
  meta <- sub("[.]body$", ".rds", a$path)
  good <- readRDS(meta)
  local_oecd(offline = TRUE)
  for (bad in list(NULL, 404L, c(200L, 204L), "200", NA_integer_)) {
    saved <- good
    saved$status <- bad
    saveRDS(saved, meta)
    expect_error(OECDdata:::.fetch("https://example.invalid/manifest", "data"),
                 class = "OECDdata_cache_miss")
  }
  saved <- good
  saved$time <- Inf
  saveRDS(saved, meta)
  expect_error(OECDdata:::.fetch("https://example.invalid/manifest", "data"),
               class = "OECDdata_cache_miss")
  local_oecd(offline = FALSE)
  expect_false(OECDdata:::.fetch("https://example.invalid/manifest", "data")$cached)
  expect_identical(state$calls, 2L)
})

test_that("XML exclusion booleans and key exclusions cannot invent availability", {
  local_oecd(availability = "actual")
  for (value in c("false", "0")) {
    doc <- fixture_doc()
    region <- xml2::xml_find_first(doc, ".//*[local-name()='CubeRegion']")
    xml2::xml_set_attr(region, "include", value)
    expect_error(OECDdata:::.metabase_one(fixture_structure(doc = doc)),
                 class = "OECDdata_availability_error")
    doc <- fixture_doc()
    key <- xml2::xml_find_first(doc,
      ".//*[local-name()='CubeRegion']/*[local-name()='KeyValue']")
    xml2::xml_set_attr(key, "include", value)
    expect_error(OECDdata:::.metabase_one(fixture_structure(doc = doc)),
                 class = "OECDdata_availability_error")
  }
})

test_that("actual inventories can be described without any enumerated dictionaries", {
  doc <- fixture_doc()
  xml2::xml_remove(xml2::xml_find_all(doc, ".//*[local-name()='Enumeration']"))
  local_fixture_metadata(doc)
  x <- describe("TEST,DEMO,1.0")
  expect_gt(nrow(x), 0L)
  expect_true(all(is.na(x$Dim_val_label)))
  y <- compare("TEST,DEMO,1.0", "TEST,OTHER,1.0")
  expect_true(all(is.na(y$Dim_val_label)))
})

test_that("unsupported CSV structure types cannot bypass identity validation", {
  s <- fixture_structure()
  for (kind in c("unknown", "datastructure", "")) {
    x <- fixture_csv()
    x$STRUCTURE <- kind
    x$STRUCTURE_ID <- "OTHER:WRONG(9.9)"
    path <- write_csv(x)
    withr::defer(unlink(path))
    expect_error(OECDdata:::.parse_data(path, s), class = "OECDdata_parse_error")
  }
  x <- fixture_csv()
  x$DATAFLOW <- "OTHER:WRONG(9.9)"
  path <- write_csv(x)
  withr::defer(unlink(path))
  expect_error(OECDdata:::.parse_data(path, s), "identity")
})

test_that("partial XML component positions cannot silently reorder v1 keys", {
  doc <- fixture_doc()
  nodes <- xml2::xml_find_all(doc,
    ".//*[local-name()='DimensionList']/*[local-name()='Dimension']")
  xml2::xml_set_attr(nodes[[2L]], "position", "1")
  expect_error(fixture_structure(doc = doc), "position")
  xml2::xml_set_attr(nodes[[2L]], "position", "not-a-position")
  expect_error(fixture_structure(doc = doc), "position")
})

test_that("latest versions are pinned before requesting partial references", {
  doc <- fixture_doc()
  calls <- list()
  testthat::local_mocked_bindings(
    .read_structure = function(type, agency, id, version, references = "all",
                               detail = "referencepartial") {
      calls[[length(calls) + 1L]] <<- list(version = version,
        references = references, detail = detail)
      if (version == "+" && detail == "referencepartial")
        stop("referencepartial requires a single artefact")
      list(doc = doc, response = list(time = Sys.time(), url = "fixture"))
    }, .package = "OECDdata")
  expect_identical(oecdDataset("TEST,DEMO"), "TEST,DEMO,1.0")
  expect_identical(calls, list(
    list(version = "+", references = "none", detail = "full"),
    list(version = "1.0", references = "all", detail = "referencepartial")))
})

test_that("CSV rows referring to the resolved DSD are accepted", {
  x <- fixture_csv()
  x$STRUCTURE <- "datastructure"
  x$STRUCTURE_ID <- "TEST:DSD_DEMO(1.0)"
  path <- write_csv(x)
  withr::defer(unlink(path))
  expect_equal(nrow(OECDdata:::.parse_data(path, fixture_structure())), 12L)
})

test_that("libcurl size limits stop without retrying a deterministic failure", {
  err <- structure(list(message = "Maximum file size exceeded", call = NULL),
    class = c("curl_error_filesize_exceeded", "curl_error", "error", "condition"))
  state <- local_fake_http(statuses = list(err))
  expect_error(OECDdata:::.fetch("https://example.invalid/size", "data"),
               class = "OECDdata_size_error")
  expect_identical(state$calls, 1L)
  expect_length(state$waits, 0L)
})
