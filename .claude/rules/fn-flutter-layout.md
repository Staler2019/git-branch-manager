---
paths:
  - "app_flutter/lib/**"
---

# Flutter: layout

Pin prefix `FLU-`. Format: [README.md](../../docs/rules/README.md).

## [FLU-renderflex-non-flex-first] `RenderFlex` lays out non-flex children first

- **Rule**: it divides only what is left, so a `Flexible` cannot rescue an overflow that non-flex children caused; `Spacer` is itself a flex child, and `Expanded` can "fit" by collapsing its child to zero (assert visibility, not absence of exception).
- **Evidence**: six surfaces overflowed at the default 1280×720; ledger: Narrow-window layout
