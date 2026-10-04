# chore/s3-l1-testing — L1 最後一片：兩份 TEST- 規則降到預算內，L1 全數過關

## Situation

最後兩份超出預算的 L1 都是 `TEST-` 前綴，而且互相引用，所以合成一片處理：

- `arch-testing-device.md`：10,178 字元，11 條。
- `arch-testing.md`：6,617 字元，13 條。上一片把它降到 5,982 之後，flutter-upgrade 那一輪新增了 `[TEST-golden-no-glyphs]`，又超過預算。

## Task

依 `memory-steward` 的處置表縮減。凡是以「已有測試守住」為由刪除的條目，都先跑 mutation 驗證。

使用者裁定：

1. 照建議處理。
2. golden 那一條選 B：寫一個原始碼掃描測試守住它，然後刪除規則。

## Action

- **M1（device，macOS）**：把 `build/native/libgbm_capi.dylib` 換成空檔後跑 `rename_branch_flow_test.dart`，結果 2/2 綠。app bundle 裡的 dylib 時間戳記是本次執行時間，證實每次 run 都由 Xcode 的「Build gbm_capi」階段重編，實際載入的是 `native_library.dart` 的 candidate #2，不會讀 `build/native`。
  - 結論：`[TEST-stale-dylib-is-silent]` 在 macOS device run 上已不成立。
  - README、harness 和三個 device 測試裡的對應說法都已更正。
  - 跑完從 scratchpad 的備份還原 dylib，並以 `cmp` 確認還原正確。
  - Linux 和 Windows 沒有實測，README 只寫 macOS 的量測結果。
- **M2**：把 rebase 的 FFI 參數型別改成 `Int64`。全套只紅 parity 測試 1 個，`[TEST-ffi-matches-symbol-only]` 的「型別已由 unit tier 守住」屬實。
- **M3**：空欄位不再包 `DragTarget`。全套紅 2 個，都在 `working_copy_board_test.dart`，`[TEST-draggable-is-not-a-drop]` 可以刪除。
- **C1，test**：在 `gbm_widgets_golden_test.dart` 新增不受平台限制的掃描測試：只要檔案含 `matchesGoldenFile`，非註解行就不得出現 `Icons.`。
  - 刻意放在既有的 golden 檔裡，不另開新檔。
  - M4：在 GbmIconButton golden 裡加入 `Icon(Icons.add)`，全套紅 4 個：掃描測試本身，以及 3 個 golden 的像素差。golden 只在 macOS 跑，所以在 Linux 和 Windows 上只有掃描測試抓得到。
- **C2，註解**：
  - 更正 dylib 載入路徑。
  - golden 檔頭原本寫「CI 跑 Ubuntu 會跳過」，已更正。
  - status_bar_cancel 測試原本說 spinner 來自 TopBar（不存在），改為 CommitGraphView。
  - README 中懸空的 CLAUDE.md 指向修掉，prefs 清單補齊。
  - 7 處引用退役 pin 的地方改成白話。
- **C3，規則檔**：
  - device 檔：4,083 字元，6 條。
  - arch-testing：5,745 字元，10 條。
  - spinner 規則補上 `welcome_screen.dart` 那個沒有 `value:` 的 `LinearProgressIndicator`；原本的 grep 只找 `Circular`，漏掉它。
  - `check-rule-pins.py`：75 條規則，懸空 0。
- **migration-loss**：剩下的缺項都是寫法差異：
  - 刻意改寫的 grep 指令
  - `strings` 範例的措辭
  - ledger 路徑

## Result

- measure.py 判定 OK：所有 L1 檔都在 6,000 字元以內。
- L0 不變，維持 28,705。
- 這一片新增一個掃描測試；四個 mutation 的結果都記在上面。
