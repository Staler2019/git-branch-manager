# Twelve lane colours, hue-ordered, with a five-column graded window — user-ratified

- **Kind**: ruling (user-ratified deviation from spec) · **Pins**: was `SPEC-lane-palette-twelve`, `SPEC-lane-colour-window` · **Code**: `GraphSnapshot.h`'s `kPaletteSize`, `LaneAllocator.h` (`requiredSeparation`, `penaltyWeight`, `colorDistance`), `tokens.dart`'s `GbmColors.graphLanes`

## Situation
The spec names `--graph-lane-1` .. `--graph-lane-6`. `kPaletteSize` was raised to 12, and `colorForSeed` returns `0 .. 11`. `GbmColors.graphLanes` still shipped with six colours, so the painter's `color % length` folded id 6 onto **0, the trunk's own colour**, and folded 7..11 onto 1..5. Two random branches looked alike 17.4% of the time instead of 9.1%. Nothing linked the C++ `constexpr` to the Dart `.length`. Separately, the user reported two branches in one colour with a single lane between them.

## Task
Twelve colours are a user-ratified deviation. Lane colours must be spread by hue, and the crowding the user reported must stop.

## Action
- **Palette.**
  - Entry `i` sits at `hue(0) + 30 * i` degrees **in OkLCH**.
  - Because of that, the allocator's colour distance is a hue distance, and the core never sees an RGB value.
  - Reorder the list and the core keeps "spreading" a number that means nothing, with no symptom.
  - Assert in OkLCH, not HSL. In HSL the same twelve colours are 12.4° apart in the teal band and 68° apart in the green one, so an HSL assertion misreads an even palette as uneven and passes an uneven one.
  - `gbm_lane_palette_test.dart` **reads `GraphSnapshot.h` itself** rather than copying the 12; a copy is what drifted.
- **Seed.**
  - A ref tip's lane is seeded by the **tip commit** (`GraphBuilder.cpp`'s no-incoming-edges path). So committing on a branch already recoloured it, long before the neighbour rule applied.
  - Keying the colour on the oid keeps it across *lane index reuse*, not across a refresh.
- **Window.**
  - It looks **five columns either side, graded**: a quarter turn from the adjacent column, 60° from the next, and merely a different colour out to five columns (`requiredSeparation` 3 / 2 / 1).
  - `penaltyWeight`'s 100/10/1 stops the tiers being traded against each other: everything below offset 1 sums to at most 46.
  - It was ±1 for one round, defended on two grounds that were both wrong:
    - Widening repaints nothing, because a colour is fixed at seed time.
    - ±1 was thinner than it read. `allocateLeftmost` returns the *lowest free* lane, so on the ref-tip path nothing sits to the right and only the left neighbour could ever fire.
- **Limit.**
  - Beyond the window, repeats stay possible.
  - Past 11 live lanes they are unavoidable: there are 11 non-trunk colours, and `kMaxLanes` is 48.
  - The rule decides *where* a repeat lands, never whether one happens.

## Result
Pinned by `gbm_lane_palette_test.dart` (size read from the header, length per theme, distinct colours, 30° OkLCH steps in index order, lane 0 is the accent) and `GraphBuilderTest.cpp`:

- the quarter turn
- one column between
- an uncrowded lane keeps its hash colour
- the penalty tiers cannot be traded
- the trunk is colour 0
- invariants over a random DAG

Evidence: ledger: 點放大，以及分支顏色不再撞在一起; ledger: 相隔一欄仍然撞色 (`docs/ledger.md`).
