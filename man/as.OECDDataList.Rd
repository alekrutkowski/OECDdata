\name{as.OECDDataList}
\alias{as.OECDDataList}
\title{Coerce a Data Frame to an OECD Catalogue}
\description{Attach the OECD catalogue class and a descriptive search caption.}
\usage{
as.OECDDataList(x, SearchCriteria = "", ...)
}
\arguments{
\item{x}{A data frame containing \code{Code}, \code{Dataset name} and \code{Link}.}
\item{SearchCriteria}{A single descriptive string attached to the report.}
\item{...}{Reserved for future extensions; currently unused.}
}
\value{An independent data frame with classes \code{OECDDataList} and \code{data.frame}.}
\details{Other columns are preserved. No network access occurs.}
\examples{
x <- data.frame(Code = "TEST,DEMO,1.0", `Dataset name` = "Synthetic demo",
                Link = "https://example.invalid/", check.names = FALSE)
y <- as.OECDDataList(x, SearchCriteria = "offline example")
inherits(y, "OECDDataList")
}
\seealso{\link{importDataList}}
