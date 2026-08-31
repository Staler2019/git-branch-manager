# CLAUDE.md

Root-level guide for Claude Code (and other AI assistants) working in this
repo. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and
[docs/FEATURES.md](docs/FEATURES.md) first — this file adds the Flutter UI's
structure, its session state machine, the UX acceptance bar `app_flutter/`
changes are held to, and the invariants and traps that keep being rediscovered.

**This file is an umbrella.** The rules themselves live in one file per
category under [docs/rules/](docs/rules/) and are pulled in by the `@` imports
below, so everything is still auto-loaded into every session — what changed is
that two parallel branches now edit two different files instead of two regions
of one 1,742-line one.

## Three layers, and what belongs in each

```
CLAUDE.md                        this file — filing rules + imports. No rule text.
  └─ docs/rules/<category>.md    the rules. Short, pinned, four fields each.
       └─ docs/ledger/<date>-<branch>.md   the decision record. Length is free.
```

| Layer | Holds | Auto-loaded | Conflict shape |
|---|---|---|---|
| `CLAUDE.md` | filing rules, imports, redirects | yes | rarely edited |
| `docs/rules/*.md` | current-state facts + distilled invariants | yes (via `@`) | different categories → different files |
| `docs/ledger/*.md` | one round's narrative and evidence | no | one round → one new file |

## Where a round's write-up goes

When you finish a round of work:

1. **The narrative goes to its own file** —
   `docs/ledger/<YYYY-MM-DD>-<branch>.md`, plus one line appended to
   [docs/ledger/INDEX.md](docs/ledger/INDEX.md). Date first, because branch
   names are too arbitrary to find a round by. Shape and rationale:
   [docs/ledger/README.md](docs/ledger/README.md). Length is free there.
2. **Only what a future session must know *before* it starts is distilled into
   [docs/rules/](docs/rules/)** — as a `## [PIN] Title` block with
   `Rule` / `Consequence` / `Do` / `Evidence`, `Evidence` pointing back at the
   round's file. Short and precise; the long form stays in the ledger. Format:
   [docs/rules/README.md](docs/rules/README.md). If an existing rule already
   covers it, edit that rule's lines rather than adding a second one.
3. **Current-state facts are rules too** — a route, a field, a state
   transition, a CI constraint, a still-open drift, all under
   `docs/rules/`. History is not: if the sentence only makes sense as "what
   happened in round N", it is ledger material.

**Do not put rule text back into this file, and do not append a round-shaped
section anywhere.** Both are what broke the previous two schemes: this file
reached ~176KB before the ledger was split out of it, and the ledger then
reached 5,900 lines with every round appending to the same end-of-file.

## Rules

@docs/rules/README.md
@docs/rules/arch-structure.md
@docs/rules/arch-state-machine.md
@docs/rules/arch-actions.md
@docs/rules/arch-testing.md
@docs/rules/fn-refs-branches.md
@docs/rules/fn-git-commands.md
@docs/rules/ops-ux-rubric.md
@docs/rules/ops-spec-reading.md
@docs/rules/ops-repo-culture.md
@docs/rules/ops-toolchain-ci.md
@docs/rules/fn-cpp-core.md
@docs/rules/drift-open.md

## Invariants and traps

Distilled from [docs/ledger.md](docs/ledger.md) — every entry here happened,
and the round that found it is named so the original measurement, the
counter-example and the issue number stay one grep away. Organised by what
you are touching, not by when it was learned.

### Tests and fixtures

