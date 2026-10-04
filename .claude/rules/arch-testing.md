---
paths:
  - "app_flutter/test/**"
  - "tests/**"
  - "app_flutter/integration_test/**"
---

# Testing tiers and fixtures

Pin prefix `TEST-`. Format: [README.md](../../docs/rules/README.md).

## [TEST-tiers] Testing tiers

- **Rule**: unit (`test/actions/`, pure models) · widget (`test/features/**`, one widget fed callbacks or a fake session) · integration (`test/integration/`, the real `WorkspaceScreen` via `pumpWorkspace()`, run by the same `flutter test`) · device (`integration_test/`, see [TEST-device-tier-not-in-ci]).
- **Do**: a claim that crosses the dispatch seam (shortcut or menu → controller; a state transition → every gated surface) goes in the integration tier; a widget test feeds the handler map directly. `pumpWorkspace`'s `extraRoutes` vs `topLevelRoutes` must match the real route structure.

## [TEST-new-gate-needs-integration] A new state-dependent gate needs an integration test

- **Do**: put the gate in `isActionEnabled()` and add an integration test that the gated surface changes on the state transition; a widget test only proves the widget renders `null`.

## [TEST-fake-seam-fails-loudly] The fake seam fails loudly on purpose, and silently in one place

- **Rule**: `FakeGbmBindings` / `FakeRecentsRepository` throw via `noSuchMethod`, so a provider a test forgot to override never reaches a real `.dylib`.
- **Do**: a `RepoSessionController` method the fake does not override no-ops silently (`_session == nullptr`), so a dead button looks dispatched; override it to record into `commandLog` (`test/support/fake_repo_session.dart`).

## [TEST-fixture-cannot-disagree] A fixture that cannot disagree with the code proves nothing

Fifteen shapes, each green before and after a real fix; comments cite them by number. Cases: [record](../../docs/records/2026-10-04-fixture-cannot-disagree-shapes.md).

1 derives one field from another · 2 borrowed from a test with the opposite subject · 3 cannot express the case · 4 cannot shrink · 5 two subjects indistinguishable to the assertion · 6 content contradicts its name · 7 premise a later decision revoked · 8 assertion too weak, not the fixture · 9 cross-language: hand-set field production never sets · 10 varies more than the subject · 11 cannot express the failing condition at this tier · 12 environment gains a permanent item (exact counts) · 13 bounded ambient constraints · 14 assertion reads a proxy for the render tree · 15 widget's box, not the box its render object paints

- **Do**: count the bytes the fixture writes, not what its name claims (6); re-read every gap/count/adjacency fixture when a grouping rule changes (7); a green mutation is as often a weak assertion as a missing one (8).
- **Do**: when something becomes always present, filter it out and re-count the subject, never bump 1 to 2 (12); hold everything but the subject identical across a transition, one tree and two states (10).
- **Do**: ask which object paints what you assert, since a finder resolves to a widget and the defect may be one render object below (14, 15); for a field crossing the FFI, ask which side assigns it, and test it in `GitIntegrationTest.cpp` / `SessionApiTest.cpp` (9).

## [TEST-mutation-check-every-test] Mutation-check every new test, and check the red is narrow

- **Do**: have the mutation script assert `count(old) == 1` before writing; a reflowed or non-unique anchor (`JsonCodec.cpp`'s `addedLines`) matches nothing or the wrong thing, so REDS=0 proves nothing.

## [TEST-count-dont-any] Count, don't `any`

- **Do**: `commandLog.where((c) => c.name == …).length`; `.any(...)` is blind to a double dispatch.

## [TEST-canvas-is-800x600] The default widget-test canvas is 800×600 and its font is monospaced

- **Rule**: an unsized canvas clamps a wider `SizedBox`, so a width bug shows only in a test sized to the real extent (`GbmLayout.splitterMainFiles.defaultExtent`); the test font draws every glyph `fontSize` wide.
- **Do**: say "in test-font terms" beside any measured width and pick the safe distortion direction; a recorded pixel figure is not portable between fixtures.

## [TEST-renderflex-main-axis-only] `RenderFlex` reports only main-axis overflow

- **Do**: a `takeException()` test cannot see a cross-axis defect; check which axis the defect is on first.

## [TEST-no-pumpandsettle-with-spinner] Never `pumpAndSettle()` while an indeterminate `CircularProgressIndicator` is on screen

- **Rule**: it schedules frames forever, so `pumpAndSettle` can only time out; this is the confirmed mechanism of the device-tier batch flake (**#101**), not **#70**.
- **Do**: find the sites with `grep -rn 'CircularProgressIndicator(' app_flutter/lib`; `StatusBar`'s bar is determinate (`BackgroundTask.progress` is a non-null `double`).

## [TEST-runasync-for-real-async] Real async inside `testWidgets` needs `tester.runAsync()`

- **Rule**: `Picture.toImage()` and `vg.loadPicture` never complete in the fake-async zone: a silent hang with no timeout.
- **Evidence**: `branch_tree_item_hover_paint_test.dart`; ledger: P02 item 2's toolbar

## [TEST-draggable-is-not-a-drop] Asserting that a `Draggable` exists is not asserting that a drop works

- **Do**: drop with `startGesture` → `pump()` → `moveTo(target)` → `pump()` → `up()` → `pump()`; an empty-state placeholder goes inside the `DragTarget` builder (`working_copy_board_test.dart`).

## [TEST-posix-fixture-on-windows-host] A fixture that shells out to `chmod`/`touch` is inert on Windows and for uid 0

- **Rule**: `flutter-ci` runs the unit tier on `windows-latest` and `macos-26`; NTFS ignores `chmod`, so the test goes green having never met the failure.
- **Do**: «cannot write» = a missing parent directory; age a directory by moving the injected clock, never its mtime; pick a failing delete per OS (`_makeUndeletable`) and prove it bites; cut a path with the simulated OS's separators.
- **Evidence**: [ledger: fix/windows-host-updater-tests](../../docs/ledger/2026-09-19-fix-windows-host-updater-tests.md)

## [TEST-golden-no-glyphs] A golden must not paint a font glyph

- **Rule**: flutter_test loads no Material Icons font, so `Icon(Icons.*)` paints a placeholder box,
  and glyph anti-aliasing differs between macOS versions at the same Flutter SDK.
- **Consequence**: `GbmIconButton`'s goldens were 6px / 2/255 red on CI's `macos-26` and green on a
  local macOS 27, and compared a placeholder instead of an icon.
- **Do**: put `LucideIcon` (SVG paths, what production uses) in a golden; path-drawn borders and
  fills matched on both machines.
- **Evidence**: [ledger: flutter-upgrade](../../docs/ledger/2026-10-04-flutter-upgrade.md)
