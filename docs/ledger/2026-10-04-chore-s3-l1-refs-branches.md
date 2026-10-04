# chore/s3-l1-refs-branches — L1 第七片：fn-refs-branches.md 13 條縮為 1 條

## Situation

`.claude/rules/fn-refs-branches.md` 有 15,361 字元、13 條，paths 涵蓋 sidebar、五個 dialog 目錄與 C++ 的 RefStore／BranchOps／RemoteOps，讀到其中任何一個檔就整份載入。裡面有三項使用者裁定的偏離：HEAD 在側邊欄不置頂、fetch 後自動 prune、History 保留 `origin/HEAD` chip。

## Task

依 `memory-steward` 的處置表縮減。使用者裁定：

1. 「照建議」：
   - 退役 10 條。
   - HEAD 裁定移到 record。
   - 只在 L1 留 `REF-fetch-auto-prunes`。
2. chip 裁定採 B：先補測試釘住，再退出 L1。
3. 「然後修」：steward 順帶發現的錯誤 fixture 這一片一起修。

## Action

- **事實核對**：
  - steward 列的符號都還在。
  - 三項裁定在現場都已引用原話：`branch_tree_builder.dart`、`repo_session_repository.dart`、`branch_context_menu_test.dart`。
  - steward 提議把 pin 改名為 `REF-origin-head-chip-stays`，不採用，因為 `docs/rules/README.md` 規定 pin 一經寫下就不改名。
- **C1，test**：
  - `graph_ref_chips_test.dart` 新增 `origin/HEAD` group：symref 遠端 ref 仍然有自己的 chip，同一列 local 分支的雲朵合併不受影響。
  - `graph_ref_chips.dart` 加上裁定註解。
  - 這個測試一寫好就是綠的，因為行為早已存在；紅燈要靠 mutation 看。在 chip 迴圈加上 `isSymbolic` 過濾：1 個變異，只紅這 1 個測試。
- **C2，fixture**：
  - steward 報 7 處 `isSymbolic: isHead`，實際掃到 29 處：還有 22 處 `isSymbolic: true` 標在普通分支上。全部改成 `false`，兩個真正的 `origin/HEAD` fixture 保留。
  - 這屬於 TEST-fixture-cannot-disagree 第 9 種：手動設了正式程式從來不設的欄位。
  - 全套 `flutter test` 3,002 個全綠。
  - 做了兩個 mutation（`isHead` 改讀 `isSymbolic`）：
    - `branch_tree_builder.dart:220`：新舊 fixture 都綠，這條路徑沒被走到。
    - `branch_tree_item.dart` 的 `selected`：新舊 fixture 都只紅 `branch_tree_item_row_chrome_test.dart` 的同一個測試。
  - 結論：這次修正消除了 fixture 與正式程式的矛盾，但量不出偵測能力有提升，照實記錄。
- **C3，record 與註解**：
  - 新增 `docs/records/2026-10-04-sidebar-head-has-no-privilege.md`，六處「see docs/ledger.md」改指向它。
  - 四處引用退役 pin 的註解改成白話。
  - `gone_marking.dart` 的第三階段原本寫成「明確按 Prune」，改寫為 fetch 自動 prune、手動 Prune 為備援。
- **C4，規則檔**：
  - 只留 `REF-fetch-auto-prunes`，paths 從 13 個 glob 收窄為 2 個。
  - `check-rule-pins.py`：100 條規則，懸空 0。
- **migration-loss**：逐條跑。
  - `fields.size() > N` 與 `DeferredPruneNotifier._dispatched` 在原始碼裡就有，屬於寫法不同的假陽性。
  - 唯一真正會遺失的是 remote-name 那條當初的症狀，保存在下方「保存的事實」。

## 保存的事實

- `feature/x` 追蹤 `origin/renamed-x` 時，對話框寫「Also delete renamed-x」，實際卻執行 `git push origin --delete feature/x`：顯示的是 upstream 的分支名，送出的卻是本機分支名。現在由 `delete_branch_dialog_test.dart` 的 `feature/x` vs `renamed-x` 案例釘住。

## Result

- `fn-refs-branches.md` 從 15,361 降到 1,620 字元。
- L0 不變，維持 28,705。
- 還超過 6k 的 L1 剩 5 份：`ops-spec-reading`、`fn-flutter-input`、`fn-flutter-state`、`arch-testing-device`、`arch-testing`。
