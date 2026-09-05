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
  frame and would force a `collapsedByDefault` drawer (`splitterMainLog`) open to `minExtent` on
  the first frame. The clamp is guarded on `stored[0] > 0` so a stored 0 survives.
- **Do**: the test that catches clamping in the wrong place is 「stored 0 stays 0」, not the
  190→220 case, which passes either way.
- **Correction**: this pin previously read that guard as protecting 「an explicit collapse」 and
  cited `splitterMainLog` as 「stored value 0」. **Neither is true any more**, and the second was
  what made the drawer 使用者回報 as always-open: a `collapsedByDefault` pane now stores a
  *height* and never an open/closed state, so it never writes 0 at all
  ([FLU-collapsed-drawer-stores-height]). The guard survives only for a **non-drawer** extent
  pane, where a 0 could in principle be stored and is not a sub-minimum value to be repaired.
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
- **See also**: this was the **first of three** defects that one fixed-height wrapper caused,
  and fixing it alone left the other two shipping — [FLU-input-paints-its-own-box] (the
  painted outline is shorter than the wrapper) and [FLU-fixed-height-box-excludes-subtext]
  (an error message eats the box). One cause, three symptoms, found one at a time.
- **Evidence**: [ledger: Worktree Dialogs G2–G8, 追加](../ledger/2026-09-05-feat-worktree-dialogs-shell-redesign.md)

## [FLU-input-paints-its-own-box] A `TextField`'s outline is painted by a *child* render box sized by `isDense`, not by the `SizedBox` around it

- **Rule**: `_RenderDecoration` lays the border and fill out as a separate child, tight to
  `containerHeight = min(max(contentHeight, minContainerHeight), maxContainerHeight)`.
  `isDense: true` sets `minContainerHeight` to the **text's own height**; a wrapping
  `SizedBox` only supplies `maxContainerHeight`. So the `min` lands on the text height and
  the painted outline comes out **shorter than the widget it sits in**.
- **Consequence**: measured on a real macOS screenshot, Add Worktree's 位置 box drew at
  **23px beside a 30px `GbmButton`** while `getRect(find.byType(TextField))` reported 30.0
  for both — the wrapper's number, not the painted one.
- **Do**: `isDense: false` is the font-independent fix: the floor becomes
  `kMinInteractiveDimension` (48), so the `min` lands on the wrapper's 30 exactly, whatever
  the font. Tuning `contentPadding` against font metrics is the fix that looks right and
  drifts between the test font and the real one.
- **Do**: it now **depends on the wrapper existing** — with no upper bound the same
  expression yields 48. `gbmInputDecoration`'s callers all wrap; the ref picker's search box
  was the one that did not, and it had to gain one in the same change.
- **Do**: a multiline field keeps `isDense: true`, because it has no fixed-height wrapper for
  the `min` to clamp against and 48 would become a real floor.
- **Do**: the assertion that can disagree measures the **painted** box —
  `find.descendant(of: find.byType(InputDecorator), matching: find.byType(CustomPaint))` —
  and compares it against the neighbour it must match, not against the shared constant
  ([FLU-finder-proves-existence-not-position]).
- **See also**: [FLU-floating-label-overflows-fixed-height] and
  [FLU-fixed-height-box-excludes-subtext] are the same fixed-height wrapper's other two
  casualties; all three arrived in one change and only the first was noticed.
- **Evidence**: [ledger: 追加二](../ledger/2026-09-05-feat-worktree-dialogs-shell-redesign.md)

## [FLU-fixed-height-box-excludes-subtext] A fixed-height wrapper bounds the box *and* its subtext, so `errorText` eats the box

- **Rule**: Material lays `errorText`/`helperText` out below the container, and both are
  inside whatever height the caller imposed. Measured: a field wrapped in
  `SizedBox(height: 30)` with an error painted its outline at **10px**.
- **Consequence**: the field is at its least readable exactly when it is trying to explain
  itself. Three dialogs shipped this (`add_worktree`, `new_branch`, `rename_branch`); nobody
  reported it, because it needs a duplicate branch name to trigger.
- **Do**: the message goes in an external `Text` under the box — the spec's own `.fld__hint`
  shape — and the decoration takes a `hasError` flag that recolours the outline only. This is
  [FLU-floating-label-overflows-fixed-height]'s decision applied to the other side of the box:
  a fixed height fits neither what Material wants to draw above it nor below it.
- **Do**: a test asserting `decoration.errorText` cannot see any of this — that is the model,
  not the paint ([TEST-fixture-cannot-disagree] row 15). Assert the rendered line, and
  identify it by its `danger` colour rather than by its text, so the finder cannot pass by
  matching some other line that says the same thing.
- **Rule**: **a bare `OutlineInputBorder()` is black.** Its default `BorderSide()` is
  `Colors.black` width 1, not the theme's colour — measured `(0,0,0)` against the neighbouring
  button's `#30363D`. Name every state (`border`, `enabledBorder`, `disabledBorder`,
  `focusedBorder`), because a field's *resting* state is whichever one its screen leaves it in
  and Add Worktree's 位置 now rests **disabled**.
- **Evidence**: [ledger: 追加二](../ledger/2026-09-05-feat-worktree-dialogs-shell-redesign.md)

