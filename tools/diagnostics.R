#!/usr/bin/env Rscript
# OECDdata CRAN diagnostic harness: fast full mode + deliberate quick mode.
# Run with: Rscript --vanilla tools/diagnostics.R PATH_TO_SOURCE_OR_ZIP [REPORT_DIR]
# Example: Rscript --vanilla tools/diagnostics.R .
# Works on Windows 11 and Linux with R >= 4.1; current checktor >= 0.2 needs R >= 4.5.
# Does NOT submit anything to CRAN or a third-party check service.
# Run with network access and a writable R package library if installing dependencies.
#
# Environment switches (0 = no, 1 = yes):
#   OECDTEST_MODE=full        full checks; 'quick' does offline tests + checktor only
#   OECDTEST_INSTALL=1       install missing required packages (default: 1)
#   OECDTEST_INSTALL_OPTIONAL=0  do not auto-install slow optional tooling
#   OECDTEST_PANDOC_DIR=path  override Pandoc executable directory, if auto-discovery fails
#   OECDTEST_CACHE_DIR=path    persistent OECD response cache shared across runs
#   Default on Windows: LOCALAPPDATA, not a potentially slow network home folder.
#   OECDTEST_LIVE_CACHE_TTL=604800  data cache lifetime for diagnostic replay (7 days)
#   OECDTEST_META_CACHE_TTL=2592000 metadata lifetime for diagnostic replay (30 days)
#   OECDTEST_PARTIAL_CHECK=0  only run partial R CMD check when explicitly requested
#   OECDTEST_CHECKTOR_URLS=0  opt in to slower live URL-liveness check
#   OECDTEST_LIVE_FRESH=0    cached live responses allowed; set 1 to force refresh
#   OECDTEST_LIVE_TIMEOUT=70 per-request live HTTP timeout in seconds
#   OECDTEST_CHECK_TIMEOUT=600 max seconds for an R CMD check subprocess
#   OECDTEST_LIVE=1          run OECD API smoke/integration tests (default: 1)
#   OECDTEST_REMOTE=1        enable online CRAN incoming checks (default: 1)
#   OECDTEST_COVERAGE=1      measure offline unit-test coverage (default: 1)
#   OECDTEST_BENCH=1         compare CSV parsers offline (default: 1)
#   OECDTEST_LINT=1          collect code style/semantic diagnostics (default: 1)
#   OECDTEST_API_COMPARE=1   compare adapted formals against CRAN eurodata (default: 1)
#   OECDTEST_BENCH_ROWS=120000  number of rows in generated benchmark CSV
#   OECDTEST_VIGNETTE_FALLBACK=1  if full build fails, also check without vignettes
# Full mode never quietly skips CRAN checks: unmet system requirements are
# reported as SKIP on the required gate, with a fast, explicitly partial check.
# A partial check with --no-manual/--ignore-vignettes is NOT CRAN-ready.
#
# Important: only the external, opt-in live stages use OECDDATA_LIVE_TESTS=true.
# The CRAN check, standard tests, coverage and benchmark always run offline.

args <- commandArgs(trailingOnly = TRUE)
input <- normalizePath(if (length(args)) args[[1L]] else ".", mustWork = TRUE)
report <- if (length(args) >= 2L) args[[2L]] else file.path(
  if (dir.exists(input)) file.path(input, ".qa") else dirname(input),
  paste0("OECDdata_diagnostics_", format(Sys.time(), "%Y%m%d_%H%M%S")))
report <- normalizePath(report, winslash = "/", mustWork = FALSE)
if (dir.exists(report) || file.exists(report)) {
  stop("Choose a new, nonexistent output directory: ", report)
}
if (!dir.create(report, recursive = TRUE, showWarnings = FALSE)) {
  stop("Cannot create the report directory: ", report)
}
logs <- file.path(report, "logs")
outputs <- file.path(report, "outputs")
dir.create(logs)
dir.create(outputs)

flag <- function(name, default = TRUE) {
  x <- tolower(trimws(Sys.getenv(name, if (default) "1" else "0")))
  if (!x %in% c("1", "0", "true", "false", "yes", "no")) {
    stop("Expected 0/1 for ", name, "; received: ", x)
  }
  x %in% c("1", "true", "yes")
}
mode <- tolower(trimws(Sys.getenv("OECDTEST_MODE", "full")))
if (!mode %in% c("full", "quick")) stop("OECDTEST_MODE must be 'full' or 'quick'")
full <- identical(mode, "full")
positive_integer <- function(name, default) {
  x <- Sys.getenv(name, as.character(default))
  value <- suppressWarnings(as.integer(x))
  if (length(value) != 1L || is.na(value) || value < 1L ||
      !identical(as.character(value), trimws(x))) {
    stop(name, " must be a positive integer in seconds (received ", x, ")")
  }
  value
}
cfg <- list(
  mode = mode, install = flag("OECDTEST_INSTALL"),
  install_optional = flag("OECDTEST_INSTALL_OPTIONAL", FALSE),
  live = full && flag("OECDTEST_LIVE"),
  live_fresh = flag("OECDTEST_LIVE_FRESH", FALSE),
  live_timeout = positive_integer("OECDTEST_LIVE_TIMEOUT", 70L),
  live_cache_ttl = positive_integer("OECDTEST_LIVE_CACHE_TTL", 604800L),
  metadata_cache_ttl = positive_integer("OECDTEST_META_CACHE_TTL", 2592000L),
  checktor_urls = full && flag("OECDTEST_CHECKTOR_URLS", FALSE),
  partial_check = full && flag("OECDTEST_PARTIAL_CHECK", FALSE),
  check_timeout = positive_integer("OECDTEST_CHECK_TIMEOUT", 600L),
  remote = full && flag("OECDTEST_REMOTE"),
  coverage = full && flag("OECDTEST_COVERAGE"),
  benchmark = full && flag("OECDTEST_BENCH"),
  lint = full && flag("OECDTEST_LINT"),
  api_compare = full && flag("OECDTEST_API_COMPARE"),
  fallback = full && flag("OECDTEST_VIGNETTE_FALLBACK")
)
# Windows user.home() may be a roaming/network drive. Verified checksum and
# XML reads on those drives can produce owner-resolution warnings and take
# minutes. Prefer LOCALAPPDATA, which is normally on a local disk; preserve
# an explicit OECDTEST_CACHE_DIR override for controlled environments.
.local_cache_root <- function() {
  if (.Platform$OS.type != "windows") {
    xdg <- Sys.getenv("XDG_CACHE_HOME", "")
    return(file.path(if (nzchar(xdg)) xdg else file.path(path.expand("~"), ".cache"),
                     "OECDdata-diagnostics"))
  }
  candidates <- c(Sys.getenv("LOCALAPPDATA", ""), Sys.getenv("TEMP", ""),
                  dirname(tempdir()))
  local <- Filter(function(x) nzchar(x) && dir.exists(x) &&
    !startsWith(x, "//") && !startsWith(x, "\\\\"), candidates)
  if (!length(local)) return(file.path(tempdir(), "OECDdata-diagnostics"))
  file.path(local[[1L]], "OECDdata-diagnostics")
}
shared_cache <- Sys.getenv("OECDTEST_CACHE_DIR", "")
if (!nzchar(shared_cache)) shared_cache <- .local_cache_root()
shared_cache <- normalizePath(shared_cache, winslash = "/", mustWork = FALSE)
writeLines(c(capture.output(str(cfg)), paste("Shared cache:", shared_cache)),
           file.path(outputs, "settings.txt"))

