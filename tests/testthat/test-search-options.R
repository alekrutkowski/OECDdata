test_that("find uses same-field AND, case-insensitive regex and minus exclusions", {
  x <- data.frame(Code = c("GDP_MAIN", "OTHER", "GDP_QUARTERLY", "GDP_MAIN"),
    `Dataset name` = c("National accounts", "GDP annual main", "GDP quarterly main", "Quarterly accounts"),
    Link = rep("https://example.invalid/", 4), check.names = FALSE)
  testthat::local_mocked_bindings(importDataList = function() as.OECDDataList(x), .package = "OECDdata")
  out <- OECDdata::find(gdp, main, -quarterly)
  # The fourth row passes in Code even though its title contains the exclusion.
  expect_identical(out$df$Code, c("GDP_MAIN", "OTHER", "GDP_MAIN"))
  expect_s3_class(out, "FoundOECDDatasetList")
  expect_identical(names(out), c("criteria", "time", "df", "report"))
  expect_equal(nrow(OECDdata::find("GDP annual")$df), 1L)
  expect_equal(nrow(OECDdata::find()$df), 4L)
  expect_error(OECDdata::find(paste("gdp")), "Each find")
  expect_error(OECDdata::find("["), "Invalid search pattern")
})

test_that("browse evaluates subset expressions in data plus the caller's environment", {
  local_fixture_metadata()
  selected <- "DEMO"
  z <- browseDataList(Dataflow == selected)
  expect_identical(z$df$Dataflow, "DEMO")
  expect_identical(names(z), c("criteria", "time", "df", "html"))
  expect_s3_class(z, "BrowsedOECDDatasetList")
  expect_equal(nrow(browseDataList(c(TRUE, NA))$df), 1L)
  expect_error(browseDataList(1), "logical vector")
})

test_that("HTML reports escape text and do not activate non-HTTP links", {
  x <- data.frame(Code = "<script>alert(1)</script>", `Dataset name` = 'A & "B"',
    Link = "javascript:alert(1)", check.names = FALSE)
  html <- OECDdata:::.html_report(x, "<img src=x>")
  expect_false(grepl("<script>", html, fixed = TRUE))
  expect_false(grepl('href="javascript:', html, fixed = TRUE))
  expect_match(html, "&lt;script&gt;", fixed = TRUE)
  expect_match(html, "&amp;", fixed = TRUE)
  expect_match(html, "&lt;img src=x&gt;", fixed = TRUE)
})

test_that("options validate input and can be restored with base options", {
  old <- oecdOptions(quiet = TRUE, api_version = "v1")
  withr::defer(options(old))
  expect_true(oecdOptions()$quiet)
  expect_identical(oecdOptions()$api_version, "v1")
  expect_true(all(startsWith(names(old), "OECDdata.")))
  expect_error(oecdOptions(unknown = 1), "Unknown option")
  expect_error(oecdOptions(retries = 1.5), "integer")
  expect_error(oecdOptions(quiet = NA), "TRUE or FALSE")
  expect_error(oecdOptions(api_version = "v3"), "v2.*v1")
  expect_error(oecdOptions(base_url = "http://example.invalid/rest"), "HTTPS")
  expect_error(oecdOptions(base_url = "https://example.invalid/rest/v2"), "ending in /rest")
})

test_that("console printing returns the input invisibly", {
  local_fixture_metadata()
  expect_output(expect_identical(withVisible(print(importDataList()))$visible, FALSE), "Dataset name")
  z <- OECDdata::find(synthetic)
  expect_output(print(z), "OECD datasets")
  expect_output(print(z$report), "OECD datasets")
})


test_that("HTML descriptions keep benign formatting but never executable content", {
  x <- data.frame(Code = "TEST,DEMO,1.0", `Dataset name` = "A & B",
    Description = paste0('<p>Intro &amp; more <strong>emphasis</strong> ',
      '<a href="https://example.org/?a=1&amp;b=2" onclick="evil()">source</a>',
      '<script>malicious()</script><img src="x" onerror="evil()">',
      '<a href="javascript:alert(1)">unsafe anchor</a>',
      '</p><ul><li>First</li><li>Second</li></ul>'),
    Link = "https://example.org/?a=1&b=2", check.names = FALSE)
  html <- OECDdata:::.html_report(x, "demo")
  expect_match(html, "<p>Intro &amp; more <strong>emphasis</strong>", fixed = TRUE)
  expect_match(html, '<a rel="noopener noreferrer" href="https://example.org/?a=1&amp;b=2">source</a>',
    fixed = TRUE)
  expect_match(html, "<ul><li>First</li><li>Second</li></ul>", fixed = TRUE)
  expect_false(grepl("malicious()", html, fixed = TRUE))
  expect_false(grepl("onclick=", html, fixed = TRUE))
  expect_false(grepl("onerror=", html, fixed = TRUE))
  expect_false(grepl('href="javascript:', html, fixed = TRUE))
  expect_false(grepl('<img', html, fixed = TRUE))
  expect_match(html, "unsafe anchor", fixed = TRUE)
})

test_that("catalogue Explorer links specify OECD dissemination space", {
  cat <- OECDdata:::.parse_catalogue(fixture_doc())
  expect_true(all(grepl("df[ds]=dsDisseminateFinalDMZ", cat$Link, fixed = TRUE)))
  expect_true(all(grepl("df[ag]=TEST", cat$Link, fixed = TRUE)))
  expect_true(all(grepl("df[vs]=1.0", cat$Link, fixed = TRUE)))
})


test_that("HTML previews survive the browser handoff until session cleanup", {
  first <- OECDdata:::.browser_report_file("<p>First</p>")
  second <- OECDdata:::.browser_report_file("<p>Second</p>")
  plain <- OECDdata:::.browser_report_file("A short report", "txt")
  withr::defer(unlink(c(first, second, plain)))
  expect_true(all(file.exists(c(first, second, plain))))
  expect_false(identical(first, second))
  expect_true(startsWith(normalizePath(first, winslash = "/"),
    normalizePath(tempdir(), winslash = "/")))
  expect_equal(readLines(second), "<p>Second</p>")
  expect_match(plain, "\\.txt$")
  expect_error(OECDdata:::.browser_report_file("x", "exe"), "Unsupported")
})

test_that("default session cache lives inside R's temporary directory", {
  old <- oecdOptions(cache_dir = NULL)
  withr::defer(options(old))
  root <- OECDdata:::.cache_directory(create = FALSE)
  expect_true(startsWith(normalizePath(root, winslash = "/", mustWork = FALSE),
    normalizePath(tempdir(), winslash = "/")))
})
