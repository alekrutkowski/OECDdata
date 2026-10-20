# OECDdata

## OECD statistics, with a familiar `eurodata` interface

`OECDdata` discovers, describes, compares and imports OECD datasets through the
public OECD SDMX API. Its workflow is inspired by `eurodata` 1.8.0, including
`importData()`, `find()`, `describe()` and `compare()`, but arguments, classes
and metadata are OECD-native. Readable short codes hide SDMX identity details
when the catalogue can resolve them safely.

The default transport is **SDMX REST v2**. Downloads go directly to disk and are
parsed by the native `data.table::fread()` implementation. The client resolves
metadata before building queries, preserves observation attributes, caches raw
responses with checksums, and handles retries and rate limits explicitly.

## Installation

Requires R 4.1.0 or newer. This is a local source release, not a claim that
`OECDdata` is already on CRAN.

```r
install.packages(c("curl", "data.table", "digest", "magrittr", "xml2"))
install.packages("OECDdata_0.2.5.tar.gz", repos = NULL, type = "source")
```

From an extracted development directory:

```sh
R CMD INSTALL OECDdata
```

For a complete R Markdown vignette build, the build machine also needs Pandoc.
On Windows, install it from [pandoc.org](https://pandoc.org/installing.html),
then verify `rmarkdown::find_pandoc()` in R. The included
`tools/diagnostics.R` script can obtain additional diagnostic results without
Pandoc by separately building with `--no-build-vignettes`; this is **not** an
acceptable substitute for the full CRAN release check.

## 1. Start without the network

```r
library(OECDdata)
library(data.table)
library(magrittr)

example <- oecdExample()
head(example)
str(example)
attr(example, "Dimensions")
```

This returns **12 invented observations**, for two country codes and six months.
They are teaching fixtures, not OECD statistics. Their identifiers and values
pass through the same structure and CSV parsing code used for live imports.

By default, the result is a flat `data.frame`: one observation per row,
factor dimension columns, a numeric `value_` column and a character `flags_`
column. Statistical attributes such as `OBS_STATUS` and `UNIT_MULT` remain
available. Numeric-looking codes such as `"00"` remain identifiers, not numbers.

## 2. Make a small live request

The following sections marked **online** contact the public OECD service.
The Composite Leading Indicators dataflow is used in OECD's API documentation.
The first call resolves the short code through the catalogue and retrieves its
current structure; the data request then uses that exact resolved version.
A short code is a package convenience, not a promise of a permanent OECD alias.
If the current catalogue makes it ambiguous, the error lists the matching
canonical references; the next section shows how to disambiguate.

```r
# Online
cli_code <- "CLI"

cli <- importData(
  OECDDatasetCode = cli_code,
  filters = list(
    REF_AREA = c("USA", "FRA"),
    FREQ = "M",
    TIME_PERIOD = c("2023-01", "2023-12")
  )
)

head(cli)
attr(cli, "OECDDatasetCode")
attr(cli, "SourceURL")
attr(cli, "DownloadTime")
```

There is no API-key argument. Restrict dimensions and time before requesting a
large flow. An unspecified dimension is a wildcard, so the example can contain
several measures, transformations or adjustment categories. Inspect those
remaining dimensions before plotting or aggregating anything.

## 3. Discover datasets instead of guessing their identifiers

### Readable input, explicit provenance

These inputs identify the same dataflow **when the catalogue match is unique**:

```r
# Online; all three resolve via the catalogue.
oecdStructure("CLI")
oecdStructure("DF_CLI")
oecdStructure("DSD_STES@DF_CLI")
```

The shortest form removes the conventional `DF_` prefix from the terminal
identifier after `@`. This is not a hard-coded list of popular datasets, a
substring search, or a translation of retired OECD.Stat codes. Any dataflow
following that convention can use the same resolution rules.

The server still needs an unambiguous identity:

```text
AGENCY,DATAFLOW,STRUCTURE_VERSION
OECD.SDD.STES,DSD_STES@DF_CLI,<resolved numeric version>
```

An omitted version means the latest stable structure. A fully qualified
reference bypasses the catalogue lookup; a bare ID or short code does not.
`"MEI"` is not silently translated into a possibly different modern dataset.

Matching is case-insensitive for catalogue lookups. After applying any identity
selectors, the first matching level is used: complete dataflow ID, terminal ID
after `@`, then that terminal ID with `DF_` removed. For example, an actual
literal dataflow ID `CLI` would take precedence over a compact alias `CLI`.
Within the selected level, **multiple matches are an error**, never an arbitrary
first match. Fully qualified references retain their supplied identifier case.

### Put exceptional identity details in `filters$.dataset`

For everyday use, `importData("CLI", filters = ...)` is enough when unique.
When needed, keep agency, namespace and version details in a reserved nested
block rather than mixing them into observation dimensions:

```r
# Online: .dataset selects the dataflow; the other entries filter observations.
cli <- importData(
  OECDDatasetCode = "CLI",
  filters = list(
    .dataset = list(
      agency = "OECD.SDD.STES",
      prefix = "DSD_STES"
    ),
    REF_AREA = c("USA", "FRA"),
    FREQ = "M",
    TIME_PERIOD = c("2023-01", "2023-12")
  )
)
```

All three identity selectors are optional. `agency` identifies the maintainer;
`prefix` selects the dataflow namespace before `@`; `version` selects a
structure version. The `prefix` selector is a match against the dataflow ID
prefix, not a substitute for looking up its actual referenced data structure.
The latter is always read from the OECD metadata.

`.dataset` is removed before generating SDMX component filters. It never becomes
`c[agency]` or a positional series key. A real `AGENCY` dimension, if present in a
dataset, remains an ordinary dimension when supplied outside that reserved block.
Block and selector names are case-insensitive. Selectors are scalar strings;
unknown names, duplicate names, invalid values and conflicts with an explicitly
qualified reference fail rather than being silently ignored.

A block with only dataset selectors does **not** restrict observations. Always
add country, period and other dimensions before downloading a large flow.

### Resolve once, then reuse the exact reference

```r
# Online metadata only: no observation download.
ref <- oecdDataset("CLI", agency = "OECD.SDD.STES", prefix = "DSD_STES")
ref                              # Actual AGENCY,DATAFLOW,VERSION string.

s <- oecdStructure(ref)
importLabels(OECDDimCode = "REF_AREA", dataset = ref)
importDimLabel(OECDDimCode = "REF_AREA", dataset = ref)

q <- oecdQuery("CLI", filters = list(
  .dataset = list(agency = s$flow$agency, prefix = "DSD_STES",
                  version = s$flow$version),
  REF_AREA = "USA", FREQ = "M", TIME_PERIOD = c("2023-01", "2023-12")
))
attr(q, "OECDDatasetCode")
```

The exact version is obtained from current metadata, not a guessed version in
an example. To request a known historical structure, set `version` to its numeric
**string**. An explicit older version is not discarded just because the current
catalogue lists a newer one; the server must still supply that historical
structure. A pinned structure version does not freeze later statistical revisions.

All dataset-taking functions accept short codes or canonical references:
`importData()`, `oecdQuery()`, `oecdStructure()`, `describe()`, `compare()`,
`importMetabase()`, and the `dataset` context of the label functions. Use
`oecdDataset()` to apply identity selectors once for metadata operations.

For imports, `RequestedDatasetCode` records the input, such as `"CLI"`, and
`OECDDatasetCode` records the exact canonical reference. `Filters` records the
original list, including `.dataset`. Short codes and canonical references that
resolve to the same flow and filters produce the same data URL and therefore
share the response cache.

Catalogue changes can make an old shorthand ambiguous. Save the canonical
reference for repeatable dataset selection and an RDS snapshot for an exact
statistical vintage. Offline shorthand resolution needs the catalogue cached
as well as the requested structure and data; a canonical reference avoids that
extra dependency.

### Search across subject areas

```r
# Online; subsequent searches normally reuse the catalogue cache.
OECDdata::find("health expenditure")
OECDdata::find(education, expenditure)
OECDdata::find("gross domestic", -quarterly)
OECDdata::find("climat|emission")
OECDdata::find(trade, services)

catalogue <- importDataList()
catalogue %>% as.data.table() %>%
  .[grepl("employment|unemployment", `Dataset name`, ignore.case = TRUE),
    .(ShortCode, `Dataset name`, Code, Agency, Version)]
```

`find()` captures unquoted words and quoted regular expressions. Positive terms
are ANDed; a leading minus negates a term. Matching is case-insensitive.

**A subtle compatibility detail:** all conditions must hold in `Code`, OR all
must hold in `Dataset name`, exactly as in `eurodata`. A matching code is not
vetoed merely because the title contains an excluded word. Terms are not mixed
across the two fields. Use `browseDataList()` for different Boolean logic:

```r
# Online; impose exclusions across BOTH fields explicitly.
browseDataList(
  (grepl("GDP|gross domestic", `Dataset name`, ignore.case = TRUE) |
     grepl("GDP", Code, ignore.case = TRUE)) &
    !grepl("quarterly", `Dataset name`, ignore.case = TRUE) &
    !grepl("quarterly", Code, ignore.case = TRUE)
)

# Caller variables are available in subset expressions.
pattern <- "health|education"
selection <- browseDataList(grepl(pattern, `Dataset name`, ignore.case = TRUE))
selection$df
```

Printing a catalogue or browser result opens a self-contained HTML report only
in an interactive session when enabled. Assignment alone does not open it.

```r
oecdOptions(open_browser = FALSE)
```

The catalogue includes `ShortCode`, `Dataset name`, canonical `Code`, `Agency`,
`Dataflow`, `DataflowPrefix`, `Version`, descriptive metadata and an explorer
`Link`. `ShortCode` is missing when a token could collide with another identity;
use `Code` or identity selectors in that case. It is a convenience column, not
an official globally unique OECD naming scheme. No artificial hierarchy columns
are added. Missing source timestamps and coverage dates stay `NA`; a download
timestamp is not misrepresented as the dataset's last revision date.

`browseDataList(subs)` evaluates its expression in the catalogue, with caller
variables still in scope. These are the **available columns** (spaces require
backticks): `ShortCode`, `Dataset name`, `Code`, `Agency`, `Dataflow`,
`DataflowPrefix`, `Version`, `Type`, `Last update of data`,
`Last table structure change`, `Data start`, `Data end`, `Description`, and
`Link`. Missing annotations stay `NA` and can be filtered with `is.na()`.

```r
# Online: select by agency and skip missing or obsolete short codes.
by_agency <- browseDataList(Agency == "OECD.SDD.STES" & !is.na(ShortCode))

# Online: search original descriptions as well as titles.
in_catalogue <- browseDataList(
  grepl("employment", `Dataset name`, ignore.case = TRUE) |
    grepl("employment", Description, ignore.case = TRUE)
)

# The returned HTML keeps OECD-provided paragraphs, lists and safe hyperlinks,
# but removes executable markup. Links to OECD Data Explorer include the
# required data-space parameter.
cat(in_catalogue$html, file = "oecd-catalogue.html")
```

## 4. Read the structure before selecting indicators

```r
# Online
s <- oecdStructure(cli_code)
s$flow                    # Includes the resolved full reference.
s$dimensions              # Actual order, IDs, names and codelist references.
s$attributes              # Flags, units and other attribute definitions.
s$labels$REF_AREA          # Dictionary of permissible area codes.
s$availability            # "actual" or "unavailable".
s$availability_reason

# Inspect only the relevant dictionaries in memory, without another request.
names(s$labels)
lapply(s$labels[intersect(c("MEASURE", "ADJUSTMENT", "TRANSFORMATION"),
                         names(s$labels))], head)
```

A **dimension** identifies an observation or series. An **attribute** describes
it, for example its status or unit multiplier. A **codelist** defines permissible
codes. A dataflow's **Actual content constraint** describes reported marginal
coverage. These are related, but not interchangeable.

```r
# Online; actual marginal coverage when the service provides usable constraints.
describe(cli_code)
describe(cli_code, wide = TRUE)
importMetabase(cli_code)
```

If actual coverage cannot be established, these functions raise an
`OECDdata_availability_error`; they do not silently substitute the entire
codelist. Explicitly request the dictionary-based alternative when that is the
information needed:

```r
# Online; explicitly PERMISSIBLE, not necessarily observed, codes.
(function() {
  old <- oecdOptions(availability = "allowed")
  on.exit(options(old))
  allowed <- describe(cli_code, wide = TRUE)
  print(allowed)
  stopifnot(identical(attr(allowed, "Availability"), "allowed"))
})()
```

Even valid marginal coverage does not imply every cross-product of codes has
observations. Some server responses contain partial dictionaries. The client
reports the metadata supplied, not an invented universal dictionary.

The original `importMetabase()` no-argument call is supported, but can request a
very large structural inventory. Prefer a dataset argument or a configured
context. A global request fails rather than returning an unmarked partial result
when one of its required structures cannot be interpreted safely.

## 5. Filter countries, frequencies and periods correctly

```r
# Online
importData(cli_code, list(REF_AREA = "USA", FREQ = "M",
                         TIME_PERIOD = "2023-06"))

# Multiple countries are ORed; other dimensions are ANDed.
importData(cli_code, list(REF_AREA = c("USA", "FRA", "DEU"), FREQ = "M",
                         TIME_PERIOD = c("2023-01", "2023-03")))
```

Dimension names are matched case-insensitively; their values retain the case
used in the source dictionaries. Unknown dimensions and codes fail early.
Use character strings for codes whose leading zeros matter.

`TIME_PERIOD` deliberately keeps `eurodata`'s **inclusive min/max range**
semantics. `c("2020", "2022")` means 2020 through 2022, including 2021.
It does not request only two isolated years. Filter locally afterwards to retain
non-contiguous periods:

```r
# Reuse an existing import instead of making another download.
cli %>% as.data.table() %>%
  .[as.character(TIME_PERIOD) %in% c("2023-01", "2023-06", "2023-12")]
```

Supported bounds are annual (`2023`), quarterly (`2023-Q1`), half-yearly
(`2023-S1`), weekly (`2023-W01`), monthly (`2023-01`) and daily (`2023-01-31`).
Aliases `2023-A1` and `2023-M01` are normalized. Bounds in one request must have
the same granularity. Subdaily periods and custom calendars are not supported.
A time bound does not itself select a frequency: use `FREQ` where that dimension
exists.

A reusable helper for annual and quarterly datasets avoids assuming that every
flow has the same frequency support:

```r
# Online when called. Discover and inspect a suitable flow before passing it in.
frequency_slice <- function(code, frequency, start, end, countries) {
  structure <- oecdStructure(code)
  required <- c("FREQ", "REF_AREA", "TIME_PERIOD")
  stopifnot(all(required %in% structure$dimensions$id))
  stopifnot(frequency %in% structure$labels$FREQ$code)
  importData(structure$flow$code,
    list(FREQ = frequency, REF_AREA = countries, TIME_PERIOD = c(start, end)))
}

# Use verified references selected from your current catalogue:
# frequency_slice(annual_code, "A", "2018", "2023", c("USA", "FRA"))
# frequency_slice(quarterly_code, "Q", "2020-Q1", "2023-Q4", "USA")
```

These last two calls are templates, not assertions that any particular discovery
result measures the intended economic concept. Check units, prices, adjustment,
sector and transformation before treating similarly named series as comparable.

## 6. Inspect the actual URL and explicitly select REST v1

```r
# Online metadata only; no observation download.
url <- oecdQuery(cli_code,
                 list(REF_AREA = c("USA", "FRA"),
                      TIME_PERIOD = c("2023-01", "2023-12")))
cat(url, "\n")
attr(url, "Accept")

(function() {
  old <- oecdOptions(api_version = "v1")
  on.exit(options(old))
  print(oecdQuery(cli_code, list(REF_AREA = "USA", FREQ = "M")))
})()
```

V2 uses `/rest/v2/data/dataflow/...` with encoded `c[DIMENSION]` constraints,
comma-separated alternatives and an encoded plus sign joining time bounds.
V1 uses `/rest/data/AGENCY,FLOW,VERSION/...` with dimension-order positional keys.
Both request flat CSV observations. Changing transports is explicit; an HTTP
failure does not silently switch APIs or reinterpret filters.

`oecdQuery()` may need metadata from the network. It is not a completely offline
URL formatter unless the necessary metadata are already cached. A raw URL opened
in a browser can negotiate a different format; the attached `Accept` value is
part of the request contract.

## 7. Use dataset-scoped labels

```r
# Online
areas <- importLabels("REF_AREA", dataset = cli_code)
importDimLabel("REF_AREA", dataset = cli_code)

# Keep the original one-argument style by supplying an explicit context once.
(function() {
  old <- oecdOptions(dataset = cli_code)
  on.exit(options(old))
  print(importLabels("REF_AREA"))
  print(importDimLabel("FREQ"))
})()

# Or include the context in a single string.
importLabels(paste0(cli_code, "::REF_AREA"))
```

The return columns remain `REF_AREA` and `REF_AREA_labels`. Labels can also be
requested for enumerated attributes such as `OBS_STATUS`.
`importDimLabel("TIME_PERIOD", dataset = cli_code)` also retrieves the name of
a component without an enumerated dictionary. A qualified component string
overrides the default dataset option; an explicit `dataset` argument must
resolve to the same dataset.

Without a dataset context, the client accepts a fully qualified codelist
reference or searches for an unambiguous `CL_<DIMENSION>` dictionary. It refuses
to pick the first of several agencies' dictionaries. Explicit context is safer
than assuming that a component ID is a globally unique classification.

```r
# Online; prefer French where supplied, then English, then another available label.
(function() {
  old <- oecdOptions(language = "fr")
  on.exit(options(old))
  print(importLabels("REF_AREA", dataset = cli_code))
})()
```

To attach a label without changing the number of observations:

```r
# Reuse cli and areas from earlier online calls.
labelled <- copy(cli) %>% as.data.table()
areas <- as.data.table(areas)
stopifnot(!anyDuplicated(areas$REF_AREA))
n_before <- nrow(labelled)
labelled[areas, on = "REF_AREA", REF_AREA_labels := i.REF_AREA_labels]
stopifnot(nrow(labelled) == n_before)
```

Labels aid presentation. Keep original codes as keys and retain the resolved
structure reference alongside exported results.

## 8. Work directly in data.table

```r
# Offline
(function() {
  old <- oecdOptions(return_data_table = TRUE, strings_as_factors = FALSE)
  on.exit(options(old))

  dt <- oecdExample()
  stopifnot(is.data.table(dt), is.character(dt$REF_AREA))

  dt %>%
    .[REF_AREA == "USA"] %>%
    .[, .(TIME_PERIOD, value_, flags_)] %>%
    print()
})()
```

These options also control `importData()`. `describe()` and `compare()` already
return `data.table` objects, matching their familiar tabular use. The package
never changes `data.table`'s global thread setting. It respects the setting chosen
by your application.

The following analysis examples use only synthetic data:

```r
old <- oecdOptions(return_data_table = TRUE, strings_as_factors = FALSE)
dt <- oecdExample()
options(old)
series_keys <- setdiff(attr(dt, "Dimensions"), "TIME_PERIOD")
```

### Audit coverage and status before calculating anything

```r
dt[, .(n_observations = .N,
       n_missing = sum(is.na(value_)),
       first_period = min(TIME_PERIOD),
       last_period = max(TIME_PERIOD)), by = series_keys]

dt[, .N, by = .(OBS_STATUS, flags_)]
```

`flags_` preserves the source status codes; it does not translate them into another provider's
flag meanings. In live data, obtain the corresponding attribute dictionary
instead of hard-coding the meaning of a status. Missing values are not zeros.
The importer handles blank, `:` and `NA` measure fields as missing, and supports
negative values and scientific notation.

### Calculate growth only between adjacent months in the same series

```r
growth <- copy(dt) %>%
  .[, month_id := as.integer(substr(TIME_PERIOD, 1, 4)) * 12L +
                  as.integer(substr(TIME_PERIOD, 6, 7))] %>%
  .[order(month_id), `:=`(previous = shift(value_),
                        previous_month = shift(month_id)), by = series_keys] %>%
  .[, growth_pct := fifelse(!is.na(previous) & previous != 0 &
                             month_id - previous_month == 1L,
                           100 * (value_ / previous - 1), NA_real_)]

growth[, .(REF_AREA, TIME_PERIOD, value_, growth_pct)]
```

This avoids treating a gap of several months as a one-month change. For real data,
add whatever status restrictions your analysis requires. Do not mix different
measures, units, transformations or seasonal adjustments in a series key.

### Pivot only after checking uniqueness

```r
# The synthetic fixture has exactly one measure/group/frequency per country.
stopifnot(dt[, uniqueN(MEASURE)] == 1L,
          dt[, uniqueN(GROUP)] == 1L,
          dt[, uniqueN(FREQ)] == 1L,
          !anyDuplicated(dt, by = c("TIME_PERIOD", "REF_AREA")))

wide <- dcast(dt, TIME_PERIOD ~ REF_AREA, value.var = "value_")
wide
```

Do not hide duplicate series by supplying an arbitrary aggregation function to
`dcast()`. Retain the missing key dimensions or select a genuinely single series.

### Plot one series, without mixing observations

```r
one <- dt[REF_AREA == "USA"][order(TIME_PERIOD)]
stopifnot(!anyDuplicated(one$TIME_PERIOD))
plot(as.Date(paste0(one$TIME_PERIOD, "-01")), one$value_, type = "l",
     xlab = "Month", ylab = "Synthetic index", main = "Invented teaching data")
```

### Export observations and preserve provenance separately

```r
# Replace dt with a verified live import when exporting actual statistics.
provenance <- attributes(dt)[c("OECDDatasetCode", "SourceURL", "DownloadTime",
                              "Dimensions", "Filters")]
# Explicit user-requested files; these are not written by package load/import.
# fwrite(dt, "observations.csv")
# saveRDS(list(data = dt, provenance = provenance), "snapshot.rds")
```

A CSV does not preserve factors, R attributes or a complete provenance record.
An RDS snapshot can preserve all three. Conversions, joins and downstream tools
may drop custom attributes, so record provenance before transformations.

## 9. Compare metadata across datasets

```r
# Online; inspect titles and structures before choosing two candidates.
candidates <- OECDdata::find("national accounts")$df
head(candidates[c("Code", "Dataset name")])

# After selecting relevant references:
# comparison <- compare(code_a, code_b)
# comparison[Dim_name == "REF_AREA"]
# comparison[get(code_a) & !get(code_b)]
```

The result contains `Dim_name`, `Dim_val`, optional labels, and one logical column
per supplied reference. A code absent from a flow is `FALSE`, not `NA`.
`compare()` compares marginal code coverage, not estimates or data vintages.
Identical dimension IDs can have different conceptual meanings across flows;
conflicting labels are retained with a warning, not silently discarded.

## 10. Cache once, refresh deliberately, and work offline

By default the cache lives in a session-specific temporary directory. Loading
the package does not create directories, alter options or contact the network.
To retain a cache across sessions, opt in to an explicit location:

```r
# Creates the configured directory only when a request first needs it.
oecdOptions(cache_dir = tools::R_user_dir("OECDdata", "cache"),
            cache_ttl = 3600, metadata_ttl = 86400)

# Online: warm the structure and observation cache.
cli <- importData(cli_code, list(REF_AREA = "USA", FREQ = "M",
                                TIME_PERIOD = c("2023-01", "2023-12")))

# No network: reuse the SAME request and its cached metadata.
(function() {
  old <- oecdOptions(offline = TRUE)
  on.exit(options(old))
  cached <- importData(cli_code, list(REF_AREA = "USA", FREQ = "M",
                                    TIME_PERIOD = c("2023-01", "2023-12")))
  stopifnot(isTRUE(attr(cached, "Cached")))
})()
```

Offline mode can use expired entries, but not missing or checksum-corrupt ones.
Cache identities include URL, response format and language. Changing an endpoint,
version, filter selection or language can therefore require a different entry.
A cache hit retains the original `DownloadTime`, rather than pretending that old
observations were downloaded just now.

```r
# Online: bypass reuse and obtain fresh metadata/data.
(function() {
  old <- oecdOptions(refresh = TRUE)
  on.exit(options(old))
  refreshed <- importData(cli_code, list(REF_AREA = "USA", FREQ = "M",
                                        TIME_PERIOD = "2023-01"))
})()

# Deletes only this package's owned .body/.rds cache files.
clearCache()
```

There is no automatic eviction policy or interprocess lock. Do not use the same
cache directory for concurrent writers. Use a directory you trust; checksums
address corruption, not a malicious local user who can rewrite both cache files.

For reproducible research, pin `s$flow$code` and save the downloaded data and
provenance. **Pinning a structure version does not pin a statistical vintage.**
Existing observations can be revised without a new structure version.

## 11. Respect the service and handle failures explicitly

OECD's published guidance currently states **60 data downloads per hour** and
warns about shared-IP effects and anonymized access restrictions. The package
uses a conservative local rolling budget and spaces requests, but cannot know
what other applications on your network are downloading. See the dated
[OECD best-practice guidance](https://www.oecd.org/en/data/insights/data-explainers/2024/11/Api-best-practices-and-recommendations.html).

```r
oecdOptions(max_downloads = 60L, download_window = 3600,
            min_interval = 1, retries = 3L, max_retry_wait = 60,
            timeout = 120, connect_timeout = 20,
            max_bytes = 100 * 1024^2)
```

Transient network failures and HTTP 408, 429, 500, 502, 503 and 504 can be retried.
`Retry-After`, including an HTTP date, is respected. A delay above
`max_retry_wait` raises an error instead of retrying early. Failed data attempts
count toward the local budget. Persistent client errors are not retried.
The size cap is also checked after download; without an advertised size it is
not a strict bound on bytes received.

```r
# Online; a failure remains a visible structured condition.
result <- tryCatch(
  importData(cli_code, list(REF_AREA = "USA", TIME_PERIOD = "2023-01")),
  OECDdata_rate_limit = function(e) {
    message(conditionMessage(e))
    NULL
  }
)
```

| Situation | Interpretation and response |
|---|---|
| HTTP 400 | Inspect dimensions, code case and structure version. |
| HTTP 403 or an HTML block page | Check the configured endpoint and OECD network/access restrictions. |
| HTTP 404 | A missing flow/version or selection is not assumed to be a successful empty dataset. |
| HTTP 413 | Narrow dimensions/time and consult OECD restrictions on expensive requests. |
| HTTP 429 | Reuse cached data; wait for the stated retry period. |
| HTTP 204 | A typed, zero-row result is returned with an `OECDdata_empty` warning. |
| Invalid numeric values or duplicate observation keys | Parsing fails; no silent coercion or aggregation is applied. |
| Missing Actual constraint | Inspect `oecdStructure()` or explicitly request `availability = "allowed"`. |
| Ambiguous dictionary | Supply `dataset = ...` or a fully qualified codelist reference. |

The client does not use `firstNObservations` or `lastNObservations`, parameters
restricted on some OECD datasets. Large datasets can require a different
published service space; the endpoint is configurable, for example:

```r
# Explicit endpoint selection; catalogue discovery now uses that space.
# oecdOptions(base_url = "https://sdmx.oecd.org/dcd-public/rest")
# oecdOptions(base_url = "https://sdmx.oecd.org/sti-public/rest")
```

For multiple queries, prefer one request with a vector of codes when possible.
Do not parallelize public downloads to evade limits. A small sequential `lapply()`
is useful when requests genuinely differ; retain failures rather than silently
binding incomplete results:

```r
# Online when executed; uses two data requests, not parallel workers.
fetch_one <- function(country) tryCatch(
  importData(cli_code, list(REF_AREA = country, FREQ = "M",
                           TIME_PERIOD = "2023-01")),
  error = identity
)
# results <- setNames(lapply(c("USA", "FRA"), fetch_one), c("USA", "FRA"))
# failed <- vapply(results, inherits, logical(1), "error")
# stopifnot(!any(failed))
# combined <- rbindlist(results, idcol = "request_country", use.names = TRUE)
```

## 12. A familiar workflow, adapted to OECD

The reference workflow is `eurodata` **1.8.0**, not a requirement to carry another
provider's names into OECD objects. The following entry points preserve useful
calling patterns and result conventions while using OECD terminology:

| OECDdata entry point | Meaning |
| --- | --- |
| `importData(OECDDatasetCode, filters = NULL)` | Flat observations, vector dimension filters, inclusive time range, `value_` and `flags_`. |
| `importDataList()` | Current catalogue with `ShortCode`, canonical `Code`, titles and OECD identity columns. |
| `importLabels(OECDDimCode, dataset = NULL)` | Code/label frame scoped to a dataset where needed. |
| `importDimLabel(OECDDimCode, dataset = NULL)` | A dimension or attribute's human-readable name. |
| `importMetabase(OECDDatasetCode = NULL)` | Dataset/dimension/code inventory with explicit availability semantics. |
| `describe(OECDDatasetCode, import_labels = !wide, wide = FALSE, import_dim_labels = TRUE)` | Long or wide marginal-code descriptions. |
| `compare(..., import_labels = TRUE, import_dim_labels = TRUE)` | Compare marginal code coverage across dataset selections. |
| `find(...)` | Search codes or titles with words, patterns and minus exclusions. |
| `browseDataList(subs)` | Browse a logical catalogue subset. |
| `as.OECDDataList(x, SearchCriteria = "", ...)` | Construct the OECD catalogue class and report caption. |

Additional helpers are `oecdDataset()`, `oecdStructure()`, `oecdQuery()`,
`oecdOptions()`, `clearCache()` and `oecdExample()`.

The result classes are `OECDDataset`, `OECDLabels`, `OECDDataList`,
`FoundOECDDatasetList`, `FoundOECDDatasetListReport` and `BrowsedOECDDatasetList`.
`OECDDatasetCode` is the resolved identity; `RequestedDatasetCode` is the original
input. Dimension labels carry `OECDDimCode`. There are no foreign-provider class
aliases or exported compatibility wrappers.

### Migrating code that actually uses eurodata

These are references to the **upstream eurodata API**, not names accepted by
OECDdata:

| In eurodata | In OECDdata |
| --- | --- |
| `EurostatDatasetCode = ...` | `OECDDatasetCode = ...` |
| `EurostatDimCode = ...` | `OECDDimCode = ...` |
| `as.EurostatDataList(x)` | `as.OECDDataList(x)` |

Positional calls such as `importData(code, filters)` remain familiar. Named calls
must use the OECD names. The maintainer's `tools/check-api.R` explicitly applies
this mapping when comparing the shared defaults against an installed `eurodata`;
it does not demand byte-identical signatures.

This is also a breaking correction to the initial 0.1.0 prototype. Update its
named arguments, class checks and attribute reads. The placeholder hierarchy
columns have been removed. There is no silent fallback for the former names.

Provider-specific semantics remain explicit: dictionaries are dataset-scoped,
observed and allowed codes are different, flags retain source meanings,
non-enumerated inventories are not invented, and missing observations are not
filled by constructing a Cartesian product. A matching dimension/code pair in
two flows does not by itself establish that their concepts or units are comparable.

## 13. Performance and development

The implementation uses native CSV parsing, in-place `data.table` column
updates, reference-aware XML parsing, full request caching and server-side
selection. It does not duplicate the entire response as a single R character
string. Numeric measures are converted once; dimension identifiers are not
inferred as numbers. No benchmark speedup is asserted without measurements.

Run the reproducible **offline parser-component benchmark** after installation:

```r
source(system.file("benchmarks", "parser.R", package = "OECDdata"))
```

It compares native CSV parsing with base `read.csv()` on identical generated
input. It reports input size, elapsed times, result sizes and thread settings.
It is not an end-to-end network benchmark, a peak-memory profiler or a claim
that all validation overhead is free.

Development and release commands:

```r
install.packages(c("testthat", "withr", "knitr", "rmarkdown", "rcmdcheck"))
# From the repository root:
testthat::test_local()
```

```sh
# Build vignettes and check the actual built package; requires Pandoc and,
# for the complete manual check, an appropriate LaTeX installation.
Rscript tools/check.R .

# Additional CRAN checks (R >= 4.5 and checktor >= 0.2.0):
Rscript tools/checktor.R .

# Optional mapped-interface check against an installed eurodata:
Rscript tools/check-api.R
```

The default test suite uses synthetic fixtures and mocked transports. The live
smoke test is opt-in and is kept out of ordinary CRAN checks:

```r
Sys.setenv(OECDDATA_LIVE_TESTS = "true")
testthat::test_local(filter = "live")
Sys.unsetenv("OECDDATA_LIVE_TESTS")
```

### Faster, evidence-rich local diagnostics

The bundled `tools/diagnostics.R` is the recommended single-entry-point
regression runner. Run from the package directory, or pass the path to a
complete source ZIP. Reports and local builds default to `.qa/`, which is
excluded from the source package and Git. The runner stages a source copy
before building so open Windows logs cannot break the build.

```powershell
# Quick iteration: source tests, checktor, naming/parse checks (seconds).
$env:OECDTEST_MODE = "quick"
Rscript --vanilla tools/diagnostics.R .

# Full diagnostic run: complete CRAN checks when prerequisites are present,
# plus checktor, coverage, lint, performance and live tests.
$env:OECDTEST_MODE = "full"
Rscript --vanilla tools/diagnostics.R .
```

For a ZIP input instead:

```powershell
Rscript --vanilla tools/diagnostics.R path/to/OECDdata-source.zip
```

Full mode detects Pandoc through `rmarkdown::find_pandoc()` and verifies
`pdflatex`, `kpsewhich`, `inconsolata.sty` and `url.sty` before running the
full CRAN gate. It does not launch a potentially very slow MiKTeX
on-the-fly installer. If Pandoc is missing, the runner still makes an
*explicitly partial* no-vignette build for installation diagnostics, but
the full CRAN gate is marked **SKIP**. A slow partial `R CMD check` is
omitted by default because it cannot prove CRAN readiness; request it with
`$env:OECDTEST_PARTIAL_CHECK = "1"` if you need additional examples/check
feedback. Install Pandoc and the missing LaTeX styles before final submission.
When the complete toolchain is ready, the full build and unmodified
`R CMD check --as-cran` run without omitting the manual or vignettes.
An additional manual build must produce a nonempty PDF: some Windows LaTeX
failures can appear as `OK` in the R check summary despite no PDF being written.

The two online stages use a persistent, integrity-checked response cache:
`%LOCALAPPDATA%/OECDdata-diagnostics` on Windows,
`~/.cache/OECDdata-diagnostics` on Linux, or the explicit
`OECDTEST_CACHE_DIR` path. The Windows default deliberately avoids network
home directories and their expensive owner lookups. Within a run, the first
stage downloads only missing/expired resources; the second runs in strict
offline mode against verified responses and the installed package.

For *diagnostic tests only*, downloaded data stay fresh for seven days and
metadata for thirty days, configurable with `OECDTEST_LIVE_CACHE_TTL` and
`OECDTEST_META_CACHE_TTL` (seconds). To force current OECD HTTP responses,
set `$env:OECDTEST_LIVE_FRESH = "1"`. The report records actual download
versus replay and individual live-call timings. Cached replay validates
client behavior but is **not** evidence of today's remote availability.

Other controls include `OECDTEST_LIVE_TIMEOUT` (per-request seconds),
`OECDTEST_CHECK_TIMEOUT` (subprocess seconds), and
`OECDTEST_INSTALL_OPTIONAL=1` to install optional `covr`, `lintr` and
`eurodata` packages if absent. All main `checktor` categories run by default;
`url_liveness` is deliberately skipped to avoid slow, flaky network checks.
Set `OECDTEST_CHECKTOR_URLS=1` to enable it. `spelling` requires a local
`aspell` or `hunspell` executable. Skipped diagnostics are listed
separately rather than counted as passes. The output ZIP contains stage timings,
`slowest-stages.csv`, machine details, `checktor` results and R CMD check
logs, with common credential patterns redacted in its feedback copy.

Windows and macOS release, Linux release/oldrel/devel, and minimum-R checks are
configured under `.github/workflows/`. Separate jobs verify the PDF manual and
run checktor with a spelling backend. The manual checktor workflow can also
check live URLs. Set `OECDTEST_CHECKTOR_STRICT=1` with `tools/checktor.R` to fail
if an enabled check cannot run. A requested URL check that cannot run always
fails explicitly. A separate manual workflow performs the small live request.
These are supplied configurations, not evidence of completed jobs.
Before submission, build with `R CMD build`, inspect every check result, run the
live test, verify name availability and maintainer details, review licensing,
and complete `cran-comments.md` with actual results.

## License and attribution

Copyright (c) 2026 Alek Rutkowski. Package-owned code, documentation and synthetic
fixtures are under the **MIT license**. See [LICENSE.md](inst/LICENSE.md).

The interface is inspired by and independently implemented against
[`eurodata`](https://cran.r-project.org/package=eurodata).
Its upstream source is GPL-2; no GPL implementation code is bundled or copied
into this MIT package. Shared workflow conventions and selected semantics are
adapted to OECD with attribution.

Runtime dependencies are `curl`, `data.table`, `digest`, `magrittr`, `xml2` and
R's `utils`. Development dependencies are `testthat`, `withr`, `knitr` and
`rmarkdown`; optional maintainer checks use `rcmdcheck` and an installed
`eurodata`. Each dependency retains its own authorship and license. See
[dependency acknowledgments](inst/ATTRIBUTION.md).

This is an independent client, not an OECD-endorsed product. The MIT license does
not relicense downloaded OECD or third-party statistics. Consult the source
attribution and applicable [OECD terms](https://www.oecd.org/en/about/terms-conditions.html)
before redistributing data. No real OECD observations are bundled.

## Official sources

Reviewed 16 October 2026:

* [OECD API introduction](https://www.oecd.org/en/data/insights/data-explainers/2024/09/api.html)
  and [technical API documentation](https://gitlab.algobank.oecd.org/public-documentation/dotstat-migration/-/raw/main/OECD_Data_API_documentation.pdf).
* [OECD API best practices](https://www.oecd.org/en/data/insights/data-explainers/2024/11/Api-best-practices-and-recommendations.html)
  and [restricted API parameters](https://www.oecd.org/en/data/insights/data-explainers/2026/03/Restricted-API-parameter.html).
* [SDMX REST data-query specification](https://github.com/sdmx-twg/sdmx-rest/blob/master/doc/data.md)
  and [structure-query specification](https://github.com/sdmx-twg/sdmx-rest/blob/master/doc/structures.md).
* [`eurodata` CRAN mirror and interface](https://github.com/cran/eurodata),
  [`data.table::fread` documentation](https://r-datatable.com/reference/fread.html),
  [CRAN policies](https://cran.r-project.org/web/packages/policies.html), and
  [Writing R Extensions](https://cran.r-project.org/doc/manuals/r-release/R-exts.html).