- **A fixture that cannot disagree with the code proves nothing.** Four
  recorded shapes, each of which passed identically before and after a real
  fix: a fixture that *derives* one field from another
  (`hasTrackingInfo: upstream.isNotEmpty`, Tier 0c); one *borrowed* from a
  test whose subject contradicts yours (`_mergeState()`'s
  `isSequencerOperation`, cancel-surface round); one that *cannot express*
  the case at all (a single shared `GraphRow` instance, graph-edge round);
  one that *cannot shrink* (a `repoRefsProvider` override pinned to one
  snapshot, so no selected branch can ever vanish); and one whose *two
  subjects are indistinguishable to the assertion* — `ActionToolbar`'s Branch
  and Stash share a gate and both only `context.push(...)`, so asserting
  `onPressed != null` stayed green with the two handlers swapped (P02-2
  round). Sentinel `dialogRoute`s are what told them apart. A sixth: one whose
  *content contradicts its own name* — a "same-size edit must be re-read" test
  wrote 8 bytes then 7, so the mutation that removes mtime from the cache key
  stayed green because size really had changed (C18). Count the bytes the
  fixture actually writes, not the bytes the test's name claims. A seventh:
  one whose *premise a later decision revoked* — 05-G's device fixture put
  its two insertions one line apart, which was "two separate changes" until
  變體 B made the default scope merge anything ≤ 2 unchanged lines apart, at
  which point the same bytes meant *one* scope and the line-granularity test
  was silently testing something else (C18). **When a rule about how input is
  grouped changes, every fixture that encodes a gap, a count or an adjacency
  has to be re-read against the new rule** — nothing else will notice. An
  eighth is not a fixture at all but the *assertion*: one weak enough that
  both candidate implementations satisfy it. «the controls are to the right
  of the status text» is true under `WrapAlignment.spaceBetween` **and**
  under `start`, so the mutation between them stayed green; «the controls'
  right edge equals the Wrap's right edge» is the same claim stated tightly
  enough to fail (conflict-banner round). A mutation that comes back green
  is as often a weak assertion as a missing one. A ninth is the cross-language
  shape, and it is the worst of them because **both languages stay green at
  once**: a fixture that hand-sets a field production never sets. Every Dart
  test of the `isSymbolic` filters wrote `isSymbolic: true` by hand while
  `RefStore` never assigned the field at all, and the C++ tests were green
  because the struct member really did exist and really was serialized. Neither
  side can see the gap; only the real binary on the far side of the boundary
  can, which is why that test belongs in `GitIntegrationTest.cpp` and the
  FFI-payload one in `SessionApiTest.cpp`. **When a field crosses a language
  boundary, ask which side assigns it** — a hand-set fixture is evidence about
  the consumer, never about the producer.
- **Mutation-check every new test**, and check the red is *narrow* — a broad
  red means the test is pinning something else. Copy the file to the
  scratchpad first (`cp file "$SCRATCH/x.bak"` → mutate → `cp` back);
  **never `git checkout -- <file>`** to revert a mutation, which once
  discarded an entire uncommitted implementation. Have the mutation script
  assert `count(old) == 1` before writing — two mutations in one round
  silently matched nothing after a formatter reflowed an argument list, and a
  `JsonCodec.cpp` anchor named only by its field matched **two** serializers
  (`DiffFile`'s and `ChangedFile`'s both emit `addedLines`). Anchor on a
  neighbouring line that is actually unique.
- **Count, don't `any`.** `commandLog.where((c) => c.name == …).length` —
  `.any(...)` is blind to a double dispatch, which is exactly what several
  of these fixes could regress into.
- **The default widget-test canvas is 800×600**, and a `SizedBox` wider than
  it is silently clamped. A widget test that sizes its own canvas proves
  nothing about layout under real constraints, and a placement bug is
  invisible to any tier whose canvas is bigger than the real window (the
  column-picker popover shipped off-screen for exactly this reason; later, a
  deliberate overflow in the Changed files row was caught **only** by the one
  test sized to `GbmLayout.splitterMainFiles.defaultExtent` — three others on
  the default canvas passed with the broken layout). Compounding it:
  **`flutter_test`'s default font draws every glyph `fontSize` wide**, so a
  42-character status line measures 548px in a test where the real
  proportional font is far narrower. Any width a widget test measures or
  asserts is in test-font terms; say so next to the number, and pick which
  direction the distortion is safe in (a banner asserted to wrap at 440px
  wraps at a *narrower* real window, which is the harmless direction).
  A recorded pixel figure taken this way is not portable between fixtures
  either — an audit's «overflows by 6.3px» measured 27px on a different
  session shape, and the gap changed the fix from «move one child to its own
  run» to «both levels have to wrap».
- **`RenderFlex` reports only main-axis overflow**, so a `takeException()`
  test cannot see a cross-axis defect. Check which axis the defect is on
  before writing a no-exception test.
- **Never `pumpAndSettle()` while an indeterminate `CircularProgressIndicator`
  is on screen** — it schedules frames forever, so `pumpAndSettle` can only
  time out. This is the confirmed mechanism behind the device-tier batch
  flake (**#101**), and it is *not* **#70** (a fixed 10s C++ `waitFor` budget
  losing to parallel load) — read the failure text before picking a family.
  The rule used to name `top_bar.dart`'s `isRefreshing` spinner; that file is
  deleted and the trap is now **narrower and elsewhere** —
  `CommitGraphView` draws one only while `isRefreshing && graph.rows.isEmpty`,
  `ScopedDiffView` while a diff request is in flight, and eight panels for
  their own loads. `StatusBar` is *not* one of them: `BackgroundTask.progress`
  is never null, so its `LinearProgressIndicator` is always determinate.
