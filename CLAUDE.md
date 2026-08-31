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
@docs/rules/arch-testing-device.md
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
