# Flutter: layout, painting and scrolling

Pin prefix `FLU-`. Format: [README.md](README.md).

## [FLU-finder-proves-existence-not-position] A finder proves existence, never position

- **Consequence**: `TabRow` shipped spanning the whole window, covering the sidebar, and all
  **2039** tests stayed green through the fix — not one asserted where it was.
- **Do**: assert `getRect()` against a *neighbour's* rect (「left edge not before the sidebar's
  right edge」), never against a pixel constant, and never `findsOneWidget` for a layout claim.
- **Consequence**: **one level deeper, the right finder can still resolve to the wrong render
  object.** `find.byType(X)` takes X's first descendant RenderBox, and if that is a
  `RenderTransform` — or any render object whose effect applies to its *children* —
  `localToGlobal` reports the untransformed position, so a pinned widget measures as if it
  never moved and the test goes red while the code is correct. Measure a node *below* the
  transform.
- **Do**: `ClipRect` does not change `getRect` at all, so a clip's geometry can only be
  asserted by asking its `CustomClipper` directly.
- **Evidence**: ledger: Working Copy 重新設計; ledger: soft-warp

## [FLU-renderflex-non-flex-first] `RenderFlex` lays out non-flex children first

- **Rule**: then divides what is left — so a `Flexible` child can never rescue an overflow that
  non-flex children caused.
- **Consequence**: six surfaces overflowed at the app's own default 1280×720 for exactly this.
- **Note**: `Spacer` is itself a flex child and competes for the space it looks like it is
  donating; and `Expanded` satisfies "no overflow" while collapsing its child to zero, so
  assert visibility, not absence of exception.

## [FLU-paint-color-quantises] `Paint.color` quantises on read-back

- **Do**: compare `.toARGB32()`, or a mismatch prints Expected and Actual identically.

## [FLU-scrollbar-paints-its-own-box] A `Scrollbar` paints along the edges of *its own* box

- **Consequence**: a scroller whose box is unbounded puts its thumb where nobody can see it.
  The Working Copy's horizontal scrollbar sat at y=1428 against a 300px pane, because
  `WorkingCopyDiffPane` put the scroller under a vertical `SingleChildScrollView` and the child
  of one gets unbounded height. Scrolling still worked (trackpad pan, Shift+wheel) — what was
  lost is the at-rest 「there is more to the right」 signal, dimension D's `material_state_hidden`.
- **Rule**: `GbmCodeScrollWell`'s shape is the rule — **horizontal scroller outside, vertical
  inside, and both `Scrollbar`s outside both**, so each paints against the bounded pane. Moving
  either scrollbar inward re-creates the bug on the other axis.
- **Do**: **the ambient `ScrollBehavior` adds its own scrollbars on desktop**, wrapped around
  the *inner* scrollables — the same bug back again, and a finder still counts one per axis — so
  the inner tree needs `ScrollConfiguration(scrollbars: false)`.
- **Do**: **`flutter_test` reports `TargetPlatform.android` by default**, where Material adds no
  ambient scrollbar at all, so any test about them must set `debugDefaultTargetPlatformOverride`
  (reset it *in the test body* — the no-debug-variable-outlived-the-test check runs before
  tearDowns) or it passes with the suppression deleted. This app ships desktop-only, so the test
  default is the one platform that never happens.
- **Consequence**: **it recurs on the other axis wherever a scroller sizes its child.**
  `GbmCodeHScroll`'s child `ListView` sits inside `SizedBox(width: contentWidth)`, so the ambient
  *vertical* scrollbar painted at `x = contentWidth` — 1025 against a pane ending at 610 — on all
  five read-only file surfaces at once.
- **Do**: the fix forces the composition owner to hold the other axis' controller —
  `GbmCodeHScroll` takes a `required verticalController` with no default and no owned fallback,
  because a null would mean a scrollbar that cannot be dragged, which is worse than the bug.
- **Do**: **ask the recurrence question whenever you fix one of these.** The two widgets'
  `ScrollConfiguration` blocks are now byte-identical, which is also why a mutation anchored on
  that block matches twice.
- **Evidence**: ledger: soft-warp

