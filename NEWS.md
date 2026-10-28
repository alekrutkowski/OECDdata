# OECDdata 0.3.1

## Windows source installation

* Fix a false "libxml2 was not found" configuration failure when Rtools has
  the library but pkg-config is missing, unusable, or resolves unrelated
  libraries from PATH.
* Discover R's selected native library directory through R_TOOLS_SOFT and
  LOCAL_SOFT. Prefer its pkg-config and fall back to its libxml2 headers and
  static dependencies without downloading libraries.
* Validate every selected set of flags with an actual compile and link probe.
  Preserve paths containing spaces and discard stale generated flags on failure.
* Add configuration regressions and Windows source-install CI across current
  and older Rtools, including installations with pkg-config deliberately disabled.
* Keep the native XML processing implementation introduced in 0.3.0.

# OECDdata 0.3.0

## Performance

* Extract catalogue and codelist columns in C through libxml2, avoiding
  per-item R callbacks, repeated XPath evaluation, and one-row catalogue tables.
* Index dataflows, DSDs, codelists, concept schemes and content constraints once
  per document. Read production XML directly from downloaded files.
* Select catalogue versions without allocating one `.SD` table per group.
* Preserve the public import API, result classes and attributes, localization,
  dictionary identifiers, version resolution and raw-response cache semantics.

## Native build and validation

* Register native routines with dynamic symbol lookup disabled. Native XML
  documents have explicit ownership, child lifetime protection and unwind cleanup.
* Require a C compiler and libxml2 development files for source installation.
  Windows uses the matching Rtools static libraries.
* Add regression coverage for XML semantics, errors, document lifetimes, complete
  public imports and offline cache replay.
* Reject DTD declarations. Predefined and numeric entities, CDATA, mixed
  content, namespace prefixes and UTF-8 remain supported.
* Add an offline XML benchmark with a frozen 0.2.5 reference implementation,
  configurable inputs, parity checks, per-run timings and input hashes.
* Add GitHub Actions to build, reinstall, test and publish native binaries for
  Windows, Ubuntu 24.04 and macOS 15, each on x86_64 and ARM64.

## Compatibility repair

* Use `data.table::setattr()` for availability attributes in metadata tables.
  This preserves allocation/reference state when `describe()` removes and adds
  columns, including with data.table 1.14.10.

See `inst/PERFORMANCE.md` and `inst/VALIDATION.md` for measured results and scope.
