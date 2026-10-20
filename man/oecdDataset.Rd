\name{oecdDataset}
\alias{oecdDataset}
\title{Resolve an OECD Dataset to a Canonical Reference}
\description{Resolve a readable dataset code, optional identity selectors and
its structure version without downloading observations.}
\usage{
oecdDataset(OECDDatasetCode, agency = NULL, prefix = NULL, version = NULL)
}
\arguments{
\item{OECDDatasetCode}{A short code, a complete dataflow ID, or a reference
\code{"AGENCY,DATAFLOW[,VERSION]"}. For example \code{"CLI"}, \code{"DF_CLI"},
\code{"DSD_STES@DF_CLI"}, or \code{"OECD.SDD.STES,DSD_STES@DF_CLI"}.}
\item{agency}{Optional single agency identifier, for example \code{"OECD.SDD.STES"}.}
\item{prefix}{Optional dataflow namespace prefix before \code{@}, for example
\code{"DSD_STES"}. This selects the prefix of the dataflow identifier; the actual
referenced data structure is still resolved from the returned metadata.}
\item{version}{Optional numeric version string, \code{"latest"}, or \code{"+"}.
An omitted version selects the catalogue's current stable version. An explicit
older version is requested even when the current catalogue lists a newer one;
the service must still supply metadata for that older version.}
}
\value{One character string containing the canonical, fully qualified
\code{"AGENCY,DATAFLOW,VERSION"} reference with an exact resolved version.}
\details{
This is a package-level convenience, not a different OECD API. For unqualified
input, matching is case-insensitive and follows three levels: complete dataflow
ID, terminal ID after the last \code{@}, then that terminal ID with a leading
\code{DF_} removed. The first non-empty level is used. No fuzzy matching,
legacy-code translation or hard-coded alias table is used.

Selectors restrict the catalogue before matching. If the chosen level contains
more than one agency/dataflow identity, an \code{OECDdata_ambiguous} error lists
canonical candidates and carries their complete rows in \code{candidates}.
Use the agency or prefix selector, or a canonical reference. Selectors that
conflict with an explicitly qualified reference are errors, not overrides.

\link{importDataList} advertises a \code{ShortCode} only if it cannot collide
with any other identity's literal, terminal or compact code. Otherwise that
column is missing. A short code can become ambiguous after catalogue changes;
store this function's canonical result for repeatable dataset selection.

A qualified reference bypasses the catalogue, but its structure is still fetched
or read from a verified cache. Offline shorthand resolution needs a cached
catalogue in addition to cached structure/data responses. This function fetches
structure metadata and dictionaries, but never observations. Returned structure
versions do not freeze future observation revisions.

\link{importData} and \link{oecdQuery} also accept these selectors in a reserved
\code{filters = list(.dataset = list(agency = ..., prefix = ..., version = ...),
REF_AREA = ...)} block. Dataset selectors are removed before building observation
filters. A block containing only dataset selectors leaves all dimensions
unrestricted. Metadata functions accept this function's returned reference.
}
\examples{
if (interactive()) {
ref <- oecdDataset("CLI", agency = "OECD.SDD.STES", prefix = "DSD_STES")
s <- oecdStructure(ref)
importLabels(OECDDimCode = "REF_AREA", dataset = ref)
q <- oecdQuery("CLI", filters = list(
  .dataset = list(agency = "OECD.SDD.STES"),
  REF_AREA = "USA", FREQ = "M", TIME_PERIOD = c("2023-01", "2023-12")))
attr(q, "OECDDatasetCode")
}
}
\seealso{\link{importData}, \link{importDataList}, \link{oecdQuery}, \link{oecdStructure}}
