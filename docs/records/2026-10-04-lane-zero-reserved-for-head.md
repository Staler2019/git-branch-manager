# Lane 0 is reserved for HEAD's branch, even when that leaves it blank above the tip — 照 spec 字面實作

- **Kind**: ruling (user-ratified literal reading of spec) · **Pins**: was `SPEC-lane-zero-is-head` · **Code**: `GraphBuilder.h`'s `GraphOptions::trunkTip`, `LaneAllocator::reserve`, `Session.cpp`'s `includeRefs.empty()` gate

## Situation
P02's〈Graph 連線規則〉opens with 「目前開發中的分支永遠佔 lane 0，且是一條從頭到尾不轉折的直線。其他分支一律往右配置，轉折全部發生在支線那一側，主線不會為了讓路而歪掉。」 `GraphBuilder.h`'s three invariants transcribe it sentence by sentence, and the second invariant had no implementation at all. The conformance matrix never audited it, because its P02 audit unit was the sixteen numbered items, and this prose sits outside them.

## Task
Implement the reservation. Decide what lane 0 shows above HEAD's tip when newer commits exist.

## Action
- **It is a *reservation*, not a race.**
  - `trunkTip` holds lane 0 vacant from before the first row (`LaneAllocator::reserve(0)` in the constructor) and hands it to that oid whenever it arrives.
  - That **includes when it arrives carrying incoming edges**. A fix that only changes `chooseLane()` misses this case: on `main`, with a newer descendant branch, HEAD's tip turns up with a first-parent edge already descending in lane 1, and keeps it.
- **「其他分支一律往右配置」 rules out lending lane 0 out until the tip arrives.**
  - So lane 0 is blank for exactly as many rows as there are commits newer than HEAD's tip.
  - User-ratified: 照 spec 字面實作.
  - History's uncommitted row fills that gap whenever the working copy is dirty.
- **Seed order does not decide lane 0.**
  - Measured under both orderings, all four combinations: the **newest tip** takes the first row, and with it the first lane.
  - Three source comments said otherwise and were corrected.
- **`trunkTip` is passed only when the walk is guaranteed to contain the commit.**
  - `Session.cpp` gates it on `includeRefs.empty()`, checked after stale refs are dropped.
  - A filtered walk need not include HEAD, and a reservation nothing claims leaves a permanently blank column.

## Result
Pinned by `GraphBuilderTest.cpp`:

- the tip takes lane 0
- it does so even with incoming edges
- lane 0 stays blank above the tip
- there is no reservation without `trunkTip`

`HistoryFilterApiTest.AFilterWithoutHeadsTipReservesNoLaneForIt` pins the Session gate: removing the gate turns only that test red, out of 173.

Evidence: [ledger: History 依 commit 時間排序](../ledger/2026-09-01-fix-history-graph-commit-date-order.md).
