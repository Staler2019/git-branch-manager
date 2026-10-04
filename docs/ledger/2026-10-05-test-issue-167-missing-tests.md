# test/issue-167-missing-tests — #167 的三個缺測試：一個補上，兩個的前提量不出來

## Situation

#167 列出 L1 整理時 mutation 跑完仍全綠的三處：

1. `_submitTemporary` 的 `clearSelection()` 必須早於 stage 的 dispatch（鍵盤路徑），`[FLU-clear-selection-before-dispatch]`。
2. 看門狗 isolate 必須 `exit(0)`。
3. diff 區 `onPointerDown` 的 focus guard：`if (!_wellFocus.hasFocus) _wellFocus.requestFocus();`。

## Task

各補一支測試，套用對應 mutation 時要紅、而且只紅它。第 3 項 widget tier 表達不出來時改用 device tier。

## Action

- **看門狗（第 2 項）**：
  - 先把 entry point 移到只依賴 `dart:io` 的 `update_watchdog.dart`（`de897b5`），讓純 `dart` 子行程載得動。
  - 測試開獨立 `dart` 行程，spawn 看門狗（200 ms），主 isolate 同步 `sleep` 30 秒，斷言 exit code 0 且 20 秒內結束（`7ee0a7f`）。
  - mutation：拿掉 `exit(0)`，全套紅 2 個。一個是這支測試；另一個是當時樹上一支未完成的第 3 項草稿，它在 clean 上也紅，與 mutation 無關，之後已刪除。
- **focus guard（第 3 項），widget tier**：
  - Shift+click 延伸選取：clean 就不會延伸，因此無法作為測試。
  - 拖曳後按住一次性卡片的按鈕跨一個 frame：clean 綠，mutation 也綠。按鈕的 tap 早於 Listener 的 pointer-up，選取被清掉也來不及影響它。
  - `SelectableRegion._handleFocusChanged` 只有在 `lifecycleState == resumed` 時才清除選取，widget test 的 binding 沒有 lifecycle state。手動設成 `resumed` 之後，「第二次拖曳」的 clean 與 mutation 輸出逐字相同（兩者都是 `Stage 2 lines (1 changed)`、focus 在 `SelectableRegion`）。
  - 依 issue 的驗收改走 device tier。
- **device tier，新增兩支**（`stage_lines_flow_test.dart`）：
  - 鍵盤路徑：拖選 `INSERTED_TWO`，按 Cmd+Alt+S，以 `git diff --cached` 斷言只 stage 那一行。這條路徑原本在 device tier 完全沒有測試。
  - 第二次拖曳取代第一次的選取，再按卡片按鈕 stage。
  - 第一次 clean 跑時鍵盤那支是紅的。探針結果：拖曳 helper 的兩次 `pump` 結束時，`temporaryScopeSubmitProvider` 已經是 closure，但 `WorkspaceActionShortcuts.handlers[repositoryStageSelectedLines]` 仍是 `null`，`hasScheduledFrame == true`；再多一個 `pump()` 就變成 closure。這是 submitter 在 post-frame 才登記所造成的一個 frame 落差，不是產品缺陷（過程中一度向使用者說成「真 bug」，已在對話中更正）。測試在按鍵前改為 `pumpAndSettle()`。
  - clean：9/9 綠。
- **device mutation**（每次都從 scratchpad 備份還原，`git diff --stat` 確認是 1 行變更）：

  | mutation | 結果 |
  |---|---|
  | C2：focus guard 拿掉，每次 pointer down 都 `requestFocus()` | 9/9 綠 |
  | C3a：`clearSelection()` 同步移到 dispatch 之後 | 9/9 綠 |
  | C3b：改回修正前的形狀，dispatch 之後 `_dropSelection(alsoClearHighlight: true)`（post-frame 清除） | 9/9 綠 |

- **歷史對照**（使用者選「先量再決定」）：
  - 在 scratchpad 開 worktree，checkout 到修掉當機的 commit `45ebc2f`（2026-08-26）。`45ebc2f^` 的 `_submitTemporary` 正是 C3b 的形狀。
  - 該 commit 自己的 `stage_lines_flow_test.dart`：control 6/6 綠；C3b 形狀 6/6 綠；log 裡 `ConcurrentModificationError` 0 次。
  - SDK 為 Flutter 3.47.4（2026-09-10）。`MultiSelectableSelectionContainerDelegate.handleClearSelection` 仍直接迭代 `selectables`，原理上的危險還在。
  - 量完已移除 worktree。

## Result

- 第 2 項：已補，mutation 紅得精準。
- 第 1、3 項：在目前的 SDK 與這台機器上，**連修正當時的 commit 都重現不了原本的當機**。只靠現有的 device harness，無法區分「危險已休眠」和「harness 看不見」，因此兩處防護都沒有測試能釘住。
- 使用者裁定：兩支 device 測試都保留。鍵盤那支補上原本沒有的覆蓋；第二次拖曳那支當作「取代選取」的一般行為覆蓋。兩支的註解都寫明不釘這兩處防護。
- 程式碼不變，兩處防護照留：
  - `handleClearSelection` 仍直接迭代 `selectables`，所以清除順序保留。
  - focus guard 的成本只是一次比較。
- 兩處現場註解補上量測結果。`[FLU-clear-selection-before-dispatch]` 的 Note 就地更正：舊說法「tap 本身先收掉選取，所以按鈕路徑看不見」被鍵盤路徑也全綠推翻，已劃掉重寫。
- #167 第 2 項已關閉。第 1、3 項的結論是「目前重現不了」，不是「已有測試釘住」。
