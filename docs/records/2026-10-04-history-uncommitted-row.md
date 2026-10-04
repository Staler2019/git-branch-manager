# History pins one uncommitted-changes row above the commit list

- **Kind**: ruling · **Pins**: was `STRUCT-history-uncommitted-row` · **Code**: `CommitGraphView`, `GraphRowPainter`, `workingCopyRowSelectedProvider`

## Situation
No spec entry: the 21 pages have no uncommitted row (searched 未提交 / 虛擬 / uncommitted / 工作區) and `spec_logic.js`'s History mock starts at a real commit. A user-requested addition.

## Task
Show the dirty working copy in History without disturbing anything keyed on row indices.

## Action
- Present only when `workingCopyStatus.entries` is non-empty and no commit search is running. **Not a `ListView` item**: edge lookups, the span index and every selection range are keyed on row indices, and `UnfilteredRowIndices` is an O(1) identity view because those indices *are* row numbers. It costs no history walk, so saving a file updates it on the same frame as the tab badge, without an O(rows) `publish()`.
- Lane 0 ([record: lane-zero-reserved-for-head](2026-10-04-lane-zero-reserved-for-head.md)), a **hollow diamond** at `kGraphLaneInset`, the same 5.0 radius as a commit dot. Hollow is geometric: a filled dot covers edges started at its centre; this shape has no fill, so the connector leaves from the vertex (`centerY + kWorkingCopyDotRadius`) with `kGraphEdgeStrokeWidth` and a round cap. The painter is public so its geometry can be tested. Suppressed under a commit search, as `CommitRowColumnPlan.drawsGraph` already does for lanes.
- **The join to HEAD is two half-lines from one boolean.** The row paints to its own bottom edge (`commit_row.dart` clips the graph column); the other half is `GraphRowPainter.connectsUpToUncommitted` on the topmost painted row, which has no incoming edge — so that half was drawn by nothing and the line stopped half a row short. `CommitGraphView` computes `connectsToHead` once for both ([CULT-single-source-of-truth]). **Not** a synthesised `GraphEdge`: its `childRow` would not exist and it would flow into `edgesSpanning`, the span index and the ASCII reference renderer (`GraphAsciiRenderer.cpp`). Condition: first painted row is HEAD's tip **and** sits in lane 0 — a filtered walk gets no `trunkTip` reservation. Every fixture here had left `refs` at its default, so `head.target` was `''`.
- Selection shares `commitSelectionProvider` under `kWorkingCopySelectionId`; `selectedCommitProvider` reports `null` for it. Plain ↑/↓ (`GbmMoveSelectionIntent`) treats it as index 0; Shift+↑/↓ does not — a range spanning it is not replayable.
- **Selecting it shows a summary, not files** — 使用者裁定 「可選取，但只顯示摘要」. `CommitDetailPanelCore` draws the count and one 「Open in Working Copy」 button (≡ Ctrl/Cmd+2); `ChangedFilesPanelCore` draws a pointer, suppressed by that flag and **not** by an empty `commitFilesProvider` (which still holds the previous commit's files). A second, non-staging list would be [UX-rubric] dimension D's redundant view.
- **05-K has no dialog under this row** — 使用者裁定 「之後有需要再設計」. Cherry-pick, Revert and Reset are 05-E items carrying the right-clicked row's own oid; a claim that they were gated on `selectedCommitProvider` stood for one round and was wrong.
- Selecting it then discarding: `workingCopyRowSelectedProvider` requires the sentinel **and** `pendingChangeCount > 0`, as a pure derivation (not a widget clearing selection — [FLU-never-write-provider-in-build]). A commit search hiding the row is deliberately not part of the condition.

## Result
Tests: `uncommitted_connector_test.dart`, `history_working_copy_row_flow_test.dart`, `commit_detail_panel_test.dart`, `working_copy_row_test.dart`. The 「not a `ListView` item」 constraint has no test and stays as an L1 rule (`.claude/rules/history-graph.md`).
