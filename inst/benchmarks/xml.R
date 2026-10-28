# Offline XML benchmarks. No network requests are made.
#
# Installed usage:
#   source(system.file("benchmarks", "xml.R", package = "OECDdata"))
#
# Defaults: 1,500 synthetic flows, a 10,000-code synthetic dictionary, three
# timed repetitions and one data.table thread. Each timed call reads the file
# and constructs the complete catalogue/structure result. Result parity is
# asserted before timing. Generation, parity checks, hashing and explicit GC
# are excluded from timings. GC occurring during parsing is included.
#
# Optional environment variables:
#   OECDDATA_BENCH_CATALOGUE  existing catalogue XML file
#   OECDDATA_BENCH_STRUCTURE  existing structure XML file
#   OECDDATA_BENCH_REFERENCE  exact AGENCY,DATAFLOW,VERSION for that structure
#                            (inferred only if its maintained flow is unique)
#   OECDDATA_BENCH_FLOWS      synthetic catalogue size (default 1500)
#   OECDDATA_BENCH_CODES      synthetic REF_AREA dictionary size (default 10000)
#   OECDDATA_BENCH_RUNS       timed repetitions (default 3)
#   OECDDATA_BENCH_THREADS    data.table threads for both parsers (default 1)
#   OECDDATA_BENCH_OUTPUT     optional per-run CSV destination
#
# File-system cache is warm after the parity check. Results measure XML
# processing, not HTTP transfers, raw-response cache hashing or peak memory.
(function() {
  stopifnot(requireNamespace("OECDdata", quietly = TRUE),
    requireNamespace("xml2", quietly = TRUE),
    requireNamespace("data.table", quietly = TRUE),
    requireNamespace("digest", quietly = TRUE))
  `%>%` <- magrittr::`%>%`
  ns <- asNamespace("OECDdata")
  integer_option <- function(name, default, minimum = 1L) {
    text <- Sys.getenv(name, as.character(default))
    value <- suppressWarnings(as.integer(text))
    if (!grepl("^[0-9]+$", text) || is.na(value) || value < minimum)
      stop(name, " must be an integer >= ", minimum, ".")
    value
  }
  runs <- integer_option("OECDDATA_BENCH_RUNS", 3L)
  threads <- integer_option("OECDDATA_BENCH_THREADS", 1L)
  old_threads <- data.table::getDTthreads()
  data.table::setDTthreads(threads)
  on.exit(data.table::setDTthreads(old_threads), add = TRUE)
  old_options <- OECDdata::oecdOptions(quiet = TRUE)
  on.exit(options(old_options), add = TRUE)

  reference_file <- system.file("benchmarks", "xml-reference-0.2.5.R", package = "OECDdata")
  if (!nzchar(reference_file)) {
    # Also allow source("inst/benchmarks/xml.R") during local development.
    source_path <- tryCatch(sys.frame(1L)$ofile, error = function(e) NULL)
    if (!is.null(source_path)) reference_file <- file.path(dirname(source_path), "xml-reference-0.2.5.R")
  }
  if (!nzchar(reference_file) || !file.exists(reference_file))
    stop("The frozen 0.2.5 benchmark reference file is missing. Reinstall OECDdata.")
  legacy <- new.env(parent = ns)
  sys.source(reference_file, envir = legacy, keep.source = FALSE)
  invisible(lapply(ls(legacy, all.names = TRUE), function(name) {
    value <- get(name, legacy, inherits = FALSE)
    if (is.function(value)) assign(name, compiler::cmpfun(value), legacy)
  }))

  temporary <- tempfile("oecd-xml-benchmark-")
  dir.create(temporary)
  on.exit(unlink(temporary, recursive = TRUE), add = TRUE)
  normalize_input <- function(path, name) {
    if (!file.exists(path) || dir.exists(path)) stop(name, " is not an existing XML file: ", path)
    normalizePath(path, winslash = "/", mustWork = TRUE)
  }
  parse_reference <- function(value) {
    parts <- strsplit(value, ",", fixed = TRUE)[[1L]]
    if (length(parts) != 3L || any(!nzchar(parts)) ||
        any(parts %in% c("*", "+", "latest")))
      stop("OECDDATA_BENCH_REFERENCE must be an exact AGENCY,DATAFLOW,VERSION.")
    stats::setNames(as.list(parts), c("agency", "id", "version"))
  }

  catalogue_path <- Sys.getenv("OECDDATA_BENCH_CATALOGUE")
  catalogue_kind <- if (nzchar(catalogue_path)) "supplied XML" else "synthetic XML"
  if (!nzchar(catalogue_path)) {
    n <- integer_option("OECDDATA_BENCH_FLOWS", 1500L)
    catalogue_path <- file.path(temporary, "catalogue.xml")
    flows <- lapply(seq_len(n), function(i) paste0(
      '<s:Dataflow agencyID="BENCH" id="DSD_BENCH@DF_', sprintf("%06d", i), '" version="1.0">',
      '<c:Name xml:lang="en">Synthetic dataset ', i, ' &amp; benchmark</c:Name>',
      '<c:Name xml:lang="fr">Jeu de donn&#233;es fictif ', i, '</c:Name>',
      '<c:Description xml:lang="en">Generated metadata; no real statistics.</c:Description>',
      '<c:Annotations><c:Annotation><c:AnnotationType>UPDATE_DATA</c:AnnotationType>',
      '<c:AnnotationTitle>2024-01-01</c:AnnotationTitle></c:Annotation>',
      '<c:Annotation><c:AnnotationType>UPDATE_STRUCTURE</c:AnnotationType>',
      '<c:AnnotationText xml:lang="en">2023-12-01</c:AnnotationText></c:Annotation>',
      '<c:Annotation><c:AnnotationType>OBS_PERIOD_OVERALL_OLDEST</c:AnnotationType>',
      '<c:AnnotationTitle>2000-01</c:AnnotationTitle></c:Annotation>',
      '<c:Annotation><c:AnnotationType>OBS_PERIOD_OVERALL_LATEST</c:AnnotationType>',
      '<c:AnnotationTitle>2023-12</c:AnnotationTitle></c:Annotation></c:Annotations>',
      '<s:Structure><Ref agencyID="BENCH" id="DSD_BENCH" version="1.0"/></s:Structure>',
      '</s:Dataflow>')) %>% unlist(use.names = FALSE)
    writeLines(c('<m:Structure xmlns:m="urn:message" xmlns:s="urn:structure" xmlns:c="urn:common">',
      '<s:Dataflows>', flows, '</s:Dataflows></m:Structure>'), catalogue_path, useBytes = TRUE)
  }
  catalogue_path <- normalize_input(catalogue_path, "OECDDATA_BENCH_CATALOGUE")

  structure_path <- Sys.getenv("OECDDATA_BENCH_STRUCTURE")
  structure_kind <- if (nzchar(structure_path)) "supplied XML" else "synthetic XML"
  reference_text <- Sys.getenv("OECDDATA_BENCH_REFERENCE")
  if (!nzchar(structure_path)) {
    n <- integer_option("OECDDATA_BENCH_CODES", 10000L, minimum = 4L)
    fixture <- system.file("extdata", "structure.xml", package = "OECDdata")
    structure_text <- paste(readLines(fixture, warn = FALSE, encoding = "UTF-8"), collapse = "\n")
    codes <- c("USA", "FRA", "DEU", "ZZZ", if (n > 4L) sprintf("X%07d", seq_len(n - 4L)))
    block <- lapply(seq_along(codes), function(i) paste0('<s:Code id="', codes[[i]], '">',
      '<c:Name xml:lang="en">Synthetic country ', i, '</c:Name>',
      '<c:Name xml:lang="fr">Pays fictif ', i, '</c:Name></s:Code>')) %>%
      unlist(use.names = FALSE) %>% paste(collapse = "")
    # Replace exactly one complete codelist in the bundled fixture, outside timings.
    pattern <- '(?s)<s:Codelist id="CL_REF_AREA"[^>]*>.*?</s:Codelist>'
    stopifnot(length(regmatches(structure_text, gregexpr(pattern, structure_text, perl = TRUE))[[1L]]) == 1L)
    replacement <- paste0('<s:Codelist id="CL_REF_AREA" agencyID="TEST" version="1.0">',
      '<c:Name xml:lang="en">Synthetic reference areas</c:Name>', block, '</s:Codelist>')
    structure_text <- sub(pattern, replacement, structure_text, perl = TRUE)
    structure_path <- file.path(temporary, "structure.xml")
    writeLines(structure_text, structure_path, useBytes = TRUE)
    if (!nzchar(reference_text)) reference_text <- "TEST,DEMO,1.0"
  }
  structure_path <- normalize_input(structure_path, "OECDDATA_BENCH_STRUCTURE")
  if (!nzchar(reference_text)) {
    doc <- xml2::read_xml(structure_path, options = c("NOBLANKS", "NONET"))
    nodes <- xml2::xml_find_all(doc, ".//*[local-name()='Dataflow' and @agencyID!='' and @id!='']")
    references <- unique(paste(xml2::xml_attr(nodes, "agencyID"), xml2::xml_attr(nodes, "id"),
      xml2::xml_attr(nodes, "version"), sep = ","))
    if (length(references) != 1L || anyNA(xml2::xml_attr(nodes, "version")))
      stop("The supplied structure does not have one exact dataflow reference; set OECDDATA_BENCH_REFERENCE.")
    reference_text <- references[[1L]]
    rm(doc, nodes)
  }
  reference <- parse_reference(reference_text)

  cases <- list(
    catalogue = list(path = catalogue_path, input = catalogue_kind, reference = "",
      old = function() legacy$.parse_catalogue(xml2::read_xml(catalogue_path,
        options = c("NOBLANKS", "NONET"))),
      new = function() ns$.parse_catalogue(ns$.read_xml(catalogue_path, TRUE)),
      count = function(value) nrow(value), count_unit = "catalogue rows"),
    structure = list(path = structure_path, input = structure_kind, reference = reference_text,
      old = function() legacy$.parse_structure(xml2::read_xml(structure_path,
        options = c("NOBLANKS", "NONET")), reference),
      new = function() ns$.parse_structure(ns$.read_xml(structure_path, TRUE), reference),
      count = function(value) sum(vapply(value$labels, nrow, integer(1))),
      count_unit = "dictionary codes"))

  cat("Offline XML benchmark: complete file read + metadata extraction.\n")
  cat("OECDdata:", as.character(utils::packageVersion("OECDdata")),
    "| language:", ns$.opt("language"), "| data.table threads:", data.table::getDTthreads(), "\n")
  cat("Legacy 0.2.5 R functions are explicitly byte-compiled.\n")
  cat("Parity checks warm file-system caches; no downloads or peak-memory measurements.\n\n")

  timings <- lapply(names(cases), function(task) {
    case <- cases[[task]]
    readers <- list(legacy_0.2.5 = compiler::cmpfun(case$old), native_C = compiler::cmpfun(case$new))
    cat("Checking result parity:", task, "...\n")
    results <- lapply(readers, function(reader) reader())
    comparison <- if (identical(results[[1L]], results[[2L]])) TRUE else
      all.equal(results[[1L]], results[[2L]], check.attributes = TRUE)
    if (!isTRUE(comparison)) stop("Result mismatch for ", task, ": ", paste(comparison, collapse = "; "))
    count <- case$count(results[[1L]])
    sizes <- vapply(results, function(value) as.numeric(utils::object.size(value)), numeric(1))
    input_bytes <- file.info(case$path, extra_cols = FALSE)$size
    sha256 <- digest::digest(file = case$path, algo = "sha256")
    cat("Parity passed |", format(count, big.mark = ","), case$count_unit,
      "|", format(input_bytes, big.mark = ","), "input bytes\n")
    cat("Input SHA-256:", sha256, "\n")
    if (nzchar(case$reference)) cat("Structure reference:", case$reference, "\n")
    rm(results)
    lapply(seq_len(runs), function(run) {
      # Alternate execution order to avoid always giving one parser first use.
      order <- if (run %% 2L) names(readers) else rev(names(readers))
      lapply(order, function(parser) {
        invisible(gc())
        elapsed <- system.time(invisible(readers[[parser]]()), gcFirst = FALSE)
        row <- data.table::data.table(task = task, parser = parser, run = run,
          user_seconds = unname(elapsed[["user.self"]]),
          system_seconds = unname(elapsed[["sys.self"]]),
          elapsed_seconds = unname(elapsed[["elapsed"]]),
          input = case$input, input_bytes = input_bytes, sha256 = sha256,
          reference = case$reference, output_count = count, count_unit = case$count_unit,
          result_bytes = unname(sizes[[parser]]), threads = data.table::getDTthreads(),
          language = ns$.opt("language"), parity = TRUE)
        cat(sprintf("  %-13s run %d: user %.3f, system %.3f, elapsed %.3f seconds\n",
          parser, run, row$user_seconds, row$system_seconds, row$elapsed_seconds))
        row
      }) %>% data.table::rbindlist()
    }) %>% data.table::rbindlist()
  }) %>% data.table::rbindlist()

  summary <- timings[, list(median_user_seconds = stats::median(user_seconds),
    median_system_seconds = stats::median(system_seconds),
    median_elapsed_seconds = stats::median(elapsed_seconds),
    min_elapsed_seconds = min(elapsed_seconds), result_bytes = result_bytes[[1L]]),
    by = c("task", "parser")]
  speedups <- lapply(unique(summary$task), function(task_name) {
    selected <- summary[task == task_name]
    old <- selected[parser == "legacy_0.2.5"]$median_elapsed_seconds
    new <- selected[parser == "native_C"]$median_elapsed_seconds
    data.table::data.table(task = task_name, legacy_median_seconds = old,
      native_median_seconds = new, speedup = if (new > 0) old / new else NA_real_)
  }) %>% data.table::rbindlist()
  cat("\nMedians over", runs, "repetitions (result size is not peak memory):\n")
  print(summary)
  cat("\nSpeedup = legacy median elapsed / native median elapsed.\n")
  cat("NA speedups mean the native median was below the elapsed timer's resolution.\n")
  print(speedups)
  output <- Sys.getenv("OECDDATA_BENCH_OUTPUT")
  if (nzchar(output)) {
    data.table::fwrite(timings, output)
    cat("\nPer-run CSV:", normalizePath(output, winslash = "/", mustWork = TRUE), "\n")
  }
  session <- utils::sessionInfo()
  cat("\n")
  print(session)
  invisible(list(timings = timings, summary = summary, speedups = speedups, session = session))
})()
