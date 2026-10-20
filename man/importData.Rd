\name{importData}
\alias{importData}
\title{Import a Flat OECD Dataset}
\description{Import a Flat OECD Dataset.}
\usage{
importData(OECDDatasetCode, filters = NULL)
}
\arguments{
\item{OECDDatasetCode}{A catalogue-resolved short code such as \code{"CLI"}, a terminal ID such
as \code{"DF_CLI"}, a complete dataflow ID such as \code{"DSD_STES@DF_CLI"},
or a qualified reference \code{"OECD.SDD.STES,DSD_STES@DF_CLI"} with an
optional numeric version. Short codes are accepted only when resolution is
unambiguous. An omitted version, \code{"latest"} or \code{"+"} selects the
latest stable structure. See \link{oecdDataset} for resolution rules.}
\item{filters}{\code{NULL} for all observations, or a non-empty named list of
character/numeric vectors. Names identify dimensions, except for the optional reserved \code{.dataset}
block described below. Multiple codes within a
dimension are combined with OR; dimensions are combined with AND. A time vector
is interpreted as an inclusive range from its minimum to its maximum, not as a
discrete set of requested dates. See Details.}
}
\value{By default, a \code{data.frame} with classes \code{OECDDataset} and
\code{data.frame}. Dimension columns are factors, \code{value_} is a double,
and \code{flags_} contains the raw \code{OBS_STATUS} text, or an empty string if
that attribute is absent. All other supplied statistical attributes are retained.
Set \code{return_data_table = TRUE} for a \code{data.table}, and
\code{strings_as_factors = FALSE} for character dimensions.

Attributes include \code{RequestedDatasetCode} (input reference),
\code{OECDDatasetCode} (resolved exact reference), \code{DownloadTime},
\code{SourceURL}, \code{Cached}, \code{Dimensions}, \code{OECDAttributes},
and \code{Filters}. A cache hit preserves the original download time.}
\details{
The optional \code{.dataset} block is a named list of \code{agency},
\code{prefix} and/or \code{version} identity selectors, with the same meaning
as in \link{oecdDataset}. For example,
\code{list(.dataset = list(agency = "OECD.SDD.STES"), REF_AREA = "USA")}.
These selectors choose a dataset and are removed before dimension filtering.
A selector-only block leaves all dimensions unrestricted. Conflicts with an
explicit reference are errors. The \code{Filters} result attribute retains the
original full list, including the selector block.

The structure is resolved before constructing the data query. Dimension names
are matched case-insensitively; values must be valid literal codes with their
original case. Leading zeros in identifiers are preserved. A single empty string
selects all values of its dimension and produces a warning. Other missing or
empty selections fail explicitly.

Common annual, quarterly, half-yearly, weekly, monthly and daily period formats
are supported: \code{YYYY}, \code{YYYY-Q1}, \code{YYYY-S1}, \code{YYYY-W01},
\code{YYYY-MM}, and \code{YYYY-MM-DD}. Annual \code{YYYY-A1} and monthly
\code{YYYY-M01} aliases are normalized. Use one granularity in a filter.
Subdaily periods, custom calendars and mixed-granularity bounds are not supported.

The client downloads to disk and parses with \code{data.table::fread}. It does
not aggregate, infer seasonal adjustment, rescale units, translate flags, or fill
in a Cartesian product of missing observations. Duplicate observation keys,
delete actions, unexpected response identities and malformed values fail rather
than being silently repaired. HTTP 204 produces a typed empty result with a
warning; HTTP errors, including 404, remain errors.

A pinned structure version does not freeze historical statistical revisions.
Save an RDS snapshot when an exact data vintage is required.
}
\examples{
x <- oecdExample()
names(x)
attr(x, "Dimensions")
if (interactive()) {
cli <- importData(OECDDatasetCode = "CLI",
  filters = list(REF_AREA = c("USA", "FRA"), FREQ = "M",
                 TIME_PERIOD = c("2023-01", "2023-12")))
}
}
\seealso{\link{oecdDataset}, \link{oecdQuery}, \link{oecdStructure}, \link{importLabels}, \link{oecdOptions}}
