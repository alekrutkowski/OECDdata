# Run from the repository root: Rscript tools/check.R . [OUTPUT_DIRECTORY]
# Builds the real package, including the vignette, before checking its tarball.
# Set OECDDATA_NO_MANUAL=true only when deliberately omitting the PDF manual.
args <- commandArgs(trailingOnly = TRUE)
source <- normalizePath(if (length(args)) args[[1L]] else ".", mustWork = TRUE)
if (!file.exists(file.path(source, "DESCRIPTION"))) stop("Point to the OECDdata source directory.")
description <- read.dcf(file.path(source, "DESCRIPTION"))
if (description[1L, "Package"] != "OECDdata") stop("Not an OECDdata source tree.")
output <- if (length(args) >= 2L) args[[2L]] else file.path(source, ".qa", "check")
if (!dir.exists(output) && !dir.create(output, recursive = TRUE))
  stop("Cannot create output directory: ", output)
output <- normalizePath(output, mustWork = TRUE)
source_prefix <- paste0(tolower(normalizePath(source, winslash = "/")), "/")
output_prefix <- paste0(tolower(normalizePath(output, winslash = "/")), "/")
if (startsWith(output_prefix, source_prefix) &&
    !startsWith(output_prefix, paste0(source_prefix, ".qa/")))
  stop("Use an output directory outside the source tree or inside its excluded .qa directory.")
Sys.setenv(OECDDATA_LIVE_TESTS = "false", NOT_CRAN = "false")
source(file.path(source, "tools", "package-source.R"))
build_source <- package_source(source)
old <- getwd(); setwd(output)
r <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R")
status <- system2(r, c("CMD", "build", shQuote(build_source)))
if (!identical(status, 0L)) { setwd(old); stop("R CMD build failed; inspect its output.") }
tarball <- file.path(output, paste0("OECDdata_", description[1L, "Version"], ".tar.gz"))
no_manual <- identical(Sys.getenv("OECDDATA_NO_MANUAL"), "true")
status <- system2(r, c("CMD", "check", "--as-cran", if (no_manual) "--no-manual", shQuote(tarball)))
setwd(old)
if (!identical(status, 0L)) stop("R CMD check failed; inspect the .Rcheck directory.")
check_log <- file.path(output, "OECDdata.Rcheck", "00check.log")
result <- if (file.exists(check_log))
  grep("^Status:", readLines(check_log, warn = FALSE), value = TRUE) else character()
if (!length(result) || any(grepl("[0-9]+ (ERROR|WARNING)", result)))
  stop("R CMD check was incomplete or reported errors/warnings; inspect ", check_log)
if (!no_manual) {
  manual <- file.path(output, "OECDdata-manual.pdf")
  manual_status <- system2(r, c("CMD", "Rd2pdf", "--no-preview", "--force",
    paste0("--output=", shQuote(manual)), shQuote(build_source)))
  if (!identical(manual_status, 0L) || !file.exists(manual) ||
      file.info(manual, extra_cols = FALSE)$size == 0)
    stop("PDF manual was not produced, even if R CMD check reported OK.")
}
if (no_manual) cat("PARTIAL CHECK: the PDF manual was deliberately omitted.\n")
cat(result, "\n")
cat("Check process finished. Inspect ALL warnings and notes before submission.\n")
cat("Built archive:", tarball, "\n")
