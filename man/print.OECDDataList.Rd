\name{print.OECDDataList}
\alias{print.OECDDataList}
\alias{print.FoundOECDDatasetList}
\alias{print.BrowsedOECDDatasetList}
\alias{print.FoundOECDDatasetListReport}
\title{Print OECD Search and Catalogue Reports}
\description{Print OECD Search and Catalogue Reports.}
\usage{
\method{print}{OECDDataList}(x, SearchCriteria = attr(x, "SearchCriteria"), ...)
\method{print}{FoundOECDDatasetList}(x, ...)
\method{print}{BrowsedOECDDatasetList}(x, ...)
\method{print}{FoundOECDDatasetListReport}(x, ...)
}
\arguments{
\item{x}{An object returned by the corresponding catalogue or search function.}
\item{SearchCriteria}{Optional catalogue report caption.}
\item{...}{Further print arguments; used by the data-frame console report.}
}
\value{The input, invisibly.}
\details{
Interactive browser or text-viewer reports are enabled only when the option
\code{open_browser} is true and R is interactive. Otherwise reports are printed
to the console. No browser is launched by ordinary package checks.
}
\seealso{\link{find}, \link{browseDataList}, \link{oecdOptions}}

\examples{
x <- as.OECDDataList(data.frame(
  Code = "TEST,DEMO,1.0",
  `Dataset name` = "Synthetic demonstration",
  Link = "https://example.org/",
  check.names = FALSE
))
print(x)
}
