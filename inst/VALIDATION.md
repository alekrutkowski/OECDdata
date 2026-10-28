# OECDdata 0.3.1 validation record

Executed on 28 October 2026. This patch repairs Windows source installation;
the native XML engine, registration, XML helpers and import implementation are
byte-for-byte identical to the delivered 0.3.0 source archive. The HTTP user
agent now reports 0.3.1. Historical performance measurements remain explicitly
labelled 0.3.0 in `PERFORMANCE.md`.

## Executed checks

| Check | Result |
|---|---|
| Configuration regression harness | 22 tests passed, including missing, broken and working pkg-config; selected-toolchain precedence; custom flags; spaces; architecture-specific R; compiler-relative and legacy root discovery; compile/link failure; stale flags; and missing headers/archives. |
| Generated flag quoting | Verified through real GNU make and shell expansion; quoted include and library directories arrive as single compiler arguments. |
| Actual compiler probe | Revised configure.win successfully compiled and linked its parser/XPath probe with R 4.3.3 and libxml2 2.9.14 on Linux, using explicit native Linux flags. This exercises the real R CMD SHLIB invocation, not Windows compilation. |
| R CMD build | Passed, including the HTML vignette. |
| R CMD check --no-manual | Status: OK, with zero errors, warnings or notes on Linux x86_64. |
| Offline package suite | 428 passing assertions, zero failures or warnings, one opt-in network case skipped. |
| Native code preservation | src/oecd_xml.c, src/init.c, R/xml.R and R/import.R match the delivered 0.3.0 source archive exactly. |
| Rtools45 dependency verification | Read actual .pc files and wrapper from official Rtools45 revision 6768; confirmed libxml2 2.12.10 and its static dependency set. |
| CI configuration | All affected YAML files parse, new R helper parses, and release publication requires the Windows source-install workflow. |
| Static source/API audit | Passed, including all 16 public exports and documented signatures. |

The configuration harness uses controlled R/pkg-config test doubles for branch
coverage. Its make and shell quoting checks are real. No Windows executable was
compiled or run in this session. Native Windows installation checks are supplied
as CI jobs and remain to be executed on their runners. The package check excludes
the PDF manual and is not a full CRAN incoming check.

## Corrected discovery behavior

The 0.3.0 Windows script required a successful generic pkg-config lookup and
stopped before testing available libraries when that lookup failed. The revised
script checks R_TOOLS_SOFT and LOCAL_SOFT, including values supplied by R CMD
config, and prefers the selected toolchain's pkg-config. If pkg-config cannot
supply usable flags, it reads that toolchain's include and library directories
directly. The static library set includes libxml2, available lzma/iconv/zlib
archives, the math library and Windows sockets.

Older Rtools40 does not provide the modern root variables. Configuration can
resolve its compiler-relative root or use its documented RTOOLS40_HOME layout,
guarded by the actual running R version and pointer size. A stale RTOOLS40_HOME
cannot select legacy MSVCRT libraries through the legacy-layout query for R 4.2
or newer. Rtools40's optional libxml2 system package must still be installed.

Every candidate must pass an actual compile and link probe using the R executable
and architecture doing the installation. The probe covers parser and XPath
symbols and rejects libxml2 versions below 2.9.0. Failed configuration removes
stale generated Makevars.win. No external libraries are downloaded by configure.

## Windows CI coverage

The source-install workflow runs nine native configurations: R 4.2.3, R 4.3.3,
current R x86_64 and current R ARM64, each with normal detection and deliberately
unusable pkg-config; plus R 4.1.3 x86_64 with its optional Rtools40 libxml2 package.
The no-pkg-config jobs assert that the direct-library fallback actually ran.
Each installation is loaded and tested in a fresh R process. The Linux/current-R
check job also runs the isolated configuration regression harness.

The six Windows/Linux/macOS native release targets are retained. Publication is
additionally gated on the Windows source-install checks. No release has been
published and no hosted workflow execution is claimed here.

## Evidence and reproduction

The final package check is recorded in `validation/R-CMD-check.log` and
`validation/R-CMD-check-0.3.1.log`. Windows configuration evidence is in
`validation/windows-configure-0.3.1.log` and
`validation/rtools45-metadata-0.3.1.json`. Historical validation records are
retained in `validation/0.3.0-validation.md` and
`validation/0.2.5-validation.md`.

From the complete repository ZIP:

```sh
python3 tools/ci/check-configure-win.py
R CMD build .
R CMD check --no-manual OECDdata_0.3.1.tar.gz
```

On a native Windows runner with dependencies installed, the CI helper installs
from source and verifies the loaded package without custom libxml2 flags.

Primary references:

* [R's Windows build guide](https://developer.r-project.org/WindowsBuilds/R-4.5/howto.html)
  documents R_TOOLS_SOFT, LOCAL_SOFT and the pkg-config caveats.
* [Official Rtools45 archives](https://cran.r-project.org/bin/windows/Rtools/rtools45/files/)
  provide the actual static-library metadata inspected here.
* [Rtools40 documentation](https://github.com/r-windows/docs/blob/master/rtools40.md)
  describes the optional libxml2 package for legacy R.
