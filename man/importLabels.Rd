\name{importLabels}
\alias{importLabels}
\alias{importDimLabel}
\title{Import Dataset-Scoped Dimension or Attribute Labels}
\description{Import Dataset-Scoped Dimension or Attribute Labels.}
\usage{
importLabels(OECDDimCode, dataset = NULL)

importDimLabel(OECDDimCode, dataset = NULL)
}
\arguments{
\item{OECDDimCode}{A component ID such as \code{"REF_AREA"}. Without dataset
context, a fully qualified codelist reference or a globally unambiguous
\code{CL_}-prefixed codelist can be used. A single string of the form
\code{"AGENCY,DATAFLOW,VERSION::DIMENSION"} also supplies context.}
\item{dataset}{Optional dataset short code or canonical reference, as in \link{oecdDataset}. Defaults to the \code{dataset} option.
Explicit dataset context is recommended because OECD codelist IDs need not be
globally unique. A qualified component reference overrides the default option;
an explicitly supplied \code{dataset} must resolve to the same dataset.}
}
\value{\code{importLabels} returns a two-column data frame with classes
\code{OECDLabels} and \code{data.frame}. The first column uses the component
name supplied by the caller; the second appends \code{_labels}. Columns are
factors by default. \code{importDimLabel} returns one character label.}
\details{
Labels are resolved from the specific DSD, concept scheme and enumerated
codelist, including agency and version. The requested language is preferred, then
English, then the first available label. Ambiguous dictionaries cause an error
rather than an arbitrary selection. Labels are permissible codes, not a claim
that observations exist. A component without an enumerable dictionary can be
passed to \code{importDimLabel} with dataset context to retrieve its name,
but cannot be passed to \code{importLabels}.
Use \link{oecdDataset} first when agency, prefix or version selectors are needed.
Attributes identify the \code{OECDDimCode}, resolved \code{OECDDatasetCode},
and \code{DownloadTime}.
}
\examples{
if (interactive()) {
code <- "CLI"
importLabels("REF_AREA", dataset = code)
importDimLabel("REF_AREA", dataset = code)
old <- oecdOptions(dataset = code)
importLabels("FREQ")
options(old)
}
}
\seealso{\link{oecdStructure}, \link{describe}}
