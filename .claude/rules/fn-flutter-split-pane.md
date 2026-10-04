---
paths:
  - "app_flutter/lib/widgets/split_pane.dart"
  - "app_flutter/test/widgets/split_pane*_test.dart"
---

# Flutter: `GbmSplitPane`

Pin prefix `FLU-`. Format: [README.md](../../docs/rules/README.md).

## [FLU-splitpane-axis-change] Changing a `GbmSplitPane`'s axis obliges you to decide what happens to its stored value

- **Rule**: only ratio (flex) mode survives an axis change; extent mode persists a raw pixel number, so re-key it (`wc.diff` → `wc.files`). The fixed pane's end is the explicit `fixedPaneEnd`, not implied by the axis.
- **Evidence**: [record: Working Copy layout](../../docs/records/2026-10-04-working-copy-layout.md)
