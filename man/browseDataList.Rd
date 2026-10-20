\name{browseDataList}
\alias{browseDataList}
\title{Browse a Catalogue Subset}
\description{Browse a Catalogue Subset.}
\usage{
browseDataList(subs)
}
\arguments{
\item{subs}{An R expression evaluating to a logical scalar or a
logical vector as long as the catalogue. Column names are available directly;
use backticks for names containing spaces. Caller variables are also available.
Available columns are listed under Details. Missing values in the result
are treated as false.}
}
\value{A list with \code{criteria}, \code{time}, \code{df}, and \code{html}, with
class \code{BrowsedOECDDatasetList}.}
\details{
The predicate in \code{subs} can refer to these catalogue columns:
\describe{
\item{\code{ShortCode}}{Unique, catalogue-resolved shorthand; missing for ambiguous tokens.}
\item{\code{Dataset name}}{Dataset title; refer to it with backticks.}
\item{\code{Code}}{Fully qualified agency, dataflow, version reference.}
\item{\code{Agency}}{Maintaining agency identifier.}
\item{\code{Dataflow}}{Complete dataflow identifier.}
\item{\code{DataflowPrefix}}{Identifier namespace before \code{@}.}
\item{\code{Version}}{Selected current structure version.}
\item{\code{Type}}{Artefact type (normally \code{dataset}).}
\item{\code{Last update of data}}{Source annotation for a data update, if present.}
\item{\code{Last table structure change}}{Source annotation for a structure update.}
\item{\code{Data start}}{Earliest period in source metadata, if reported.}
\item{\code{Data end}}{Latest period in source metadata, if reported.}
\item{\code{Description}}{Original OECD dataset description, which may contain HTML.}
\item{\code{Link}}{URL to the dataset in OECD Data Explorer.}
}
The HTML report escapes ordinary catalogue fields. The Description column
retains only safe formatting elements (such as paragraphs, lists and emphasis)
and HTTP(S) or mailto links; scripts, event handlers and other potentially unsafe
markup are excluded. Link URLs include OECD Data Explorer's data-space
selector. Browser opening is a print side effect restricted to interactive
sessions and controlled by \code{open_browser}. Assignment does not launch a
browser. The expression is ordinary R code and should not be accepted from
untrusted users.
}
\examples{
if (interactive()) {
browseDataList(grepl("employment", `Dataset name`, ignore.case = TRUE))
pattern <- "GDP|gross domestic"
browseDataList(grepl(pattern, `Dataset name`, ignore.case = TRUE))
}
}
\seealso{\link{find}, \link{importDataList}}