- `StatusBar` lingers a finished task for 3 seconds (`_lingerTimer`), so
  "the task cleared" cannot be asserted on the next frame.
- **Real async inside `testWidgets` needs `tester.runAsync()`.**
  `Picture.toImage()` (and asset decoding through `vg.loadPicture`) never
  completes in flutter_test's fake-async zone: no output, no timeout of its
  own, just a hang — eight minutes of silence in the recorded case. This is
  how an asset-rendering check is written when a string-level "it ships and
  parses" assertion is not enough (`docs/ledger.md`, P02 item 2's toolbar).
- **The fake seam fails loudly on purpose.** `FakeGbmBindings` /
  `FakeRecentsRepository` throw via `noSuchMethod` for anything not
  explicitly implemented, so a provider a test forgot to override never
  silently reaches a real `.dylib`. The opposite risk is inside
  `RepoSessionController`: a method the fake does not override hits its own
  `if (_session == nullptr) return;` guard and **no-ops silently**, so a
  test cannot tell a dead button from a dispatched one until that method is
  overridden to record into `commandLog`.
- **Device tier (`integration_test/`) runs one file at a time per platform**
  (`-d macos` / `-d linux` / `-d windows`); the whole directory in one
  command is unreliable. Never reduce a device batch's output to `tail -1` —
  on failure the last line is the *test name*, not the error. Never edit
  `lib/` while a device run is in flight: each run recompiles from the
  working tree, so a green from such a run attests nothing. A stale
  `gbm_flutter` process blocks the entire tier and looks exactly like a
  broken test — `pkill -f "gbm_flutter.app/Contents/MacOS/gbm_flutter"`, and
  run one pre-existing device test as a control before believing a new one.
  **The same hazard ruins a manual on-screen check, where it is harder to spot
  because the window looks entirely reasonable**: the user's installed
  `/Applications/gbm_flutter.app` runs alongside a freshly built one, and
  `osascript`'s `first process whose name contains "gbm_flutter"` fronts
  whichever it likes — a correct fix screenshots as a failure. Run `ps aux |
  grep gbm_flutter` first, front the build you mean by `unix id` (its PID), and
  confirm the binary really carries the change (`strings <dylib> | grep <a
  string only the fix introduces>`) before trusting what you see.
  But **`Failed to foreground app; open returned 1` is not itself the failure
  signal** — it prints on fully green runs too, and what discriminates is
  whether test-result lines follow it. Read past that line to the counts
  before concluding the tier is blocked; taking it at face value cost the
  side-by-side round a wrong 「裝置層跑不成」 verdict that had already been
  written into the ledger before the re-run disproved it. It cost soft-warp
  the same verdict a round later, for the same reason and with the counts
  sitting right there in the log — **3 passed and then a hang on test 4** is
  a hang on one test, not a blocked tier, and the two call for completely
  different next moves. **Run the control on the *parent commit* too**, not
  just on a different test: soft-warp's parent got only 1 test through where
  the branch got 3, which is the evidence that says 「這輪沒有弄壞它」 —
  it costs one detached-HEAD run and it is the half of the diagnosis the
  foreground line can never give you. **And a hang is not yet a defect**: the
  same soft-warp file, re-run at the end of the branch after a `pkill` and a
  `scripts/build_capi.sh` rebuild, went **7/7 in 1m50s** with the previously
  hanging test passing in 15s. Which of the three changes (fresh dylib, no
  stale process, three more commits) cleared it was not isolated — so the
  honest claim is 「not reproducible」, not a cause. Rebuild the dylib and
  sweep stale processes *before* filing a device hang as a finding.
- **The device tier is in no CI job and is not part of `flutter test`**, so a
  UI redesign can leave it broken for rounds with every other tier green. C18
  swept all ten files and found two red — neither from that round's own
  commits, both from the Working Copy redesign four rounds earlier: a test
  still tapping a deleted checkbox, and two finders that a new titlebar had
  made ambiguous. **A round that removes or replaces a user affordance owns
  grepping `integration_test/` for it**, the same way it owns `lib/`.
- `build/native/libgbm_capi.dylib` is a **copy**: a stale one loads happily,
  and a new capi entry point then appears to be a Dart bug. A stale one is
  *three days old and silent* in practice — C18 found one predating that
  round's own capi fields, where the symptom was a badge that simply never
  rendered, not an error of any kind. Run `app_flutter/scripts/build_capi.sh`
  before any device-tier run that is meant to attest a capi change.
