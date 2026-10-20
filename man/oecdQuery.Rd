\name{oecdQuery}
\alias{oecdQuery}
\title{Construct an Encoded OECD Data Request}
\description{Construct an Encoded OECD Data Request.}
\usage{
oecdQuery(OECDDatasetCode, filters = NULL)
}
\arguments{
\item{OECDDatasetCode}{A catalogue-resolved short code such as \code{"CLI"}, a terminal ID such
as \code{"DF_CLI"}, a complete dataflow ID such as \code{"DSD_STES@DF_CLI"},
or a qualified reference \code{"OECD.SDD.STES,DSD_STES@DF_CLI"} with an
optional numeric version. Short codes are accepted only when resolution is
unambiguous. An omitted version, \code{"latest"} or \code{"+"} selects the
latest stable structure. See \link{oecdDataset} for resolution rules.}
\item{filters}{Same named filter list as \link{importData}, including its optional
reserved \code{.dataset} selector block.}
}
\value{A character URL with attributes \code{Accept}, \code{RequestedDatasetCode} and \code{OECDDatasetCode}.
The URL contains an exact resolved structure version.}
\details{
This can fetch structural metadata but never downloads observations. V2 uses
named component constraints with encoded comma-OR and plus-AND operators. V1
uses positionally ordered keys and start/end period parameters. Reserved literal
filter characters are rejected. The URL alone does not include the HTTP Accept
header; send the attached Accept value when inspecting it with another client.
}
\examples{
if (interactive()) {
q <- oecdQuery("CLI",
               list(REF_AREA = "USA", TIME_PERIOD = c("2023-01", "2023-12")))
cat(q)
attr(q, "Accept")
}
}
\seealso{\link{importData}, \link{oecdOptions}}
