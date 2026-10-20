# Protocol and compatibility sources

Review date: 2026-10-16. These links identify the contract used to author the
client; they are not evidence that a live request or executable R test passed.

## OECD primary sources

- https://www.oecd.org/en/data/insights/data-explainers/2024/09/api.html
- https://sdmx.oecd.org/public/
- https://gitlab.algobank.oecd.org/public-documentation/dotstat-migration/-/raw/main/OECD_Data_API_documentation.pdf
- https://www.oecd.org/en/data/insights/data-explainers/2024/11/Api-best-practices-and-recommendations.html
- https://www.oecd.org/en/data/insights/data-explainers/2026/03/Restricted-API-parameter.html

The technical documentation identifies `/public/rest/v2` as the REST v2 route,
with `/data/dataflow/agency/id/version/key`, named `c[component]` filters,
comma-separated alternatives and `ge:...+le:...` time constraints. The client
encodes reserved query characters, including the plus sign. The documentation
also retains `/public/rest` for REST v1 and describes CSV 2 and XML 2.1 messages.

Current best-practice guidance states 60 data downloads per hour. The local
budget is per R session, not a globally coordinated IP quota. Certain expensive
first/last-observation queries are restricted; this client does not issue them.

## SDMX primary specifications

- https://github.com/sdmx-twg/sdmx-rest/blob/master/doc/data.md
- https://github.com/sdmx-twg/sdmx-rest/blob/master/doc/structures.md
- https://github.com/sdmx-twg/sdmx-rest/blob/master/doc/querying_versions.md
- https://github.com/sdmx-twg/sdmx-csv

REST transport versions, artefact structure versions and message-format versions
are distinct. A dataflow structure version is not a frozen data vintage.

## eurodata 1.8.0 public contract

- https://raw.githubusercontent.com/cran/eurodata/master/DESCRIPTION
- https://raw.githubusercontent.com/cran/eurodata/master/NAMESPACE
- https://raw.githubusercontent.com/cran/eurodata/master/R/core_import.R
- https://raw.githubusercontent.com/cran/eurodata/master/R/core_search.R
- https://raw.githubusercontent.com/cran/eurodata/master/R/extras.R
- https://raw.githubusercontent.com/cran/eurodata/master/R/helpers.R

Useful workflow conventions and selected semantics are retained with OECD-native names. No upstream GPL
implementation is copied or included. See ATTRIBUTION.md for acknowledgments.
The test suite records the adapted OECD formals; tools/check-api.R applies an
explicit naming map before comparing defaults with an installed upstream package.

## Implementation and release references

- https://r-datatable.com/reference/fread.html
- https://jeroen.r-universe.dev/curl/doc/manual.html
- https://xml2.r-lib.org/reference/read_xml.html
- https://testthat.r-lib.org/reference/local_mocked_bindings.html
- https://cran.r-project.org/web/packages/policies.html
- https://cran.r-project.org/doc/manuals/r-release/R-exts.html

## Short-code design in 0.2.0

The OECD documentation identifies dataflows by agency, ID and structure version.
The package adds catalogue-based shorthand resolution and a reserved
`filters$.dataset` selector block. These are client design choices, not claims
that the OECD service accepts `CLI` as a universal resource identifier. The
`prefix` selector matches the namespace before `@` in the dataflow ID; the
referenced DSD is independently read from metadata. Aliases are not hard-coded.