- **`dart:ffi`'s `lookupFunction` matches by symbol name only, never by
  signature.** Changing a capi parameter list and its Dart typedef in
  lockstep is checked by nothing — it compiles, analyzes and unit-tests
  clean, then corrupts the stack at runtime. Only a device-tier test crosses
  that seam.
- `pumpRealAppOn` clears `panelLayout.*` and `graphColumns.*`, because device
  tests share the machine's real `shared_preferences` — a splitter ratio or a
  hidden column the developer once set silently changes what later tests
  render. **It also clears the flat keys `fileListViewMode` and
  `diffViewMode`**, which the two prefix filters had never covered: Tree mode
  nests rows under folder rows and side-by-side draws two columns of cells
  where there was one, both of which are exactly the shape that makes a
  finder ambiguous or miss. A new app-wide preference means adding its key
  here — a prefix filter will not catch a flat one.
- **A memory-ordering race *is* falsifiable here.** `CMakeLists.txt`'s
  `GBM_SANITIZE` option and the configured `build/tsan` / `build/asan-ubsan`
  presets turn "a race in principle" into a test:
  `cmake --build build/tsan --target gbm_capi_tests`. A *timing* race
  (**#70**, **#77**) still cannot be reproduced on demand — its evidence is a
  deterministic mechanism test plus the causal chain, never an A/B.
- Swapping a widget for a design-system one can break device-tier finders
  nothing else uses (`find.byType(ListTile)` → `GbmRow`), so a round touching
  shared row widgets has to rerun all device tests, one at a time.
- **Asserting that a `Draggable` exists is not asserting that a drop works**,
  and the gap between them is where a shipped defect lived: the Working Copy
  board's empty column drew its "No staged changes" placeholder *instead of*
  the `DragTarget`, so the one column every repository starts with could not
  be dropped on — and with 變體 B's checkboxes gone, dragging is the only way
  a file changes side. An empty-state placeholder belongs **inside** the
  target's builder, never in place of it. The gesture recipe that actually
  drops in a widget test is `startGesture` → `pump()` → `moveTo(target)` →
  `pump()` → `up()` → `pump()`; extra intermediate moves are not needed.
- **A pointer drag can never carry `PointerDeviceKind.trackpad`, so "test the
  trackpad path" is not a thing you do by changing the kind.**
  `PointerDownEvent`, `PointerMoveEvent`, `PointerUpEvent`, `PointerCancelEvent`
  and the two hover events each assert `kind != PointerDeviceKind.trackpad` in
  their own constructor, and `TestGesture.moveTo` asserts it again — the kind is
  reserved for `PointerPanZoom*` (two-finger pan/zoom), which is also the only
  route by which it reaches the `dragDevices` set (`_kTouchLikeDeviceTypes`)
  it is a member of. A trackpad **click and drag** must therefore arrive as
  one of the permitted kinds — `mouse`, on macOS — so a mouse-kind synthetic
  drag already *is* the trackpad path. This killed an otherwise well-evidenced hypothesis — that four green
  mutations of the Working Copy's mid-drag gate were green only because the
  synthetic drag never said "trackpad" while the reporting user's did (ledger:
  「因為我是用觸控板」). The kinds a drag *can* vary over change hit/pan slop
  and scrollable claiming (`mouse` vs `touch`), and that is a different claim
  from the one hardware makes.
  **The same two facts settle whether a `Scrollable` competes with a drag, and
  they cut the opposite way from the obvious guess.** `ScrollBehavior.dragDevices`
  defaults to `_kTouchLikeDeviceTypes`, which **has no `mouse` in it** — so a
  scroller never contests a desktop selection drag, and "protecting" the
  selection by clearing that set is unnecessary. It is also actively harmful:
  trackpad two-finger pan reaches a `Scrollable` *through* membership of that
  very set, so an empty set deletes the main scroll input and leaves only the
  scrollbar thumb and Shift+wheel. Never override `dragDevices` to guard a
  selection; `gbm_code_hscroll_test.dart` pins the premise with a mouse-kind
  drag that must **not** scroll (ledger: soft-warp). **The 「unnecessary」 half
  is stronger than 「they never meet」, and it was measured**: adding `mouse`
  to a `GbmCodeScrollWell`'s `dragDevices` — the premise inverted — left
  `diff_pane_drag_stage_test.dart` fully green, and a probe confirmed the
  mutation was live (the same drag moved the horizontal offset 0 → 50 with no
  selection in the way). So even when a scroller *does* enter the arena, the
  `SelectableRegion` wins it. The corollary matters for what a test can
  claim: a drag test under a scroller pins the **composition**, not the arena,
  because no realistic mutation of the arena reddens it.

