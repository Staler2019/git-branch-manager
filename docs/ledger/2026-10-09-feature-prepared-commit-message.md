# feature/prepared-commit-message — commit 框帶入 git 準備好的 merge／squash 訊息

## Situation

merge 衝突解完回到 Working Copy 時，commit 框是空的（或留著使用者先前打的字），但 git 早已寫好
MERGE_MSG／SQUASH_MSG。core 有 `readPreparedCommitMessage()` 與覆蓋判斷
`shouldApplyPreparedCommitMessage()`，兩者在 `src/capi/` 與 `lib/` 都沒有 caller
（[ledger: feature/mergePanel](2026-10-08-feature-mergePanel.md) 只報告未處理）。

先實測（git 2.56.0），結果全部記在設計稿 `docs/claude-design-demo/prepared-commit-message-spec.html`：

| # | 實測 | 結果 |
|---|---|---|
| M1 | merge 衝突後的 MERGE_MSG | `Merge branch 'topic'\n\n# Conflicts:\n#\tf\n`，註解行會進框 |
| M2 | 把 M1 原樣交給 `git commit --file -` | 註解行留在永久訊息：沒開 editor 時 cleanup 是 whitespace，不是 strip |
| M3 | squash 衝突寫哪些檔 | SQUASH_MSG 與 MERGE_MSG 都寫，MERGE_MSG 只有註解；舊註解「mutually exclusive in practice」是錯的 |
| M4 | 解完後 git 自己的組法 | SQUASH_MSG 接 MERGE_MSG，再 strip |
| M5 | `git stripspace -s` 配 `core.commentChar=;` | 只去 `;` 開頭的行 → 交給 git，不在 Dart 寫死 `#` |
| M6 | merge 衝突解完後 `commit --amend` | `fatal: You are in the middle of a merge -- cannot amend.` |
| M7 | squash 等待中 `commit --amend` | 成功 |
| M8 | 衝突全取 ours | staged 0，`git commit` 照樣建出 merge commit |
| M9 | `merge --abort`／squash 後 `reset --hard` | 兩個 MSG 檔都刪 |
| M10 | `core.commentChar=""` | `stripspace` exit 128，用作讀取失敗的 fixture |
| M11 | `core.commentChar=auto` | `stripspace` 與 `git commit` 結果一致 |

## Task

使用者裁定（設計稿 §04，編號沿用）：

- ① 用 `git stripspace` 去註解；**覆蓋**使用者已打的字。② merge／squash 發生時就填。
- ③⑨ Abort 時框內仍是自動帶入的內容 → 放回 merge 前的字。
- ④ merge 中不畫 Amend，`isActionEnabled(repositoryAmendLastCommit)` 一併 false。
- ⑤⑭ merge 中 staged 0 也可 Commit。**這條推翻 spec P3 第 8 項「staged 為 0 或 summary 為空時停用」，只限 merge 進行中**（M8：照 spec 做 merge 結束不了）。
- ⑥⑩ ConflictBanner 不畫不能用的按鈕：merge 只有 Abort（有衝突再加 Resolve…），revert 只有 Resolve…。
- ⑦ 刪除 C++ 的 `shouldApplyPreparedCommitMessage`。⑧ RepoState 加 bool + request／event。
- ⑪ 預設覆蓋、啟動時也覆蓋，Preferences 開關 `overwriteWithPreparedMessage`（預設 true），關掉時只填空框；兩個開關標題加「（預設）」。
- ⑫ commit 框改用 `gbmInputDecoration`／`gbmMultilineInputDecoration`，summary h30 text-sm，72 尺標偏移跟著 space3。
- ⑬ 兩個 helper 補 `hintStyle: textTertiary`。⑮ commit 區底色 surface-panel-raised，`Amend…` → `Amend`（不是 `Commit N`，placeholder 維持英文）。

## Action

Slice A（core／capi／Dart 管線，風險單元，verifier CONFIRMED）：`3aa4f23` 組法改照 M4、`b8bf1d1`
`PreparedMessageStore` 經 stdin 跑 `stripspace --strip-comments`、`f843c4a` `RepoState.preparedMessagePending`、
`3ffb2a6` `gbm_request_prepared_message` 與事件 37、`06e8d64` commit 完成後重讀 RepoState、`3f926f9` 事件號 parity 測試。

Slice B（UI）：

