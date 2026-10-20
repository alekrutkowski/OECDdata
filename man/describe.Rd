\name{describe}
\alias{describe}
\title{Describe Dimensions and Marginal Code Coverage}
\description{Describe Dimensions and Marginal Code Coverage.}
\usage{
describe(OECDDatasetCode, import_labels = !wide, wide = FALSE,
         import_dim_labels = TRUE)
}
\arguments{
\item{OECDDatasetCode}{A catalogue-resolved short code such as \code{"CLI"}, a terminal ID such
as \code{"DF_CLI"}, a complete dataflow ID such as \code{"DSD_STES@DF_CLI"},
or a qualified reference \code{"OECD.SDD.STES,DSD_STES@DF_CLI"} with an
optional numeric version. Short codes are accepted only when resolution is
unambiguous. An omitted version, \code{"latest"} or \code{"+"} selects the
latest stable structure. See \link{oecdDataset} for resolution rules.}
\item{import_labels}{Logical; include human-readable code labels. Defaults to the opposite of \code{wide}.}
\item{wide}{Logical; collapse codes into one comma-separated string per dimension.}
\item{import_dim_labels}{Logical; include descriptive dimension names.}
}
\value{A \code{data.table}. Long form contains \code{Dim_name}, \code{Dim_val},
optional \code{Dim_name_label} and \code{Dim_val_label}, and a logical membership
column named exactly as the input dataset reference. Wide form uses
\code{Dim_values} instead of \code{Dim_val}.}
\details{
The coverage semantics and limitations are those of \link{importMetabase}.
\code{wide = TRUE} requires \code{import_labels = FALSE}. Label and shape defaults follow the familiar \pkg{eurodata} workflow. Results are returned normally;
assignment does not force an extra print side effect.
}
\examples{
if (interactive()) {
code <- "CLI"
describe(code)
describe(code, wide = TRUE)
}
}
\seealso{\link{compare}, \link{importMetabase}}
