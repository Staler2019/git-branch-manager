# chore/s3-l1-drift-open — L1 第五片：drift-open.md 14 條縮為 8 條，關閉 #69

## Situation

`.claude/rules/drift-open.md` 有 20,092 字元、14 條，記的是 spec 與實作之間的已知落差，加上一份 open issue 清單。它的 paths 涵蓋整個 `lib`、`test`、`src`、`tests` 和 `docs/reports`。

## Task

依 `memory-steward` 的處置表縮減。使用者裁定三件事：

1. #69 可以關。
2. 退役 pin 的註解引用照前幾片的做法改掉。
3. 另外問：rebase 的 FFI 縫（`integration_test/` 摸不到 `gbm_rebase_start`）有沒有辦法補測試。

## Action

- **issue 狀態**：用 `gh issue view` 查了 22 個 issue，全部仍是 OPEN。#69 的內容是「Windows／macOS 的 runner 不被 PR CI 編譯」，但 `ci.yml` 的 `flutter-ci` 已經是三 OS matrix，而且每一腿都跑 `flutter build <target> --debug`。經使用者同意，附上證據留言後關閉。
- **處置**：
  - 留 8 條並縮寫，paths 收窄到各 drift 所屬的檔案。
  - 刪 6 條：
    - checkout、rebase 兩條已在 G1d 關閉，程式碼與 `dialog_copy_test.dart` 都可佐證。
    - 05c-is-remote-only 已由 `branch_context_menu_test.dart` 的「gone row (05-B…)」group 釘住；steward 沒讀這個測試，是我補查的。
    - lfs-match-approximate 的內容，`lfs_pattern_match.dart` 的註解已經寫明。
    - absent-for-no-capi 是 #76 的重複，其中「待提交數」那句早已過時。
    - open-issues 與 GitHub 重複。
- **過時說法，就地更正**：
  - updater 那條「PR CI 不編 Windows（#69）」：從新文字拿掉。
  - `fn-flutter-input.md` 的「PR CI compiles no macOS (#69)」：劃掉後改寫。
  - `window_title_test.dart`、`update_script_golden_test.dart` 的對應註解：改寫。
  - shortcuts 那條說 dialog「只有一個字面字串」：實際上第 48 行還有一個。
- **C1，只動註解**：
  - 退役 pin 的引用有 8 處，改為白話。
  - 四處錯誤路徑 `docs/rules/drift-open.md` 改為 `.claude/rules/`；其中一處在測試名稱字串裡。
  - `dart format` 順手改了 6 個沒碰的檔案，原因是本機 Dart 版本與 CI 不同。已用 scratchpad 的 patch 還原。
  - `flutter analyze` 0；相關測試 +120 全綠。
- **C2，規則檔**：
  - 縮減後 5,505 字元。
  - `check-rule-pins.py`：122 條、33 個引用，懸空 0。
  - 逐條跑 migration-loss，缺的項目分三類：
    - restore 那條的 mock 值，原文就在 spec HTML 裡。
    - 換了寫法的程式碼名稱。
    - 已關閉 drift 的歷史細節，G1d 的 ledger 已經有。
  - 沒有接受任何真實遺失。

## Result

- `drift-open.md` 從 20,092 降到 5,505 字元，碰任何 lib／test 檔就整份載入的情況也一併消失。
- #69 已關閉。
- rebase FFI 縫要不要補測試，提了兩個方案，等使用者選：
  - A：unit 層的 capi 宣告與 Dart typedef parity 測試，CI 會跑，涵蓋所有函式。
  - B：device 層的 autosquash 測試，只在本機跑。
- L0 不變，維持 28,705。
- 還超過 6k 的 L1 剩 6 份：ops-toolchain-ci、fn-refs-branches、ops-spec-reading、fn-flutter-input、fn-flutter-state、arch-testing-device。
