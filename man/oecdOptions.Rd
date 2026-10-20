\name{oecdOptions}
\alias{oecdOptions}
\alias{clearCache}
\title{Read or Set OECDdata Options}
\description{Read or Set OECDdata Options.}
\usage{
oecdOptions(...)

clearCache()
}
\arguments{
\item{...}{Named option values without the \code{OECDdata.} prefix. With no arguments, return all current settings.}
}
\value{With no arguments, \code{oecdOptions} returns a named settings list. When
setting options, it invisibly returns the previous, fully prefixed options, so
\code{options(old)} restores them. \code{clearCache} invisibly returns the number
of owned cache files removed, not the number of requests.}
\details{
All settings are ordinary R options prefixed with \code{OECDdata.}.
\describe{
\item{api_version}{\code{"v2"} by default; explicitly select \code{"v1"} for legacy routes.}
\item{base_url}{\code{"https://sdmx.oecd.org/public/rest"}. An HTTPS root ending in \code{/rest}, without \code{/v2}.}
\item{language}{\code{"en"}; requested metadata language.}
\item{dataset}{\code{NULL}; default context for labels and scoped metabase calls.}
\item{cache, cache_dir}{\code{TRUE}, \code{NULL}; a session temporary directory unless explicitly configured.}
\item{cache_ttl, metadata_ttl}{\code{3600}, \code{86400} seconds, respectively.}
\item{offline, refresh}{Both \code{FALSE}. Offline accepts expired but verified entries. Refresh bypasses cache reuse online.}
\item{timeout, connect_timeout}{\code{120}, \code{20} seconds.}
\item{retries, max_retry_wait}{\code{3}, \code{60}; retry count after the initial attempt and maximum allowed retry delay in seconds.}
\item{min_interval}{\code{1} second between requests in this session.}
\item{max_downloads, download_window}{\code{60}, \code{3600}; local rolling data-attempt budget. Retries count; metadata requests do not.}
\item{strings_as_factors, return_data_table}{\code{TRUE}, \code{FALSE}; compatible default result types.}
\item{quiet, open_browser}{\code{FALSE}, \code{interactive()}; suppress progress messages or control interactive reports.}
\item{availability}{\code{"actual"}; use \code{"allowed"} only for explicitly requested dictionary-code inventories.}
\item{max_bytes}{\code{Inf}; optional response-size limit in bytes.}
}
HTTP Retry-After is respected. Delays above the configured maximum produce an
error, never an early retry. A local budget cannot account for other sessions
sharing an IP address. It is not a guarantee against service throttling.

Cache identities include URL, media type and language. Entries carry checksums,
status and original download times. Only package-owned files are removed by
\code{clearCache}. No shared-process locking or automatic eviction is provided;
use a separate cache directory per concurrent writer. Checksums detect corruption
but are not a substitute for trusting the configured local directory.
The setter returns the prior namespaced settings invisibly. In a function,
use \code{old <- oecdOptions(...)} and
\code{on.exit(options(old), add = TRUE)} to restore them when leaving.

The size limit is enforced by libcurl when the server advertises a usable length
and is checked after transfer and before returning a cached response as well.
It is not an absolute bound on bytes
received when a response has no advertised size.
}
\examples{
old <- oecdOptions(quiet = TRUE, strings_as_factors = FALSE)
x <- oecdExample()
stopifnot(is.character(x$REF_AREA))
options(old)

}
\seealso{\link{importData}, \link{importMetabase}}
