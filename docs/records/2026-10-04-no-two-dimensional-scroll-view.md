# `TwoDimensionalScrollView` was rejected for surfaces whose rows must stay mounted

- **Kind**: history · **Pins**: was `FLU-no-twodimensional-viewport` · **Code**: `GbmCodeHScroll`, `GbmCodeScrollWell` (`gbm_code_hscroll.dart`), `ScopedDiffView`

## Situation
The code surfaces needed both axes bounded by the pane (ledger: soft-warp), which is the textbook case for `TwoDimensionalScrollView`.

## Task
Choose the scrolling structure for `ScopedDiffView` and the read-only code surfaces.

## Action
Rejected: it is a *lazy* viewport — off-screen children are destroyed unless individually kept alive — and `ScopedDiffView`'s rows each hold the `SelectionListener` that tells `SCOPES` row 7's drag-to-stage what it framed, so unmounting one silently breaks staging across a scroll. Keeping every row alive costs a custom render object and returns a non-lazy list. 「Core ships only the abstract halves」 is a real cost but **not** the disqualifier: `package:two_dimensional_scrollables`' `TableView` is concrete and built on the same lazy viewport. Passing off a cost as a disqualifier is the same error as [SPEC-cell-names-capability]. Built instead with plain scrollers.

## Result
`gbm_code_hscroll.dart`'s doc comment carries the same argument at the code site.
