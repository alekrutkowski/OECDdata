test_that("bare dataflows, terminal IDs and compact short codes resolve", {
  cat <- alias_catalogue()[1:2, ]
  testthat::local_mocked_bindings(importDataList = function() cat, .package = "OECDdata")
  expected <- list(agency = "TEST", id = "DSD_DEMO@DF_DEMO", version = "1.0")
  invisible(lapply(c("DSD_DEMO@DF_DEMO", "DF_DEMO", "demo"), function(code)
    expect_identical(OECDdata:::.parse_reference(code), expected)))
})

test_that("ambiguous short codes expose every candidate instead of choosing first", {
  cat <- alias_catalogue()
  testthat::local_mocked_bindings(importDataList = function() cat, .package = "OECDdata")
  err <- tryCatch(OECDdata:::.parse_reference("DEMO"), OECDdata_ambiguous = identity)
  expect_s3_class(err, "OECDdata_ambiguous")
  expect_setequal(err$candidates$Code, cat$Code[c(1, 3)])
  expect_match(conditionMessage(err), "agency/prefix", fixed = TRUE)
  expect_identical(OECDdata:::.parse_reference("DEMO", agency = "test")$agency, "TEST")
})

test_that("agency and prefix selectors are jointly required when appropriate", {
  cat <- alias_catalogue()
  z <- cat[1, ]; z$Dataflow <- "DSD_ALTERNATE@DF_DEMO"; z$Code <- "TEST,DSD_ALTERNATE@DF_DEMO,1.0"
  cat <- rbind(cat, z)
  testthat::local_mocked_bindings(importDataList = function() cat, .package = "OECDdata")
  expect_error(OECDdata:::.parse_reference("DEMO", agency = "TEST"), class = "OECDdata_ambiguous")
  expect_error(OECDdata:::.parse_reference("DEMO", prefix = "DSD_DEMO"), class = "OECDdata_ambiguous")
  expect_identical(OECDdata:::.parse_reference("DEMO", agency = "TEST", prefix = "DSD_DEMO")$id,
                   "DSD_DEMO@DF_DEMO")
})

test_that("literal exact IDs precede aliases and terminal IDs precede compact codes", {
  cat <- alias_catalogue()[1:2, ]
  cat$Dataflow[[2L]] <- "DEMO"; cat$Code[[2L]] <- "TEST,DEMO,2.0"
  testthat::local_mocked_bindings(importDataList = function() cat, .package = "OECDdata")
  expect_identical(OECDdata:::.parse_reference("DEMO")$id, "DEMO")
  cat$Dataflow[[2L]] <- "DSD_OTHER@DF_DF_DEMO"; cat$Code[[2L]] <- "TEST,DSD_OTHER@DF_DF_DEMO,2.0"
  expect_identical(OECDdata:::.parse_reference("DF_DEMO")$id, "DSD_DEMO@DF_DEMO")
})

test_that("short codes are exact conventions, not fuzzy searches or legacy mappings", {
  cat <- alias_catalogue()[1:2, ]
  testthat::local_mocked_bindings(importDataList = function() cat, .package = "OECDdata")
  expect_error(OECDdata:::.parse_reference("DEM"), "Unknown dataflow")
  expect_error(OECDdata:::.parse_reference("MEI"), "legacy OECD.Stat")
  expect_error(OECDdata:::.parse_reference("DEMO", agency = "MISSING"), "No match")
  expect_error(OECDdata:::.parse_reference("DEMO", prefix = "MISSING"), "No match")
})

test_that("explicit historical versions are not filtered out by a current catalogue", {
  cat <- alias_catalogue()[1:2, ]
  testthat::local_mocked_bindings(importDataList = function() cat, .package = "OECDdata")
  expect_identical(OECDdata:::.parse_reference("DEMO", version = "0.9")$version, "0.9")
  expect_identical(OECDdata:::.parse_reference("DEMO", version = "latest")$version, "+")
  expect_error(OECDdata:::.parse_reference("DEMO", version = 1), "string")
  expect_error(OECDdata:::.parse_reference("DEMO", version = "draft"), "Version")
})