## [FLU-no-twodimensional-viewport] `TwoDimensionalScrollView` is not the answer for a surface whose rows must stay mounted

- **Rule**: the disqualifier is that it is a *lazy* viewport — off-screen children are destroyed
  unless individually kept alive.
- **Do not** lead with 「core ships only the abstract halves」: that is a real cost but not a
  disqualifier, and it does not survive the concrete form —
  `package:two_dimensional_scrollables`' `TableView` is a concrete class built on the same lazy
  viewport. **Passing off a cost as a disqualifier is the same error as
  [SPEC-cell-names-capability]**: a true, checkable fact standing in for the claim that actually
  needed checking.
- **Consequence**: `ScopedDiffView`'s rows each hold the `SelectionListener` that reports whether
  the live selection touches them, which is how `SCOPES` row 7's drag-to-stage knows what it
  framed, so unmounting one silently breaks staging across a scroll. Keeping every row alive pays
  for a custom render object and gets a non-lazy list back.
- **Do**: when the thing actually wanted is 「both axes bounded by the pane」, build that with
  plain scrollers.
- **Evidence**: ledger: soft-warp

## [FLU-pinned-gutter-opacity] A widget that paints over a row has to know whose background it is covering

- **Rule**: `GbmPinnedGutter` holds a line-number gutter at the viewport edge while code scrolls
  under it, so it must be opaque — and opaque is right **only when the row paints its own
  full-width background** (a `DiffLineView` does).
- **Consequence**: a `GbmRow` does not — its hover and selection tints are drawn by an
  *ancestor*, and an opaque strip covers them **at every scroll offset including zero**, silently
  killing hover feedback the way the sidebar once did ([FLU-hand-rolled-inkwell-hover]).
- **Do**: that case takes `opaque: false` + `GbmPinnedGutterClip`, which clips the content in
  viewport coordinates instead of painting over it.
- **Rule**: the rule lives on `GbmPinnedGutter.opaque` — own full-width background → opaque;
  ancestor-drawn background that must stay visible → clip.
- **Evidence**: ledger: soft-warp

## [FLU-splitpane-axis-change] Changing a `GbmSplitPane`'s axis obliges you to decide what happens to its stored value

- **Rule**: only ratio mode survives the change; extent mode persists a raw pixel number and must
  be re-keyed.
- **Note**: its fixed pane's end is the explicit `fixedPaneEnd`, not implied by the axis.

## [FLU-splitpane-stored-extent-ignores-min] Raising a splitter's `minExtent` obliges you to clamp what was already stored

- **Rule**: `GbmSplitPane.initState` adopts the persisted value verbatim, and the build-time
  `_clampedFixedExtent()` clamps only the **upper** bound (`.clamp(0, maxFixed)`, deliberately —
  what it protects is the filling side).
- **Consequence**: a user who had dragged the pane to 190 stays at 190 forever after the floor
  is raised to 220. The raise is invisible to everyone who has ever touched that splitter, which
  is exactly the population it was raised for.
- **Do**: clamp **in `initState`**, never in `_clampedFixedExtent()` — the latter runs every
  frame and would force a `collapsedByDefault` drawer (`splitterMainLog`, stored value 0) open to
  `minExtent` on the first frame. Guard the clamp on `stored[0] > 0` so an explicit collapse
  survives.
- **Do**: the test that catches clamping in the wrong place is 「stored 0 stays 0」, not the
  190→220 case, which passes either way.
- **See also**: [FLU-splitpane-axis-change] — the same obligation from the other direction; there
  the stored number stops meaning anything, here it stops being reachable.
- **Evidence**: [ledger: 十二個管理面板照 P19 樣板統一](../ledger/2026-09-02-feat-p19-panel-template-conformance.md)

## [FLU-storage-id-not-tab-id] A per-tab persisted layout key is spelled from the tab's *identity*, never from its id

- **Rule**: `panelStorageId()` (`features/panels/panel_storage_id.dart`) is the one place a
  management panel's `panelLayout.*` key is composed, and its subject suffix is derived from
  `GbmPanelKind.isPerSubject` — the same property `PanelTabsNotifier.open()` dedupes on. So 「can two
  of these exist at once」 and 「does the key tell them apart」 are two faces of one fact instead of
  two decisions someone has to keep in step.
