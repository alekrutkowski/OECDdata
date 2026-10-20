# Attribution, provenance and licenses

Package-owned code, documentation and synthetic fixtures:
Copyright (c) 2026 Alek Rutkowski <alek.rutkowski@gmail.com>, MIT license.

## Interface provenance

The public interface is modeled on **eurodata 1.8.0**, authored by Aleksander
Rutkowski. Its CRAN DESCRIPTION, NAMESPACE, help descriptions and public calling
conventions were reviewed on 16 October 2026. Its GPL-2 implementation is not
bundled, linked as a runtime dependency, or copied into this independently
written MIT implementation. Shared workflow conventions are explicitly acknowledged. Public arguments,
classes and dataset selection are adapted to OECD rather than copied verbatim.

Upstream: https://cran.r-project.org/package=eurodata
CRAN mirror: https://github.com/cran/eurodata

## Runtime dependencies

All dependencies retain their original copyright notices, authors and licenses.
No dependency source code is vendored. The exact installed license and author
records can be inspected with `utils::packageDescription()`.

| Dependency | Contribution | Official project/documentation |
|---|---|---|
| data.table | Native CSV parser, efficient joins, grouping and reference updates | https://r-datatable.com/ |
| curl | libcurl-backed HTTPS transfer, URL encoding and HTTP-date parsing | https://jeroen.r-universe.dev/curl |
| digest | SHA-256 request identities and response checksums | https://eddelbuettel.github.io/digest/ |
| magrittr | Functional pipe syntax | https://magrittr.tidyverse.org/ |
| xml2 | libxml2-backed namespace-independent structure parsing | https://xml2.r-lib.org/ |
| R utils | Package metadata, version comparison, browser/report utilities | https://www.r-project.org/ |

`data.table` and the native libraries behind `curl` and `xml2` provide the native
performance used by this package. No custom C, Rcpp or cpp11 extension is needed.

## Development and documentation dependencies

`testthat` supplies assertions and scoped mocked bindings; `withr` restores
options and cleans temporary resources; `knitr` and `rmarkdown` build the offline
vignette. Maintainer scripts optionally use `rcmdcheck` and an installed copy of
`eurodata` for a mapped public-interface comparison. GitHub workflows use `r-lib/actions`
and GitHub-maintained actions. These tools retain their own licenses.

- https://testthat.r-lib.org/
- https://withr.r-lib.org/
- https://yihui.org/knitr/
- https://rmarkdown.rstudio.com/
- https://rcmdcheck.r-lib.org/
- https://github.com/r-lib/actions

Inspect installed dependency provenance programmatically:

```r
packages <- c("data.table", "curl", "digest", "magrittr", "xml2", "utils",
              "testthat", "withr", "knitr", "rmarkdown")
lapply(packages, function(p) utils::packageDescription(p)[c("Package", "Version",
                                                          "Author", "License")])
```

## OECD and SDMX

OECD supplies the public API and its metadata; the SDMX community specifies the
exchange formats and REST contracts. This independent client is not endorsed by
either organization. The MIT license on this client does not replace terms for
OECD or third-party data obtained through it.

All bundled observations and metadata are invented fixtures with a `TEST`
agency. They are not republished OECD statistics. No live statistical response
or downloaded personal data is included in the release.