### Flutter, Riverpod and widgets

- **`addPostFrameCallback` does not ask for a frame.** It registers a callback
  for the end of the *next* frame, and if nothing else schedules one the
  callback simply never runs. A drag hides this — the drag itself keeps
  frames coming — so a notification coalesced onto a post-frame callback can
  work for months and then not arrive at all the first time a plain click
  drives it (`selection_touch.dart`'s `_scheduleNotify`; the scope a
  hunk-heading click had already recorded stayed invisible). In a widget test
  the gap is total rather than intermittent, because `tester.pump()` runs a
  frame only `if (hasScheduledFrame)` — six pumps in a row did nothing.
  Pair every deferred notification with
  `SchedulerBinding.instance.ensureVisualUpdate()`.
- **`ref` inside a `ConsumerState.dispose()` always throws.**
  `_assertNotDisposed()` gates every `ref` member on `context.mounted`, and
  the element is already unmounted by then. Capture the notifier in
  `initState()` into a field and guard on `StateNotifier.mounted`.
- **Never write a provider from `build()`.** Riverpod's guard is
  `assert`-wrapped, so debug crashes but **release strips it and lets the
  write land mid-frame**. Defer to a post-frame callback and recompute from
  then-current state, not from a captured list.
- **An unfiltered `ref.watch(repoSessionProvider(identity))` rebuilds the
  whole shell on *every* state publish, including caches nothing on screen
  reads.** Scrolling History prefetches commit metadata per scroll tick, so
  each reply republished state and rebuilt `MenuBarRow`,
  `PlatformMenuBarHost`, `ActionToolbar`, `TabRow` and
  `_buildActionHandlers()` — on macOS that rebuilds a real native menu bar,
  and the reported symptom was 「每次捲動 menubar 都會閃爍」. `WorkspaceScreen`
  now watches a **record of the nine fields it consumes** and `read`s the
  full state (it is passed whole to ~40 sites, which is what `grep
  'session\.'` undercounts — bare `session` arguments do not match).
  **Never put a derived getter that builds a new collection into such a
  record**: `gonePendingRefs` returns a fresh `Set` and a `Set` has no value
  equality, so including it makes the record unequal every time and silently
  restores the storm it was meant to remove (ledger: History 捲動卡頓).
- **`ref.listen` never fires for the value already present when it
  registers.** Every `ref.listen`-driven piece of session state needs
  something else covering the value that was already there — a filter query
  surviving a repository close is the recorded case. The test that sees it is
  the one that seeds the provider *before* pumping. **The mirror case is that
  a seeded test is blind to the opposite defect**: a surface that reads a
  provider once per *mount* instead of once per *build* answers correctly on
  its only build, so `ref.watch` → `ref.read` stays green across every test
  that seeds-then-pumps. Only flipping the notifier while the tree is on
  screen tells the two apart — verified by exactly that mutation going red in
  `test/integration/soft_wrap_preference_flow_test.dart` and green in the
  four seeded wrap tests next door (ledger: soft warp round).
- **An entry point gated on one resting state replays stale answers forever
  once the machine has terminal states.** The update dialog checked on mount
  only from `idle`, but `upToDate` / `failed` / `developmentBuild` are
  terminal — nothing returns them to `idle` — so re-opening it re-showed the
  previous answer for the rest of the session. Gate on a *named predicate*
  over the whole enum (`UpdateState.wantsFreshCheck`) rather than on one
  value, and check whether every state the machine can rest in has a way
  out. Note the partition is rarely two-way: a **standing offer** the user
  has not acted on is neither stale nor in-flight, and refreshing it costs an
  API call on the commonest path. Where a `ref.listen` fills the remaining
  gap, key it on the specific *transition*, never on "arrived at X" — `idle`
  is also where `dismiss()` lands, and re-checking there re-offers the very
  thing the user just declined (ledger: 更新流程的三個缺陷).
- **A finder proves existence, never position.** `TabRow` shipped spanning
  the whole window, covering the sidebar, and all **2039** tests stayed green
  through the fix — not one asserted where it was. Assert `getRect()` against
  a *neighbour's* rect (「left edge not before the sidebar's right edge」),
  never against a pixel constant, and never `findsOneWidget` for a layout
  claim (ledger: "Working Copy 重新設計"). **One level deeper: the right finder
  can still resolve to the wrong render object.** `find.byType(X)` takes X's
  first descendant RenderBox, and if that is a `RenderTransform` — or any
  render object whose effect applies to its *children* — `localToGlobal`
  reports the untransformed position, so a pinned widget measures as if it
  never moved and the test goes red while the code is correct. Measure a node
  *below* the transform. Corollary for clipping: `ClipRect` does not change
  `getRect` at all, so a clip's geometry can only be asserted by asking its
  `CustomClipper` directly (ledger: soft-warp).
