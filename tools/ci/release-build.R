# Native binary release support. Run by release-binaries.yaml, not package tests.
# API references:
# https://search.r-project.org/R/refmans/utils/html/INSTALL.html
# https://contributor.r-project.org/windows-arm64/
# https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job

args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L || !args %in% c("source", "binary", "verify"))
  stop("Use release-build.R source, binary or verify.")
root <- normalizePath(".", winslash = "/", mustWork = TRUE)
description <- read.dcf("DESCRIPTION")
package <- unname(description[1L, "Package"])
version <- unname(description[1L, "Version"])
r_version <- as.character(getRversion())
r_minor <- paste(R.version$major, strsplit(R.version$minor, ".", fixed = TRUE)[[1L]][1L], sep = ".")
r_command <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R")

cmd <- function(arguments) {
  status <- system2(r_command, arguments)
  if (!identical(status, 0L)) stop("R command failed with status ", status)
}
directory <- function(path) {
  dir.create(path, recursive = TRUE, showWarnings = FALSE)
  normalizePath(path, winslash = "/", mustWork = TRUE)
}
emit <- function(values, destination) {
  path <- Sys.getenv(destination)
  if (nzchar(path)) cat(paste0(names(values), "=", values, "\n"),
    file = path, append = TRUE, sep = "")
}
canonical_arch <- function(x) {
  if (grepl("^(aarch64|arm64)", x)) "arm64" else
    if (grepl("^(x86_64|amd64|x64)", x, ignore.case = TRUE)) "x86_64" else x
}
check_arch <- function() {
  expected <- Sys.getenv("OECD_BINARY_ARCH")
  actual <- canonical_arch(R.version$arch)
  if (!expected %in% c("x86_64", "arm64") || !identical(actual, expected))
    stop("Wrong R architecture: expected ", expected, ", found ", R.version$arch)
  if (.Machine$sizeof.pointer != 8L) stop("Release builds require 64-bit R.")
  invisible(actual)
}

# Read the native machine identifier directly. This also catches a mislabeled
# binary when a runner has both native and emulated R installations available.
binary_arch <- function(path) {
  bytes <- readBin(path, "raw", n = 4096L)
  take <- function(offset, count) {
    if (offset < 0 || offset + count > length(bytes)) stop("Truncated native library header.")
    bytes[seq.int(offset + 1L, length.out = count)]
  }
  uint <- function(offset, count, endian = "little") {
    z <- as.integer(take(offset, count))
    if (endian == "big") z <- rev(z)
    sum(z * 256^(seq_along(z) - 1L))
  }
  magic <- paste(format(take(0L, 4L)), collapse = "")
  if (magic == "7f454c46") {
    if (uint(4L, 1L) != 2) stop("Expected a 64-bit ELF library.")
    endian <- if (uint(5L, 1L) == 1) "little" else "big"
    machine <- uint(18L, 2L, endian)
    return(switch(as.character(machine), `62` = "x86_64", `183` = "arm64", "unknown"))
  }
  if (identical(take(0L, 2L), charToRaw("MZ"))) {
    pe <- uint(60L, 4L)
    if (!identical(take(pe, 4L), as.raw(c(80, 69, 0, 0)))) stop("Invalid PE library.")
    machine <- uint(pe + 4L, 2L)
    return(switch(as.character(machine), `34404` = "x86_64", `43620` = "arm64", "unknown"))
  }
  if (magic %in% c("cffaedfe", "feedfacf")) {
    machine <- uint(4L, 4L, if (magic == "cffaedfe") "little" else "big")
    return(switch(as.character(machine), `16777223` = "x86_64", `16777228` = "arm64", "unknown"))
  }
  stop("Unrecognized native library format: ", path)
}

