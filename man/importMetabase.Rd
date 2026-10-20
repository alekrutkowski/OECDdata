\name{importMetabase}
\alias{importMetabase}
\title{Import a Dataset-Dimension-Code Inventory}
\description{Import a Dataset-Dimension-Code Inventory.}
\usage{
importMetabase(OECDDatasetCode = NULL)
}
\arguments{
\item{OECDDatasetCode}{Optional character vector of dataset short codes or canonical references.
See \link{oecdDataset} for resolution rules.
Defaults to the \code{dataset} option. With neither supplied, attempts the
complete catalogue inventory, which can be very large.}
}
\value{A data frame with columns \code{Code}, \code{Dim_name}, and \code{Dim_val}.
The \code{Availability} attribute records \code{"actual"} or \code{"allowed"}.
Time dimensions are excluded.}
\details{
By default, actual marginal availability must be enumerated by a matching
SDMX Actual content constraint. A marginal list does not guarantee observations
for every combination of the listed codes. Missing metadata or constraints whose
conditional exclusions cannot safely be projected cause an explicit error.

Set \code{oecdOptions(availability = "allowed")} to request dictionary codes
instead. This is an explicit alternate mode, not a claim of observed coverage.
The source may return partial dictionaries. Prefer dataset-scoped requests over
a global inventory. The no-argument call is retained for compatibility but is
expensive and may fail if any selected dataset lacks usable metadata.
}
\examples{
if (interactive()) {
importMetabase("CLI")
}
}
\seealso{\link{describe}, \link{compare}, \link{oecdStructure}}
