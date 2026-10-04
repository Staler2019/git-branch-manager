---
paths:
  - "app_flutter/lib/**"
  - "app_flutter/test/**"
  - "docs/claude-design-demo/**"
  - "docs/reports/**"
---

# Reading the spec

Pin prefix `SPEC-`. Format: [README.md](../../docs/rules/README.md).

The spec HTML is `docs/claude-design-demo/Flutter Desktop Spec (standalone).html`. Graph
geometry and colour rulings (pitch 11, dot 5.0, twelve colours, lane 0) are records:
`docs/records/2026-10-04-graph-*.md` and `…-lane-zero-reserved-for-head.md`.

## [SPEC-how-column-is-a-requirement] A spec table's `how` column is a requirement, not an illustration

- **Rule**: the cell names the *input*; 「this granularity is reachable」 is a capability, and a capability is not evidence for an input.
- **Do**: read a row's `how` and its `note` separately; one can conform while the other does not (`SCOPES` rows 6 and 7, [SPEC-cell-names-capability]).

## [SPEC-demo-dom-is-the-spec] The style demo is a spec too, and its DOM is the readable part

- **Rule**: fetch the "Diff Scope Studies" artifact (URL in `working-copy-layout-spec.html`) with WebFetch and read the **HTML**, not only the CSS.
- **Consequence**: the CSS says what a block looks like; only the DOM says **where it goes**, which is the half that shipped wrong.

## [SPEC-mockup-is-not-prose] A mockup shows what the user sees, not who draws it

- **Rule**: a conformance verdict rests on the spec's prose; the prose wins over the picture.
- **Consequence**: reading an illustration as a requirement produced an issue asking for the *opposite* (#60, closed not-planned); P10's mockup draws `--prune`, its prose says 「標記為 gone（尚未 prune）」.

## [SPEC-range-follows-paint-order] A "range" is measured in the order the rows are painted

- **Rule**: not the model's order, and it recurs **per display mode and per ordering rule, not per widget**: the sidebar tree, the Working Copy list vs tree mode, and the merged diff list each failed it.
- **Do**: build the painted order once and derive the range from it (`scoped_diff_view.dart`'s `_orderedBlocks`); assert with set equality, never `containsAll`.

## [SPEC-21-pages-and-revisions] The spec HTML has 21 pages, and P16 revises earlier ones

- **Rule**: a later page can overrule a verdict written before it; check P16's `REVISIONS` before trusting an old matrix row.
- **Evidence**: per-page audit status is `docs/reports/spec-conformance-matrix.md`'s banner and #76, not this file.

## [SPEC-cell-names-capability] A conformance cell whose evidence is a helper proves the gate, never the surface

- **Rule**: the tell is a cell that names a *capability* instead of the widget that draws it (P02 item 2 read 符合 off `isActionEnabled()` while no toolbar existed).
- **Do**: check the row's *title* against the spec's own wording first, then grep for a caller under `lib/` ([CULT-orphan-wiring]).

## [SPEC-correct-the-issue-in-place] When an issue's premise does not survive the source, correct it in place

- **Rule**: correct the issue text and record the evidence; close as not-planned rather than quietly retitle (#45/#50/#51/#60 precedent).

## [SPEC-absent-not-faked] Where a spec row cannot be honoured, the feature is absent and recorded

- **Rule**: never faked; working capi with no spec entry point **stays** rather than being orphaned (**#92**–**#95**).

## [SPEC-titlebar-is-ambiguous] 標題列 means four different things across this spec

- **Do**: settle the reading before moving code (**#68**).

## [SPEC-audit-unit-is-not-the-page] A conformance section's heading names its audit unit, and prose outside that unit was never read

- **Rule**: a heading like 「Page 02 — History (16 numbered items)」 is a scope declaration; the page's prose blocks outside it (P02's 〈Graph 連線規則〉, P19's six 樣板規則) were never audited.
- **Do**: ask what the page holds outside the heading's unit; this is [SPEC-cell-names-capability] one level up: there the cell's evidence was wrong, here there is no cell.