# Unpack the complete development ZIP, or use a package source directory.
source_dir <- input
if (!dir.exists(input)) {
  unpack <- file.path(report, "unpacked")
  dir.create(unpack)
  if (grepl("[.]zip$", input, ignore.case = TRUE)) {
    utils::unzip(input, exdir = unpack)
  } else if (grepl("[.]tar[.]gz$|[.]tgz$", input, ignore.case = TRUE)) {
    utils::untar(input, exdir = unpack)
  } else {
    stop("Supply a source directory, .zip, or .tar.gz, not: ", input)
  }
  candidates <- list.files(unpack, pattern = "^DESCRIPTION$", recursive = TRUE,
                           full.names = TRUE)
  candidates <- dirname(candidates)
  candidates <- Filter(function(d) {
    x <- tryCatch(read.dcf(file.path(d, "DESCRIPTION")), error = function(e) NULL)
    !is.null(x) && identical(unname(x[1L, "Package"]), "OECDdata")
  }, candidates)
  if (length(candidates) != 1L) stop("Could not uniquely find OECDdata in the archive.")
  source_dir <- candidates[[1L]]
}
source_dir <- normalizePath(source_dir, winslash = "/", mustWork = TRUE)
if (!file.exists(file.path(source_dir, "DESCRIPTION"))) {
  stop("Not an R package source tree: ", source_dir)
}
inside_source <- startsWith(paste0(tolower(report), "/"), paste0(tolower(source_dir), "/"))
inside_qa <- startsWith(paste0(tolower(report), "/"), paste0(tolower(source_dir), "/.qa/"))
if (inside_source && !inside_qa) {
  stop("Use a report directory outside the source tree or inside its excluded .qa directory.")
}
dcf <- read.dcf(file.path(source_dir, "DESCRIPTION"))
stopifnot(identical(unname(dcf[1L, "Package"]), "OECDdata"))
version <- unname(dcf[1L, "Version"])
name <- unname(dcf[1L, "Package"])

# A permanent CSV is written after every stage so interrupted runs are useful.
stages <- data.frame(stage = character(), class = character(), status = character(),
                     detail = character(), elapsed_seconds = numeric(),
                     stringsAsFactors = FALSE)
record <- function(stage, group, status, detail = "", seconds = NA_real_) {
  stages <<- rbind(stages, data.frame(
    stage = stage, class = group, status = status, detail = as.character(detail),
    elapsed_seconds = round(seconds, 2), stringsAsFactors = FALSE))
  utils::write.csv(stages, file.path(report, "STAGES.csv"), row.names = FALSE,
                   na = "")
  message(sprintf("[%s] %-30s %s", status, stage, detail))
  invisible(status)
}
skip <- function(stage, group, reason) record(stage, group, "SKIP", reason)

# Isolated log per stage. An error never prevents the remaining checks from running.
stage <- function(label, group, fun) {
  message("\n=== ", label, " ===")
  start <- Sys.time()
  logpath <- file.path(logs, paste0(gsub("[^[:alnum:]_-]", "_", label), ".log"))
  con <- file(logpath, open = "wt")
  sink(con, type = "output")
  sink(con, type = "message")
  result <- tryCatch(withCallingHandlers(fun(), error = function(e) {
    cat("\nCALL STACK AT FAILURE:\n")
    calls <- sys.calls()
    print(utils::tail(vapply(calls, function(z) paste(deparse(z), collapse = " "),
                             character(1)), 35L))
  }), error = function(e) {
    cat("\nSTAGE ERROR: ", conditionMessage(e), "\n", sep = "")
    structure(list(message = conditionMessage(e)), class = "OECDtest_error")
  })
  sink(type = "message")
  sink(type = "output")
  close(con)
  elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  if (inherits(result, "OECDtest_error")) {
    record(label, group, "FAIL", result$message, elapsed)
    return(invisible(FALSE))
  }
  if (is.list(result) && identical(result$stage_status, "WARN")) {
    record(label, group, "WARN", result$detail, elapsed)
    return(invisible(FALSE))
  }
  detail <- if (is.list(result) && !is.null(result$detail)) result$detail else "completed"
  record(label, group, "PASS", detail, elapsed)
  invisible(TRUE)
}

# Don't leave changed environment variables behind after executing a subprocess.
with_env <- function(env, code) {
  keys <- names(env)
  if (is.null(keys) || any(!nzchar(keys))) stop("Environment keys must be named")
  prior <- Sys.getenv(keys, unset = NA_character_)
  on.exit({
    Sys.unsetenv(keys)
    present <- !is.na(prior)
    if (any(present)) do.call(Sys.setenv, as.list(stats::setNames(prior[present], keys[present])))
  }, add = TRUE)
  do.call(Sys.setenv, as.list(env))
  force(code)
}

r_binary <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "R.exe" else "R")
cmd <- function(command, arguments, working_dir, log_file, env = character(),
                timeout = cfg$check_timeout) {
  old <- setwd(working_dir)
  on.exit(setwd(old), add = TRUE)
  code <- with_env(env, suppressWarnings(system2(command, arguments,
    stdout = log_file, stderr = log_file, wait = TRUE, timeout = timeout)))
  if (length(code) != 1L || is.na(code)) stop("No process status returned")
  as.integer(code)
}
need <- function(pkgs) {
  absent <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (length(absent)) stop("Missing R packages: ", paste(absent, collapse = ", "))
  invisible(TRUE)
}
install_if_missing <- function(pkgs, optional = FALSE) {
  pkgs <- unique(pkgs)
  missing <- pkgs[!vapply(pkgs, requireNamespace, logical(1), quietly = TRUE)]
  if (!length(missing)) return(invisible(TRUE))
  if (!cfg$install || (optional && !cfg$install_optional)) {
    cat("Missing: ", paste(missing, collapse = ", "), "\n", sep = "")
    return(invisible(FALSE))
  }
  cat("Installing missing ", if (optional) "optional" else "required",
      " packages: ", paste(missing, collapse = ", "), "\n", sep = "")
  tryCatch(utils::install.packages(missing, dependencies = NA),
           error = function(e) cat("Installation error: ", conditionMessage(e), "\n"))
  all(vapply(pkgs, requireNamespace, logical(1), quietly = TRUE))
}
packages_in_field <- function(field) {
  if (!field %in% colnames(dcf) || is.na(dcf[1L, field])) return(character())
  x <- trimws(unlist(strsplit(dcf[1L, field], ",", fixed = TRUE)))
  x <- trimws(sub("[[:space:]]*\\(.*$", "", x))
  setdiff(x[nzchar(x)], c("R", "utils", "stats", "tools", "base", "methods",
                           "graphics", "grDevices", "datasets", "grid", "parallel"))
}

