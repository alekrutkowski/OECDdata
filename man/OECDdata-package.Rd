\name{OECDdata-package}
\alias{OECDdata}
\alias{OECDdata-package}
\title{Fast and Friendly Access to OECD Data}
\description{Discover, describe, compare and import OECD statistical datasets.}
\value{The package provides functions for discovery, metadata inspection and flat data imports.}
\details{
The discovery and import workflow is inspired by \pkg{eurodata} 1.8.0 and adapted
to OECD dataset identities, dimension dictionaries and observation attributes.
Public arguments, result classes and metadata attributes use OECD terminology.
Short codes are resolved from the catalogue; ambiguous matches are errors.

SDMX REST v2 is the default route. Observation payloads use SDMX-CSV 2 and
structure payloads use SDMX-ML 2.1. The REST version and message version are
independent. Version 1 routes are available by explicit option.

XML metadata use bulk C extraction through libxml2, with document-level
indexes for structural definitions. Observation CSV files use \pkg{data.table}.
Source installation requires a C compiler and libxml2 development files.

The package makes no requests and changes no options when loaded. Caching is
session-local unless a directory is explicitly configured. Network examples
are not run by ordinary checks. See the README for a worked tutorial, the
installed vignette for offline examples, and \code{inst/ATTRIBUTION.md} in the
source tree for provenance and dependency acknowledgments.
}
\examples{
x <- oecdExample()
head(x)
stopifnot(is.numeric(x$value_))
}
\seealso{\link{importData}, \link{importDataList}, \link{oecdDataset}, \link{oecdOptions}}
