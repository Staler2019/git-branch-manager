# Graph lane pitch 11 and dot radius 5.0 — user-ratified deviations from spec

- **Kind**: ruling (user-ratified deviation from spec) · **Pins**: was `SPEC-graph-lane-pitch` · **Code**: `tokens.dart`'s `GbmLayout.graphLaneWidth`, `graph_column_painter.dart`'s `kGraphDotRadius` / `kGraphLaneInset`, `graph_column.dart`'s `GbmGraphColumnId`

## Situation
The spec's geometry is `const L0 = 15, L1 = 32, RH = 26` (`spec_logic.js:428` — a file extracted from the spec HTML by `tools/extract_design_spec.py` and gitignored, so a fresh clone does not have it). That is a 17px pitch, which an earlier round corrected a drifted 18 to. The spec's dot is `r: 4.2`.

## Task
The user ruled two changes. First, the lanes should sit at about two thirds of the 17px pitch. Second, after that change, the dot should be larger. The ask was spacing, not a smaller graph.

## Action
- **Pitch 11** (`17 × 2/3`, taken to an integer).
  - The halo, the HEAD ring and the connector keep the spec's 2.0, 7.0+1.5 and 1.75.
  - The pitch and the dot geometry no longer come from one source.
- **Dot 5.0, and not more.**
  - The ring keeps the spec's numbers, so its *inner* edge is 6.25.
  - A dot's visible outer edge is `radius + halo / 2` = 6.0, which leaves 0.25px of background.
  - Any larger, and the ring reads as a thick edge on the dot, **everywhere**, because the ring is painted after the dot.
- **A lane's centre is `kGraphLaneInset` (8 = `ceil(7.75)`, the HEAD ring's outer edge) plus whole pitches.**
  - It is never `laneWidth * (lane + 0.5)`. That form made the ring's room a function of the pitch.
  - At 11, lane 0's centre would sit at 5.5, and `commit_row.dart`'s `ClipRect` cut the ring on the trunk, the lane HEAD sits in most often.
  - With the inset at 8 the margin is 0.25px, so **anything that grows the ring has to move the inset with it**.
- **Three numbers moved with the pitch, and one did not.**
  - `GbmGraphColumnId.graph` went 153/34/425 → 99/22/275. These are lane counts written in pixels; leaving them alone would have redefined the cap from eight lanes to thirteen.
  - The refs corridor's measured ceiling went 287 → 341.
  - `commit_row_narrow_width_test`'s rung fixture went 610 → 552.
  - The refs *floor* of 91 is a chip measurement and does not depend on the pitch.

## Result
Pinned by `gbm_layout_test.dart` (the pitch), `graph_dot_geometry_test.dart` (5.0, the 0.25px arithmetic, the inset, and the ring never clipped), `graph_column_test.dart` (exact lane multiples, the refs floor) and `commit_row_narrow_width_test.dart` (552). The ceiling of 341 is a bisection against `workspace_narrow_window_test.dart`, which goes red once `refs.defaultWidth` passes it.

**Do not "fix" either number back on the strength of the citation.** The citations are still accurate; they no longer decide the numbers.

Evidence: ledger: commit graph 的 lane 間距; ledger: 點放大，以及分支顏色不再撞在一起 (`docs/ledger.md`).