stage("environment", "required", function() {
  cat("OECDdata version: ", version, "\n", sep = "")
  cat("R version: ", R.version.string, "\n", sep = "")
  cat("OS: ", .Platform$OS.type, "\n", sep = "")
  cat("Source path: ", source_dir, "\n", sep = "")
  cat("Report path: ", report, "\n", sep = "")
  cat("Timestamp UTC: ", format(Sys.time(), tz = "UTC", usetz = TRUE), "\n")
  print(Sys.which(c("make", "gcc", "g++", "qpdf", "pdflatex", "pandoc", "git", "zip")))
  print(utils::sessionInfo())
  writeLines(capture.output(utils::sessionInfo()), file.path(outputs, "sessionInfo.txt"))
  writeLines(capture.output(utils::installed.packages()[,
    c("Package", "Version", "LibPath"), drop = FALSE]),
    file.path(outputs, "installed_packages.txt"))
  if (getRversion() < "4.1.0") stop("OECDdata requires R >= 4.1.0")
  list(detail = R.version.string)
})

stage("dependencies", "required", function() {
  required <- unique(c(packages_in_field("Imports"), packages_in_field("Suggests"),
                       packages_in_field("VignetteBuilder")))
  cat("Required for all CRAN checks and vignettes: ", paste(required, collapse = ", "), "\n")
  if (!install_if_missing(required)) stop("Not all mandatory check dependencies installed")
  need(required)
  list(detail = paste(length(required), "dependencies available"))
})

# A missing LaTeX package previously caused MiKTeX to hang for 13+ minutes.
# Check *before* calling R CMD check; there must be no prompt/install attempt.
# Rscript --vanilla launched outside RStudio often does not inherit RSTUDIO_PANDOC.
# Discover standalone and RStudio/Quarto Pandoc automatically on Windows,
# as well as honoring OECDTEST_PANDOC_DIR for nonstandard installations.
# Do not require users to add a second Pandoc installation or edit system PATH.
.pandoc_candidates <- function() {
  path_bins <- unname(Sys.which(c("pandoc", "pandoc.exe")))
  path_bins <- path_bins[nzchar(path_bins)]
  candidates <- c(
    Sys.getenv("OECDTEST_PANDOC_DIR", ""),
    Sys.getenv("RSTUDIO_PANDOC", ""),
    if (length(path_bins)) dirname(path_bins) else character()
  )
  if (.Platform$OS.type == "windows") {
    localapp <- Sys.getenv("LOCALAPPDATA", "")
    pf <- unique(Filter(nzchar, c(Sys.getenv("ProgramFiles", ""),
      Sys.getenv("ProgramW6432", ""), Sys.getenv("ProgramFiles(x86)", ""))))
    candidates <- c(candidates,
      if (nzchar(localapp)) file.path(localapp, "Pandoc") else character(),
      file.path(path.expand("~"), "AppData", "Local", "Pandoc"),
      unlist(lapply(pf, function(root) c(
        file.path(root, "RStudio", "resources", "app", "bin", "quarto", "bin", "tools"),
        file.path(root, "RStudio", "bin", "quarto", "bin", "tools")
      )), use.names = FALSE)
    )
  }
  candidates <- candidates[nzchar(candidates) & !is.na(candidates)]
  # Explicit overrides may be supplied as the executable path or its directory.
  candidates <- vapply(candidates, function(path) {
    if (file.exists(path) && !dir.exists(path) &&
        tolower(basename(path)) %in% c("pandoc", "pandoc.exe")) dirname(path) else path
  }, character(1), USE.NAMES = FALSE)
  candidates <- unique(candidates[dir.exists(candidates)])
  if (length(candidates)) normalizePath(candidates, winslash = "/") else character()
}

pandoc_dir <- ""
pandoc_version <- ""
has_pandoc <- FALSE
tex_missing <- character()
has_pdf_manual <- FALSE
if (full) {
  stage("toolchain-preflight", "advisory", function() {
    bin <- if (.Platform$OS.type == "windows") "pandoc.exe" else "pandoc"
    if (requireNamespace("rmarkdown", quietly = TRUE)) {
      discovered <- tryCatch(rmarkdown::find_pandoc(cache = FALSE),
        error = function(e) list(dir = NULL, version = "0"))
      candidate_dirs <- unique(c(
        Sys.getenv("OECDTEST_PANDOC_DIR", ""),
        if (length(discovered$dir) == 1L) discovered$dir else "",
        .pandoc_candidates()))
      # rmarkdown::find_pandoc(dir=...) confirms both the executable and its
      # version. A valid explicit override takes priority over other installs.
      override <- Sys.getenv("OECDTEST_PANDOC_DIR", "")
      if (nzchar(override)) {
        explicit_dir <- if (file.exists(override) && !dir.exists(override))
          dirname(override) else override
        chosen <- tryCatch(rmarkdown::find_pandoc(cache = FALSE, dir = explicit_dir),
          error = function(e) list(dir = NULL, version = "0"))
      } else chosen <- list(dir = NULL, version = "0")
      if (length(chosen$dir) != 1L || is.null(chosen$dir) || !nzchar(chosen$dir)) {
        chosen <- tryCatch(rmarkdown::find_pandoc(cache = FALSE,
          dir = candidate_dirs[nzchar(candidate_dirs)]),
          error = function(e) list(dir = NULL, version = "0"))
      }
      candidate <- chosen$dir
      if (length(candidate) == 1L && !is.null(candidate) && nzchar(candidate) &&
          file.exists(file.path(candidate, bin))) {
        pandoc_dir <<- normalizePath(candidate, winslash = "/")
        pandoc_version <<- as.character(chosen$version)
        has_pandoc <<- TRUE
        # Propagate to the R CMD build/check subprocesses, even from Rscript.
        Sys.setenv(RSTUDIO_PANDOC = pandoc_dir)
        Sys.setenv(PATH = paste(pandoc_dir, Sys.getenv("PATH"), sep = .Platform$path.sep))
      }
      cat("Pandoc candidates:\n", paste(candidate_dirs, collapse = "\n"), "\n")
      cat("Pandoc selection: ", if (has_pandoc)
        paste0("v", pandoc_version, " at ", pandoc_dir) else "MISSING", "\n", sep = "")
      if (nzchar(override) && !has_pandoc)
        cat("OECDTEST_PANDOC_DIR was provided but no usable Pandoc was found.\n")
    } else cat("rmarkdown is not installed, so Pandoc cannot be validated.\n")
    pdflatex <- Sys.which("pdflatex")
    kpsewhich <- Sys.which("kpsewhich")
    if (!nzchar(pdflatex)) tex_missing <<- c(tex_missing, "pdflatex executable")
    if (!nzchar(kpsewhich)) tex_missing <<- c(tex_missing, "kpsewhich executable")
    if (length(tex_missing) == 0L) {
      for (sty in c("inconsolata.sty", "url.sty")) {
        # The timeout prevents MiKTeX's on-the-fly installer becoming a hang.
        out <- tryCatch(suppressWarnings(system2(kpsewhich, sty,
          stdout = TRUE, stderr = FALSE, timeout = 8L)), error = function(e) character())
        if (!length(out) || !any(nzchar(trimws(out))) ||
            (!is.null(attr(out, "status")) && attr(out, "status") != 0L)) {
          tex_missing <<- c(tex_missing, sty)
        }
      }
    }
    has_pdf_manual <<- !length(tex_missing)
    txt <- c(
      paste("Pandoc:", if (has_pandoc) paste0(pandoc_dir, " (", pandoc_version, ")") else "MISSING"),
      paste("Manual PDF:", if (has_pdf_manual) "READY" else paste("MISSING:",
        paste(tex_missing, collapse = ", "))),
      if (!has_pandoc) "Set OECDTEST_PANDOC_DIR to the directory containing pandoc.exe (or pandoc)." else
        "Pandoc is on PATH and RSTUDIO_PANDOC for R CMD build/check subprocesses.",
      if (!has_pdf_manual) "Install the missing LaTeX styles before the complete --as-cran check." else
        "LaTeX prerequisites verified; no package installation is attempted."
    )
    writeLines(txt, file.path(outputs, "toolchain-preflight.txt"))
    cat(paste(txt, collapse = "\n"), "\n")
    if (!has_pandoc || !has_pdf_manual)
      list(stage_status = "WARN", detail = paste(
        if (!has_pandoc) "Pandoc missing;" else "Pandoc OK;",
        if (!has_pdf_manual) "LaTeX incomplete; fast partial check only" else "LaTeX OK"))
    else list(detail = paste("Pandoc", pandoc_version, "and manual-PDF prerequisites available"))
  })
} else skip("toolchain-preflight", "advisory", "quick mode")