- **`RenderFlex` lays out non-flex children first**, then divides what is
  left — so a `Flexible` child can never rescue an overflow that non-flex
  children caused. Six surfaces overflowed at the app's own default 1280×720
  for exactly this. Related: `Spacer` is itself a flex child and competes for
  the space it looks like it is donating; and `Expanded` satisfies "no
  overflow" while collapsing its child to zero, so assert visibility, not
  absence of exception.
- Tapping an `InkWell` does **not** give it focus — call `requestFocus()`
  first if a focus-scoped shortcut has to work after a click. In the sidebar
  that call lives in `_onBranchSelect`, so it now runs on *every* click; the
  clause that used to be here ("a plain click on a branch row routes through
  checkout") stopped being true when single-click became selection.
- **A hand-rolled `InkWell` silently inherits `ThemeData.hoverColor`** — about
  4% black/white, invisible on a real display. `lib/widgets/gbm_row.dart`
  exists to pass `surfaceHover`/`surfaceSelected` for you; the sidebar shipped
  with no visible hover for months because its row built its own `Container` +
  `InkWell` instead (ledger: "Sidebar branch rows"). Reach for `GbmRow` for
  anything row-shaped, and assert the token by identity — hover cannot be
  proven by a widget test that only checks for no exception. It recurred twice
  more in C18, both found by *sweeping every `InkWell(`/`GestureDetector(` in
  the round's changed files*: `FileTreeFolderRow` (folder rows had no hover
  while the file rows around them in the same list did) and a private
  `_MiniButton` in `working_copy_view.dart` that also re-implemented
  `GbmButton(secondary, sm)`'s border, text size and padding by hand. That
  grep is worth running at the end of any round that touches widgets.
- **The gesture arena taxes double-clickable rows, and it is not local.** An
  `InkWell` holding both `onTap` and `onDoubleTap` withholds the tap for
  `kDoubleTapTimeout` (~300ms), and a `DoubleTapGestureRecognizer` anywhere on
  the *ancestor* path does the same to every child button underneath it — a
  row's own ⋯ button waits out the row's double-tap timer. Put an immediate
  action on `Listener(onPointerDown:)` (never enters the arena) and keep the
  double-tap on the narrowest subtree that needs it. `InkResponse` stays
  hover-enabled with no primary callback at all, because `isWidgetEnabled` is
  `_primaryButtonEnabled || _secondaryButtonEnabled` and `onSecondaryTapDown`
  satisfies the second half.
- **`SelectionArea` tells you the selected *string*, not which widgets it
  covers.** `selection_touch.dart` asks each row's own subtree via a
  `SelectionListener`, which brings three traps: a row moving between subtrees
  builds its new listener before the old unmounts (two listeners, one
  notifier, framework assert — give each row a stable `GlobalKey` so Flutter
  reparents one element); inserting a widget *among* keyed rows reparents
  everything below it and perturbs the selection, so a derived card takes a
  **fixed slot**; and reacting to every report is a feedback loop
  (`setState` → geometry moves → delegates re-report), so listen only between
  pointer-down and pointer-up. **Draw nothing derived from that set while the
  pointer is down**: the one-shot block sits inside the scope card, so
  drawing it mid-drag reparents the rows whose listeners are still reporting.
  The live feedback during a drag is `SelectionArea`'s own text highlight;
  the block is what the drag settles into, so `endGesture()` is what
  notifies. Note the honest limit — **no synthetic gesture at either tier
  reproduces the symptom this was reported for** (「只能選一行」): with the
  gate removed, row-by-row and sub-row device drags both stayed green. The
  invariant is pinned; the cure is not. All three are 「first frame right,
  later frames wrong」 — a one-frame assertion cannot see any of them. But note
  what the second one is *not* an argument for: the one-shot block's fixed
  slot at the top of the column was justified by it and **was not the
  design** (the demo nests it inside the scope card, wrapping the selected
  rows in place). What makes the nested form safe is the same sentence the
  hazard note rests on — those keys are `GlobalKey`s, so Flutter *moves* the
  element into its new parent rather than rebuilding it. A recorded hazard
  is a reason to solve the problem, not a licence to change the design. A fourth is
  not about frames at all: **the submit path is a diff-change path, one
  dispatch later.** `_dropSelection` documented that clearing the highlight
  is unsafe while the tree restructures, and staging *is* what restructures
  it — so a `clearSelection()` deferred to after the dispatch lands inside
  the restructure it caused and the framework throws
  ConcurrentModificationError out of `handleClearSelection`. Clear
  synchronously **before** dispatching. Nothing below the device tier can see
  it: the fakes never restage, so the diff never changes and the clear always
  finds a settled tree.
