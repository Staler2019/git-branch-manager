# Testing tiers and fixtures

Pin prefix `TEST-`. Format: [README.md](README.md).

## [TEST-tiers] Testing tiers

- **Unit** (`test/actions/gbm_action_availability_test.dart`, and pure-model
  tests elsewhere) — no widgets, no Riverpod. Exercises `isActionEnabled()`
  directly against every id + a representative `RepoSessionState`.
- **Widget** (`test/features/**/*_test.dart`) — a single presentational
  widget (`MenuBarRow`, `TabRow`, `BranchTreeItem`, ...) pumped with plain
  callbacks/`ProviderContainer` overrides and a fake session, per-widget in
  isolation. This is where most of the suite lives, and it cannot catch a
  dispatch-path bug like the one above, because it never goes through
  `WorkspaceScreen._buildActionHandlers()` — it feeds a handler map (or
  named callback) directly to the widget under test.
- **Integration** (`test/integration/`, run by the same `flutter test`, no
  separate `integration_test/` device harness) — the real
  `WorkspaceScreen` behind a `GoRouter`, driven by
  `test/support/pump_workspace.dart`'s `pumpWorkspace()`. Exists
  specifically to cross the seam widget tests can't: does a keyboard
  shortcut/menu click/system-menu path really reach the controller, does a
  state transition (conflict ↔ clean, an interrupt overlay opening) leave
  every gated surface consistent with no residue, does navigating into
  `ConflictResolveWindow` and back preserve the right content. Use
  `pumpWorkspace`'s `extraRoutes` for a route that's a ShellRoute child in
  the real router (Compare tab) and `topLevelRoutes` for one that's a
  sibling of it (any `dialogRoute(...)`, `conflicts`) — mixing them up tests
  the wrong route structure and can pass for the wrong reason.

## [TEST-fake-session-seam] The fake session seam

**Fake session seam** (`test/support/fake_repo_session.dart`):
`FakeRepoSessionController extends RepoSessionController`, constructed with
a `FakeGbmBindings` whose `sessionOpen()` returns `nullptr` — the real
`_open()` sees that as "open failed" and returns before touching bindings or
recents again, so every controller method the fake doesn't override hits its
own `if (_session == nullptr) return;` guard and safely no-ops. Overridden
methods do the opposite: they record the call into `commandLog` (or a
bespoke field, for the handful of tests written before `commandLog` existed)
instead of no-opping. `FakeGbmBindings`/`FakeRecentsRepository` throw via
`noSuchMethod` on anything not explicitly implemented — a provider a test
forgot to override fails loudly instead of quietly reaching a real
`.dylib`/`.so`. Call `controller.emit(nextState)` to simulate an FFI event
publishing a new `RepoSessionState`, exactly as `_onEvent()` would.

## [TEST-new-gate-needs-integration] A new state-dependent gate needs an integration test

