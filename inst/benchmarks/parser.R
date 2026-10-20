# Offline component benchmark; never run by package examples or ordinary checks.
# OECDDATA_BENCH_ROWS controls generated row count (default 120,000).
# Compares only CSV ingestion, not metadata, HTTP, validation or peak memory.
(function() {
  stopifnot(requireNamespace("data.table", quietly = TRUE))
  n <- suppressWarnings(as.integer(Sys.getenv("OECDDATA_BENCH_ROWS", "120000")))
  if (length(n) != 1L || is.na(n) || n < 12L) stop("Set OECDDATA_BENCH_ROWS to an integer >= 12.")
  seed <- data.table::fread(system.file("extdata", "example.csv", package = "OECDdata"),
                           colClasses = "character", na.strings = NULL)
  path <- tempfile(fileext = ".csv")
  on.exit(unlink(path))
  data.table::fwrite(seed[rep(seq_len(nrow(seed)), length.out = n)], path)
  readers <- list(
    native_fread = function() data.table::fread(path, colClasses = "character",
      na.strings = NULL, check.names = FALSE, showProgress = FALSE),
    base_read_csv = function() utils::read.csv(path, colClasses = "character",
      na.strings = NULL, check.names = FALSE, stringsAsFactors = FALSE, comment.char = "")
  )
  check <- lapply(readers, function(f) as.data.frame(f()))
  stopifnot(identical(check[[1L]], check[[2L]]))
  result <- lapply(names(readers), function(name) {
    f <- readers[[name]]
    elapsed <- vapply(seq_len(3L), function(i) {
      invisible(gc())
      unname(system.time(f())[["elapsed"]])
    }, numeric(1))
    data.frame(parser = name, rows = n, file_mb = file.info(path, extra_cols = FALSE)$size / 1024^2,
      median_seconds = stats::median(elapsed), min_seconds = min(elapsed),
      result_mb = as.numeric(utils::object.size(check[[name]])) / 1024^2)
  })
  cat("Native parser threads:", data.table::getDTthreads(), "\n")
  cat("Three warm-file repetitions. Result size is not peak RSS. No network included.\n")
  print(do.call(rbind, result), row.names = FALSE)
  print(utils::sessionInfo())
})()
