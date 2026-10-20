\name{find}
\alias{find}
\title{Search Dataset Codes or Titles}
\description{Search Dataset Codes or Titles.}
\usage{
find(...)
}
\arguments{
\item{...}{Unquoted words, scalar numbers, or quoted regular-expression
patterns. Prefix a term with unary minus for exclusion. Terms are captured rather
than evaluated as function calls.}
}
\value{A list with \code{criteria}, \code{time}, \code{df}, and \code{report}, with
class \code{FoundOECDDatasetList}.}
\details{
Matching is case-insensitive and uses partial regular expressions. As in \pkg{eurodata}, all positive and negative conditions must hold in Code, OR all
must hold in Dataset name. Terms are not matched across a concatenation of both
fields. Consequently an exclusion in the title does not veto a successful Code
match. Use \link{browseDataList} for explicitly global exclusions.

Use \code{OECDdata::find} to avoid confusion with \code{utils::find}. Printing
shows a text report, using a text viewer only in interactive mode when enabled.
Unlike eurodata's search report, the returned data frame retains the full
catalogue schema, including missing optional columns.
}
\examples{
if (interactive()) {
OECDdata::find(gdp, annual, -quarterly)
OECDdata::find("health expenditure")
OECDdata::find("climat|emission")
}
}
\seealso{\link{browseDataList}, \link{importDataList}}
