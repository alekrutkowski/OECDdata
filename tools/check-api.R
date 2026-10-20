# Optional comparison with the actual upstream eurodata API, with intentional
# provider-specific renaming. OECDdata never calls eurodata at runtime.
if (!requireNamespace("OECDdata", quietly = TRUE)) stop("Install OECDdata first.")
if (!requireNamespace("eurodata", quietly = TRUE)) stop("Install eurodata to run this optional comparison.")
reference <- c("as.EurostatDataList", "browseDataList", "compare", "describe", "find",
               "importData", "importDataList", "importDimLabel", "importLabels", "importMetabase")
name_map <- c(as.EurostatDataList = "as.OECDDataList")
argument_map <- c(EurostatDatasetCode = "OECDDatasetCode", EurostatDimCode = "OECDDimCode")
upstream <- sort(getNamespaceExports("eurodata"))
stopifnot(identical(upstream, sort(reference)))
results <- lapply(reference, function(upstream_name) {
  local_name <- if (upstream_name %in% names(name_map)) name_map[[upstream_name]] else upstream_name
  a <- as.list(formals(getExportedValue("eurodata", upstream_name)))
  b <- as.list(formals(getExportedValue("OECDdata", local_name)))
  # Map argument names, retaining default expressions. Added trailing formals
  # remain allowed. Provider-specific output identities are tested separately.
  if (length(a)) names(a) <- vapply(names(a), function(n)
    if (n %in% names(argument_map)) argument_map[[n]] else n, character(1))
  pass <- if (!length(a)) TRUE else identical(a, b[seq_along(a)])
  data.frame(upstream_function = upstream_name, oecd_function = local_name,
             mapped_defaults_match = pass)
})
results <- do.call(rbind, results)
print(results, row.names = FALSE)
cat("Compared against eurodata", as.character(utils::packageVersion("eurodata")), "\n")
stopifnot(all(results$mapped_defaults_match))
