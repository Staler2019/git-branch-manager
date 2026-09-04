# Device tier (`integration_test/`)

Pin prefix `TEST-` (shared with [arch-testing.md](arch-testing.md)).
Format: [README.md](README.md).

## [TEST-device-runs-one-file] The device tier runs one file at a time per platform

- **Rule**: `-d macos` / `-d linux` / `-d windows`; the whole directory in one command is
  unreliable.
- **Do not** reduce a device batch's output to `tail -1` — on failure the last line is the
  *test name*, not the error.
- **Do not** edit `lib/` while a device run is in flight: each run recompiles from the working
  tree, so a green from such a run attests nothing.

## [TEST-stale-process-blocks-tier] A stale `gbm_flutter` process blocks the tier and looks exactly like a broken test

- **Do**: `pkill -f "gbm_flutter.app/Contents/MacOS/gbm_flutter"`, then run one pre-existing
  device test as a control before believing a new one.
- **Consequence**: **the same hazard ruins a manual on-screen check, and is harder to spot
  there because the window looks entirely reasonable.** The user's installed
  `/Applications/gbm_flutter.app` runs alongside a freshly built one, and `osascript`'s
  `first process whose name contains "gbm_flutter"` fronts whichever it likes — a correct fix
  screenshots as a failure.
- **Do**: run `ps aux | grep gbm_flutter` first, front the build you mean by `unix id` (its
  PID), and confirm the binary really carries the change
  (`strings <dylib> | grep <a string only the fix introduces>`) before trusting what you see.

## [TEST-foreground-line-is-not-a-failure] `Failed to foreground app; open returned 1` is not itself the failure signal

- **Rule**: it prints on fully green runs too. What discriminates is whether test-result lines
  follow it.
- **Consequence**: taking it at face value cost the side-by-side round a wrong 「裝置層跑不成」
  verdict that had already been written into the ledger before the re-run disproved it. It
  cost soft-warp the same verdict a round later, with the counts sitting right there in the log.
- **Do**: read past that line to the counts. **3 passed and then a hang on test 4** is a hang
  on one test, not a blocked tier, and the two call for completely different next moves.
- **Do**: **run the control on the *parent commit* too**, not just on a different test.
  Soft-warp's parent got only 1 test through where the branch got 3 — that is the evidence
  that says 「這輪沒有弄壞它」. It costs one detached-HEAD run and it is the half of the
  diagnosis the foreground line can never give you.

## [TEST-hang-is-not-yet-a-defect] A device-tier hang is not yet a defect

- **Consequence**: the same soft-warp file, re-run at the end of the branch after a `pkill`
  and a `scripts/build_capi.sh` rebuild, went **7/7 in 1m50s** with the previously hanging
  test passing in 15s.
- **Note**: which of the three changes (fresh dylib, no stale process, three more commits)
  cleared it was not isolated — so the honest claim is 「not reproducible」, not a cause.
- **Do**: rebuild the dylib and sweep stale processes *before* filing a device hang as a finding.

## [TEST-device-tier-not-in-ci] The device tier is in no CI job and is not part of `flutter test`

- **Consequence**: a UI redesign can leave it broken for rounds with every other tier green.
  C18 swept all ten files and found two red — neither from that round's own commits, both from
  the Working Copy redesign four rounds earlier: a test still tapping a deleted checkbox, and
  two finders that a new titlebar had made ambiguous.
- **Do**: **a round that removes or replaces a user affordance owns grepping
  `integration_test/` for it**, the same way it owns `lib/`.

## [TEST-stale-dylib-is-silent] `build/native/libgbm_capi.dylib` is a copy, and a stale one loads happily

- **Consequence**: a new capi entry point then appears to be a Dart bug. A stale one is *three
  days old and silent* in practice — C18 found one predating that round's own capi fields,
  where the symptom was a badge that simply never rendered, not an error of any kind.
- **Do**: run `app_flutter/scripts/build_capi.sh` before any device-tier run meant to attest a
  capi change.

## [TEST-ffi-matches-symbol-only] `dart:ffi`'s `lookupFunction` matches by symbol name only, never by signature

- **Consequence**: changing a capi parameter list and its Dart typedef in lockstep is checked
  by nothing — it compiles, analyzes and unit-tests clean, then corrupts the stack at runtime.
- **Do**: only a device-tier test crosses that seam.

## [TEST-pumprealappon-clears-prefs] `pumpRealAppOn` clears the preferences device tests would otherwise inherit

- **Rule**: it clears `panelLayout.*` and `graphColumns.*`, because device tests share the
  machine's real `shared_preferences` — a splitter ratio or a hidden column the developer once
  set silently changes what later tests render.
- **Rule**: **it also clears the flat keys `fileListViewMode` and `diffViewMode`**, which the
  two prefix filters had never covered. Tree mode nests rows under folder rows and
  side-by-side draws two columns of cells where there was one — exactly the shape that makes a
  finder ambiguous or miss.
- **Do**: a new app-wide preference means adding its key here. **A prefix filter will not
  catch a flat one.**

## [TEST-design-system-swap-breaks-finders] Swapping a widget for a design-system one breaks device-tier finders

- **Consequence**: `find.byType(ListTile)` → `GbmRow` breaks finders nothing else uses.
- **Do**: a round touching shared row widgets has to rerun all device tests, one at a time.

## [TEST-grep-misses-intent-driven-device-tests] Grepping `integration_test/` for the strings you changed cannot find a test that enters through an action id

- **Rule**: [TEST-device-tier-not-in-ci] makes a round that touches an affordance own grepping
  `integration_test/` for it. That is necessary and **not sufficient**: a device test may reach
  the surface through `Actions.invoke(GbmActionIntent(...))` ([ACT-intent-layer] dispatch path 1,
  used because a macOS `PlatformMenuBar` cannot be tapped) and then walk down through *fixture*
  data — a temp directory's name, a number it wrote itself — naming neither the widget nor any
  label the round edited.
- **Consequence**: `worktree_pending_counts_test.dart` mounts `WorktreesPanel` for its whole
  duration and matched **none** of six greps (`WorktreesPanel`, `Remove worktree`,
  `removeWorktree`, `Lock…`, `'Worktrees'`, `panelTabs`), while one round changed its rows'
  badges, gated its Remove button, relabelled its Lock button and made its entry point land on an
  already-open tab. The write-up had already concluded 「裝置層不受影響」 off those six misses.
- **Do**: grep the **`GbmActionId`** that opens the surface, and the panel's `GbmPanelKind`, as
  well as its widget and labels. Those are what an intent-driven test must name, because it is the
  one thing it cannot reach the surface without.
- **Do**: a run is cheaper than the reasoning — this file was 1/1 in 4 seconds. Prefer running the
  candidate to arguing it is unaffected.
- **Evidence**: [ledger: worktree 五個回報](../ledger/2026-09-03-feat-p19-panel-template-conformance-review.md)
