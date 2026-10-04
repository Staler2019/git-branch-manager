# chore/s3-l1-spec-reading — L1 第八片：ops-spec-reading.md 15 條縮為 10 條

## Situation

`.claude/rules/ops-spec-reading.md` 有 14,071 字元、15 條，paths 涵蓋整個 `app_flutter/lib`、`app_flutter/test`、`src/core/graph` 和 `Session.cpp`。內容混了兩類：「讀 spec 的方法」，以及「graph 幾何與顏色」。後者包含四項使用者裁定的偏離：lane pitch 11、點的半徑 5.0、12 色調色盤、lane 0 保留給 HEAD（照 spec 字面實作）。這四項只記在 ledger 和部分程式註解裡，`docs/records/` 一份都沒有。

## Task

依 `memory-steward` 的處置表縮減。使用者裁定：

1. 照建議做。
2. `Session.cpp` 只在未篩選時設 `trunkTip`，這個閘門採方案 B：補 capi 測試，不寫進 L1。

## Action

- **事實核對**：
  - `gh` 查得 #68、#76、#92～#95 為 OPEN，#60 為 CLOSED。
  - `LaneAllocator.h:161-169` 的顏色間距是分級的（3/2/1/0），規則寫的單一門檻 `min(d, 12 - d) >= kMinColorSeparation` 已經過時。
  - `src/core/graph` 底下沒有任何裁定註解。
  - `trunkTip` 只出現在 `GraphBuilderTest.cpp`。
  - 有 3 處把規則檔路徑寫成 `docs/rules/`。
  - **否決 steward 一項判斷**：它說上限 341「只是記錄的量測、沒有斷言」。`graph_column.dart` 自己的註解寫明，`workspace_narrow_window_test.dart` 在預設寬度超過 341 時會紅，所以上限其實有測試守著。真正過時的是 `graph_column_test.dart` 還寫著「93／92」。
- **C1，test**：
  - `HistoryFilterApiTest.AFilterWithoutHeadsTipReservesNoLaneForIt`：篩選一條不含 HEAD tip 的 `side-one`，最左欄仍有 commit。
  - 測試寫好時就是綠的，因為行為早已存在。
  - mutation：把閘門改成 `if (true)`。173 個 capi 測試只紅這 1 個。原檔從 scratchpad 還原並重新建置。
- **C2，record 與註解**：
  - 新增三份 record：
    - geometry-rulings
    - colour-palette-and-window
    - lane-zero-reserved-for-head
  - 在 `tokens.dart`、`graph_column_painter.dart`、`GraphSnapshot.h`、`GraphBuilder.h` 加上指向 record 的 ruling 註解；後兩處原本完全沒有。
  - `graph_column_test.dart` 的「93／92」更正為 341。
  - 3 處錯誤路徑更正。
  - 2 處引用即將退役 pin 的地方改指向新 record。
  - `gbm_lane_palette_test.dart` 會自己讀 `GraphSnapshot.h`，加了註解後仍然綠，C++ 也重新建置通過。
- **C3，規則檔**：
  - 留 10 條方法類，降到 3,917 字元。
  - paths 移除 C++ 的兩行。
  - `check-rule-pins.py`：95 條規則，懸空 0。
- **migration-loss**：
  - artifact URL 完整寫在 `working-copy-layout-spec.html` 裡。
  - `min(d, 12 - d)` 是刻意拿掉的過時公式。
  - ledger 路徑是假陽性。
  - 沒有真正遺失的事實。

## Result

- `ops-spec-reading.md` 從 14,071 降到 3,917 字元。
- 四項裁定各有 record、現場註解和測試三處保存。
- L0 不變，維持 28,705。
- `docs/rules/README.md:111` 列的檔案大小（167 等）已經過時。這個檔案是 L0，改了要重算預算上限，所以這一片不動，留給使用者決定。
- 還超過 6k 的 L1 剩 4 份：`fn-flutter-input`、`fn-flutter-state`、`arch-testing-device`、`arch-testing`。