stage("R-source-parsing", "required", function() {
  paths <- list.files(file.path(source_dir, "R"), pattern = "[.]R$", full.names = TRUE)
  stopifnot(length(paths) > 0L)
  invisible(lapply(paths, function(f) parse(file = f, keep.source = TRUE)))
  cat("Successfully parsed ", length(paths), " R files\n", sep = "")
  list(detail = paste(length(paths), "R implementation files parsed"))
})

stage("OECD-native-names", "required", function() {
  places <- c(file.path(source_dir, "R"), file.path(source_dir, "man"),
              file.path(source_dir, "tests"))
  sources <- unlist(lapply(places, function(d) if (dir.exists(d))
    list.files(d, pattern = "\\.(R|Rd)$", full.names = TRUE, recursive = TRUE)
    else character()), use.names = FALSE)
  sources <- c(sources, file.path(source_dir, "NAMESPACE"))
  hits <- unlist(lapply(sources, function(path) {
    if (!file.exists(path)) return(character())
    txt <- readLines(path, warn = FALSE, encoding = "UTF-8")
    at <- grep("Eurostat|EurostatDatasetCode|as\\.EurostatDataList", txt,
               ignore.case = TRUE)
    if (length(at)) paste0(path, ":", at, ": ", trimws(txt[at])) else character()
  }), use.names = FALSE)
  if (length(hits)) {
    writeLines(hits, file.path(outputs, "misleading-names.txt"))
    stop("Misleading legacy provider references in R/man/tests/NAMESPACE: ", length(hits))
  }
  list(detail = paste(length(sources), "runtime/help/test files free of legacy names"))
})

# checktor is a CRAN-hosted add-on, not an official substitute for R CMD check.
# checktor 0.2.0 requires R >= 4.5.0. Its full diagnostic covers ALL five groups.
if (cfg$install && getRversion() >= "4.5.0") {
  stage("checktor-install", "required", function() {
    # Do not load the old Windows binary namespace before upgrading it.
    installed <- tryCatch(utils::packageVersion("checktor"), error = function(e) NULL)
    if (cfg$install && (is.null(installed) || installed < "0.2.0")) {
      cat("Attempting a CRAN source install of checktor 0.2.0+\n")
      tryCatch(utils::install.packages("checktor", type = "source"),
        error = function(e) cat("Source upgrade failed: ", conditionMessage(e), "\n"))
    }
    installed <- tryCatch(utils::packageVersion("checktor"), error = function(e) NULL)
    if (is.null(installed) || installed < "0.2.0")
      stop("checktor 0.2.0+ needed for severity-specific feedback; install ",
        "the source version first and run this script again")
    need("checktor")
    list(detail = paste("checktor", as.character(installed)))
  })
}
if (getRversion() >= "4.5.0" && requireNamespace("checktor", quietly = TRUE) &&
    utils::packageVersion("checktor") >= "0.2.0") {
  stage("checktor-all-diagnostics", "required", function() {
    fn <- checktor::checktor
    params <- list(path = source_dir, verbose = FALSE, progress = FALSE)
    if ("severity" %in% names(formals(fn))) {
      params$severity <- c("policy", "robustness", "opinion")
    }
    url_options <- options(checktor.url_check = cfg$checktor_urls)
    on.exit(options(url_options), add = TRUE)
    result <- do.call(fn, params)
    saveRDS(result, file.path(outputs, "checktor-full-results.rds"))
    findings <- checktor::issues(result)
    # Since issues() differs across checktor releases, join check-level tiers
    # when its per-issue table does not expose a severity column.
    checks <- as.data.frame(result)
    utils::write.csv(checks, file.path(outputs, "checktor-checks.csv"),
                     row.names = FALSE, na = "")
    skipped <- checks[!is.na(checks$skipped) & checks$skipped, , drop = FALSE]
    utils::write.csv(skipped, file.path(outputs, "checktor-skipped.csv"),
                     row.names = FALSE, na = "")
    if (nrow(findings) && !"severity" %in% names(findings) &&
        all(c("category", "check") %in% names(findings)) &&
        all(c("category", "check", "severity") %in% names(checks))) {
      findings$severity <- checks$severity[match(
        paste(findings$category, findings$check, sep = "::"),
        paste(checks$category, checks$check, sep = "::"))]
    }
    utils::write.csv(findings, file.path(outputs, "checktor-issues.csv"), row.names = FALSE,
                     na = "")
    writeLines(capture.output(summary(result)), file.path(outputs, "checktor-summary.txt"))
    writeLines(capture.output(checktor::prescribe(result)),
               file.path(outputs, "checktor-remedies.txt"))
    checktor::health_report(result, file = file.path(outputs, "checktor-report.md"),
                            format = "markdown")
    checktor::health_report(result, file = file.path(outputs, "checktor-report.txt"),
                            format = "text")
    if ("ci_report" %in% getNamespaceExports("checktor")) {
      tryCatch(checktor::ci_report(result, format = "sarif",
          file = file.path(outputs, "checktor.sarif")),
        error = function(e) cat("SARIF export unavailable: ", conditionMessage(e), "\n"))
    }
    cat("checktor version: ", as.character(utils::packageVersion("checktor")), "\n")
    cat("Total findings: ", nrow(findings), "\n")
    print(summary(result))
    if (length(result$metadata$skipped_checks))
      cat("checktor checks not executed:",
          paste(result$metadata$skipped_checks, collapse = ", "), "\n")
    if (cfg$checktor_urls && "url_liveness" %in% result$metadata$skipped_checks)
      stop("URL checking was requested but did not run; inspect checktor-skipped.csv")
    if (nrow(findings)) print(findings)
    if ("severity" %in% names(findings)) {
      hard <- findings$severity %in% c("policy", "robustness")
      if (any(hard, na.rm = TRUE)) stop(sum(hard, na.rm = TRUE),
                                      " policy/robustness findings (see CSV/Markdown)")
      if (nrow(findings)) return(list(stage_status = "WARN", detail = paste(
        nrow(findings), "opinion-tier findings; policy/robustness clear")))
    } else if (nrow(findings)) {
      stop(nrow(findings), " findings without classifiable severity; inspect report")
    }
    list(detail = "no findings in policy, robustness or opinion tiers")
  })
} else {
  skip("checktor-all-diagnostics", "required", paste0(
    "checktor unavailable; install it before claiming CRAN readiness. R=",
    as.character(getRversion()), "; checktor 0.2.0 requires R >= 4.5"))
}

