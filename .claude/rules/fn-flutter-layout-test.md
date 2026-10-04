---
paths:
  - "app_flutter/test/**"
  - "app_flutter/integration_test/**"
---

# Flutter: asserting layout and paint in tests

Pin prefix `FLU-`. Format: [README.md](../../docs/rules/README.md).

## [FLU-finder-proves-existence-not-position] A finder proves existence, never position

- **Do**: assert layout with `getRect()` against a neighbour's rect, never `findsOneWidget` or a pixel constant. `find.byType(X)` takes X's first RenderBox, so under a `RenderTransform` `localToGlobal` is untransformed (measure a node below it); `ClipRect` does not change `getRect` (ask its `CustomClipper`).
- **Evidence**: `TabRow` once spanned the whole window with all 2039 tests green; ledger: Working Copy 重新設計; ledger: soft-warp

## [FLU-paint-color-quantises] `Paint.color` quantises on read-back

- **Do**: compare `.toARGB32()`, or a mismatch prints Expected and Actual identically.
- **Evidence**: `test/features/sidebar/branch_tree_item_test.dart`'s icon colour assertions
