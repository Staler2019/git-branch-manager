# chore/s3-l1-flutter-input — L1 第九片：fn-flutter-input.md 13 條縮為 6 條

## Situation

`.claude/rules/fn-flutter-input.md` 有 13,864 字元、13 條，`paths` 是 `app_flutter/**`，碰到任何 Flutter 檔案（包括 `macos/` 和 `test/`）都會整份載入。

## Task

依 `memory-steward` 的處置表縮減。使用者裁定兩件事：

1. 照建議做：留 5 條，退役 8 條。`clear-selection-before-dispatch` 先跑 device mutation 再決定去留。
2. steward 找到 9 處手寫 `InkWell` 沒有 hover 色，選 A：這一片只處理 memory，hover 另開一輪處理（G1：先派 spec-auditor，再給使用者看設計）。

## Action

- **事實核對**：
  - `gbm_theme.dart` 沒有設定 `hoverColor`。
  - `#87` 仍為 OPEN。
  - `_submitTemporary` 的現場註解完整寫明「清除先於 dispatch」。
  - `window_title_test.dart:16-18` 還寫著「PR CI 只編 Linux」，是 #158 漏改的一處。
- **device mutation**：
  - 把 `clearSelection()` 移到 dispatch 之後，在 macOS 跑 `integration_test/stage_lines_flow_test.dart`，結果 **7/7 綠**。
  - 原因是測試按的是按鈕，tap 本身就會先收掉選取；鍵盤路徑（`repositoryStageSelectedLines`）沒有 device 測試。
  - 所以這條沒有任何測試釘住，依事先約定改為第 6 條留在 L1，並寫明這件事。
  - mutation 前後都從 scratchpad 的副本還原檔案。
- **C1，註解**：
  - `window_title_test.dart` 檔頭更正為「flutter-ci 會建置三個 runner，但建置只證明能編譯」。
  - macOS group 前補上「每次修改至少用一次 `flutter build macos` 對照斷言的值」，這句原本只寫在退役的 `FLU-macos-app-name-from-bundle`。
- **C2，規則檔**：
  - 留 6 條，降到 4,706 字元。
  - `paths` 收窄為 `app_flutter/lib/**`。
  - `check-rule-pins.py`：88 條規則，懸空 0。
  - 8 條退役 pin 在其他檔案沒有任何引用。
- **migration-loss**：缺的都是寫法差異，原文都還在：
  - `!_wellFocus.hasFocus`
  - `_systemProvided` 寫在 class 裡
  - 帶型別的函式簽名
  - 檔案路徑寫法不同

## 保存的事實

- gesture arena 的實測：Working Copy 衝突檔案列原本用 `InkWell(onDoubleTap:)` 包住三顆解決按鈕。按 `Take Ours` 後只 pump 一個 frame，什麼都沒有 dispatch（`Expected: <1>, Actual: <0>`）。現在由 `working_copy_view_test.dart` 的 'a button fires on the frame it is pressed' 釘住。

## Result

- `fn-flutter-input.md` 從 13,864 降到 4,706 字元。
- L0 不變，維持 28,705。
- 待辦：9 處手寫 `InkWell` 的 hover（使用者選 A，另開一輪），其中 3 處是列表列：
  - `conflict_resolve_window.dart:1243`
  - `repo_switcher_popover.dart:779`
  - `preferences_dialog.dart:155`
- 還超過 6k 的 L1 剩 3 份：`fn-flutter-state`、`arch-testing-device`、`arch-testing`。