# Unit tests: always run in both quick and full modes. In full mode R CMD check
# will also run them within the installed/checked build (intentional verification).
if (requireNamespace("testthat", quietly = TRUE) &&
    requireNamespace("pkgload", quietly = TRUE)) {
  stage("testthat-offline", "required", function() {
    with_env(c(OECDDATA_LIVE_TESTS = "false", NOT_CRAN = "false"), {
      testthat::test_local(source_dir, reporter = "summary", stop_on_failure = TRUE,
                           stop_on_warning = TRUE, load_package = "source")
    })
    list(detail = "all non-network unit tests completed")
  })
} else {
  skip("testthat-offline", "required", "testthat/pkgload unavailable")
}

build_path <- file.path(report, "build")
dir.create(build_path)
build_source <- source_dir
if (full) {
  staging_helper <- file.path(source_dir, "tools", "package-source.R")
  if (file.exists(staging_helper)) {
    source(staging_helper)
    build_source <- package_source(source_dir)
  }
}
tarball <- file.path(build_path, paste0(name, "_", version, ".tar.gz"))
built <- FALSE
diagnostic_built <- FALSE
if (!full) {
  skip("R-CMD-build", "advisory", "quick mode: not a CRAN build")
  skip("R-CMD-check-as-cran", "advisory", "quick mode: CRAN status not assessed")
} else {
  if (has_pandoc) {
    built <- stage("R-CMD-build", "required", function() {
      log_file <- file.path(logs, "R-CMD-build-console.txt")
      code <- cmd(r_binary, c("CMD", "build", shQuote(build_source)), build_path,
                  log_file, c(OECDDATA_LIVE_TESTS = "false", NOT_CRAN = "false"),
                  timeout = 240L)
      cat("Exit status: ", code, "\n", sep = "")
      if (file.exists(log_file)) cat(paste(tail(readLines(log_file, warn = FALSE), 35L),
                                        collapse = "\n"), "\n")
      if (code != 0L || !file.exists(tarball)) stop("R CMD build failed. See build console.")
      writeLines(unname(tools::md5sum(tarball)), file.path(outputs, "built-tarball.md5"))
      list(detail = paste("built", basename(tarball)))
    })
  } else {
    skip("R-CMD-build", "required", "Pandoc absent; do not attempt known-to-fail vignette build")
  }
  if (!built && cfg$fallback) {
    diagnostic_built <- stage("R-CMD-build-no-vignettes", "advisory", function() {
      log_file <- file.path(logs, "R-CMD-build-no-vignettes-console.txt")
      code <- cmd(r_binary, c("CMD", "build", "--no-build-vignettes", shQuote(build_source)),
                  build_path, log_file,
                  c(OECDDATA_LIVE_TESTS = "false", NOT_CRAN = "false"), timeout = 180L)
      if (file.exists(log_file)) cat(paste(tail(readLines(log_file, warn = FALSE), 35L),
                                        collapse = "\n"), "\n")
      if (code != 0L || !file.exists(tarball)) stop("Source build without vignettes failed")
      list(detail = "built without vignettes; NOT a CRAN build pass")
    })
  }
  check_dir <- file.path(report, "R-CMD-check")
  dir.create(check_dir)
  check_subdir <- file.path(check_dir, paste0(name, ".Rcheck"))
  cr_env <- c(OECDDATA_LIVE_TESTS = "false", NOT_CRAN = "false",
              `_R_CHECK_CRAN_INCOMING_` = "true",
              `_R_CHECK_CRAN_INCOMING_REMOTE_` = if (cfg$remote) "true" else "false",
              `_R_CHECK_FORCE_SUGGESTS_` = "true")
  check_record <- function(code, partial = FALSE) {
    checklog <- file.path(check_subdir, "00check.log")
    if (!file.exists(checklog)) stop("R CMD check produced no 00check.log (exit=", code, ")")
    lines <- readLines(checklog, warn = FALSE)
    status_line <- grep("^Status: ", lines, value = TRUE)
    if (!length(status_line)) stop("R CMD check did not complete; inspect console log")
    writeLines(c(if (partial) "PARTIAL: not a complete CRAN check", status_line),
               file.path(outputs, "R-CMD-check-status.txt"))
    cat("Final status: ", paste(status_line, collapse = " | "), "\n", sep = "")
    cat(paste(tail(lines, 90L), collapse = "\n"), "\n")
    if (code != 0L && !partial) stop("Full R CMD check reported issues; see 00check.log")
    if (identical(trimws(status_line), "Status: OK") && code == 0L) {
      return(list(detail = if (partial) "partial check OK (manual/vignettes not fully tested)"
                  else "Status: OK (0 ERROR, 0 WARNING, 0 NOTE)"))
    }
    if (partial && !grepl("[0-9]+ ERROR|[0-9]+ WARNING", status_line))
      return(list(stage_status = "WARN", detail = paste("partial check has NOTES:",
        paste(status_line, collapse = " | "))))
    stop("R CMD check has non-OK status; inspect 00check.log")
  }
  if (built && has_pdf_manual) {
    stage("PDF-manual-artifact", "required", function() {
      pdf <- file.path(outputs, paste0(name, "-manual.pdf"))
      log_file <- file.path(logs, "PDF-manual-console.txt")
      code <- cmd(r_binary, c("CMD", "Rd2pdf", "--no-preview", "--force",
        paste0("--output=", shQuote(pdf)), shQuote(build_source)),
        build_path, log_file)
      if (code != 0L || !file.exists(pdf) || file.info(pdf, extra_cols = FALSE)$size == 0)
        stop("LaTeX did not produce the PDF manual; inspect PDF-manual-console.txt")
      list(detail = paste("PDF manual created:", basename(pdf)))
    })
    stage("R-CMD-check-as-cran", "required", function() {
      log_file <- file.path(logs, "R-CMD-check-console.txt")
      code <- cmd(r_binary, c("CMD", "check", "--as-cran", "--timings", shQuote(tarball)),
        check_dir, log_file, cr_env, timeout = cfg$check_timeout)
      check_record(code, FALSE)
    })
  } else {
    skip("R-CMD-check-as-cran", "required", if (!built)
      "Full build unavailable; a diagnostic check is not sufficient"
      else paste("PDF manual prerequisites missing:", paste(tex_missing, collapse = ", ")))
  }
  if ((built || diagnostic_built) && !(built && has_pdf_manual) && cfg$partial_check) {
    stage("R-CMD-check-partial-no-manual", "advisory", function() {
      log_file <- file.path(logs, "R-CMD-check-partial-console.txt")
      flags <- c("CMD", "check", "--as-cran", "--timings", "--no-manual",
        if (!built) "--ignore-vignettes", shQuote(tarball))
      env <- cr_env; env[["_R_CHECK_CRAN_INCOMING_REMOTE_"]] <- "false"
      code <- cmd(r_binary, flags, check_dir, log_file, env,
                  timeout = cfg$check_timeout)
      check_record(code, TRUE)
    })
  } else if ((built || diagnostic_built) && !(built && has_pdf_manual)) {
    skip("R-CMD-check-partial-no-manual", "advisory",
      "disabled by default to avoid a slow repeat of an incomplete CRAN check; set OECDTEST_PARTIAL_CHECK=1")
  }
}

