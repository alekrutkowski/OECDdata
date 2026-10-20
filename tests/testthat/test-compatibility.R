test_that("the familiar workflow uses OECD-native names and expected defaults", {
  expected <- list(importData = c("OECDDatasetCode", "filters"),
    importDataList = character(), importLabels = "OECDDimCode",
    importDimLabel = "OECDDimCode", importMetabase = "OECDDatasetCode",
    describe = c("OECDDatasetCode", "import_labels", "wide", "import_dim_labels"),
    compare = c("...", "import_labels", "import_dim_labels"), find = "...",
    browseDataList = "subs", as.OECDDataList = c("x", "SearchCriteria", "..."))
  expect_true(all(names(expected) %in% getNamespaceExports("OECDdata")))
  invisible(lapply(names(expected), function(n) {
    got <- names(formals(getExportedValue("OECDdata", n)))
    if (is.null(got)) got <- character()
    expect_identical(utils::head(got, length(expected[[n]])), expected[[n]])
  }))
  expect_setequal(getNamespaceExports("OECDdata"), c(names(expected),
    "oecdDataset", "oecdStructure", "oecdQuery", "oecdOptions", "clearCache", "oecdExample"))
  expect_null(formals(importData)$filters)
  expect_identical(formals(describe)$import_labels, quote(!wide))
  expect_identical(formals(describe)$wide, FALSE)
  expect_identical(formals(describe)$import_dim_labels, TRUE)
  expect_identical(formals(compare)$import_labels, TRUE)
})

test_that("flat output retains familiar types, classes and metadata", {
  local_oecd(strings_as_factors = TRUE, return_data_table = FALSE, quiet = TRUE)
  x <- oecdExample()
  expect_identical(class(x), c("OECDDataset", "data.frame"))
  expect_s3_class(x, "data.frame")
  expect_false(data.table::is.data.table(x))
  expect_type(x$value_, "double")
  expect_type(x$flags_, "character")
  expect_true(all(vapply(x[attr(x, "Dimensions")], is.factor, logical(1))))
  expect_identical(as.character(unique(x$GROUP)), "00")
  expect_identical(attr(x, "RequestedDatasetCode"), "TEST,DEMO,1.0")
  expect_s3_class(attr(x, "DownloadTime"), "POSIXct")
  expect_identical(x$flags_, x$OBS_STATUS)
})

test_that("native data.table mode is opt-in and returns independent objects", {
  local_oecd(return_data_table = TRUE, strings_as_factors = FALSE, quiet = TRUE)
  x <- oecdExample(); y <- oecdExample()
  expect_true(data.table::is.data.table(x))
  expect_type(x$REF_AREA, "character")
  x[, value_ := 0]
  expect_true(any(y$value_ != 0))
})

test_that("labels and catalogue use the compatible columns and classes", {
  local_fixture_metadata()
  x <- importLabels(OECDDimCode = "REF_AREA", dataset = "TEST,DEMO,1.0")
  expect_identical(names(x), c("REF_AREA", "REF_AREA_labels"))
  expect_identical(class(x), c("OECDLabels", "data.frame"))
  expect_true(is.factor(x$REF_AREA))
  expect_type(importDimLabel("REF_AREA", "TEST,DEMO,1.0"), "character")
  cat <- importDataList()
  expect_identical(class(cat), c("OECDDataList", "data.frame"))
  expect_true(all(c("Code", "Dataset name", "Link", "Agency", "Version") %in% names(cat)))
  expect_true(all(c("ShortCode", "DataflowPrefix") %in% names(cat)))
  expect_s3_class(as.OECDDataList(as.data.frame(cat)), "OECDDataList")
})

test_that("metabase, describe and compare report marginal membership", {
  local_fixture_metadata()
  a <- "TEST,DEMO,1.0"; b <- "TEST,OTHER,1.0"
  m <- importMetabase(a)
  expect_identical(names(m), c("Code", "Dim_name", "Dim_val"))
  expect_false("ZZZ" %in% m$Dim_val)
  expect_false("TIME_PERIOD" %in% m$Dim_name)
  d <- describe(a)
  expect_identical(names(d), c("Dim_name", "Dim_name_label", "Dim_val", "Dim_val_label", a))
  expect_true(all(d[[a]]))
  expect_identical(attr(d, "Availability"), "actual")
  w <- describe(a, wide = TRUE)
  expect_true("Dim_values" %in% names(w))
  expect_false("Dim_val_label" %in% names(w))
  expect_error(describe(a, wide = TRUE, import_labels = TRUE), "requires")
  z <- compare(a, b, import_labels = FALSE, import_dim_labels = FALSE)
  expect_identical(names(z), c("Dim_name", "Dim_val", a, b))
  expect_true(z[Dim_name == "REF_AREA" & Dim_val == "USA"][[a]])
  expect_false(z[Dim_name == "REF_AREA" & Dim_val == "DEU"][[a]])
  expect_true(z[Dim_name == "REF_AREA" & Dim_val == "DEU"][[b]])
  expect_false(anyNA(z[[a]]))
  expect_error(compare(a, a), "two different")
})


test_that("wide descriptions handle comma-containing canonical OECD references", {
  local_fixture_metadata()
  code <- "TEST,DEMO,1.0"
  w <- describe(code, wide = TRUE)
  expect_identical(names(w), c("Dim_name", "Dim_name_label", "Dim_values", code))
  expect_true(all(w[[code]]))
  expect_false(anyDuplicated(w$Dim_name) > 0L)
  expect_true(all(nzchar(w$Dim_values)))
})
