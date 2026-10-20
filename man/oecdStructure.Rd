\name{oecdStructure}
\alias{oecdStructure}
\title{Inspect the Resolved OECD Structure}
\description{Inspect the Resolved OECD Structure.}
\usage{
oecdStructure(OECDDatasetCode)
}
\arguments{
\item{OECDDatasetCode}{A catalogue-resolved short code such as \code{"CLI"}, a terminal ID such
as \code{"DF_CLI"}, a complete dataflow ID such as \code{"DSD_STES@DF_CLI"},
or a qualified reference \code{"OECD.SDD.STES,DSD_STES@DF_CLI"} with an
optional numeric version. Short codes are accepted only when resolution is
unambiguous. An omitted version, \code{"latest"} or \code{"+"} selects the
latest stable structure. See \link{oecdDataset} for resolution rules.}
}
\value{An \code{OECDStructure} list with \code{flow}, \code{dsd}, \code{dimensions},
\code{attributes}, \code{measure}, \code{labels}, \code{available},
\code{availability}, and \code{availability_reason}. The flow includes its
resolved agency, identifier, version, title, description and canonical code.
The \code{dsd} entry records the resolved DSD agency, identifier and version.
Component tables include ID, label, kind, position and codelist reference.
Download time and source URL are attributes.}
\details{
This makes a metadata request, not an observation download. The referenced
DSD and its dictionaries are resolved by full identity, not XML document order.
Only structures with a single observation measure are supported. The dictionary
and observed marginal availability are separate elements. Inspect the latter's
status and explanation before interpreting it as coverage.
}
\examples{
if (interactive()) {
s <- oecdStructure("CLI")
s$flow
s$dimensions
s$labels$REF_AREA
s$availability
}
}
\seealso{\link{oecdQuery}, \link{importData}}
