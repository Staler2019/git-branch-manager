# Reading the spec

Pin prefix `SPEC-`. Format: [README.md](README.md).

The spec HTML is `docs/claude-design-demo/Flutter Desktop Spec (standalone).html`.

## [SPEC-how-column-is-a-requirement] A spec table's `how` column is a requirement, not an illustration

- **Rule**: the cell names the *input*; 「this granularity is reachable」 names a
  *capability*, and a capability is not evidence for an input.
- **Consequence**: `SCOPES` row 6's `how` is 「點 hunk 標頭列」 and the heading was a bare
  `Text` with no gesture; row 7's is 「拖過多行，**或 Shift + ↑ ↓**」 and only the drag
  existed. Every non-drag way of staging a line was missing while the matrix read 符合.
- **Do**: read a row's `how` and its `note` separately — row 6's `note` (right-click Stage
  hunk) conformed all along while its `how` did not.
- **Evidence**: took a user report to surface, twice; the same row had already been
  rewritten once for the same class of error. See [SPEC-cell-names-capability].

## [SPEC-demo-dom-is-the-spec] The style demo is a spec too, and its DOM is the readable part

- **Rule**: fetch `claude.ai/code/artifact/bd3d9fdf-…` ("Diff Scope Studies") with WebFetch
  and read the **HTML**, not only the CSS.
- **Consequence**: the CSS says what a block looks like; only the DOM says **where it goes**,
  which is the half that shipped wrong.
- **Do**: 變體 B's real structure is `.variant-B-temp` nested inside `.variant-B-card`,
  with `.variant-B-card-muted` and `.variant-B-btn-off`; the class names already appear in
  `scoped_diff_view.dart`'s comments.

## [SPEC-mockup-is-not-prose] A mockup shows what the user sees, not who draws it

