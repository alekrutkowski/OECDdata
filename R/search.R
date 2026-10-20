#' Coerce a data frame to an OECD catalogue
#' @export
as.OECDDataList <- function(x, SearchCriteria = "", ...) {
  if (!is.data.frame(x) || !all(c("Code", "Dataset name", "Link") %in% names(x)))
    .abort("`x` must be a data frame containing Code, Dataset name and Link.")
  .scalar_string(SearchCriteria, "SearchCriteria", empty = TRUE)
  x <- data.table::copy(x) %>% as.data.frame()
  class(x) <- c("OECDDataList", "data.frame")
  attr(x, "SearchCriteria") <- SearchCriteria
  x
}

.term <- function(expr) {
  negative <- is.call(expr) && identical(expr[[1L]], as.name("-")) && length(expr) == 2L
  if (negative) expr <- expr[[2L]]
  if (!(is.symbol(expr) || (is.atomic(expr) && length(expr) == 1L && !is.na(expr))))
    .abort("Each find() term must be a word, number or quoted pattern, optionally preceded by minus.")
  list(text = as.character(expr), negative = negative)
}
.matches <- function(x, terms) {
  x[is.na(x)] <- ""
  Reduce(function(keep, term) {
    found <- tryCatch(grepl(term$text, x, ignore.case = TRUE),
      error = function(e) .abort(paste0("Invalid search pattern: ", term$text)),
      warning = function(w) .abort(paste0("Invalid search pattern: ", term$text)))
    keep & if (term$negative) !found else found
  }, terms, init = rep(TRUE, length(x)))
}
.text_report <- function(df, criteria) {
  rows <- vapply(seq_len(nrow(df)), function(i) paste0(i, ". ", df[["Dataset name"]][[i]],
    "\n   ", df$Code[[i]], "\n   ", df$Link[[i]]), character(1))
  paste(c(paste0("OECD datasets: ", nrow(df), " matches"), paste0("Search: ", criteria), rows), collapse = "\n\n")
}

#' Search dataset codes or titles using words and exclusions
#' @export
find <- function(...) {
  expr <- as.list(substitute(list(...)))[-1L]
  terms <- lapply(expr, .term)
  criteria <- paste(vapply(expr, function(x) paste(deparse(x), collapse = " "), character(1)), collapse = ", ")
  df <- importDataList()
  # eurodata matches all conditions in Code OR all conditions in Dataset name.
  keep <- .matches(as.character(df$Code), terms) | .matches(as.character(df[["Dataset name"]]), terms)
  df <- df[keep, , drop = FALSE]
  report <- structure(.text_report(df, criteria), class = c("FoundOECDDatasetListReport", "character"))
  structure(list(criteria = criteria, time = Sys.time(), df = df, report = report),
    class = "FoundOECDDatasetList")
}

.escape_html <- function(x) {
  x <- as.character(x); x[is.na(x)] <- ""
  Reduce(function(s, pair) gsub(pair[[1L]], pair[[2L]], s, fixed = TRUE),
    list(c("&", "&amp;"), c("<", "&lt;"), c(">", "&gt;"), c('"', "&quot;"), c("'", "&#39;")), init = x)
}
# OECD descriptions contain HTML fragments (often malformed).  Render only
# semantic formatting and safe links.  The source catalogue is not trusted HTML.
.safe_description_html <- function(x) {
  if (is.na(x) || !nzchar(x)) return("")
  doc <- tryCatch(xml2::read_html(
    paste0('<!doctype html><html><body><div id="oecd-description-root">',
      x, '</div></body></html>'),
    options = c("RECOVER", "NONET", "NOERROR", "NOWARNING")),
    error = function(e) NULL)
  if (is.null(doc)) return(.escape_html(x))
  root <- xml2::xml_find_first(doc, "//*[@id='oecd-description-root']")
  if (inherits(root, "xml_missing")) return(.escape_html(x))
  allowed <- c("p", "div", "br", "hr", "b", "strong", "em", "i", "u",
    "ul", "ol", "li", "h2", "h3", "h4", "blockquote", "code", "sup", "sub")
  omitted <- c("script", "style", "iframe", "object", "embed", "svg", "math",
    "form", "input", "button", "template", "meta", "link", "head")
  safe_href <- function(url) {
    length(url) == 1L && !is.na(url) &&
      (grepl('^https?://[^[:space:][:cntrl:]"<>]+$', url, ignore.case = TRUE) ||
       grepl('^mailto:[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$', url, ignore.case = TRUE))
  }
  render <- function(node) {
    type <- xml2::xml_type(node)
    if (type %in% c("text", "cdata")) return(.escape_html(xml2::xml_text(node)))
    if (type != "element") return("")
    tag <- tolower(xml2::xml_name(node))
    if (tag %in% omitted) return("")
    if (tag == "br" || tag == "hr") return(paste0("<", tag, ">"))
    content <- paste(vapply(as.list(xml2::xml_contents(node)), render,
      character(1)), collapse = "")
    if (tag == "a") {
      url <- xml2::xml_attr(node, "href")
      if (safe_href(url)) return(paste0('<a rel="noopener noreferrer" href="',
        .escape_html(url), '">', content, '</a>'))
      return(content)
    }
    if (tag %in% allowed) paste0("<", tag, ">", content, "</", tag, ">")
    else content
  }
  paste(vapply(as.list(xml2::xml_contents(root)), render, character(1)),
    collapse = "")
}