# Preserve the actual R CMD check logs even when checks fail or are interrupted.
if (full && dir.exists(file.path(report, "R-CMD-check", paste0(name, ".Rcheck")))) {
stage("collect-check-logs", "required", function() {
  check_subdir <- file.path(report, "R-CMD-check", paste0(name, ".Rcheck"))
  if (!dir.exists(check_subdir)) stop("R CMD check output directory does not exist")
  fs <- list.files(check_subdir, recursive = TRUE, full.names = TRUE, all.files = FALSE)
  fs <- fs[file.exists(fs) & !dir.exists(fs)]
  keep <- grepl("(\\.log$|\\.out$|\\.Rout$|\\.Rout[.]fail$|\\.txt$|00check[.]log$)",
                basename(fs), ignore.case = TRUE)
  fs <- fs[keep]
  root <- file.path(outputs, "R-CMD-check-logs")
  dir.create(root)
  for (f in fs) {
    rel <- substring(f, nchar(check_subdir) + 2L)
    dest <- file.path(root, rel)
    dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
    if (!file.copy(f, dest, overwrite = TRUE)) stop("Could not copy ", rel)
  }
  list(detail = paste(length(fs), "check logs copied"))
})
} else skip("collect-check-logs", "advisory", "no R CMD check output in this run")

# R CMD INSTALL checks that the freshly built archive can actually be installed.
local_lib <- file.path(report, "local-library")
dir.create(local_lib)
if (built || diagnostic_built) {
  stage("install-built-package", "required", function() {
    log_file <- file.path(logs, "R-CMD-INSTALL-console.txt")
    code <- cmd(r_binary, c("CMD", "INSTALL", paste0("--library=", shQuote(local_lib)),
                           shQuote(tarball)), report, log_file,
                c(OECDDATA_LIVE_TESTS = "false"))
    if (file.exists(log_file)) cat(paste(tail(readLines(log_file, warn = FALSE), 60L),
                                        collapse = "\n"), "\n")
    if (code != 0L) stop("R CMD INSTALL failed (exit=", code, ")")
    .libPaths(c(local_lib, .libPaths()))
    # test_local() may have left the development namespace loaded. Ensure that
    # the installed API and integration stages really exercise this archive.
    if ("OECDdata" %in% loadedNamespaces()) unloadNamespace("OECDdata")
    if (!requireNamespace("OECDdata", quietly = TRUE)) stop("Installation not loadable")
    stopifnot(identical(
      normalizePath(getNamespaceInfo("OECDdata", "path"), winslash = "/"),
      normalizePath(file.path(local_lib, "OECDdata"), winslash = "/")),
      as.character(utils::packageVersion("OECDdata")) == version)
    list(detail = paste("installed", as.character(utils::packageVersion("OECDdata"))))
  })
} else {
  skip("install-built-package", "required", "No successfully built tarball")
}

if (requireNamespace("OECDdata", quietly = TRUE) &&
    "OECDdata" %in% rownames(utils::installed.packages(lib.loc = local_lib))) {
  stage("offline-public-API", "required", function() {
    exports <- getNamespaceExports("OECDdata")
    expected <- c("importData", "importDataList", "importLabels", "importDimLabel",
                  "importMetabase", "describe", "compare", "find", "browseDataList",
                  "as.OECDDataList", "oecdStructure", "oecdDataset", "oecdQuery",
                  "oecdOptions", "oecdExample", "clearCache")
    stopifnot(setequal(exports, expected),
              "OECDDatasetCode" %in% names(formals(OECDdata::importData)),
              !"EurostatDatasetCode" %in% names(formals(OECDdata::importData)),
              !"as.EurostatDataList" %in% exports)
    x <- OECDdata::oecdExample()
    stopifnot(inherits(x, "OECDDataset"), nrow(x) == 12L,
              is.numeric(x$value_), is.character(x$flags_),
              identical(attr(x, "RequestedDatasetCode"), "TEST,DEMO,1.0"),
              length(attr(x, "Dimensions")) > 0L)
    print(utils::head(x)); str(x)
    print(attributes(x)[c("RequestedDatasetCode", "OECDDatasetCode", "Dimensions")])
    list(detail = paste(length(expected), "exports verified; 12 synthetic rows parsed"))
  })
} else {
  skip("offline-public-API", "required", "OECDdata was not installed from this build")
}

if (cfg$api_compare && file.exists(file.path(source_dir, "tools", "check-api.R"))) {
  stage("eurodata-interface-compatibility", "advisory", function() {
    if (!install_if_missing("eurodata", optional = TRUE)) stop("eurodata unavailable")
    need("OECDdata")
    source(file.path(source_dir, "tools", "check-api.R"), local = new.env(parent = globalenv()))
    list(detail = "provider-aware eurodata-formals comparison passed")
  })
} else {
  skip("eurodata-interface-compatibility", "advisory", "disabled or script missing")
}

if (cfg$coverage && !install_if_missing("covr", optional = TRUE)) {
  skip("test-coverage", "advisory",
       "covr not installed; run install.packages('covr') once to enable offline coverage")
} else if (cfg$coverage) {
  stage("test-coverage", "advisory", function() {
    with_env(c(OECDDATA_LIVE_TESTS = "false", NOT_CRAN = "false"), {
      cov <- covr::package_coverage(source_dir, type = "tests", quiet = TRUE)
      saveRDS(cov, file.path(outputs, "test-coverage.rds"))
      coverage <- as.data.frame(cov)
      utils::write.csv(coverage, file.path(outputs, "test-coverage-by-expression.csv"),
                       row.names = FALSE, na = "")
      pct <- as.numeric(covr::percent_coverage(cov))
      cat("Offline test coverage: ", sprintf("%.1f%%", pct), "\n", sep = "")
      list(detail = paste("offline coverage", sprintf("%.1f%%", pct)))
    })
  })
} else {
  skip("test-coverage", "advisory", "disabled by OECDTEST_COVERAGE=0")
}