- **Rule**: a conformance verdict rests on the spec's prose. The prose wins over the picture.
- **Consequence**: reading an illustration as a requirement produced an issue asking for the
  *opposite* of what the spec wanted (#60, closed as not-planned).
- **Evidence**: settled the fetch/prune contradiction — P10's mockup draws `--prune`, its own
  prose says 「標記為 gone（尚未 prune）」, and the prose wins.

## [SPEC-multikeys-has-no-checkbox] P13's `MULTIKEYS` is the branch list's selection model

- **Rule**: 「單擊 ＝ 只選這一項」, Ctrl/Cmd toggles, Shift ranges, Ctrl/Cmd+A, Esc.
  Checkout is a *double* click (`BRANCH_STATES`). There is no checkbox in it.
- **Consequence**: a selection UI that needs a checkbox to be visible is a sign the row is
  missing its selected background, not that the spec wants a box.
- **Evidence**: ledger: Sidebar branch rows

## [SPEC-range-follows-paint-order] A "range" is measured in the order the rows are painted

- **Rule**: not the order the model happens to hold them.
- **Consequence**: the sidebar's tree sorts folders before leaves and each group
  alphabetically, so ref order and render order disagree the moment a folder exists;
  Shift-click and Shift+↑/↓ both spanned the wrong rows until they read a list walked out
  of the built tree.
- **Consequence**: **painted order is per display mode, not per widget.** The Working Copy
  board failed the same clause a second time — `FileListModeSwitcher` builds a tree only in
  tree mode and hands `items` straight to a `ListView` in list mode, the default — so one
  range implementation cannot serve both (C18).
- **Do**: assert with set equality; a `containsAll` assertion cannot see this.

## [SPEC-21-pages-and-revisions] The spec HTML has 21 pages, and P16 revises earlier ones

- **Rule**: `docs/reports/spec-conformance-matrix.md` was written against 12 pages.
  **P16's `REVISIONS` table revises earlier pages**, so check whether a later page overrules
  a verdict written before it.
- **Consequence**: two issues went stale exactly that way.
- **Note**: P16's `REVISIONS` is now fully honoured (its four shortcut rows, #75) and P14's
  `IAMAP` was checked. P13 B, P15 and P17–P21 remain unaudited (**#76**).

## [SPEC-cell-names-capability] A conformance cell whose evidence is a helper proves the gate, never the surface

- **Rule**: the tell is always the same — the cell names a *capability* instead of the widget
  that draws it.
- **Consequence**: P02 item 2 and P07's `Toolbar` row read 符合 off
  `gbm_action_availability.dart` while the toolbar they describe was drawn by nothing;
  Fetch/Pull/Push had only a shortcut and a menu item. Items 11, 12 and 14 fell the same way.
- **Consequence**: **not specific to `isActionEnabled()`** — P03's 「all 7 `SCOPES`
  granularities implemented」 rested on `WorkingCopySelectionState.getCheckState()` and
  `FileTreeNode.getCheckState()`, which exist, are correct, are unit-tested, and which
  **nothing under `lib/` has ever called**. Orphan wiring dressed as evidence.
- **Consequence**: it cuts the other way too — removing the surface leaves the cell looking
  unchanged.
- **Do**: check the row's *title* against the spec's own wording first.
  「三顆同組。Push 為主要樣式。」 describes buttons, and the disabled-during-conflict clause
  hangs off them.
- **Evidence**: feat/p02-action-toolbar; ledger: Working Copy 重新設計

## [SPEC-correct-the-issue-in-place] When an issue's premise does not survive the source, correct it in place

- **Rule**: correct the issue text and record the evidence; close as not-planned rather than
  quietly retitle (#45/#50/#51/#60 precedent).
- **Consequence**: several rounds found the premise wrong in a way that moved the work; that
  correction is the most valuable thing the ledger carries.

## [SPEC-absent-not-faked] Where a spec row cannot be honoured, the feature is absent and recorded

- **Rule**: never faked. Conversely, working capi with no spec entry point **stays** rather
  than being orphaned (**#92**–**#95**).

## [SPEC-graph-lane-pitch] The lane pitch is 11 while the dot geometry is still spec's

- **Rule**: user-ratified — the two stopped coming from one source. `spec_logic.js:428`'s
  `L0 = 15, L1 = 32` is a 17px pitch (an earlier round corrected a drifted 18 to it); the
  user then ruled the lanes should sit at about two thirds of that. So
  `GbmLayout.graphLaneWidth` is **11** while the halo, HEAD ring and connector in
  `graph_column_painter.dart` keep spec's 2.0 / 7.0+1.5 / 1.75 untouched — that ask was
  spacing, not a smaller graph.
- **Rule**: the dot alone went 4.2 → **5.0** on a second ruling, and 5.0 is not a taste.
  The ring keeps spec's numbers, so its *inner* edge is 6.25 and a dot's visible outer edge
  is `radius + halo / 2` = 6.0 — leaving 0.25px of background. Past it the ring reads as a
  thick edge on the dot, **with no exception anywhere**, because the ring is painted after
  the dot. Only `graph_dot_geometry_test.dart`'s arithmetic sees it.
- **Do**: a lane's centre is `kGraphLaneInset` (8 = `ceil(7.75)`, the HEAD ring's outer edge)
  plus whole pitches — **never** `laneWidth * (lane + 0.5)`, which made the ring's room a
  function of the pitch. At 11 that left lane 0's centre at 5.5 and `commit_row.dart`'s
  `ClipRect` cut the ring on the trunk, the lane HEAD sits in most often.
- **Do**: margin at 8 is 0.25px, so **anything that grows the ring has to move the inset
  with it**.
- **Do**: three numbers move with the pitch and one does not —
  `GbmGraphColumnId.graph`'s 153/34/425 → 99/22/275 (lane counts written in pixels; leaving
  them would have redefined the cap from eight lanes to thirteen), the refs corridor's
  measured ceiling 287 → 341, and `commit_row_narrow_width_test`'s rung fixture 610 → 552.
  The refs *floor* 91 is a chip measurement and is pitch-independent.
- **Do not** "fix" either number back on the citation's authority; the citations are still
  true and no longer decide the numbers.
- **Evidence**: ledger: commit graph 的 lane 間距; ledger: 點放大，以及分支顏色不再撞在一起

## [SPEC-lane-palette-twelve] The lane palette has twelve colours, and their order is a contract

- **Rule**: `GraphSnapshot.h`'s `kPaletteSize` is 12 and `colorForSeed` returns `0 .. 11`.
  Twelve is a user-ratified deviation — spec names `--graph-lane-1` .. `--graph-lane-6`.
- **Consequence**: `GbmColors.graphLanes` shipped with six, so the painter's `color % length`
  folded id 6 onto **0, the trunk's own colour**, and 7..11 onto 1..5 — two random branches
  looked alike 17.4% of the time instead of 9.1%, silently, because nothing linked a C++
  `constexpr` to a Dart `.length`.
- **Rule**: entry `i` sits at `hue(0) + 30 * i` degrees **in OkLCH**, so `LaneAllocator`'s
  `min(d, 12 - d) >= kMinColorSeparation` is a hue distance without the core ever seeing an
  RGB value. Reorder the list and the core keeps "spreading" a number that means nothing,
  with no symptom.
- **Do**: assert in **OkLCH, not HSL** — the same twelve colours are 12.4° apart in HSL's
  teal band and 68° in its green one, so an HSL assertion misreads an even palette as uneven
  and passes an uneven one.
- **Do**: `gbm_lane_palette_test.dart` **reads `GraphSnapshot.h` itself** rather than copying
  the 12; a copy is what drifted.
- **Evidence**: ledger: 點放大，以及分支顏色不再撞在一起

## [SPEC-lane-colour-window] A lane's colour is the hash of its seed oid, repaired only when it crowds a neighbour

- **Rule**: the seed of a ref tip's lane is the **tip commit** (`GraphBuilder.cpp`'s
  no-incoming-edges path), so committing on a branch already recoloured it long before the
  neighbour rule. Oid-keying keeps a colour across *lane index reuse*, not across a refresh —
  `LaneAllocator`'s comment used to claim the wider thing.
- **Rule**: the window is **five columns either side, graded** — a quarter turn from the
  column beside you, 60° from the one after that, merely a different colour out to five.
  `penaltyWeight`'s 100/10/1 stops the tiers being traded against each other (everything
  below offset 1 sums to at most 46).
- **Consequence**: it was ±1 for one round, defended on two grounds that were both wrong.
  Widening repaints nothing, because a colour is fixed at seed time and never revisited; and
  ±1 was thinner than it read, since `allocateLeftmost` returns the *lowest free* lane, so on
  the ref-tip path there is nothing to the right by construction and only the left neighbour
  could ever fire. What actually broke was the user's own case — two branches in one colour
  with a single lane between them.
- **Consequence**: beyond the window repeats stay possible, and past 11 live lanes they are
  unavoidable — the palette has 11 non-trunk colours and `kMaxLanes` is 48. The rule decides
  *where* a repeat lands, never whether.
- **Evidence**: ledger: 相隔一欄仍然撞色

## [SPEC-titlebar-is-ambiguous] 標題列 means four different things across this spec

- **Do**: settle the reading before moving code (**#68**).
