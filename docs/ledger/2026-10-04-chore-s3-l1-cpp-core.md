# chore/s3-l1-cpp-core — L1 第四片：fn-cpp-core.md 17 條縮為 4 條，補一個 ~Session() 順序測試

## Situation

`.claude/rules/fn-cpp-core.md`：22,894 字元、17 條，`paths: src/**, tests/**, CMakeLists.txt`。多數條目的理由早已寫在程式碼註解裡，量測也已收進 ledger 與 `docs/reports/windows-process-cost.md`。

## Task

照 `memory-steward` 的處置表縮減。使用者裁定兩點：

1. 過時註解照建議在這一片一起修。
2. `CPP-session-dtor-order` 退役之前先**補測試**：「operations 先 drain，pool 才 drain」這個順序原本沒有任何測試守著。

## Action

- **抽查 steward 的發現**，都對得上程式碼：
  - `ProcessRunner.cpp:676` 在 `idleTimeout > 0` 時也會啟動 watchdog，所以舊 Note 說的「timeout 0 沒有 watchdog」已經過時。28 個 timeout-0 指令都設了 `kHangCeiling`。
  - `ProcessRunner.cpp:773` 指向一段不存在的 `detach()` note。
  - 程式碼註解寫「~24」，實際是 28。
  - 兩處註解寫成錯誤路徑 `docs/rules/fn-cpp-core.md`。
- **C1**：`PoolBlockade` 從 `WorkingCopyApiTest.cpp` 原文搬到 `tests/support/PoolBlockade.h`。第一次抽取時把切點切在 lambda 的 `});`，編譯失敗，改從 `git show HEAD:` 重新抽取。這次沒有派 `arch-suggester`，因為是把既有類別搬進既有的 `tests/support/`，沒有要新設計的東西。
- **C2，新測試 `SessionCloseDrainsOperationsBeforeTheReadPool`**：
  - 做法：hook 讓 completion callback 停在 onDone 內、post 之前，並在 `gbm_session_close()` 開始後用 blockade 塞滿 pool，讓 `refreshWorkingCopy()` 的 post 只能排隊。斷言是 close 返回之後不會再收到任何事件。
  - 正確的順序下，連跑 5 次都綠。
  - mutation 1 個：把 `operations_->drain()` 移到 `cancelQueuedAndDrain()` 之後。連跑 3 次，3 次都只有這個測試紅，形式是 SIGSEGV（exit 139），正是這個順序要防的 use-after-free；同檔另外 2 個測試仍是綠。
  - 這個紅是當掉而不是乾淨的斷言失敗，理由寫在測試註解裡。CI 的 `asan-ubsan` preset 不 build capi，所以這個測試不能依賴 ASan，靠的是 blockade 讓順序確定下來。
  - 本機 `build/` 底下的目錄都還指向 repo 的舊路徑，所以改在 scratchpad 重新 configure 一個 capi build。C++ 全套 **699 個測試 100% 通過**。中途有一次背景執行經過 `| tail`，exit code 是 tail 的，那次不算數，已重跑。
- **C3**：修正上面列的過時註解。`detach()` 的 use-after-free 警告寫進 `cancelBlockedIoAndJoin`，第 773 行的引用因此接得上。退役 pin 在程式、測試、records 的引用都改成白話。`spec-conformance-matrix.md` 裡還留著前兩片沒改到的 `GIT-` 引用，也一併改指。clang-format 的差異數在修改前後相同，這一輪沒有新增。
- **C4**：
  - 規則檔縮成 4 條，Windows 那條只留下兩句（POSIX 不要為對稱去改；只有 Windows CI 測得紅），`detach` 那句已經移進程式碼。
  - 引用改指：`drift-open.md` 3 處，`ops-toolchain-ci.md` 1 處。
  - `check-rule-pins.py` 127 條規則、43 個引用，懸空 0。
  - 逐條跑 migration-loss：缺的項目都是程式碼裡換了寫法（例如 `history_->walk(...)`、`gitFromRegistry()`、`hang_forever` 的 `--drip N`），或是行號範圍。沒有接受任何真實遺失。

## Result

- `fn-cpp-core.md` 從 22,894 降到 2,581 字元。
- 一個原本只靠註解守著的解構順序，現在有確定性的測試守住。
- L0 不變，維持 28,705。
- 還超過 6k 的 L1 剩 7 份：drift-open、ops-toolchain-ci、fn-refs-branches、ops-spec-reading、fn-flutter-input、fn-flutter-state、arch-testing-device。