- **Do not** key it on the tab id, however literally 「各自記憶」 reads. A tab id is
  `'${kind.slug}-${_nextId++}'` from an in-memory counter and `PanelTabsNotifier` persists nothing,
  so keying on it loses every stored width across a restart **and collides** — this run's `blame-0`
  is next run's different file inheriting a stranger's width.
- **Consequence**: before this, thirteen ids were hand-written across twelve files with nothing
  checking them for collisions, and two panels sharing one id share one splitter position silently.
  A test named 「a singleton kind keeps its unsuffixed id」 made the nine look like a blessed
  exception rather than the rule applied.
- **Do**: spell the stem from the kind's existing `slug` rather than adding a second naming switch
  beside it — a parallel `storageStem` preserves a few more stored widths and re-creates, in one
  file, the drift being removed from twelve.
- **Note**: re-keying orphans a stored value — a read-miss falling back to the default, never a
  wrong number — which is [FLU-splitpane-axis-change]'s trade-off from a third direction.
- **Evidence**: [ledger: 十二個管理面板照 P19 樣板統一](../ledger/2026-09-02-feat-p19-panel-template-conformance.md)

## [FLU-column-nonflex-unbounded-height] A `Column` hands its non-flex children unbounded max-height, whatever its own bound is

- **Rule**: `RenderFlex` must measure a non-flex child's natural size before it can decide whether
  the sum overflows, so every such child gets `maxHeight: double.infinity` along the main axis —
  this is true even when the `Column` itself sits inside a bounded parent (a `SizedBox`, a bounded
  `Scaffold` body). It is *why* a `Column` can overflow at all.
- **Consequence**: a child that uses `CrossAxisAlignment.stretch` on an inner `Row` throws
  "BoxConstraints forces an infinite height" the moment it is mounted inside a real `Column` — this
  is exactly how `GbmDialogWarnField` broke (see [FLU-row-stretch-needs-intrinsic-height]) the
  moment it left its own isolated widget test and was wired into five real dialog bodies at once.
- **Do**: wrap the stretching `Row` in `IntrinsicHeight` when the ambient context cannot be trusted
  to hand down a bounded height — which for anything living inside a dialog body `Column` is
  always.
- **Evidence**: [ledger: Worktree Dialogs G2–G8](../ledger/2026-09-05-feat-worktree-dialogs-shell-redesign.md)

## [FLU-row-stretch-needs-intrinsic-height] `CrossAxisAlignment.stretch` on a `Row` needs a bounded cross-axis constraint to stretch into

- **Rule**: without one — see [FLU-column-nonflex-unbounded-height] for the commonest source of an
  unbounded one — `Row` tries to hand its children the incoming (infinite) height as a tight
  constraint and the framework throws rather than silently doing nothing.
- **Do**: `IntrinsicHeight` measures the `Row`'s children's own intrinsic height first and hands
  the `Row` a tight, finite constraint derived from that — the fix for "stretch two unequal-height
  children to match" with no ambient bound to stretch into. `GbmDialogWarnField`'s 2px warning
  rail is the worked example.
- **Note**: [TEST-fixture-cannot-disagree] gained a thirteenth shape from this exact bug — G8a's
  own widget test wrapped the component in `Scaffold(body: Center(child: ...))`, and `Center`
  hands its child a *bounded* constraint, so the isolated test could not see a defect that only
  reproduces once the widget is inside a `Column`.
- **Evidence**: [ledger: Worktree Dialogs G2–G8](../ledger/2026-09-05-feat-worktree-dialogs-shell-redesign.md)

## [FLU-border-uniform-color-required] `Border.paint` refuses a `borderRadius` on a non-uniform-colour border

- **Rule**: Flutter throws "A borderRadius can only be given on borders with uniform colors" at
  paint time — not a design choice, an engine constraint — the moment a `BoxDecoration` combines a
  `borderRadius` with a `Border` whose sides differ in colour or width (e.g. three
  `border-subtle` sides plus one thicker, differently-coloured accent side).