.html_report <- function(df, criteria) {
  cols <- names(df)[!vapply(df, function(x) all(is.na(x) | as.character(x) == ""), logical(1))]
  cells <- lapply(cols, function(n) {
    x <- as.character(df[[n]])
    if (n == "Description") return(vapply(x, .safe_description_html, character(1)))
    if (n != "Link") return(.escape_html(x))
    safe <- !is.na(x) &
      grepl('^https?://[^[:space:][:cntrl:]"<>]+$', x, ignore.case = TRUE)
    ifelse(safe, paste0('<a rel="noopener noreferrer" href="', .escape_html(x), '">Open dataset</a>'), .escape_html(x))
  })
  rows <- vapply(seq_len(nrow(df)), function(i) paste0("<tr>",
    paste0("<td>", vapply(cells, `[[`, character(1), i), "</td>", collapse = ""), "</tr>"), character(1))
  paste0('<!doctype html><html lang="en"><head><meta charset="utf-8">',
    '<meta name="viewport" content="width=device-width, initial-scale=1">',
    '<title>OECDdata catalogue</title><style>',
    'body{font:16px system-ui,sans-serif;margin:2rem}table{border-collapse:collapse;width:100%}',
    'td,th{border:1px solid #bbb;padding:.6rem;text-align:left;vertical-align:top}',
    'th{background:#eee;position:sticky;top:0}tr:nth-child(even){background:#fafafa}',
    '</style></head><body><h1>OECDdata</h1><p>', nrow(df), ' datasets. ', .escape_html(criteria),
    '</p><table><thead><tr>', paste0("<th>", .escape_html(cols), "</th>", collapse = ""),
    '</tr></thead><tbody>', paste(rows, collapse = ""), '</tbody></table></body></html>')
}

#' Browse a catalogue subset specified as an R expression
#' @export
browseDataList <- function(subs) {
  expr <- substitute(subs)
  df <- importDataList()
  keep <- eval(expr, envir = df, enclos = parent.frame())
  if (!is.logical(keep) || !(length(keep) %in% c(1L, nrow(df))))
    .abort("`subs` must evaluate to a logical vector of length one or nrow(importDataList()).")
  if (length(keep) == 1L) keep <- rep(keep, nrow(df))
  keep[is.na(keep)] <- FALSE
  df <- df[keep, , drop = FALSE]
  criteria <- paste(deparse(expr), collapse = " ")
  structure(list(criteria = criteria, time = Sys.time(), df = df, html = .html_report(df, criteria)),
    class = "BrowsedOECDDatasetList")
}

# The browser can read the file asynchronously after browseURL() returns.
# Keep previews for this R session rather than unlinking them prematurely;
# R cleans its per-session tempdir() when the session exits. A monotonically
# increasing index avoids collisions when the user opens several previews.
.browser_report_file <- function(contents, extension = "html") {
  if (!(extension %in% c("html", "txt"))) .abort("Unsupported browser report format.")
  .state$browser_file_index <- .state$browser_file_index + 1L
  path <- file.path(tempdir(), sprintf("OECDdata-preview-%d-%08d.%s",
    Sys.getpid(), .state$browser_file_index, extension))
  writeLines(contents, path, useBytes = TRUE)
  path
}

print.OECDDataList <- function(x, SearchCriteria = attr(x, "SearchCriteria"), ...) {
  if (is.null(SearchCriteria)) SearchCriteria <- ""
  .scalar_string(SearchCriteria, "SearchCriteria", empty = TRUE)
  if (isTRUE(.opt("open_browser")) && interactive()) {
    utils::browseURL(.browser_report_file(.html_report(x, SearchCriteria)))
  } else print.data.frame(x, ...)
  invisible(x)
}
print.BrowsedOECDDatasetList <- function(x, ...) {
  if (isTRUE(.opt("open_browser")) && interactive()) {
    utils::browseURL(.browser_report_file(x$html))
  } else print.data.frame(x$df, ...)
  invisible(x)
}
print.FoundOECDDatasetList <- function(x, ...) {
  if (isTRUE(.opt("open_browser")) && interactive()) {
    file.show(.browser_report_file(as.character(x$report), "txt"),
      title = "OECDdata search results")
  } else cat(as.character(x$report), "\n")
  invisible(x)
}
print.FoundOECDDatasetListReport <- function(x, ...) {
  if (length(x)) cat(as.character(x), "\n")
  invisible(x)
}
