\name{oecdExample}
\alias{oecdExample}
\title{Load a Small Synthetic Dataset Without Network Access}
\description{Load a Small Synthetic Dataset Without Network Access.}
\usage{
oecdExample()
}
\value{Twelve synthetic monthly observations for two country codes, in the same
format as \link{importData}. Values, structures and labels are invented teaching
fixtures, not OECD statistics.}
\details{
The bundled structure and CSV are parsed through the same core code paths as
live responses. The synthetic reference is \code{TEST,DEMO,1.0}; its illustrative
metadata timestamp is fixed. This function makes no requests and creates no
cache files. Current output-type options are respected.
}
\examples{
x <- oecdExample()
head(x)
stopifnot(nrow(x) == 12L, is.numeric(x$value_))
attr(x, "OECDDatasetCode")
}
\seealso{\link{importData}}
