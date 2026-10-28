# Native XML performance in OECDdata 0.3.0

Measured on 28 October 2026 against the supplied OECDdata 0.2.5 source.

## Results for the requested public functions

Both installed package versions processed the **same downloaded OECD responses**
from an integrity-checked raw-response cache. Offline mode prevented all network
requests. Neither implementation cached parsed catalogues or structures: each
call still verified the cache, read and parsed XML, resolved metadata, performed
its normal validation and constructed its public result.

| Public call | 0.2.5 elapsed | 0.3.0 elapsed | Ratio | Returned result |
|---|---:|---:|---:|---|
| `importDataList()` | 43.827 s | 0.144 s | 304 times | 1,550 rows, 14 columns |
| `importData("CLI", filters)` | 48.228 s | 0.177 s | 272 times | 396 rows, 16 columns |

These are **one complete execution per function and version**, rather than
multi-run medians. The repeated XML measurements below provide separate evidence
for the parser improvement. Ratios are rounded.

The CLI filter is the one in the request:

```r
filters <- list(REF_AREA = c("USA", "FRA"), FREQ = "M",
                TIME_PERIOD = c("2023-01", "2023-12"))
cli <- importData("CLI", filters = filters)
```

The downloaded catalogue resolves this short code to
`OECD.SDD.STES,DSD_STES@DF_CLI,4.1`. The observations were obtained using the
package's generated REST v2 URL and SDMX-CSV 2 Accept header. The downloaded
metadata and observations are not bundled with the source package.

For both public functions, `identical(old_result, new_result)` was **TRUE**.
This checks values, column order, factor levels, classes and attributes,
including the cached download time, source URL, requested/resolved dataset
identities and filters. CSV values were not inferred or approximated.

**These results isolate local processing.** Live calls additionally incur HTTP
transfer time, service latency, configured request spacing and any retries.
They should not be interpreted as a promise that an uncached internet request
finishes in 0.14 or 0.18 seconds. The original timings supplied by the user were
from a different machine and are not used as denominators here.

## Repeated XML measurements

Each timed operation starts from an existing XML file and finishes with the
complete catalogue or `OECDStructure` result. File reading, libxml2 tree
construction and result extraction are included. Result equivalence is checked
before timing. An explicit garbage collection runs before each measured call;
garbage collection triggered during a call remains part of its timing.

| Input and operation | Size | 0.2.5 median | 0.3.0 median | Ratio |
|---|---:|---:|---:|---:|
| OECD catalogue, 1,550 flows | 8,918,674 bytes | 63.850 s | 0.071 s | 899 times |
| CLI structure, 598 dictionary codes | 459,074 bytes | 0.243 s | 0.012 s | 20 times |

The medians use three repetitions. All elapsed measurements, in seconds:

| Operation | Version | Run 1 | Run 2 | Run 3 |
|---|---|---:|---:|---:|
| Catalogue | 0.2.5 | 79.606 | 60.186 | 63.850 |
| Catalogue | 0.3.0 | 0.068 | 0.078 | 0.071 |
| CLI structure | 0.2.5 | 0.243 | 0.178 | 0.251 |
| CLI structure | 0.3.0 | 0.012 | 0.012 | 0.012 |

The catalogue timings show noticeable baseline variability. The public-call
and XML-component experiments also have different surrounding work and session
state, so their ratios should be read separately. A distinct check using the
installed original 0.2.5 catalogue parser also reproduced the slow path. No
peak-memory measurement is claimed; `object.size()` in the reusable benchmark
measures the returned R object only.

The repeated component experiment loaded the unchanged original `R/xml.R` into
an isolated environment with the installed package namespace as its parent.
It completed an equality run before the three measured calls. The reusable
benchmark now included in the package explicitly byte-compiles its frozen
reference functions and alternates old/new execution order. Its default thread
count is one; set it to four to match the recorded experiment's data.table
setting. Exact timing ratios will vary across systems and thread settings.

### Measurement environment

| Component | Value |
|---|---|
| OS and architecture | Ubuntu 24.04.3 LTS, x86_64 |
| R | 4.3.3 |
| C compiler | GCC 13.3.0 |
| libxml2 | 2.9.14 |
| data.table | 1.14.10 |
| xml2 | 1.3.6 |
| curl | 5.2.0 |
| data.table threads for recorded measurements | 4 |

CPU and elapsed timings, test counts and input fingerprints are retained in
`inst/validation/catalogue-times.csv`, `cli-structure-times.csv`,
`old-public.csv`, `new-public.csv`, `tests.csv` and `native-xml-results.json`.

### Input fingerprints

| Input | SHA-256 |
|---|---|
| Catalogue XML | `c4b4b51fb2346b100956c33144f6cd603bfe0957758cf15debadd8757911a816` |
| CLI structure XML | `f5c30b47985020abfe1b9a41da751a3eaeb726fb11dedb7895ebf200a5a45c92` |
| CLI CSV, 39,640 bytes | `ceb05ea8847162d7196aa1d5e2d6c53bba0364f0c5011570ed6d3b8e1fff8f86` |