if (cfg$lint) {
  stage("lintr", "advisory", function() {
    if (!install_if_missing("lintr", optional = TRUE)) stop("lintr unavailable")
    findings <- lintr::lint_package(path = source_dir)
    writeLines(capture.output(print(findings)), file.path(outputs, "lintr-findings.txt"))
    list(detail = paste(length(findings), "style/semantic lints (advisory)"))
  })
} else {
  skip("lintr", "advisory", "disabled by OECDTEST_LINT=0")
}

if (cfg$benchmark && requireNamespace("OECDdata", quietly = TRUE)) {
  stage("offline-parser-benchmark", "advisory", function() {
    bench <- system.file("benchmarks", "parser.R", package = "OECDdata")
    if (!nzchar(bench)) stop("Installed benchmark script not found")
    n <- Sys.getenv("OECDTEST_BENCH_ROWS", "120000")
    with_env(c(OECDDATA_BENCH_ROWS = n, OECDDATA_LIVE_TESTS = "false"), {
      source(bench, local = new.env(parent = globalenv()))
    })
    list(detail = paste("offline benchmark on", n, "synthetic rows"))
  })
} else {
  skip("offline-parser-benchmark", "advisory", "disabled or package not installed")
}

# Share raw OECD responses across BOTH live stages and subsequent diagnostic runs.
# On a warm cache, the second stage downloads nothing. Explicit refresh mode
# still performs a current live fetch and then reuses it for the live testthat run.
live_smoke_ok <- FALSE
if (cfg$live && requireNamespace("OECDdata", quietly = TRUE)) {
  live_smoke_ok <- stage("OECD-live-v2-smoke", "online", function() {
    if (!dir.exists(shared_cache) && !dir.create(shared_cache, recursive = TRUE))
      stop("Cannot create shared live cache: ", shared_cache)
    old <- OECDdata::oecdOptions(api_version = "v2", cache = TRUE,
      cache_dir = shared_cache, cache_ttl = cfg$live_cache_ttl,
      metadata_ttl = cfg$metadata_cache_ttl,
      refresh = cfg$live_fresh, quiet = TRUE,
      strings_as_factors = FALSE, return_data_table = TRUE,
      max_downloads = 5L, retries = 0L, timeout = cfg$live_timeout,
      connect_timeout = 15, min_interval = 0.2)
    on.exit(options(old), add = TRUE)
    selected <- list(
      .dataset = list(agency = "OECD.SDD.STES", prefix = "DSD_STES"),
      REF_AREA = "USA", FREQ = "M", TIME_PERIOD = c("2023-01", "2023-02")
    )
    # If fresh testing is requested, this first import downloads each resource
    # once. Immediately disable refresh to prevent redundant catalogue/structure
    # requests in the follow-up discovery/provenance/cache assertions.
    clocked <- function(label, expression) {
      tic <- proc.time()[["elapsed"]]
      value <- force(expression)
      cat(sprintf("TIMING %-22s %6.2f seconds\n", label,
                  proc.time()[["elapsed"]] - tic))
      value
    }
    dat <- clocked("importData", OECDdata::importData("CLI", selected))
    initial_cached <- isTRUE(attr(dat, "Cached"))
    OECDdata::oecdOptions(refresh = FALSE)
    # The original `old` snapshot restores every setting at stage exit.
    # A live CLI short-code resolution has just been tested by importData().
    # Reuse its exact resolved identity in the remaining assertions. Re-resolving
    # the short code three times would repeatedly parse the large catalogue.
    ref <- attr(dat, "OECDDatasetCode")
    stopifnot(is.character(ref), length(ref) == 1L, nzchar(ref))
    resolved <- clocked("oecdDataset", OECDdata::oecdDataset(ref))
    stopifnot(identical(resolved, ref))
    cat("Canonical reference: ", ref, "\n", sep = "")
    struc <- clocked("oecdStructure", OECDdata::oecdStructure(ref))
    cat("Dimensions:\n"); print(struc$dimensions)
    stopifnot(all(c("REF_AREA", "FREQ", "TIME_PERIOD") %in% struc$dimensions$id))
    query <- clocked("oecdQuery", OECDdata::oecdQuery(ref,
      selected[names(selected) != ".dataset"]))
    cat("Query preview: ", as.character(query), "\n", sep = "")
    cat("Rows returned: ", nrow(dat), "\n", sep = "")
    print(utils::head(dat))
    stopifnot(nrow(dat) > 0L, is.numeric(dat$value_),
              all(as.character(dat$REF_AREA) == "USA"),
              all(as.character(dat$FREQ) == "M"),
              all(as.character(dat$TIME_PERIOD) %in% c("2023-01", "2023-02")),
              identical(attr(dat, "OECDDatasetCode"), ref))
    cached <- clocked("cached import", OECDdata::importData(ref,
      selected[names(selected) != ".dataset"]))
    stopifnot(isTRUE(attr(cached, "Cached")), nrow(cached) == nrow(dat))
    writeLines(c(paste("canonical_ref:", ref), paste("rows:", nrow(dat)),
      paste("source_url:", attr(dat, "SourceURL")),
      paste("initial_call_cached:", initial_cached),
      paste("second_call_cached:", attr(cached, "Cached")),
      paste("refresh_required:", cfg$live_fresh),
      paste("shared_cache:", shared_cache)),
      file.path(outputs, "OECD-live-provenance.txt"))
    list(detail = paste(nrow(dat), "observations; first call",
      if (isTRUE(attr(dat, "Cached"))) "CACHED" else "DOWNLOADED",
      "; cached replay confirmed"))
  })
} else {
  skip("OECD-live-v2-smoke", "online", "disabled or package not installed")
}

# Reuse the identical metadata/data-response cache and canonical identity
# across the separately gated live testthat case. It remains an independent
# test entry point with its own assertions but needs no new catalogue lookup.
if (cfg$live && live_smoke_ok && requireNamespace("testthat", quietly = TRUE) &&
    requireNamespace("pkgload", quietly = TRUE) &&
    requireNamespace("OECDdata", quietly = TRUE)) {
  stage("OECD-live-testthat", "online", function() {
    old <- OECDdata::oecdOptions(api_version = "v2", cache = TRUE,
      cache_dir = shared_cache, cache_ttl = cfg$live_cache_ttl,
      metadata_ttl = cfg$metadata_cache_ttl,
      refresh = FALSE, offline = TRUE, quiet = TRUE, retries = 0L,
      min_interval = 0.2, timeout = cfg$live_timeout, connect_timeout = 15)
    on.exit(options(old), add = TRUE)
    # The smoke stage has already established this reference through a fresh
    # (or verified cached) short-code request. Passing it to the separately
    # executed test prevents another costly catalogue parse, while keeping
    # the standalone live test's normal short-code behavior unchanged.
    provenance <- readLines(file.path(outputs, "OECD-live-provenance.txt"), warn = FALSE)
    canonical <- sub("^canonical_ref:", "", provenance[grepl("^canonical_ref:", provenance)])
    canonical <- trimws(canonical)
    stopifnot(length(canonical) == 1L, nzchar(canonical))
    with_env(c(OECDDATA_LIVE_TESTS = "true", NOT_CRAN = "true",
               OECDDATA_LIVE_REFERENCE = canonical), {
      testthat::test_local(source_dir, reporter = "summary", filter = "live",
                           stop_on_failure = TRUE, stop_on_warning = TRUE,
                           load_package = "installed")
    })
    list(detail = "opt-in integration test assertions passed from verified offline cache")
  })
} else {
  skip("OECD-live-testthat", "online", "disabled, smoke test failed, or required testing packages unavailable")
}

