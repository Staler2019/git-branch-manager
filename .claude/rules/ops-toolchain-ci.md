---
paths:
  - ".github/**"
  - "CMakeLists.txt"
  - "**/CMakeLists.txt"
  - "CMakePresets.json"
  - ".gitattributes"
  - "app_flutter/scripts/**"
  - "app_flutter/pubspec.yaml"
  - "app_flutter/analysis_options.yaml"
  - "app_flutter/windows/**"
  - "app_flutter/macos/**"
  - "app_flutter/linux/**"
  - ".pre-commit-config.yaml"
  - ".clang-format"
  - "scripts/**"
---

# Toolchain, CI and platform

Pin prefix `CI-`. Format: [README.md](../../docs/rules/README.md). Rules a workflow, `.gitattributes`
or test now enforces live at that site, with the reason in its comment; history is in the ledger.

## [CI-dart-sdk-floor] Dart ≥ 3.13.0

- **Rule**: `app_flutter/pubspec.yaml` has `sdk: ^3.13.0`; Flutter 3.47.4 ships Dart 3.13.3.
- **Do**: four pins move together — `ci.yml`, `cq.yml`, `release.yml`, `.claude/hooks/session-start.sh` (all 3.47.4); `cq.yml` lints only that a pin exists, not that they agree. The floor sets the language version `dart format` styles by, so raising it reformats the tree: do it in the pin's round.
- **Evidence**: [ledger: flutter-upgrade](../../docs/ledger/2026-10-04-flutter-upgrade.md)

## [CI-formatter-version-drift] Both formatters drift by version, in both directions

- **Rule**: `dart format` output differs across Dart SDKs; `clang-format` is pinned to v18 (`cq.yml`, `.pre-commit-config.yaml`) and a local v22 reformats lines v18 left alone. A local Flutter that differs from the pin also rewrites `pubspec.lock` and `analysis_options.yaml`.
- **Do**: never run either formatter wholesale on a local version that differs from CI's pin; restore the file and re-apply only the intended edit. With `flutter --version` equal to the pin, `dart format .` is safe.
- **Do**: check `.clang-format` first — a suggestion from the repo's own config applies to v18 too.
- **Evidence**: ledger: Known gaps; [ledger: flutter-upgrade](../../docs/ledger/2026-10-04-flutter-upgrade.md); [ledger: fix/windows-host-updater-tests](../../docs/ledger/2026-09-19-fix-windows-host-updater-tests.md)

## [CI-no-ctest-timeout] `enable_testing()` without `include(CTest)` means there is **no** per-test timeout

- **Rule**: root `CMakeLists.txt` calls `enable_testing()` only, so ctest has no default deadline and a hanging test runs to GitHub's 6-hour cap.
- **Do**: the deadline is `tbase.execution.timeout` in `CMakePresets.json` (all five test presets inherit it; an explicit `TIMEOUT` property still wins) plus `timeout-minutes` on every `ci.yml` job. A job timeout cancels, so `if: failure()` log upload never runs; only the ctest timeout leaves a named `***Timeout`.
- **Do not**: `include(CTest)` (its `BUILD_TESTING` fights `GBM_BUILD_TESTS`; adds CDash targets) or `gtest_discover_tests(PROPERTIES TIMEOUT)` (misses `add_test()` fixtures).
- **Evidence**: [ledger: 追加，Windows CI 卡 81 分鐘](../../docs/ledger/2026-09-05-fix-benign-exit-not-logged-as-error.md)

## [CI-platform-guarded-block-uncompiled] A `#ifdef _WIN32` block is parsed only by Windows jobs, so its errors arrive one per CI round-trip

- **Rule**: a local macOS/Linux build never parses it, and the compiler stops at the first error.
- **Do**: after the second round-trip, type-check locally: a signature-only `windows.h` stub plus a wrapper that includes std headers *before* `#define _WIN32`, then `c++ -fsyntax-only`; mutation-check with a Win32 call first. MSVC `/W4 /WX` (e.g. C4774) still needs a CI run.
- **Do**: verify include paths from `compile_commands.json`, not a probe with hand-fed `-I` (`tests/CMakeLists.txt`'s `gbm_spawn_cost` comment is the worked case).
- **Evidence**: [ledger: 追加五](../../docs/ledger/2026-09-05-fix-benign-exit-not-logged-as-error.md)
