# chore/s3-l1-arch-testing — L1 第三片：arch-testing.md 18 條縮為 12 條

## Situation

`.claude/rules/arch-testing.md`：24,623 字元、18 條，碰任何一個 test 檔就會載入。內容多半是寫測試的方法，沒辦法用測試去釘住，最大的一塊是 `TEST-fixture-cannot-disagree` 的 15 列表；約 100 處註解靠編號引用其中的列。

## Task

依 `memory-steward` 處置表縮到 6k 以下，並保住 pin 與 1–15 的編號。使用者裁定「照你建議」：

- dragdevices 退役，兩處引用一起改。
- `SessionCloseCancelsQueuedOperationsInsteadOfDraining` 的時序脆弱問題不補 `DRIFT-`：只記在 ledger `2026-09-28-chore-accept-toolchain-bump.md`，CI 上沒出現過。
- 兩段長測試註解這一片不縮短。

## Action

- **處置**：
  - 留 L1 12 條，全部縮寫。
  - 刪 4 條：fake-session-seam、statusbar-lingers-3s、no-trackpad-pointer-kind 已寫在程式碼註解；callback-hook-outlives-test-body 只有一個測試用到 hook，完整敘事在 ledger。
  - ENCODE 2 條：race-is-falsifiable 由 `CMakePresets.json` 的 tsan/asan preset 與 CI job 守；dragdevices-is-not-a-guard 由 `gbm_code_hscroll_test.dart` 守。
- **否決 steward 一項**：它說 TEST-tiers 的「no separate `integration_test/` device harness」是錯的。原句指的是 `test/integration/` 這一層由同一個 `flutter test` 跑、不另用 device harness，這是對的。新文字把這層意思寫得更直接（「run by the same `flutter test`」）。
- **就地更正兩處過時說法**：
  - 標題「Twelve recorded shapes」，表格實際 15 列。
  - spinner 清單「eight panels」，實際 8 個檔、13 處。改成附一條 grep 指令，不再列清單。
- **與全域重複**：mutation-check 那條與 `~/.claude/CLAUDE.md` 的 G2 及 standing rule 6 重複的部分刪掉，只留 repo 獨有的 `count(old) == 1`。代價是沒有 `~/.claude` 的協作者看不到「自己讀 `-N`、記兩個數字」這兩句。
- **C1**：新增 `docs/records/2026-10-04-fixture-cannot-disagree-shapes.md`，15 列表與各形狀的 Do 原文照搬；逐行比對，缺 0 行。
- **C2**：三處測試註解改指程式碼；`flutter analyze` 0。
- **C3**：
  - 改寫規則檔，第一次量是 6,052 字元；只刪措辭，降到 5,982。
  - `arch-testing-device.md` 的 dragdevices 引用改指 `gbm_code_hscroll.dart`。
  - `check-rule-pins.py` 140 條、62 個引用，懸空 0。
- **migration-loss 檢查**，逐條跑：缺的都是樹裡存在的檔案路徑（hay 只比內容，不比檔名），或在程式碼裡換了寫法：`controller.emit(nextState)` 是 `emit`，`isRefreshing && graph.rows.isEmpty` 在 `commit_graph_view.dart` 寫成巢狀的 `if (graph.rows.isEmpty)` 加 `isRefreshing ?`，`UpdateInstaller._executableName` 在 `update_installer.dart`。沒有接受任何真實遺失。

## Result

- `arch-testing.md` 從 24,623 降到 5,982 字元。只比 6k 少 18 字元，下次加條目要先刪。
- L0 不變，維持 28,705。
- 還超過 6k 的 L1 剩 8 份：fn-cpp-core、drift-open、ops-toolchain-ci、fn-refs-branches、ops-spec-reading、fn-flutter-input、fn-flutter-state、arch-testing-device。
