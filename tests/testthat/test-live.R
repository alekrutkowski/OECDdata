# Explicit opt-in only. Ordinary checks and CI never contact OECD.
test_that("the documented live v2 route imports a small monthly selection", {
  skip_if_not(identical(Sys.getenv("OECDDATA_LIVE_TESTS"), "true"))
  local_oecd(api_version = "v2", quiet = TRUE, max_downloads = 2L,
    strings_as_factors = FALSE, return_data_table = FALSE, retries = 0L)
  # A standalone opt-in run resolves the user-facing short code here.
  # The diagnostic runner has already checked that route against live OECD data;
  # it supplies the resulting canonical reference to avoid fetching and parsing
  # the same large catalogue again during its independent integration stage.
  known_ref <- Sys.getenv("OECDDATA_LIVE_REFERENCE", "")
  ref <- if (nzchar(known_ref)) known_ref else
    oecdDataset("CLI", agency = "OECD.SDD.STES", prefix = "DSD_STES")
  expect_match(ref, "^OECD[.]SDD[.]STES,DSD_STES@DF_CLI,")
  s <- oecdStructure(ref)
  expect_true(all(c("FREQ", "REF_AREA", "TIME_PERIOD") %in% s$dimensions$id))
  filters <- list(FREQ = "M", REF_AREA = "USA",
    TIME_PERIOD = c("2023-01", "2023-02"))
  x <- if (nzchar(known_ref)) importData(ref, filters) else
    importData("CLI", c(list(.dataset = list(agency = "OECD.SDD.STES",
      prefix = "DSD_STES", version = s$flow$version)), filters))
  expect_gt(nrow(x), 0L)
  expect_true(all(x$REF_AREA == "USA"))
  expect_true(all(x$FREQ == "M"))
  expect_true(all(x$TIME_PERIOD %in% c("2023-01", "2023-02")))
  expect_true(is.double(x$value_))
})