test_that("canonical references bypass the catalogue and reject conflicting selectors", {
  testthat::local_mocked_bindings(importDataList = function() stop("Unexpected catalogue request"),
                                  .package = "OECDdata")
  ref <- OECDdata:::.parse_reference("TEST,DSD_DEMO@DF_DEMO", agency = "test",
    prefix = "dsd_demo", version = "1.0")
  expect_identical(ref, list(agency = "TEST", id = "DSD_DEMO@DF_DEMO", version = "1.0"))
  expect_error(OECDdata:::.parse_reference("TEST,DEMO", agency = "OTHER"), "Conflicting agency")
  expect_error(OECDdata:::.parse_reference("TEST,DSD_DEMO@DF_DEMO", prefix = "WRONG"), "Conflicting dataflow prefix")
  expect_error(OECDdata:::.parse_reference("TEST,DEMO,1.0", version = "2.0"), "Conflicting version")
  expect_error(OECDdata:::.parse_reference("TEST,DEMO,latest", version = "1.0"), "Conflicting version")
  expect_identical(OECDdata:::.parse_reference("TEST,DEMO,", version = "1.0")$version, "1.0")
})

test_that("dataset-selector blocks are removed from dimension filters", {
  x <- OECDdata:::.split_filters(list(.dataset = list(agency = "TEST", version = "1.0"),
    REF_AREA = "USA", FREQ = "M"))
  expect_identical(x$selectors, list(agency = "TEST", version = "1.0"))
  expect_identical(x$filters, list(REF_AREA = "USA", FREQ = "M"))
  expect_null(OECDdata:::.split_filters(list(.dataset = list(agency = "TEST")))$filters)
  expect_identical(OECDdata:::.split_filters(list(.DATASET = list(AGENCY = "TEST")))$selectors,
                   list(agency = "TEST"))
})

test_that("invalid selector blocks fail before metadata retrieval", {
  testthat::local_mocked_bindings(.read_structure = function(...) stop("Unexpected network"),
    importDataList = function() stop("Unexpected catalogue"), .package = "OECDdata")
  invalid <- list(list(.dataset = list()), list(.dataset = "TEST"), list(.dataset = NULL),
    list(.dataset = list(agency = c("TEST", "OTHER"))), list(.dataset = list(agency = NULL)),
    list(.dataset = list(agency = "TEST", Agency = "OTHER")),
    list(.dataset = list(agency = "TEST"), .DATASET = list(agency = "OTHER")),
    list(.dataset = list(unknown = "TEST")), list(.dataset = list(version = "draft")),
    list(.dataset = list(prefix = "DSD_DEMO@DF_DEMO")))
  invisible(lapply(invalid, function(f)
    expect_error(importData("DEMO", f), class = "OECDdata_error")))
})

test_that("reserved dataset selectors never appear in either transport's data query", {
  local_fixture_metadata(alias_doc())
  invisible(lapply(c("v1", "v2"), function(v) {
    old <- oecdOptions(api_version = v); on.exit(options(old))
    q <- oecdQuery("demo", list(.dataset = list(agency = "TEST", prefix = "DSD_DEMO", version = "1.0"),
      REF_AREA = "USA", TIME_PERIOD = c("2024-01", "2024-02")))
    expect_false(grepl("dataset", as.character(q), fixed = TRUE))
    expect_false(grepl("c%5Bagency", as.character(q), fixed = TRUE))
    expect_identical(attr(q, "OECDDatasetCode"), "TEST,DSD_DEMO@DF_DEMO,1.0")
    expect_identical(attr(q, "RequestedDatasetCode"), "demo")
    expect_match(as.character(q), "DSD_DEMO", fixed = TRUE)
  }))
})

test_that("canonical and shorthand queries produce identical cache identities", {
  local_fixture_metadata(alias_doc())
  f <- list(REF_AREA = "USA", FREQ = "M")
  a <- oecdQuery("DEMO", f)
  b <- oecdQuery("TEST,DSD_DEMO@DF_DEMO,1.0", f)
  c <- oecdQuery("DF_DEMO", c(list(.dataset = list(agency = "TEST")), f))
  expect_identical(as.character(a), as.character(b))
  expect_identical(as.character(a), as.character(c))
  expect_identical(attr(a, "Accept"), attr(c, "Accept"))
})

