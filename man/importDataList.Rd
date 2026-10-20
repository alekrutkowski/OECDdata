\name{importDataList}
\alias{importDataList}
\title{Import the Current OECD Dataflow Catalogue}
\description{Retrieve dataset titles, readable codes and canonical identities.}
\usage{
importDataList()
}
\value{A data frame with classes \code{OECDDataList} and \code{data.frame}.
Columns are \code{ShortCode}, \code{Dataset name}, \code{Code}, \code{Agency},
\code{Dataflow}, \code{DataflowPrefix}, \code{Version}, \code{Type},
\code{Last update of data}, \code{Last table structure change}, \code{Data start},
\code{Data end}, \code{Description}, and \code{Link}.}
\details{
There is one current structure version per agency/dataflow identity.
\code{Code} is the fully qualified reference with that version. \code{ShortCode}
is a compact, catalogue-resolved shorthand, or missing when another identity
could match the same token. It is a package convenience, not an official global
OECD alias. \code{DataflowPrefix} is the namespace before \code{@}, or missing
when that delimiter is absent. See \link{oecdDataset} for matching rules.

No artificial hierarchy columns are supplied. Timestamps and period bounds
are populated only when recognized source annotations supply them; other
values remain missing. A retrieval time is not a last-data-update time.

The catalogue belongs to the configured \code{base_url}. Its printable HTML
report escapes ordinary cells and renders a restricted, safe subset of HTML from
OECD descriptions. Dataset links include the OECD Data Explorer space selector
\code{df[ds]=dsDisseminateFinalDMZ}. Printing opens a browser only in an
interactive session with \code{open_browser = TRUE}.
}
\examples{
if (interactive()) {
catalogue <- importDataList()
head(catalogue[c("ShortCode", "Dataset name", "Code")])
}
}
\seealso{\link{find}, \link{browseDataList}, \link{as.OECDDataList}, \link{oecdDataset}}
