# Offline portability validation

## Automatic FPGA restoration

The committed v13 manager payload matches the home-run qualified SHA-256 and size. Nine offline tests pass for the new host restore controller: skip v13 without staging, verify all serials before staging, reject unknown versions/corrupt payloads, require device preflight, preserve unresolved dispatch state, reject foreign terminal tokens, and avoid repeating dispatch after a simulated disconnect. All five derived helper/watchdog pairs pass real POSIX shell syntax and offline `--plan` execution, retain the original device gates, and bind the fresh boot plus staged file hashes. These tests mock transport and do not claim an actual v8-to-v13 hardware load.

## Current fixed-mu regret collector

The launcher now runs one normal regret-learning round at fixed μ=50, horizon40 and initial level3. Per-epoch learner updates remain enabled. The unchanged fixed-pure firmware and separately authored plan/package verifier pass their frozen source checks under the portable Linux mappings. The retained RF engine imports successfully, and the Windows-style build launcher adapter executes the packaged ARM compiler natively. The immutable bundle now contains10,171 file entries; registry evolution is preserved during support updates. No device contact or session allocation occurred in these checks.

The portability adapter changes host command invocation only; actual plan/package checks, canonical allocation, preflight, sensor payload, learning firmware and RF collection are retained. Its live execution on the lab laptop is still unvalidated.

## Previous fixed-action package checks

Validated on Ubuntu 22.04 x86-64 with Python 3.10, a fresh virtual environment and a separate extracted runtime directory, on 2026-09-17 UTC.

- Archive SHA-256 verification and extraction passed.
- All 9,932 bundled file entries verified; the live registry is deliberately mutable and excluded from repeated immutable checks.
- Reviewed collector and batch imports passed under the portable path mappings.
- Frozen transport imports, independent review-chain checks and five-node constructor binding passed without invoking device methods.
- Packaged ARM toolchain compiled and linked the real file-helper C source against the packaged libiio/libad9361 libraries; output verified as ARM ELF.
- Named collector dry run reported three repeats per model, no device contact, no allocation and no RF transmission.
- All seven named result-export tests passed, including ZIP checksums, unique names, fixture rejection and incomplete-batch preservation.

This validates portable software packaging. No live RF collection was performed, and no RF dataset acceptance is claimed. The unchanged underlying source integration review is bundled with the runtime.
