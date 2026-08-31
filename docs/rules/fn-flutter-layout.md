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