## [FLU-collapsed-drawer-stores-height] A `collapsedByDefault` pane's storage holds its *height*, never its open/closed state

- **Rule**: `GbmSplitterSpec.collapsedByDefault` means the pane starts collapsed on **every**
  launch, not only on a virgin profile. So the persisted number is the height to *reopen to*,
  and `_GbmSplitPaneState.initState` ignores it when deciding the starting state.
- **Consequence**: it used to read `stored == null && collapsedByDefault`, which made the flag
  hold exactly until the first time the pane was opened — an open persists a non-zero extent
  through `_setExtent` → `_persistFlexes`, `stored` is never null again, and the branch is
  unreachable for the rest of that profile's life. The log drawer was 使用者回報 as always
  open, and the round that had just made `View → Log` a real toggle is what let everyone reach
  it ([ACT-intent-layer] dispatch, `GbmActionId.viewLog`).
- **Do**: uphold the other half in `_persistFlexes` — **never write such a pane's 0**. Writing
  it erases the height the user dragged to, and the next open lands on `minExtent` instead of
  where they left off. `_openToMinimum` reads a `_reopenExtent` field for exactly this, because
  `_currentFlexes[0]` is the thing the collapse set to 0.
- **Note**: `_collapse()` is no longer the only producer of that 0 — a drag past the bottom edge
  is the second ([FLU-clamp-loses-drag-overshoot]). It rides the same guard, so this rule is
  unchanged by it.
- **Do**: `_resetToSpecDefault` clears `_reopenExtent` alongside the stored value, or a drawer
  reopened later in the same session comes back at the size the reset was meant to forget.
- **Do**: **a test that pumps a virgin profile cannot see any of this** — the flag is correct
  there, which is why 「starts collapsed and the shortcut expands it」 stayed green throughout.
  The discriminating fixture seeds the storage a *previous open* would have left
  (`panelLayout.main.log: '[200.0]'`, via `pumpWorkspace`'s `initialPrefs`), which is
  [TEST-fixture-cannot-disagree]'s 「cannot express the failing condition」 shape.
- **Note**: no migration is needed for a profile already stuck open — the stored number stays,
  startup ignores it, and the first toggle restores it.
- **See also**: [FLU-splitpane-stored-extent-ignores-min], whose `stored[0] > 0` clamp guard
  now covers only a **non-drawer** extent pane; its 「explicit collapse」 rationale was corrected
  in place by this round.
- **Evidence**: [ledger: 追加五](../ledger/2026-09-05-feat-worktree-dialogs-shell-redesign.md)

## [FLU-clamp-loses-drag-overshoot] A per-step clamp destroys drag overshoot, so 「dragged past the edge」 needs its own accumulator

- **Rule**: `_onDividerDelta` clamps every step to `minExtent` and writes the result back to
  `_currentFlexes[0]`, so once the pane has bottomed out each further step recomputes from that
  same clamped number. `_currentFlexes[0] + delta` therefore never falls far below `minExtent`
  **however far the pointer travels** — it can only ever see one frame's delta, a handful of px.
- **Consequence**: a threshold written against that expression is unreachable in practice and
  looks like a tuning problem. The honest fix is a second number: `_dragRawExtent` accumulates
  the *unclamped* travel, opened on `onDragStart` and cleared on **both** `onDragEnd` and
  `onDragCancel` — a cancelled drag that leaves it non-null sends the next keyboard step down
  the drag path, against a position the pointer left behind.
- **Do**: clamp the accumulator too, per step, with a floor that depends on the gate (0 when the
  pane may collapse, `minExtent` otherwise). Unclamped, dragging 300px below the bottom then
  needs 300px of travel back up before the divider follows the pointer again; and for every pane
  that *cannot* collapse the accumulator becomes byte-for-byte the old expression, so no existing
  drag behaviour moves.
- **Rule**: the collapse gate is `GbmSplitterSpec.collapsedByDefault`, and the reasoning is the
  flag's own meaning — 「starts closed at every launch」 implies an affordance that reopens it
  ([FLU-collapsed-drawer-stores-height]), so a drag-close is recoverable exactly there. A pane
  without one dragged to 0 is hidden with no way back.
- **Do**: **keyboard steps are excluded** (`_dragRawExtent == null`), deliberately: an arrow key
  is a discrete nudge rather than a gesture aimed at the edge, and a drawer already has
  `GbmSplitPaneController.toggle`. So the ask 「拖到底關閉」 is what was built, and no existing
  keyboard behaviour changed.
- **Do**: **the discriminating test drags in many small steps.** One large `moveBy` exceeds the
  clamp gap by itself and goes green with no accumulator at all — the accumulator is precisely
  what many-small-steps tests ([TEST-fixture-cannot-disagree], [TEST-draggable-is-not-a-drop]'s
  gesture recipe).
- **Note**: the height left behind is drag-speed dependent, and deliberately not engineered away.
  A real drag passes through the clamp region, so the last persisted height is `minExtent`; a
  single frame large enough to skip it leaves the previous height. Both are self-consistent, and
  forcing one would need `_reopenExtent` cleared in memory while storage kept the old number —
  which reads deterministic in-session and differs after a restart.
- **Evidence**: [ledger: 追加六](../ledger/2026-09-05-feat-worktree-dialogs-shell-redesign.md)
