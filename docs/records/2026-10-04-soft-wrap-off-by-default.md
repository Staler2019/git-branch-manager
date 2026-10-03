# Soft wrap is an app-level preference, off by default

- **Kind**: ruling · **Pins**: was `STRUCT-soft-wrap-preference` · **Code**: `AppPreferences.softWrapEnabled`

## Situation
Before, nothing was configurable and every file-content surface wrapped unconditionally, because a bare `Text` defaults to `softWrap: true` inside an `Expanded`. The spec has no wrap row anywhere in its 21 pages.

## Task
The user asked for long lines to scroll horizontally instead of wrapping (ledger: soft-warp). A user-requested addition, not a conformance item.

## Action
`AppPreferences.softWrapEnabled` (Preferences → Appearance → 程式碼, G1i; the section header was English "CODE" before that round's Chinese-copy pass) decides how every file-content surface handles a line too wide for its pane. **Off is the shipped default**: the line runs right behind a horizontal scrollbar, with the line-number gutter pinned at the viewport's left edge; on means it wraps.

Surfaces: `DiffLineView`/`DiffPage` (History detail, Compare, file-history and stashes panels all render through `DiffPage`), `SideBySideDiffView` (History's 並排 mode), `ScopedDiffView` (Working Copy), `PanelDiffText` (patches and line-history panels), `BlamePanel`, `ConflictResolveWindow`. The commit-message box is deliberately untouched.

**`SideBySideDiffView` pins neither gutter**: two columns have two gutters, only the left one is at the viewport edge, and freezing it alone desynchronises the pair; the two columns share one scroller so a pair stays aligned. That is the implementer's judgement, **not the user's ruling** — the user's standing position on pinning is the opposite, open on **#119** pending a real-hardware check.

Machinery: `lib/widgets/gbm_code_hscroll.dart` (`GbmCodeHScroll`, `GbmPinnedGutter`, `GbmPinnedGutterClip`) plus `lib/widgets/code_line_metrics.dart`, which measures the widest line with one `TextPainter.layout` and memoises it.

## Result
5,000 lines cost 46ms to measure, so the memo is a correctness requirement, not an optimisation. Pinned by `app_preferences_repository_test.dart` (`softWrapEnabled` is false by default), `test/integration/soft_wrap_preference_flow_test.dart` and the `*_wrap_test.dart` files. Open: #119.