- **Do**: split the shape into two legal pieces instead — an outer `Container` carrying the
  *uniform* ring colour plus the `borderRadius` (legal together) with
  `clipBehavior: Clip.antiAlias`, and the differently-coloured edge as a separate solid-colour
  `Container` inside a `Row`/`Column`, clipped to match by the outer container. `GbmDialogWarnField`
  (its 1px `border-subtle` ring plus a 2px `--warning` left rail) is the worked example.
- **Evidence**: [ledger: Worktree Dialogs G2–G8](../ledger/2026-09-05-feat-worktree-dialogs-shell-redesign.md)

## [FLU-inherited-default-scope] An `InheritedWidget` can override a widget's own constructor default without touching every call site

- **Rule**: `GbmButtonSizeScope` (`gbm_button.dart`) is the pattern: the widget's own parameter
  becomes nullable with no hardcoded default (`GbmButtonSize? size`), and resolution at build time
  is `size ?? GbmButtonSizeScope.maybeOf(context)?.size ?? GbmButtonSize.normal` — the `??` chain
  keeps a call site's own explicit value winning over the ambient scope, and the scope's value
  winning over the hardcoded fallback.
- **Consequence**: this is what let `GbmDialogShell`'s action row change all ~34 dialogs' button
  sizes (spec's `.gbm-btn-sm`) by editing 2 files (`gbm_button.dart` +
  `gbm_dialog_shell.dart`) instead of every call site's own `GbmButton(...)` constructor.
- **Do**: reach for this shape whenever a shared container wants to change a descendant widget's
  *default* without asserting authority over every call site's explicit choice — never for a value
  a call site cannot legitimately override.
- **Evidence**: [ledger: Worktree Dialogs G2–G8](../ledger/2026-09-05-feat-worktree-dialogs-shell-redesign.md)

## [FLU-floating-label-overflows-fixed-height] `InputDecoration.labelText`'s floating label does not fit inside a fixed-height box

- **Rule**: Material's floating label needs room *above* the input line. Measured: a
  `TextField` wrapped in `SizedBox(height: 30)` with both `labelText` and a pre-filled
  `controller` renders the label's rect at `y: 14.9–26.1` while the `SizedBox` itself starts
  at `y: 20` — the label paints outside its own box and overlaps the value text's leading
  ~6px. The identical value with no `labelText` (hint-only) renders cleanly inside the same
  box with no overlap.
- **Consequence**: a real pre-filled value reads as garbled or missing, which is exactly
  what shipped: G4b wrapped every single-line dialog field in `SizedBox(height:
  GbmSpacing.inputHeight)` while `gbmInputDecoration()` still took `labelText`, and the user
  reported Add Worktree's 位置 field as having "no default" — the value was there all along,
  visually eaten by its own label.
- **Do**: a dialog field's label is an external `Text` above the box (the G3 pattern already
  used for 分支/來源/從哪裡分出/檔案/還原成), never `InputDecoration.labelText`, whenever the
  field sits inside a fixed-height wrapper. `gbmInputDecoration()`/
  `gbmMultilineInputDecoration()` have no `labelText` parameter at all for this reason —
  removed rather than left unused, so no tenth call site can reintroduce the bug; the
  parameter's absence is a compile error, not a convention to remember.
- **Do not** reach for `floatingLabelBehavior: never` instead — the label would vanish
  entirely the moment the field has content, which is always true for a pre-filled field
  (identity name/email, a configured number, a computed default path).
- **Do**: `errorText` was probed the same way and found *not* to have this defect — it
  renders inside the same fixed box (measured `y: 33–50` against the box's own `20–50`), no
  overflow, no exception — so it was left alone rather than "fixed" for a problem it doesn't have.
- **Do**: pin the fix with a rect assertion (`labelRect.bottom <= fieldRect.top`), never a
  bare `find.text(label)` — [FLU-finder-proves-existence-not-position] applies here exactly:
  existence of the label text proves nothing about whether it overlaps the value.
- **Evidence**: [ledger: Worktree Dialogs G2–G8, 追加](../ledger/2026-09-05-feat-worktree-dialogs-shell-redesign.md)
