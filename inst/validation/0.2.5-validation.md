# OECDdata 0.2.5 validation record

Tested on 20 October 2026, Windows 11 x64, R 4.6.1 (ucrt).
The discovered package defects are fixed. Complete CRAN release sign-off still
requires the outstanding checks below; this record does not claim CRAN acceptance
or completed GitHub Actions runs.

## Executed checks

| Check | Result |
|---|---|
| Offline testthat suite | 347 passing assertions across 74 executed cases; zero failures, errors or warnings. One additional live case is skipped by default. |
| New regressions | 11 cases covering 36 assertions; the original defects were reproduced before repair. |
| `R CMD build` | Successful source archive with the rendered vignette. |
| Windows `R CMD check --as-cran --no-manual` | Successful with remote incoming and clock verification disabled for the restricted environment; see the recorded log. |
| checktor 0.2.0 | No policy, robustness or opinion findings; no suppressed findings. All offline checks, including spelling with Hunspell 1.7.4, executed. |
| checktor URL liveness | Requested in the initial audit, but could not execute because R's outbound network access is blocked. Not counted as a pass. |
| Installed package | The diagnostic runner unloads the development namespace and loads the newly installed archive before checking its public API. |
| Real libcurl transport | Local HTTP integration passed gzip decoding, redirects, Retry-After handling, HTTP 204, HTML rejection, request headers and size enforcement. |
| Real OECD responses | Fresh REST v1 and v2 requests via PowerShell returned identical 32-row datasets, including values and attributes. |
| Cached integration | All seven assertions in the opt-in live test passed in strict offline mode against checksum-verified responses downloaded on 16 October 2026. |
| API compatibility | The intended argument/default mapping to eurodata 1.8.0 passed. |
| Offline coverage | 87.7% measured by covr 3.6.5. |
| Parser benchmark | 120,000 synthetic rows; native and base parser results verified. Timings are retained in the diagnostic log. |
| GitHub configuration | All three workflow YAML files parsed; jobs have not run on GitHub. |
| Current CRAN name | No case-insensitive `OECDdata` match in the CRAN package index downloaded on 20 October 2026. This is not name reservation or approval. |

The fresh data requests used `format=csvfile` with PowerShell's HTTP client.
The package's parser used the verified cached XML 2.1 metadata. This is fresh
REST/data-format evidence, not an end-to-end fresh run of the package's R HTTPS
transport. The recorded CSV 2 response was also exercised by cache replay.

## Defects repaired

* Pin latest dataflow versions before asking OECD for `referencepartial`
  references. The former wildcard request was observed returning HTTP 400;
  dataflow-only latest resolution and the exact-version request both succeeded.
* Return names for non-enumerated components such as `TIME_PERIOD`.
* Honour qualified component references over default dataset options and reject
  conflicting explicit contexts.
* Describe actual code availability even when no codelists are enumerated.
* Validate cache status/time fields and apply size limits to cache hits.
* Classify libcurl size failures correctly and avoid retrying them.
* Treat XML `false` and `0` exclusions conservatively; do not advertise excluded
  values as observed codes.
* Reject invalid or duplicate dimension positions and reserved component IDs.
* Validate dataflow and DSD identities in CSV responses, including conflicting
  identity columns.
* Stage development source before building so Windows logs under `.qa` cannot
  cause `R CMD build` to fail while copying the tree.
* Verify the installed namespace and actual PDF output in release tooling;
  fail explicitly when requested URL checks cannot execute.

## Outstanding release gates

1. **PDF manual:** the initial `R CMD check --as-cran` summary incorrectly
   reported the manual as OK. `Rdlatex.log` recorded a failed MiKTeX `texify`
   command and no manual PDF was produced. MiKTeX cannot initialize its
   configuration under this session's permissions. A portable TeX Live attempt
   also failed on inaccessible ancestor-path information. Neither is a proven
   package documentation error. The updated scripts explicitly require a
   nonempty PDF; the full-manual GitHub job does the same.
2. **Remote checks:** run CRAN incoming checks and checktor with
   `OECDTEST_CHECKTOR_URLS=1` using working R network access. The OECD service
   homepage was reachable through PowerShell.
3. **Other platforms:** execute the configured Windows/macOS release and Linux
   release, oldrel, devel and R 4.1.3 jobs. WSL was inaccessible locally.
4. **Fresh R integration:** run the manual live workflow or the opt-in test
   using the package's own transport.
5. **Publication:** this directory arrived without Git metadata or a specified
   GitHub remote. No repository was created or pushed, and nothing was submitted
   to CRAN. The maintainer still confirms submission and licensing declarations.

## Reproduction and local evidence

```sh
Rscript --vanilla tools/checktor.R .
Rscript --vanilla tools/check.R .
Rscript --vanilla tools/diagnostics.R .
```

The full check needs a working LaTeX installation; checktor spelling needs
`aspell` or `hunspell`. Strict checktor execution is available with
`OECDTEST_CHECKTOR_STRICT=1`. A partial manual-free check requires the explicit
`OECDDATA_NO_MANUAL=true` switch and is labelled accordingly.

Local evidence is kept in `.qa/`, excluded from Git and the CRAN package:
`final-tests.csv`, `finish-audit-final.log`, `http-integration-final.log`,
`checktor-spelling-final.log`, `replay-live.log`, and
`release-diagnostics/` (stage results, build, installation, coverage, lint,
benchmark and R check logs). The lint audit reported style findings only;
there were no lint warnings or errors. Coverage and benchmark results are
recorded without treating them as proof of correctness or network performance.

Checktor is an additional tool, separate from the
[CRAN policy](https://cran.r-project.org/web/packages/policies.html) and
[R's package checks](https://cran.r-project.org/doc/manuals/r-release/R-exts.html).
Its [severity and skipped-check reporting](https://r-pkg.thecoatlessprofessor.com/checktor/reference/checktor.html)
are preserved in the local reports.