test_that("metadata helpers accept the canonical reference from oecdDataset", {
  local_fixture_metadata(alias_doc())
  testthat::local_mocked_bindings(.fetch = function(...) stop("Unexpected observation download"),
                                  .package = "OECDdata")
  ref <- oecdDataset("DEMO", agency = "TEST", prefix = "DSD_DEMO", version = "1.0")
  expect_identical(ref, "TEST,DSD_DEMO@DF_DEMO,1.0")
  expect_identical(oecdStructure("DEMO")$flow$code, ref)
  expect_identical(importLabels("REF_AREA", dataset = "DEMO"), importLabels("REF_AREA", dataset = ref))
  expect_identical(importLabels("DEMO::REF_AREA"), importLabels("REF_AREA", dataset = ref))
  expect_true(all(importMetabase("DEMO")$Code == "DEMO"))
  expect_true("DEMO" %in% names(describe("DEMO")))
})

test_that("full imports retain original selection and resolved identity separately", {
  local_fixture_metadata(alias_doc())
  csv <- fixture_csv(); csv[, STRUCTURE_ID := "TEST:DSD_DEMO@DF_DEMO(1.0)"]
  path <- write_csv(csv); withr::defer(unlink(path))
  testthat::local_mocked_bindings(.fetch = function(url, kind) list(path = path, cleanup = FALSE,
    status = 200L, time = as.POSIXct("2024-01-01", tz = "UTC"), url = url, cached = FALSE),
    .package = "OECDdata")
  f <- list(.dataset = list(agency = "TEST"), REF_AREA = c("USA", "FRA"), FREQ = "M")
  x <- importData(OECDDatasetCode = "demo", filters = f)
  expect_identical(class(x), c("OECDDataset", "data.frame"))
  expect_identical(attr(x, "RequestedDatasetCode"), "demo")
  expect_identical(attr(x, "OECDDatasetCode"), "TEST,DSD_DEMO@DF_DEMO,1.0")
  expect_identical(attr(x, "Filters"), f)
  expect_equal(nrow(x), 12L)
})

test_that("catalogues advertise only unambiguous shorthand tokens", {
  local_fixture_metadata(alias_doc())
  cat <- importDataList()
  expect_identical(cat$ShortCode[cat$Dataflow == "DSD_DEMO@DF_DEMO"], "DEMO")
  expect_identical(cat$DataflowPrefix[cat$ShortCode == "DEMO"], "DSD_DEMO")
  expect_false(any(grepl("Data subgroup", names(cat), fixed = TRUE)))
  expect_identical(OECDdata:::.catalogue_short_codes(c("DSD_A@DF_X", "DSD_B@DF_X")),
                   c(NA_character_, NA_character_))
  expect_identical(OECDdata:::.catalogue_short_codes(c("DSD_A@DF_X", "X")),
                   c(NA_character_, NA_character_))
  expect_identical(OECDdata:::.catalogue_short_codes(c("DF_X", "DF_Y")), c("X", "Y"))
  expect_identical(OECDdata:::.catalogue_short_codes(c("DSD_A@DF_X", "DSD_A@DF_X")),
                   c(NA_character_, NA_character_))
})

test_that("short codes do not acquire hidden country, frequency or measure defaults", {
  local_fixture_metadata(alias_doc())
  q <- oecdQuery("DEMO", list(.dataset = list(agency = "TEST")))
  expect_false(grepl("c%5B", q, fixed = TRUE))
  q <- oecdQuery("DEMO", list(.dataset = list(agency = "TEST"), REF_AREA = "USA"))
  expect_match(q, "c%5BREF_AREA%5D=USA", fixed = TRUE)
  expect_false(grepl("c%5BFREQ%5D", q, fixed = TRUE))
  expect_false(grepl("c%5BMEASURE%5D", q, fixed = TRUE))
})
