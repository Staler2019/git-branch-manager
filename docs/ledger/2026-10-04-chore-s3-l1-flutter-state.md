# chore/s3-l1-flutter-state — L1 第十片：fn-flutter-state.md 9 條縮為 4 條，補兩個測試

## Situation

`.claude/rules/fn-flutter-state.md` 有 11,746 字元、9 條，`paths` 設為 `app_flutter/**`。上一片「有測試守住」的判斷，跑了 mutation 才發現是錯的；所以這一片凡是要以「已有測試守住」為由刪除的條目，都先實際跑 mutation 再交給使用者裁定。

## Task

依 `memory-steward` 的處置表縮減。steward 為每條列出了驗證用的 mutation。使用者裁定：

- 照建議處理。
- 7 個沒有測試守住的地方，這一片補上測試（方案 B）。
- 另外開 issue 列出仍缺的測試。

## Action

- **第一輪 mutation**：17 個，每個都跑全套 Flutter 測試，跑完從 scratchpad 的副本還原。
  - 守住的 10 個：
    | mutation | 內容 | 紅 |
    |---|---|---|
    | M1 | credential dispose 改用 `ref.read` | 7 |
    | M2 | `_pruneSelection` 在 build 裡直接寫 | 4 |
    | M3 | record 加 `gonePendingRefs` | 1 |
    | M4a | 拿掉 `upToDate` | 2 |
    | M4b | 拿掉 checking 條件 | 1 |
    | M5a | 只看路徑是否存在就保留 | 4 |
    | M5b | 拿掉 mtime | 1 |
    | M5c | 拿掉 0/0 判斷 | 1 |
    | M5d | 上限改為 5 | 1 |
    | M7 | `ref.watch` 改為 `ref.read` | 1 |
  - 沒守住的 7 個（全套都綠）：指紋拿掉 `untrackedSize`、`isSubmodule`、`worktreeStatus`、`indexStatus`、`unstagedRemoved`、`oldPath` 各一，以及從 `app.dart` 拿掉 `AppExitSessionCleanup`（orphan wiring 的形狀）。
- **C1，test**：新增 'every fingerprint field invalidates its own side'。
  - 每個欄位一例，只改那一個欄位，並斷言另一側仍保留。另外補上 `stagedRemoved`、`similarity` 兩欄。
  - 測試寫好時就是綠的。重跑 8 個欄位的 mutation，全套 3,160 個測試裡，每個 mutation 都只紅對應的那 1 個。
- **C2，test**：在 `app_auto_update_check_test.dart` 加入 `AppExitSessionCleanup` 的 `findsOneWidget`。重跑 M6，只紅這 1 個。
- **C3，註解**：
  - `workspace_screen.dart` 的「nine」更正為 ten：實際 select 十個欄位，`workspace_meta_cache_rebuild_test.dart` 也寫 ten。
  - 4 處引用即將退役的 pin，改指向 `_pruneSelection` 與 `updateWatchdogEntryPoint`。
- **C4，規則檔**：
  - 留 4 條，降到 2,782 字元，`paths` 收窄為 `app_flutter/lib/**`。
  - `check-rule-pins.py`：83 條規則，懸空 0。
- **migration-loss**：
  - `_selectedSides` 等名稱在程式碼中都還在，屬於寫法差異。
  - 有兩個框架事實沒有落腳處，保存在下方。

## 保存的事實

- **macOS 不需要改原生碼**：`AppDelegate.swift` 本來就繼承 `FlutterAppDelegate`，Flutter 內建的 `applicationShouldTerminate:` 會轉成 Dart 的 `onExitRequested`。
- **退出流程**：`WidgetsBinding.handleRequestAppExit()` 會分派給所有 `WidgetsBindingObserver.didRequestAppExit()`，`AppLifecycleListener` 是其中一個 observer。所以測試用 `tester.binding.handleRequestAppExit()` 走的就是真實的分派路徑。

## Result

- `fn-flutter-state.md` 從 11,746 降到 2,782 字元。
- 原本 7 個沒有測試守住的地方都補上了，每個都經 mutation 驗證會紅，而且只紅新加的那個測試。
- **開 issue 前先驗證兩個疑似缺口**：
  - 拿掉 `updateWatchdogEntryPoint` 的 `exit(0)`：全套 3,161 個測試都綠。
  - 拿掉 `scoped_diff_view.dart` 的 `if (!_wellFocus.hasFocus)` guard：全套都綠。
  - 這兩個缺口和第九片 device mutation 證實的 clear-selection 鍵盤路徑，一起列入使用者要求開的 issue。
- L0 不變，維持 28,705。
- 還超過 6k 的 L1 剩 2 份：`arch-testing-device`、`arch-testing`。