# Explain which stages dominate elapsed time so the next optimisation is data-driven.
wall <- sum(stages$elapsed_seconds, na.rm = TRUE)
top <- stages[order(stages$elapsed_seconds, decreasing = TRUE, na.last = TRUE),
              c("stage", "status", "elapsed_seconds")]
utils::write.csv(top, file.path(outputs, "slowest-stages.csv"), row.names = FALSE, na = "")
writeLines(c(paste("Mode:", mode), sprintf("Total measured stage time: %.1f s", wall),
  "Overlapping dependency installation time and system startup are not included.",
  "A cached live response validates parsing and cache operation, not fresh OECD availability.",
  "Only an unskipped, OK full R CMD check is evidence of local CRAN check success."),
  file.path(outputs, "runtime-summary.txt"))

# Prepare compact feedback: logs and result tables, NOT potentially large caches,
# source copies, temporary installed libraries or binary package trees.
summary_file <- file.path(report, "READ_ME_FIRST.txt")
writeLines(c(
  paste("OECDdata diagnostics for version", version),
  paste("Generated:", format(Sys.time(), tz = "UTC", usetz = TRUE)),
  paste("R:", R.version.string),
  "",
  "Open STAGES.csv first, then logs/ and outputs/.",
  "FAIL = a check failed; WARN = advisory or opinion-tier issue; SKIP = not run.",
  paste("Mode:", mode),
  "A skipped required test is NOT evidence of CRAN-readiness.",
  "Quick mode tests are not a substitute for CRAN's full checks.",
  "If only a no-vignettes diagnostic build passed, the full CRAN gate still failed.",
  "A fast --no-manual diagnostic is not a complete CRAN check.",
  "If a check was skipped owing to Pandoc/LaTeX, install those prerequisites for a true full run.",
  "R CMD check --as-cran without skip flags is the complete local gate.",
  "checktor is an additional CRAN-hosted third-party check package.",
  "Local results do not guarantee acceptance by CRAN or other R platforms.",
  "The report may contain local filesystem paths and public data URLs.",
  "CAUTION: logs can contain sensitive proxy credentials or internal URLs.",
  "Review/redact them before sharing outside a trusted private channel.",
  "",
  "Send back the report ZIP together with your desired R/OS version targets.",
  "If zip creation fails, compress the report directory manually."
), summary_file)

archive_dir <- file.path(report, "feedback")
dir.create(archive_dir)
file.copy(file.path(report, "STAGES.csv"), archive_dir)
file.copy(summary_file, archive_dir)
file.copy(file.path(outputs, "settings.txt"), archive_dir)
file.copy(logs, archive_dir, recursive = TRUE)
file.copy(outputs, archive_dir, recursive = TRUE)

# The report ZIP is meant for feedback and must not publish common credentials
# exposed by verbose proxy/curl logs. Preserve full local logs only in report/;
# redact the COPIED plaintext records in feedback/ before compressing them.
redact_feedback <- function(path) {
  text_files <- list.files(path, recursive = TRUE, full.names = TRUE,
    pattern = "\\.(log|txt|csv|md|json)$", ignore.case = TRUE)
  invisible(lapply(text_files, function(f) {
    lines <- readLines(f, warn = FALSE, encoding = "UTF-8")
    clean <- gsub("(?i)(https?://)[^/@[:space:]]+@",
      "\\1[REDACTED]@", lines, perl = TRUE)
    clean <- gsub("(?i)(proxy-authorization|authorization):[[:space:]]+",
      "\\1: ", clean, perl = TRUE)
    clean <- gsub("(?i)((?:Basic|Bearer)[[:space:]]+)[A-Za-z0-9._~+/-]+=*",
      "\\1[REDACTED]", clean, perl = TRUE)
    clean <- gsub("(?i)((?:password|passwd|access_token|api_key|apikey|secret)=)[^&[:space:]]+",
      "\\1[REDACTED]", clean, perl = TRUE)
    if (!identical(lines, clean)) writeLines(clean, f, useBytes = TRUE)
  }))
}
redact_feedback(archive_dir)

zip_file <- paste0(report, ".zip")
nzip_ok <- FALSE
if (!requireNamespace("zip", quietly = TRUE) && cfg$install) {
  tryCatch(utils::install.packages("zip"), error = function(e)
    message("Could not install 'zip': ", conditionMessage(e)))
}
if (requireNamespace("zip", quietly = TRUE)) {
  nzip_ok <- tryCatch({
    zip::zipr(zip_file, files = list.files(archive_dir, all.files = TRUE,
                  no.. = TRUE), root = archive_dir)
    file.exists(zip_file)
  }, error = function(e) {
    message("zip::zipr failed: ", conditionMessage(e)); FALSE
  })
}
if (!nzip_ok && nzchar(Sys.which("zip"))) {
  previous <- setwd(archive_dir)
  nzip_ok <- tryCatch({
    utils::zip(zip_file, files = list.files(".", all.files = TRUE, no.. = TRUE),
               flags = "-r9X")
    file.exists(zip_file)
  }, error = function(e) FALSE, finally = setwd(previous))
}
message("\n=== SUMMARY ===")
print(stages, row.names = FALSE)
message("Report directory: ", report)
if (nzip_ok) {
  message("SHARE THIS ZIP: ", zip_file)
} else {
  message("ZIP unavailable. Compress the feedback/ subdirectory and share it.")
}
message("R CMD check may report environment-specific NOTES. Inspect them individually.")
message("Do not treat SKIP or WARN statuses as a confirmed CRAN pass.")

# Exit 1 for failed/skipped required tests, AFTER producing the report.
# A completed 'quick' run has an exit 0 only for that explicit, limited mode.
core_bad <- with(stages, (
  class == "required" & status != "PASS" &
    !(stage == "checktor-all-diagnostics" & status == "WARN" &
      grepl("opinion-tier findings", detail, fixed = TRUE))) |
  (cfg$live & class == "online" & status != "PASS"))
if (!interactive()) {
  quit(save = "no", status = if (any(core_bad) || !nzip_ok) 1L else 0L)
}
invisible(stages)