| commit | 內容 | mutations-run | tests-reddened |
|---|---|---|---|
| `fdf2d67` C5 | Preferences 開關＋「（預設）」 | 5 | 5 |
| `22786b9` C6 | 純函式 `decidePreparedMessageAction` 與 controller episode | 11＋10 | 11（各一列）；7，三個存活 → 補 3 測試後各 1 |
| `3ae16b2` C7 | WorkingCopyView 接線 | 8 | 6／7 有效；存活的空白回覆 → 補測試後 1 |
| `01f7245` C8 | merge 中無 Amend、`Amend…`→`Amend` | 4 | 3；存活的「cherry-pick 衝突仍停用 amend」→ 補測試後 1 |
| `e3dfdc0` C9 | merge 中 0 staged 可 Commit | 3 | 1／6／1 |
| `c3cbd61` C10 | banner 不畫不能用的按鈕 | 4 | 1／5／4／11 |
| `6cd1f44` C11 | commit 框 kit 樣式、區塊底色 | 6 | 6 |
| `ba3465e` C12 | `hintStyle` | 2 | 2 |
| `53078a6` C13 | 刪 `shouldApply…` 與 4 個測試 | 0（純刪除） | — |
| C14 | 裝置層 `prepared_message_flow_test.dart` 3 例 | 1（拿掉 mount 時的 pass） | 1（只有 squash 例紅） |

Slice A 各 commit 的 mutation 數：C0a 1／1、C0b 1／1、C1 3（1 個等價變異存活，未計）、C2 3、C3 6、C4 4。

偏離計畫與自己的錯：

- 純函式放在 `lib/data/models/prepared_message_policy.dart`，不是計畫寫的 `lib/data/repositories/prepared_commit_message_policy.dart`：arch-suggester 依 layering 建議，data 層不能 import features。
- C8 漏改 `working_copy_view_test.dart` 的 `'Amend…'`：grep 字面 `…` 找不到 escape 寫法，全套跑紅才發現。
- 三個 mutation 第一次沒生效：C7 M2 與 C9 M2 是腳本寫壞（編譯失敗的紅不算），C11 M6 的錨點在檔內出現兩次、根本沒套用（綠不算）。都重跑後才記數。
- `[ACT-availability]` 加 amend 那行讓 L0 超出 ceiling 204 字；改為精簡同段文字，ceiling 由 28,705 → 28,689；本輪記錄 orphan 第 13 例後再降到 28,678。
- ⑥⑩ 與 `[FLU-menu-enabled-is-visual-only]` 的「disabled-with-a-tooltip beats hidden」相反；依使用者裁定 banner 不畫，那條規則只講選單，未改。

## Result

- `flutter test` 3,353 綠；core 591（原 595，刪 4）、capi 188 綠；analyzer 0；clang-format（src）0。
- 裝置層（macOS，逐檔）：見下方「裝置層重跑」。
- Orphan grep 兩方向：`preparedMessagePending`、`preparedMessage` 回覆、`overwriteWithPreparedMessage`、capi 函式都有讀者；`readPreparedCommitMessage` 已接上 → [record](../records/2026-10-04-orphan-wiring-instances.md) 第 13 例。
- Hover sweep：改動檔中的 `InkWell`／`GestureDetector` 都是既有、本輪未碰；banner 的 `TextButton` 只是抽成 `_BannerButton`。

已知但未處理（報告給使用者，未裁定）：

- 用 Cmd+Enter 或選單 commit 一個沒改過的 merge 訊息後，框會放回 merge 前的字：policy 只看 pending 由 true 變 false，分不出 commit 與 Abort；按鈕 commit 因為隨後 `reset()` 清框，結果是空的。③⑨ 只講 Abort。
- merge 中改過訊息後重開 app 再 Abort：merge 前的字只在記憶體，拿不回來。
- verifier A1（P3，defer）：先進 amend 模式再開始 merge，模式內送出用的 `Amend` 仍畫且可按，按下得到 M6 的 `cannot amend`（lastError，可恢復）。④ 只規定進入模式的那顆按鈕。
- verifier A2（P4，defer）：pending 變 true 時正在 amend 模式則 episode 不開始，Cancel amend 後也不補填——與設計稿 01 圖「不在 amend 模式 → 請求」一致。

最後 verifier（整輪 Slice B，HEAD `0417bfd`）：**CONFIRMED**。重跑 `flutter test` +3353、analyze 0、裝置層 3／3、core＋capi ctest 782／782。

### 裝置層重跑

逐檔、每次先 `pkill` 殘留的 `gbm_flutter`（[TEST-device-runs-one-file]）：

| 檔 | 結果 |
|---|---|
| `prepared_message_flow_test.dart`（新） | +3 All tests passed |
| 同上，拿掉 `initState` 的 `_schedulePreparedPass()` | +2 -1，只有 squash 例紅 |
| `merge_current_flow_test.dart` | +1 All tests passed |
| `merge_squash_flow_test.dart` | +2 All tests passed |
| `conflict_flow_test.dart` | +1 All tests passed |
| `commit_flow_test.dart` | +1 All tests passed |

`real_repo_harness.dart` 的 `flatKeysToClear` 加了 `appPrefs.overwriteWithPreparedMessage`（[TEST-pumprealappon-clears-prefs]）。