The inputs came from the OECD's
[catalogue request](https://sdmx.oecd.org/public/rest/v2/structure/dataflow/*/*/+?references=none&detail=full)
and exact-version
[CLI structure request](https://sdmx.oecd.org/public/rest/v2/structure/dataflow/OECD.SDD.STES/DSD_STES@DF_CLI/4.1?references=all&detail=referencepartial).
Future responses at these URLs can differ, which is why input hashes accompany
the measurements.

## What changed

The original package already used native XML decoding through xml2/libxml2.
The expensive work was the repeated **R-level extraction and assembly around
that parser**. A catalogue flow created its own data.table and performed
separate XPath and R calls for names, descriptions and annotations. Codelists
performed a localization callback per code, and component resolution repeatedly
searched large documents for structural definitions.

The revised machinery changes that work as follows:

1. **Bulk catalogue extraction.** One C call fills complete character vectors
   for all catalogue fields. There is one conversion of those vectors to a
   data.table. Link construction and final catalogue formatting stay vectorized
   in R.
2. **Bulk dictionaries.** C extracts identifiers and language-selected labels
   directly into full-length columns, avoiding a node wrapper and R callback
   for each code. Duplicate-code validation remains in place.
3. **Document indexes.** Dataflows, DSDs, codelists, concept schemes and content
   constraints are indexed once when a document is read. Later lookups reuse
   these indexes. Remaining tree traversal, attributes, text, references and
   localization run in C.
4. **Cheaper catalogue version selection.** Numeric versions are validated
   together. Unique identities need no per-group version work; duplicates are
   selected by row index without allocating a separate `.SD` table per group.
5. **Direct file input.** Production metadata are read from the downloaded file
   by the package's native parser. R does not construct an intermediate giant
   XML string. Existing editable xml2 fixtures are converted once at the
   internal parser boundary.

The public signatures are unchanged. The data transport, `fread()` observation
parser, structured errors for metadata validation, short-code resolution,
language preference, version semantics and raw cache policy retain their
existing roles. The original XML code is frozen under `inst/benchmarks` only;
it is not a production fallback.

Native documents own their libxml2 trees and indexes. A child handle retains
its owner through R's protected external-pointer slot. Temporary resources use
unwind cleanup for ordinary returns, R errors and interrupts. Native routines
are registered and require symbols; dynamic symbol lookup is disabled, following
[Writing R Extensions](https://cran.r-project.org/doc/manuals/r-release/R-exts.html).
The implementation uses public libxml2 APIs and does not depend on xml2's
private external-pointer layout.

DTD declarations are rejected. Standard predefined/numeric entities, CDATA,
mixed text and UTF-8 are supported. No external entity loading or global
libxml2 handler changes are enabled. See the upstream
[parser option documentation](https://gnome.pages.gitlab.gnome.org/libxml2/html/parser_8h.html).

## Reproduce the comparison

After installing 0.3.0, run the entirely offline generated-input benchmark:

```r
source(system.file("benchmarks", "xml.R", package = "OECDdata"))
```

Defaults are 1,500 synthetic flows, a 10,000-code dictionary and three timed
runs. It checks both full catalogue and full structure results before timing.
The original thread setting is restored afterward. Optional controls include
`OECDDATA_BENCH_FLOWS`, `OECDDATA_BENCH_CODES`, `OECDDATA_BENCH_RUNS` and
`OECDDATA_BENCH_THREADS`. Small inputs can fall below timer resolution; the
script then reports an unavailable ratio instead of inventing precision.

To compare existing downloaded OECD XML files, without fetching them again:

```r
Sys.setenv(
  OECDDATA_BENCH_CATALOGUE = "catalogue.xml",
  OECDDATA_BENCH_STRUCTURE = "cli-structure.xml",
  OECDDATA_BENCH_REFERENCE = "OECD.SDD.STES,DSD_STES@DF_CLI,4.1",
  OECDDATA_BENCH_THREADS = "4",
  OECDDATA_BENCH_OUTPUT = "xml-timings.csv"
)
source(system.file("benchmarks", "xml.R", package = "OECDdata"))
```

Use the reference belonging to the supplied XML, rather than assuming that
4.1 will remain the latest version. The benchmark does not infer an ambiguous
dataflow identity or use the network to resolve one.

## Source installation and native releases

Source installation needs a C compiler and libxml2 development files. Unix
configuration uses pkg-config or xml2-config and verifies compilation/linking.
Custom paths can be passed through `LIBXML_CFLAGS`/`LIBXML_LIBS` or
`INCLUDE_DIR`/`LIB_DIR`. Windows configuration uses architecture-matched Rtools
and its static libxml2 dependencies. The package-owned code remains MIT
licensed, attributed to Alek Rutkowski; libxml2 retains its own license and
authorship. See `ATTRIBUTION.md`.

`.github/workflows/release-binaries.yaml` builds one source package and runs
native binary jobs for all six targets:

| Platform | x86_64 runner | ARM64 runner |
|---|---|---|
| Windows | `windows-2022` | `windows-11-arm` |
| Ubuntu 24.04 | `ubuntu-24.04` | `ubuntu-24.04-arm` |
| macOS 15 | `macos-15-intel` | `macos-15` |

Every job reinstalls its binary in a fresh library, verifies the actual
ELF/PE/Mach-O architecture, checks the registered C routines, runs the offline
example and test suite, and records build information. A matching `v0.3.0` tag
publishes the source archive, all six binaries and checksums only after every
job succeeds. A manual branch run creates Actions artifacts. The workflow does
not publish anything merely because this source package is downloaded.

Windows ARM64 uses the community-maintained ARM64 R distribution documented by
the [R Contributors](https://contributor.r-project.org/windows-arm64/).
Linux binaries target the stated Ubuntu and R version; they are not universal
Linux archives. macOS binaries select the system libxml2 library. Runner
availability and architecture names were checked against
[GitHub's documentation](https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job)
and [r-lib/actions release notes](https://github.com/r-lib/actions/releases).
Cross-platform CI execution and publication are separate from the local checks
recorded in `VALIDATION.md`.
