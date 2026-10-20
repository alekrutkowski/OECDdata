# Extra CRAN diagnostics: Rscript --vanilla tools/checktor.R .
# Set OECDTEST_CHECKTOR_URLS=1 for live URL checks and
# OECDTEST_CHECKTOR_STRICT=1 to require every enabled check to execute.
args <- commandArgs(trailingOnly = TRUE)
path <- normalizePath(if (length(args)) args[[1L]] else ".", mustWork = TRUE)
if (!requireNamespace("checktor", quietly = TRUE) ||
    utils::packageVersion("checktor") < "0.2.0")
  stop("Install checktor >= 0.2.0 (requires R >= 4.5).")
urls <- Sys.getenv("OECDTEST_CHECKTOR_URLS", "0") %in% c("1", "true")
strict <- Sys.getenv("OECDTEST_CHECKTOR_STRICT", "0") %in% c("1", "true")
options(checktor.url_check = urls)
result <- checktor::checktor(path, verbose = FALSE, progress = FALSE,
                            severity = c("policy", "robustness", "opinion"))
out <- file.path(path, ".qa", "checktor")
if (!dir.exists(out) && !dir.create(out, recursive = TRUE))
  stop("Cannot create checktor output directory.")
saveRDS(result, file.path(out, "results.rds"))
utils::write.csv(as.data.frame(result), file.path(out, "checks.csv"),
                 row.names = FALSE)
findings <- checktor::issues(result)
utils::write.csv(findings, file.path(out, "issues.csv"), row.names = FALSE)
print(result)
if (nrow(findings)) print(findings)
skipped <- result$metadata$skipped_checks
if (length(skipped)) message("Not executed: ", paste(skipped, collapse = ", "))
required_skips <- setdiff(skipped, if (!urls) "url_liveness" else character())
if (nrow(findings) || (strict && length(required_skips)) ||
    (urls && "url_liveness" %in% skipped))
  stop("checktor found issues or could not execute required checks; see ", out)