if (args == "source") {
  if (identical(Sys.getenv("GITHUB_REF_TYPE"), "tag") &&
      !identical(Sys.getenv("GITHUB_REF_NAME"), paste0("v", version)))
    stop("The release tag must equal v", version, " from DESCRIPTION.")
  build <- directory(".qa/release-source")
  setwd(build)
  cmd(c("CMD", "build", shQuote(root)))
  tarball <- file.path(build, paste0(package, "_", version, ".tar.gz"))
  if (!file.exists(tarball)) stop("The source archive was not produced.")
  emit(c(r_version = r_version, version = version), "GITHUB_OUTPUT")
} else if (args == "binary") {
  arch <- check_arch()
  if (!identical(version, Sys.getenv("OECD_RELEASE_VERSION")))
    stop("Source version does not match the release version.")
  target <- Sys.getenv("OECD_BINARY_TARGET")
  if (!target %in% c("windows", "ubuntu-24.04", "macos-15")) stop("Unknown target.")
  archive <- normalizePath(file.path(".qa/release-source",
    paste0(package, "_", version, ".tar.gz")), winslash = "/", mustWork = TRUE)
  build <- directory(".qa/binary-build")
  library <- directory(".qa/binary-library")
  assets <- directory(".qa/release-assets")
  setwd(build)
  cmd(c("CMD", "INSTALL", "--build", "--preclean", "--install-tests", "--no-multiarch",
    paste0("--library=", shQuote(library)), shQuote(archive)))
  binaries <- list.files(build, pattern = "\\.(zip|tgz|tar\\.gz)$", full.names = TRUE)
  if (length(binaries) != 1L) stop("Expected exactly one newly built binary archive.")
  extension <- if (grepl("\\.zip$", binaries)) ".zip" else
    if (grepl("\\.tgz$", binaries)) ".tgz" else ".tar.gz"
  label <- paste0(package, "_", version, "_R-", r_minor, "_", target, "_", arch)
  destination <- file.path(assets, paste0(label, extension))
  if (!file.copy(binaries, destination, overwrite = TRUE)) stop("Could not stage binary archive.")
  emit(c(OECD_BINARY_FILE = destination, OECD_BINARY_LABEL = label), "GITHUB_ENV")
} else {
  arch <- check_arch()
  archive <- Sys.getenv("OECD_BINARY_FILE")
  if (!nzchar(archive) || !file.exists(archive)) stop("Missing OECD_BINARY_FILE.")
  fresh <- directory(".qa/binary-verification-library")
  if (dir.exists(file.path(fresh, package)))
    stop("The binary verification library must be fresh.")
  if (.Platform$OS.type == "windows") {
    utils::install.packages(archive, repos = NULL, type = "win.binary", lib = fresh)
  } else {
    cmd(c("CMD", "INSTALL", paste0("--library=", shQuote(fresh)), shQuote(archive)))
  }
  .libPaths(c(fresh, .libPaths()))
  library(package, lib.loc = fresh, character.only = TRUE)
  dll <- getLoadedDLLs()[[package]]
  if (is.null(dll)) stop("The package did not load its compiled library.")
  if (!length(getDLLRegisteredRoutines(dll)[[".Call"]]))
    stop("The compiled library has no registered .Call entry points.")
  actual <- binary_arch(dll[["path"]])
  if (!identical(actual, arch)) stop("Wrong compiled architecture: ", actual, "; expected ", arch)
  example <- getExportedValue(package, "oecdExample")()
  if (!inherits(example, "OECDDataset") || nrow(example) == 0L)
    stop("The offline XML/CSV example failed.")
  testthat::test_package(package, reporter = "summary", stop_on_failure = TRUE)
  assets <- file.path(root, ".qa/release-assets")
  dependencies <- tools::package_dependencies(package,
    db = utils::installed.packages(), recursive = TRUE)[[package]]
  versions <- vapply(dependencies, function(x) as.character(utils::packageVersion(x)), character(1))
  info <- c(paste("Package:", package), paste("Version:", version),
    paste("R:", r_version), paste("R platform:", R.version$platform),
    paste("Target:", Sys.getenv("OECD_BINARY_TARGET")),
    paste("Architecture:", arch), paste("Compiled library architecture:", actual),
    paste("Git commit:", Sys.getenv("GITHUB_SHA")),
    paste("Runner:", Sys.getenv("RUNNER_OS"), Sys.getenv("RUNNER_ARCH")),
    "Validation: binary reinstallation, native architecture, offline example and offline tests passed.",
    "", "R dependencies:", paste(names(versions), versions), "", capture.output(sessionInfo()))
  writeLines(info, file.path(assets, paste0(Sys.getenv("OECD_BINARY_LABEL"), "-build-info.txt")))
}