- **`SelectableRegion` clears its selection when it loses focus**
  (`_handleFocusChanged`, non-web), and it requests focus for itself as a
  drag begins — so an *ancestor* that calls `requestFocus()` on every pointer
  down is a live way to wipe out the selection the gesture is still making.
  Guard on `!node.hasFocus`: `hasFocus` is true for an ancestor of the
  primary focus, so the guard already covers "the region below me is the one
  holding it", and key events reach an ancestor `CallbackShortcuts` either
  way.
- **`Ctrl/Cmd+A` must be bound inside the list's own focus scope**, never
  app-wide: a `Shortcuts` closer to a focused editor than
  `DefaultTextEditingShortcuts` steals text select-all.
- **`GbmMenuItem.enabled: false` is only a visual signal** — set `onTap: null`
  too, or a "disabled" item still fires. Disabled-with-a-tooltip beats
  hidden: 隱藏會讓人以為功能不存在.
- **A `PlatformProvidedMenuItem` silently forks one action id into two
  different windows, and the dispatch-parity test cannot see it.** `helpAbout`
  was wired in `_buildActionHandlers()` *and* listed in
  `PlatformMenuBarHost._systemProvided`, so Windows/Linux opened
  `AboutDialogContent` while macOS got the native About panel — for months,
  with every tier green. The reason no test caught it: a system-provided item
  takes **no handler from the map at all**, so «the handler is non-null» was
  vacuously true, and the in-window click test only ever exercised the
  non-macOS path. **Assert what a menu handler renders, not that it exists** —
  `item.onSelected!()` then a finder on the route's content
  (`workspace_about_dialog_test.dart`), with a second dialog route present as a
  decoy so a mis-wire fails on content rather than on a missing route. Spec
  page 01 is the rule being enforced: only the menu bar's *position* follows
  the OS; every window's *contents* are Flutter's on all three platforms. Note
  `PlatformMenuBar` replaces menus from index 1 only, so `MainMenu.xib`'s
  `systemMenu="apple"` menu survives untouched — macOS already has a native
  About/Quit/Hide there, which is what makes a second one under Help redundant
  rather than required. Quit stays system-provided for exactly that reason.
- **macOS reads the *application* name from the bundle, never from
  `NSWindow.title`.** `MainMenu.xib` writes the Apple menu, About, Hide and
  Quit items as the literal placeholder `APP_NAME`, which AppKit resolves from
  `CFBundleDisplayName` → `CFBundleName` at load time; the Dock tooltip and
  Force-Quit list read the same. It said `gbm_flutter` because `CFBundleName`
  was `$(PRODUCT_NAME)` and `PRODUCT_NAME` is also the built artifact's name,
  which `release.yml` hardcodes as `gbm_flutter.app` in four places. Writing
  the literal into `Info.plist` decouples the two (#67 candidate fix 1);
  renaming `PRODUCT_NAME` does not, and is a tag-build-only change. **No Dart
  tier reads a bundle's Info.plist and PR CI compiles no macOS (#69)**, so
  `test/platform/window_title_test.dart` asserts the plist as source text —
  and the value it asserts must be checked against a real
  `flutter build macos` at least once per change.
- `showGbmMenu` is built on Material's `showMenu`, whose modal barrier makes
  a hover-opened flyout unhoverable from its own parent — submenus open on
  tap, and the parent is popped *before* the child's action runs (menu items
  routinely push a dialog). **#87**.
- `RadioListTile` needs a `Material` ancestor; `Container(color:)` builds an
  opaque hit-test box while `Listener` defaults to `deferToChild`;
  `ReorderableDragStartListener` accepts at `kPrecisePointerHitSlop` (**1.0px**
  for a mouse), so a whole-row drag handle loses ordinary clicks.
- `Paint.color` quantises on read-back — compare `.toARGB32()`, or a mismatch
  prints Expected and Actual identically.
