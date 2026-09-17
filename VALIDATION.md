# Offline portability validation

Validated on Ubuntu 22.04 x86-64 with Python 3.10, a fresh virtual environment and a separate extracted runtime directory, on 2026-09-17 UTC.

- Archive SHA-256 verification and extraction passed.
- All 9,932 bundled file entries verified; the live registry is deliberately mutable and excluded from repeated immutable checks.
- Reviewed collector and batch imports passed under the portable path mappings.
- Frozen transport imports, independent review-chain checks and five-node constructor binding passed without invoking device methods.
- Packaged ARM toolchain compiled and linked the real file-helper C source against the packaged libiio/libad9361 libraries; output verified as ARM ELF.
- Named collector dry run reported three repeats per model, no device contact, no allocation and no RF transmission.
- All seven named result-export tests passed, including ZIP checksums, unique names, fixture rejection and incomplete-batch preservation.

This validates portable software packaging. No live RF collection was performed, and no RF dataset acceptance is claimed. The unchanged underlying source integration review is bundled with the runtime.
