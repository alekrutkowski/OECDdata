\name{compare}
\alias{compare}
\title{Compare Marginal Dimension-Code Coverage}
\description{Compare Marginal Dimension-Code Coverage.}
\usage{
compare(..., import_labels = TRUE, import_dim_labels = TRUE)
}
\arguments{
\item{...}{Two or more different dataset references, each supplied as a separate scalar string.}
\item{import_labels}{Logical; include code labels.}
\item{import_dim_labels}{Logical; include dimension labels.}
}
\value{A \code{data.table} with \code{Dim_name}, \code{Dim_val}, optional labels,
and one logical column per input dataset. Missing membership is \code{FALSE}.}
\details{
Rows are the full union of dimension-ID/code pairs. Matching IDs are not proof
of conceptual equivalence across datasets. Conflicting labels are joined with
\code{" | "} and generate a warning rather than being silently overwritten.
Availability follows \link{importMetabase}. This function compares metadata
coverage, not numeric observations, units or revisions.
}
\examples{
if (interactive()) {
# Discover two relevant references first rather than guessing identifiers.
candidates <- OECDdata::find("national accounts")$df$Code
if (length(candidates) >= 2L) compare(candidates[[1]], candidates[[2]])
}
}
\seealso{\link{describe}, \link{importMetabase}}