**Rule**: a new state-dependent gate goes into `isActionEnabled()` (or, if
it's not action-shaped, gets an equally-named single function) *and* gets an
integration test asserting the gated surface actually changes when the
state transitions — a widget test alone proves the widget renders `null`
correctly, not that the real dispatch path ever produces that `null`.

## [TEST-fixture-cannot-disagree] A fixture that cannot disagree with the code proves nothing

Twelve recorded shapes, each of which passed identically before and after a real fix.
One row per shape — when you find a thirteenth, append a row.

| # | Shape | Recorded case | Why it stayed green |
|---|---|---|---|
| 1 | *derives* one field from another | `hasTrackingInfo: upstream.isNotEmpty` (Tier 0c) | the fixture computes what the code computes |
| 2 | *borrowed* from a test whose subject contradicts yours | `_mergeState()`'s `isSequencerOperation` (cancel-surface round) | the borrowed state asserts the opposite case |
| 3 | *cannot express* the case | a single shared `GraphRow` instance (graph-edge round) | two rows are the same object |
| 4 | *cannot shrink* | a `repoRefsProvider` override pinned to one snapshot | no selected branch can ever vanish |
| 5 | two subjects *indistinguishable to the assertion* | `ActionToolbar`'s Branch and Stash share a gate and both only `context.push(...)`, so `onPressed != null` stayed green with the handlers swapped (P02-2) | sentinel `dialogRoute`s are what told them apart |
| 6 | *content contradicts its own name* | a "same-size edit must be re-read" test wrote 8 bytes then 7 (C18) | size really had changed, so dropping mtime from the key stayed green |
| 7 | *premise a later decision revoked* | 05-G's device fixture put two insertions one line apart; 變體 B then merged anything ≤ 2 unchanged lines apart (C18) | the same bytes silently became *one* scope |
| 8 | the **assertion**, not the fixture, is too weak | «controls are to the right of the status text» is true under `WrapAlignment.spaceBetween` **and** `start` (conflict-banner round) | «controls' right edge equals the Wrap's right edge» is the same claim stated tightly enough to fail |
| 9 | **cross-language**: hand-sets a field production never sets | every Dart test wrote `isSymbolic: true` by hand while `RefStore` never assigned it | **both languages stay green at once** — the C++ struct member did exist and was serialized |
| 10 | *varies more than the subject*, so an unrelated path answers correctly | History's uncommitted-row fixture rebuilt its `GraphSnapshotView` on every call, so emitting a clean working copy also handed `repoGraphProvider` a new object (discard round) | the rebuild that repaints the row came from the graph, not the working copy — mutating the row's `ref.watch` to `ref.read` left the file **fully green** |
| 11 | *cannot express* the failing condition at this tier at all | `.timeout()` around a synchronously-blocking `_closeSessions()` (Windows update round) | no fake-async widget test blocks a real event loop, so an empty fix goes green — see [FLU-timeout-cannot-bound-sync] |
| 12 | the **environment** gains a permanent item, quietly widening an exact count | D7 seeded a pinned Worktrees tab, and `expect(tabs, hasLength(1))` had meant 「this menu item opened exactly one tab」 | the seed alone satisfies the count, so the assertion now passes for a menu item that opens **nothing** |
| 13 | the fixture supplies **bounded ambient constraints by construction**, and the defect only fires under unbounded ones | `GbmDialogWarnField`'s own widget test pumped it inside `Scaffold(body: Center(child: ...))` — `Center` hands its child a *bounded* constraint | a `Row` using `CrossAxisAlignment.stretch` needs an unbounded ambient height to break under ([FLU-column-nonflex-unbounded-height]); the isolated test could never produce one, so it stayed green until the widget was wired into a real dialog's `Column` |

- **Do**: count the bytes the fixture actually writes, not the bytes the test's name claims (6).
- **Do**: **when a rule about how input is grouped changes, every fixture that encodes a gap,
  a count or an adjacency has to be re-read against the new rule** — nothing else will
  notice (7).
- **Do**: a mutation that comes back green is as often a weak assertion as a missing one (8).
- **Do**: when something becomes **always present**, every exact-count assertion about it turns
  vague. Fix it by *filtering the constant out and re-counting the subject*, never by bumping 1 to
  2 — the bumped number is satisfied by the constant alone (12).
- **Do**: **hold everything but the subject identical across a transition** — hoist the
  untouched halves of a state fixture into shared instances, so the only thing that can
  drive the rebuild is the thing under test (10). Two fixtures pumped separately cannot see
  this at all; it needs one tree and two states.
- **Do**: **when a field crosses a language boundary, ask which side assigns it** — a
  hand-set fixture is evidence about the consumer, never about the producer. Neither side can
  see the gap; only the real binary across the boundary can, which is why that test belongs in
  `GitIntegrationTest.cpp` and the FFI-payload one in `SessionApiTest.cpp` (9).

## [TEST-mutation-check-every-test] Mutation-check every new test, and check the red is narrow

- **Rule**: a broad red means the test is pinning something else.
- **Do**: copy the file to the scratchpad first (`cp file "$SCRATCH/x.bak"` → mutate → `cp`
  back). **Never `git checkout -- <file>`** to revert a mutation — it once discarded an
  entire uncommitted implementation.
- **Do**: have the mutation script assert `count(old) == 1` before writing. Two mutations in
  one round silently matched nothing after a formatter reflowed an argument list, and a
  `JsonCodec.cpp` anchor named only by its field matched **two** serializers (`DiffFile`'s and
  `ChangedFile`'s both emit `addedLines`). Anchor on a neighbouring line that is actually unique.
- **Do**: **count the reds from the progress line's `-N`, and read that line with your own eyes —
  not through a grep, a helper or a loop you wrote.** 「Is the red narrow」 is the *only* question a
  mutation check asks, so the entire result is that one number. It was misread three times in one
  round, three different ways: `grep -c` on the 「Failing tests:」 summary (**that list truncates at
  4 entries** plus 「... and N more」) read 8 as 4; a `\+[0-9]+ -[0-9]+` pattern matched the wrong
  line and read 3 as 1; and a `reds()` shell helper reported 1/1/1 for three mutations that were
  really 7/2/1. Each wrapper looked right and each was cheaper to trust than to check.
- **Note**: an anchor that matches nothing means **the mutation never applied**, so REDS=0 is not
  evidence of a vacuous test. Redo it against the real text before drawing any conclusion.
- **Do**: **write the two numbers down as two numbers** — how many mutations were run, and how
  many tests each reddened. One mutation may legitimately redden several tests, so the totals
  differ, and a write-up that reports the red total as the mutation count reads as a wider sweep
  than actually happened. Three commit messages and one ledger section in a single round each
  stated a count one-to-four higher than the items they went on to enumerate, all by this one
  substitution; the table beside the sentence is what caught it.

## [TEST-count-dont-any] Count, don't `any`

- **Do**: `commandLog.where((c) => c.name == …).length`. `.any(...)` is blind to a double
  dispatch, which is exactly what several of these fixes could regress into.

## [TEST-canvas-is-800x600] The default widget-test canvas is 800×600, and the test font is monospaced

- **Rule**: a `SizedBox` wider than the canvas is silently clamped, so a widget test that
  sizes its own canvas proves nothing about layout under real constraints.
- **Consequence**: a placement bug is invisible to any tier whose canvas is bigger than the
  real window. The column-picker popover shipped off-screen for exactly this; later a
  deliberate overflow in the Changed files row was caught **only** by the one test sized to
  `GbmLayout.splitterMainFiles.defaultExtent` — three others on the default canvas passed
  with the broken layout.
- **Rule**: **`flutter_test`'s default font draws every glyph `fontSize` wide**, so a
  42-character status line measures 548px where the real proportional font is far narrower.
- **Do**: any width a widget test measures is in test-font terms — say so next to the number,
  and pick which direction the distortion is safe in (a banner asserted to wrap at 440px wraps
  at a *narrower* real window, the harmless direction).
- **Do**: a recorded pixel figure is not portable between fixtures. An audit's «overflows by
  6.3px» measured 27px on a different session shape, and the gap changed the fix from «move
  one child to its own run» to «both levels have to wrap».

## [TEST-renderflex-main-axis-only] `RenderFlex` reports only main-axis overflow

- **Consequence**: a `takeException()` test cannot see a cross-axis defect.
- **Do**: check which axis the defect is on before writing a no-exception test.

## [TEST-no-pumpandsettle-with-spinner] Never `pumpAndSettle()` while an indeterminate `CircularProgressIndicator` is on screen

- **Rule**: it schedules frames forever, so `pumpAndSettle` can only time out.
- **Consequence**: this is the confirmed mechanism behind the device-tier batch flake
  (**#101**). It is *not* **#70** (a fixed 10s C++ `waitFor` budget losing to parallel load) —
  read the failure text before picking a family.
- **Do**: the spinners are `CommitGraphView` (only while `isRefreshing && graph.rows.isEmpty`),
  `ScopedDiffView` (while a diff request is in flight), and eight panels for their own loads.
  `StatusBar` is **not** one — `BackgroundTask.progress` is never null, so its
  `LinearProgressIndicator` is always determinate.

## [TEST-statusbar-lingers-3s] `StatusBar` lingers a finished task for 3 seconds

- **Consequence**: `_lingerTimer` means "the task cleared" cannot be asserted on the next frame.

## [TEST-runasync-for-real-async] Real async inside `testWidgets` needs `tester.runAsync()`

- **Rule**: `Picture.toImage()` (and asset decoding through `vg.loadPicture`) never completes
  in flutter_test's fake-async zone — no output, no timeout of its own, just a hang. Eight
  minutes of silence in the recorded case.
- **Do**: this is how an asset-rendering check is written when a string-level "it ships and
  parses" assertion is not enough.
- **Evidence**: ledger: P02 item 2's toolbar

## [TEST-fake-seam-fails-loudly] The fake seam fails loudly on purpose — and silently in one place

- **Rule**: `FakeGbmBindings` / `FakeRecentsRepository` throw via `noSuchMethod` for anything
  not explicitly implemented, so a provider a test forgot to override never silently reaches a
  real `.dylib`.
- **Consequence**: the opposite risk is inside `RepoSessionController` — a method the fake does
  not override hits its own `if (_session == nullptr) return;` guard and **no-ops silently**,
  so a test cannot tell a dead button from a dispatched one until that method is overridden to
  record into `commandLog`.
- **See also**: [TEST-fake-session-seam] for the seam's construction.

## [TEST-race-is-falsifiable] A memory-ordering race *is* falsifiable here

- **Do**: `CMakeLists.txt`'s `GBM_SANITIZE` option and the configured `build/tsan` /
  `build/asan-ubsan` presets turn "a race in principle" into a test:
  `cmake --build build/tsan --target gbm_capi_tests`.
- **Note**: a *timing* race (**#70**, **#77**) still cannot be reproduced on demand — its
  evidence is a deterministic mechanism test plus the causal chain, never an A/B.

## [TEST-draggable-is-not-a-drop] Asserting that a `Draggable` exists is not asserting that a drop works

- **Consequence**: the Working Copy board's empty column drew its "No staged changes"
  placeholder *instead of* the `DragTarget`, so the one column every repository starts with
  could not be dropped on — and with 變體 B's checkboxes gone, dragging is the only way a file
  changes side.
- **Do**: an empty-state placeholder belongs **inside** the target's builder, never in place
  of it.
- **Do**: the gesture recipe that actually drops in a widget test is `startGesture` →
  `pump()` → `moveTo(target)` → `pump()` → `up()` → `pump()`. Extra intermediate moves are
  not needed.

## [TEST-no-trackpad-pointer-kind] A pointer drag can never carry `PointerDeviceKind.trackpad`

- **Rule**: so "test the trackpad path" is not a thing you do by changing the kind.
  `PointerDownEvent`, `PointerMoveEvent`, `PointerUpEvent`, `PointerCancelEvent` and the two
  hover events each assert `kind != PointerDeviceKind.trackpad` in their own constructor, and
  `TestGesture.moveTo` asserts it again.
- **Rule**: the kind is reserved for `PointerPanZoom*` (two-finger pan/zoom), which is also
  the only route by which it reaches the `dragDevices` set (`_kTouchLikeDeviceTypes`) it is a
  member of. A trackpad **click and drag** therefore arrives as one of the permitted kinds —
  `mouse`, on macOS — so **a mouse-kind synthetic drag already *is* the trackpad path**.
- **Consequence**: this killed an otherwise well-evidenced hypothesis — that four green
  mutations of the Working Copy's mid-drag gate were green only because the synthetic drag
  never said "trackpad" while the reporting user's did.
- **Note**: the kinds a drag *can* vary over change hit/pan slop and scrollable claiming
  (`mouse` vs `touch`), which is a different claim from the one hardware makes.
- **Evidence**: ledger: 因為我是用觸控板

## [TEST-dragdevices-is-not-a-guard] Never override `dragDevices` to guard a selection

- **Rule**: `ScrollBehavior.dragDevices` defaults to `_kTouchLikeDeviceTypes`, which **has no
  `mouse` in it** — so a scroller never contests a desktop selection drag, and "protecting"
  the selection by clearing that set is unnecessary.
- **Consequence**: it is also actively harmful — trackpad two-finger pan reaches a
  `Scrollable` *through* membership of that very set, so an empty set deletes the main scroll
  input and leaves only the scrollbar thumb and Shift+wheel.
- **Rule**: **the 「unnecessary」 half is stronger than 「they never meet」, and it was
  measured** — adding `mouse` to a `GbmCodeScrollWell`'s `dragDevices` (the premise inverted)
  left `diff_pane_drag_stage_test.dart` fully green, and a probe confirmed the mutation was
  live (the same drag moved the horizontal offset 0 → 50 with no selection in the way). Even
  when a scroller *does* enter the arena, the `SelectableRegion` wins it.
- **Consequence**: a drag test under a scroller pins the **composition**, not the arena,
  because no realistic mutation of the arena reddens it.
- **Do**: `gbm_code_hscroll_test.dart` pins the premise with a mouse-kind drag that must
  **not** scroll.
- **Evidence**: ledger: soft-warp
