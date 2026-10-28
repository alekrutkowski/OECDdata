# Source-install regression checks for the Windows libxml2 discovery path.
# Deliberately failing PKG_CONFIG is a CI test fixture, not a toolchain change.
# Rtools40 library guidance:
# https://github.com/r-windows/docs/blob/master/rtools40.md

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L || !args %in% c("install", "verify"))
  stop("Use windows-source-install.R install or verify.")
if (.Platform$OS.type != "windows") stop("This check requires native Windows R.")
actual_arch <- if (grepl("^(aarch64|arm64)", R.version$arch)) "arm64" else
  if (grepl("^(x86_64|amd64|x64)", R.version$arch, ignore.case = TRUE)) "x86_64" else R.version$arch
if (!identical(actual_arch, Sys.getenv("OECD_WINDOWS_TEST_ARCH")))
  stop("Unexpected R architecture: ", R.version$arch)

dir.create(".qa", showWarnings = FALSE)
root <- normalizePath(".", winslash = "/", mustWork = TRUE)
test_library <- file.path(root, ".qa/windows-source-library")
mode <- Sys.getenv("OECD_WINDOWS_TEST_MODE")
if (!mode %in% c("normal", "no-pkg-config")) stop("Unknown Windows test mode.")

if (args == "install") {
  dir.create(test_library, recursive = TRUE, showWarnings = FALSE)
  # This must work through the installed R/Rtools toolchain without a CI-only
  # INCLUDE_DIR, LIB_DIR or complete compiler/linker flag workaround.
  Sys.unsetenv(c("LIBXML_CFLAGS", "LIBXML_LIBS", "INCLUDE_DIR", "LIB_DIR", "PKG_CONFIG"))
  if (mode == "no-pkg-config") {
    shim_dir <- file.path(root, ".qa/pkg-config-unavailable")
    dir.create(shim_dir, showWarnings = FALSE)
    shim <- file.path(shim_dir, "pkg-config")
    writeLines(c("#!/bin/sh", 'printf "%s\\n" "$*" >> "$OECD_WINDOWS_PKG_CONFIG_LOG"',
      "exit 1"), shim, useBytes = TRUE)
    Sys.chmod(shim, "0755")
    Sys.setenv(PKG_CONFIG = shim,
      OECD_WINDOWS_PKG_CONFIG_LOG = file.path(root, ".qa/windows-pkg-config-calls.log"),
      PATH = paste(shim_dir, Sys.getenv("PATH"), sep = .Platform$path.sep))
  }
  diagnostics <- c(capture.output(sessionInfo()), "", "Toolchain environment:",
    capture.output(print(Sys.getenv(c("R_TOOLS_SOFT", "LOCAL_SOFT", "RTOOLS40_HOME",
      "RTOOLS42_HOME", "RTOOLS43_HOME", "RTOOLS44_HOME", "RTOOLS45_HOME",
      "RTOOLS45_AARCH64_HOME", "PKG_CONFIG")))), "", "Tools visible before R CMD INSTALL:",
    capture.output(print(Sys.which(c("sh", "make", "gcc", "pkg-config")))))
  writeLines(diagnostics, ".qa/windows-source-session.txt")
  r_command <- file.path(R.home("bin"), "R.exe")
  output <- suppressWarnings(system2(r_command, c("CMD", "INSTALL", "--preclean",
    "--install-tests", "--no-multiarch", paste0("--library=", shQuote(test_library)),
    shQuote(root)), stdout = TRUE, stderr = TRUE))
  writeLines(output, ".qa/windows-source-install.log")
  cat(paste(output, collapse = "\n"), "\n")
  status <- attr(output, "status")
  if (!is.null(status) && status != 0L) stop("Windows source installation failed: ", status)
  if (mode == "no-pkg-config" && !file.exists(".qa/windows-pkg-config-calls.log"))
    stop("The unusable pkg-config regression fixture was not exercised.")
  if (mode == "no-pkg-config" &&
      !any(grepl("Checking libxml2 directly in Rtools:", output, fixed = TRUE)))
    stop("The unusable pkg-config test did not exercise direct Rtools library discovery.")
} else {
  .libPaths(c(test_library, .libPaths()))
  library("OECDdata", lib.loc = test_library)
  dll <- getLoadedDLLs()[["OECDdata"]]
  if (is.null(dll)) stop("The installed package did not load its native DLL.")
  routines <- names(getDLLRegisteredRoutines(dll)[[".Call"]])
  stopifnot(all(c("oecd_xml_read", "oecd_xml_find", "oecd_xml_codes") %in% routines))
  example <- OECDdata::oecdExample()
  stopifnot(inherits(example, "OECDDataset"), nrow(example) > 0L)
  testthat::test_package("OECDdata", reporter = "summary", stop_on_failure = TRUE)
}
