---
paths:
  - "app_flutter/integration_test/**"
---

# Device tier (`integration_test/`)

Pin prefix `TEST-` (shared with [arch-testing.md](arch-testing.md)).
Format: [README.md](../../docs/rules/README.md). Run steps and which native library loads: `app_flutter/integration_test/README.md`.

## [TEST-device-runs-one-file] The device tier runs one file at a time, and its output is read down to the result lines

- **Rule**: `flutter test integration_test/<file> -d macos` (or `linux`/`windows`), never the directory: every file after the first fails to attach. `Failed to foreground app; open returned 1` prints on green runs too; what discriminates is whether `+N:` test lines follow it.
- **Do not**: reduce a batch to `tail -1` (the last line is a test name, not the error), or edit `lib/` mid-run (each run recompiles the working tree, so a green from it attests nothing).
- **Evidence**: `app_flutter/integration_test/README.md`'s "Running"

## [TEST-stale-process-blocks-tier] A stale `gbm_flutter` process blocks the tier and looks exactly like a broken test

- **Do**: `pkill -f "gbm_flutter.app/Contents/MacOS/gbm_flutter"`, then run one pre-existing test as a control; for a hang, also run the *parent commit*. A hang that does not reproduce after that is 「not reproducible」, not a cause.
- **Do**: a manual on-screen check has the same hazard: `/Applications/gbm_flutter.app` runs beside a fresh build and `osascript` fronts either. `ps aux | grep gbm_flutter`, front by PID, and confirm the binary carries the fix (`strings <dylib> | grep <string only the fix adds>`).

## [TEST-device-tier-not-in-ci] The device tier is in no CI job and is not part of `flutter test`

- **Rule**: `ci.yml`'s three-OS `flutter-ci` runs `flutter test` and `flutter build` only; a UI redesign can leave `integration_test/` red for rounds with every other tier green.
- **Do**: **a round that removes or replaces a user affordance owns grepping `integration_test/` for it**, and re-runs every device file (one at a time) after touching a shared row widget.

## [TEST-ffi-matches-symbol-only] `dart:ffi`'s `lookupFunction` matches by symbol name only, never by signature

- **Rule**: a `_XxxNative` that disagrees with its own `XxxDart` is an analyzer error (`must_be_a_subtype`); the header drifting from both is caught at the unit tier by `test/data/ffi/gbm_capi_signature_parity_test.dart` (text compare). Two same-type parameters swapped (`rebaseMerges` ↔ `autosquash`) still pass it.
- **Do**: a capi parameter whose *meaning* changes needs a device-tier test that drives it across `dart:ffi`.
- **Evidence**: [ledger: #159 簽章 parity](../../docs/ledger/2026-10-04-feature-issue159.md)

## [TEST-pumprealappon-clears-prefs] `pumpRealAppOn` clears the preferences device tests would otherwise inherit

- **Rule**: device tests share the machine's real `shared_preferences`; the harness removes `panelLayout.*`, `graphColumns.*` and a hand-listed `flatKeysToClear` (`real_repo_harness.dart`), because a developer's own splitter, column, list/tree or diff-mode setting silently changes what a finder sees.
- **Do**: a new app-wide preference that changes layout or tree shape adds its key to `flatKeysToClear`; a prefix filter will not catch a flat key.

## [TEST-grep-misses-intent-driven-device-tests] Grepping `integration_test/` for the strings you changed cannot find a test that enters through an action id

- **Rule**: [TEST-device-tier-not-in-ci]'s grep is necessary, not sufficient: a device test may reach the surface through `Actions.invoke(GbmActionIntent(...))` ([ACT-intent-layer] dispatch path 1; a macOS `PlatformMenuBar` cannot be tapped) and walk down fixture data, naming no widget or label the round edited.
- **Do**: also grep the **`GbmActionId`** that opens the surface and its `GbmPanelKind`; then run the candidate (`worktree_pending_counts_test.dart` matched none of six label greps and runs 1/1 in 4 seconds) rather than argue it is unaffected.
- **Evidence**: [ledger: worktree 五個回報](../../docs/ledger/2026-09-03-feat-p19-panel-template-conformance-review.md)
