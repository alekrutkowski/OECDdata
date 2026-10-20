# R CMD build copies the source tree before applying .Rbuildignore. On Windows,
# open diagnostic logs inside .qa cannot be copied. Stage source without local
# build output so checks work even when their reports live inside the project.
package_source <- function(path) {
  snapshot <- tempfile("OECDdata-source-")
  dir.create(snapshot)
  snapshot <- file.path(snapshot, "OECDdata")
  dir.create(snapshot)
  entries <- list.files(path, all.files = TRUE, no.. = TRUE, full.names = TRUE)
  entries <- entries[!basename(entries) %in% c(".qa", ".git", ".agents", ".codex", ".aws")]
  if (!all(file.copy(entries, snapshot, recursive = TRUE, copy.date = TRUE)))
    stop("Could not stage the package source for R CMD build.")
  snapshot
}
