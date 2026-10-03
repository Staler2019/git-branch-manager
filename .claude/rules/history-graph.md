---
paths:
  - "app_flutter/lib/features/history_graph/**"
  - "app_flutter/test/features/history_graph/**"
---

# History graph

Pin prefix `STRUCT-`. Format: [README.md](../../docs/rules/README.md).

## [STRUCT-history-uncommitted-row] The uncommitted-changes row is pinned above the list, never a `ListView` item

- **Rule**: edge lookups, the span index and every selection range are keyed on row indices, and `UnfilteredRowIndices` is an O(1) identity view because those indices *are* row numbers — prepending a row shifts all of it.
- **Do**: its join to HEAD is two half-lines from one `connectsToHead` boolean computed once in `CommitGraphView`; never a synthesised `GraphEdge`.
- **Evidence**: [record: history-uncommitted-row](../../docs/records/2026-10-04-history-uncommitted-row.md)