- **A `Scrollbar` paints along the edges of *its own* box, so a scroller
  whose box is unbounded puts its thumb where nobody can see it.** The
  Working Copy's horizontal scrollbar sat at y=1428 against a 300px pane,
  because `WorkingCopyDiffPane` put the scroller under a vertical
  `SingleChildScrollView` and the child of one gets unbounded height.
  Scrolling still worked (trackpad pan, Shift+wheel) — what was lost is the
  at-rest 「there is more to the right」 signal, dimension D's
  `material_state_hidden`. `GbmCodeScrollWell` is the fix and its shape is
  the rule: **horizontal scroller outside, vertical inside, and both
  `Scrollbar`s outside both** so each paints against the bounded pane;
  moving either scrollbar inward re-creates the bug on the other axis. Two
  traps come with it. **The ambient `ScrollBehavior` adds its own scrollbars
  on desktop**, wrapped around the *inner* scrollables — the same bug back
  again, and a finder still counts one per axis — so the inner tree needs
  `ScrollConfiguration(scrollbars: false)`. And **`flutter_test` reports
  `TargetPlatform.android` by default**, where Material adds no ambient
  scrollbar at all, so any test about them must set
  `debugDefaultTargetPlatformOverride` (reset it *in the test body* — the
  no-debug-variable-outlived-the-test check runs before tearDowns) or it
  passes with the suppression deleted. This app ships desktop-only, so the
  test default is the one platform that never happens (ledger: soft-warp).
  **It recurs on the other axis wherever a scroller sizes its child**, and
  `GbmCodeHScroll` did: its child `ListView` sits inside
  `SizedBox(width: contentWidth)`, so the ambient *vertical* scrollbar painted
  at `x = contentWidth` — 1025 against a pane ending at 610 — on all five
  read-only file surfaces at once. The fix is the same shape, and it forces
  the composition owner to hold the other axis' controller: `GbmCodeHScroll`
  takes a `required verticalController` with no default and no owned fallback,
  because a null would mean a scrollbar that cannot be dragged, which is worse
  than the bug. **Ask the recurrence question whenever you fix one of these**
  — the two widgets' `ScrollConfiguration` blocks are now byte-identical,
  which is also why a mutation anchored on that block matches twice.
- **`TwoDimensionalScrollView` is not the answer for a surface whose rows
  must stay mounted.** The disqualifier is that it is a *lazy* viewport:
  off-screen children are destroyed unless individually kept alive. Lead with
  that, not with 「core ships only the abstract halves」 — that is a real cost
  but not a disqualifier, and it does not survive the concrete form:
  `package:two_dimensional_scrollables`' `TableView` is a concrete class built
  on the same lazy viewport. **Passing off a cost as a disqualifier is the
  same error as a conformance cell whose evidence is `isActionEnabled()`** —
  a true, checkable fact standing in for the claim that actually needed
  checking. `ScopedDiffView`'s rows each hold the `SelectionListener` that
  reports whether the live selection touches them, which is how `SCOPES`
  row 7's drag-to-stage knows what it framed, so unmounting one silently
  breaks staging across a scroll. Keeping every row alive pays for a custom
  render object and gets a non-lazy list back. When the thing actually
  wanted is 「both axes bounded by the pane」, build that with plain
  scrollers (ledger: soft-warp).
- **A widget that paints over a row to hide something has to know whose
  background it is covering.** `GbmPinnedGutter` holds a line-number gutter at
  the viewport edge while code scrolls under it, so it must be opaque — and
  opaque is right only when the row paints its own full-width background (a
  `DiffLineView` does). A `GbmRow` does not: its hover and selection tints are
  drawn by an *ancestor*, and an opaque strip covers them **at every scroll
  offset including zero**, silently killing hover feedback the way the sidebar
  once did. That case takes `opaque: false` + `GbmPinnedGutterClip`, which
  clips the content in viewport coordinates instead of painting over it. The
  rule lives on `GbmPinnedGutter.opaque`: own full-width background → opaque;
  ancestor-drawn background that must stay visible → clip (ledger: soft-warp).
- **Changing a `GbmSplitPane`'s axis obliges you to decide what happens to its
  stored value**; only ratio mode survives the change, extent mode persists a
  raw pixel number and must be re-keyed. Its fixed pane's end is the explicit
  `fixedPaneEnd`, not implied by the axis.

## Engineering ledger

[docs/ledger.md](docs/ledger.md) holds every round's narrative, moved here
verbatim (the moved block is byte-identical; nothing was reworded, dropped, or
summarised away). Filing rule for a new round: see the top of this file.

**Everything a source comment cites as "CLAUDE.md's Tier 0c note",
"Known gaps", "Tier 6c", "Spec conformance audit" or any other `Tier N` /
round heading is in `docs/ledger.md` now**, under the same heading text. The
comments were left alone rather than rewritten across ~30 files; this
paragraph is the redirect.
