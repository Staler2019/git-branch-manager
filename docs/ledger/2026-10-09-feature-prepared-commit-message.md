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

- ~~用 Cmd+Enter 或選單 commit 一個沒改過的 merge 訊息後，框會放回 merge 前的字：policy 只看 pending 由 true 變 false，分不出 commit 與 Abort；按鈕 commit 因為隨後 `reset()` 清框，結果是空的。③⑨ 只講 Abort。~~ 已修（Slice C `d8769a9`）。
- ~~merge 中改過訊息後重開 app 再 Abort：merge 前的字只在記憶體，拿不回來。~~ 已修（Slice C `0e00e5e`，episode 存進 SharedPreferences）。
- ~~verifier A1（P3，defer）：先進 amend 模式再開始 merge，模式內送出用的 `Amend` 仍畫且可按，按下得到 M6 的 `cannot amend`（lastError，可恢復）。④ 只規定進入模式的那顆按鈕。~~ 已修（Slice C `56b76b0`：merge／squash 發生時取消 amend）。
- ~~verifier A2（P4，defer）：pending 變 true 時正在 amend 模式則 episode 不開始，Cancel amend 後也不補填——與設計稿 01 圖「不在 amend 模式 → 請求」一致。~~ 由使用者裁定改寫（Slice C：取消 amend 後開始 episode），設計稿 01 圖的「不在 amend 模式」分支因此不再成立。

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

## Slice C — follow-ups（branch `feature/prepared-message-followups`，2026-10-10）

### Task

使用者 2026-10-10 裁定：

- 先進 amend 再開始 merge：「以merge為優先，也就是以git狀態為主」；squash 同。cancel 時恢復訊息。
- 改過的訊息要帶到下次開這個 repo。**⑪ 修訂**（重開時）：同一筆 merge／squash → 沿用框（改過與否皆同）；
  新的或不同筆 → 重抓 git 的訊息，Preferences 開關關著且框非空則不覆蓋（「如果開關關著的，不要覆蓋」）；
  上次在 merge／squash 中、這次已沒有 → 清空；其他 → 沿用上次 draft。上次讀取失敗（raw 為空）：「HEAD 沒變就當同一筆，沿用框」。
- Cmd+Enter／選單 commit 後也清空框（「commit後清空message box聽起來也合理」）。

### Action

| commit | 內容 | mutations-run | tests-reddened |
|---|---|---|---|
| `56b76b0` D1 | merge／squash 發生時取消 amend（`cancelAmendAndStart`） | 4 | 5／4／5／1 |
| `d8769a9` D2 | 三條 commit 路徑共用 `pendingCommitFrom`，由 `WorkspaceScreen` 看 HEAD／lastError 收尾 | 6 | 6／3／2／1／1／5 |
| `0e00e5e` D3 | episode 持久化（`workingCopyPreparedEpisode:<workDir>`，7 欄）與重開規則 | 17 | 見下 |
| `6b51041` D4 | 裝置層：Cmd+Enter commit 沒改過的 merge 訊息 → 框空 | 1 | 1（只紅新案例） |

D3 逐項：PM1 2、PM2 1*、PM3 2、PM4 3、PM5 7、PM6 1、PM7 3、CM1 2、CM2 1、CM3 2、CM4 9、CM5 1*、CM6 4、CM7 1*、CM8 1、RM1 1、RM2 1。
`*` = 第一次存活，補強測試後才紅：PM2（重開時 HEAD 未知的守衛）、CM5（未填的 episode 被存下）、
CM7（每輪只取一次 state 快照）——CM7 只在兩次寫入之間看得到舊 draft，原測試只看最終磁碟狀態；補強為檢查 reset 後每一次寫入。
CM4（先寫 draft 再寫 episode）紅 9 個，範圍偏廣，未再收窄。

D2 的行為改變：按鈕以外的 commit 路徑原本在 merge 結束時被當成 Abort、放回 merge 前的字；現在一律在 HEAD 移動後清框，
HEAD 未動且有 lastError 時保留框。

自己的錯：D3 的 `_drain` 在 dispose 後讀 state（「Tried to use WorkingCopyDraftController after dispose」），補 `mounted` 守衛；
數個 mutation 腳本錨點失效（D2 M1/M3 formatter 改了錨點、D3 CM7 第一次），無效的一次不計。
Plan readiness：epoch 1、2、4、5 皆 plan-verifier REVISE，blocker 就地修正；4、5 暫停交使用者，使用者以「a is ok」核准 epoch 5 修正版。

### Result

- `flutter test` +3396（~1 skip，既有）、analyze 0、format 0 changed。
- 裝置層逐檔：`prepared_message_flow_test` +4、`commit_flow_test` +1、`conflict_flow_test` +1、`merge_current_flow_test` +1、`merge_squash_flow_test` +2。

殘留（報告，未裁定）：

- ~~`reset()` 與磁碟寫入之間仍有毫秒級的 crash 視窗：此時當掉，下次開啟可能看到剛 commit 的訊息。~~ 已修（Slice D `eb6a3a7`，R1）。
- ~~app 開著時從外部 commit（終端機）：`pendingCommitFrom` 只由 app 內的 `submitCommit` 設定，外部 commit 結束 merge 時照 Abort 規則處理（框若仍是 autofill 會放回 merge 前的字）。~~ 已修（Slice D `53e9ac2`，R2）。

最後 verifier（Slice C，HEAD `1377804`）：**CONFIRMED**。重跑 `flutter test` +3396 ~1、analyze 0、裝置層 `prepared_message_flow_test` +4、`commit_flow_test` +1；7 個 scratchpad probe 全綠。
三個 P4 advisory，皆 defer（報告給使用者）：

- ~~A1：commit 進行中若剛好來了一個無關的 lastError（例如背景 fetch 失敗），`commitAbandoned` 先跑，merge 結束時框若仍是 autofill 會放回 merge 前的字。merge commit 已存在，無資料遺失。~~ 已修（Slice D `44dde6c`）。
- ~~A2：refs 載入前送出的 commit 記到的 HEAD 是 ''，第一次 refs 載入就被當成 HEAD 移動而清框，即使 commit 之後失敗。非本輪引入（舊 view 程式同樣讀法）。~~ 已修（Slice D `44dde6c`）。
- ~~A3：格式錯的 episode key 被 `read()` 忽略但不刪，直到下一個已填 episode 覆寫；不影響行為。~~ 已修（Slice D `6f350b7`）。

## Slice D — advisories A1–A3 與兩個殘留（2026-10-11）

### Task

使用者 2026-10-10「這些都修掉」：A1、A2、A3、R1（reset 前當掉）、R2（app 開著時外部 commit）。
R2 的非 commit HEAD 移動由使用者 2026-10-11 裁定「分辨 commit，其他照 Abort」：新 HEAD 的第一個 parent 是 episode 的 HEAD 才算 commit。

Plan readiness：五個 epoch。epoch 1、2、3 皆 REVISE（未填 episode 被清框；commit 失敗後標記殘留；同 HEAD 的 Abort 不重跑 pass；非 commit 的 HEAD 移動被當成 commit）。
epoch 3 是 closing review，REVISE 後暫停交使用者，取得上面的裁定。epoch 4 REVISE（meta 不回時沒有出口；root commit 的 `.first`）。
使用者 2026-10-11「contiue & 再審一次」後，epoch 5 為 **READY**。

### Action

| commit | 內容 | mutations-run | tests-reddened |
|---|---|---|---|
| `da5f63b` E1 | `CommitOperation::kind()` 回 `"commit"` | 1 | 1 |
| `b99ebde` E2 | session state：`commitOutcomeSeq`／`lastCommitSucceeded`、`refsEpoch`、`commitMetaReplySeq` | 6 | 各 1（另 1 個存活、屬等價） |
| `44dde6c` E3 | A1＋A2：只看 commit 自己的 outcome | 6 | 1／1／2／10／4／12 |
| `eb6a3a7` E4 | R1：送出前把在途 commit 標記寫入磁碟 | 8 | 1／3／1／1／3／1／2／1 |
| `53e9ac2` E5 | R2：重讀 refs → HEAD 動了 → 查 parent | 10 | 1／1／4／1／5／2／5／2／1／3 |
| `6f350b7` E6 | A3：開啟時刪除格式錯的 episode key | 3 | 各 1 |
| `9481bf5` E7 | 裝置層：外部 commit 後框為空；輪詢改讀檔 | 1（parent 比對恆假） | 1（只紅外部 commit 案例） |

偏離計畫與自己的錯：

- E4 的標記存 `[headFrom, headKnown]`，不是計畫寫的 `[headFrom]`：refs 未載入時送出的 commit，HEAD 讀到 ''，重開時無法比較，改照「無法判斷 → 保留文字」。判斷集中在 `WorkingCopyDraftController.settleCommit`，`WorkspaceScreen` 只轉交 session 的值。
- E5 掛載後的第一次 pass，只要 parent 還沒有答案就再問一次（計畫寫的是「請求之後沒有任何回覆」才再問）。回覆可能在 view 卸載期間到達又被淘汰，所以改成無條件再問。
- E5 的 controller 層測試是在實作之後才寫的，沒有先紅。policy 測試是先紅的。這部分靠 10 個 mutation 補上檢查。
- E2 的 M4／M5 第一次寫成計數加了兩次，紅得太廣，不算數；重寫後各紅 1。M4'（錯誤先發、計數後發）存活，這個順序本來就允許，屬等價。
- E3 的 N2–N6 第一批無效：zsh 不會拆開未加引號的 `$T`，兩個測試檔被當成一個路徑，全部在載入時失敗。改用陣列後重跑。
- E4 的 P2 第一次沒讓「app 內 commit 失敗會刪標記」那個測試變紅：測試之後又打了字，下一輪寫入順手把標記刪掉了。改成不打字（使用者保留原文字）後才紅。
- E5 把舊測試的 `reconcile(pending: false)` 一律替換時，連 helper 自己那行也換掉了，變成無限遞迴（Stack Overflow），已修正。

### Result

- `flutter test` +3444 ~1、analyze 0；core 與 capi ctest 各 783／783。clang-format：本機 23 版對 HEAD 原檔就有違規，CI 用 18 版；本輪只檢查改動行（`git clang-format --diff`），0。

### 裝置層：一個跑了 30 分鐘被砍、和一個隨機紅的根因

- 第一次逐檔跑時，`prepared_message_flow_test` 30 分鐘內沒有任何測試行，被背景時限砍掉。
  - pkill 後先跑 `commit_flow_test` 當對照：+1 綠。
  - 再跑 `prepared_message_flow_test`：不再卡住，但 3 次中有 3 次隨機紅在第 2 或第 3 個案例（框是 `''` 或 `mine`，不是 merge 訊息）。
  - 卡住那次之後沒有重現，記為「未重現」，不認定原因。
- 用 `debugPrint` 追蹤時 3 次全綠：印出的字串拖慢了每次 pass，問題就消失，是時序問題。改成記進記憶體、測試結束才印，才抓到原因。
  - 失敗那筆是 core 的 `git stripspace --strip-comments` 回傳 `exitCode: -1`，`detail` 是空的。
  - 該讀取被當成失敗，框於是維持原狀（`keep`）。不是 Slice D 的 Abort 規則造成的。
- `exitCode -1` 來自 `PosixChild::wait()` 的 `waitpid` 失敗（ECHILD）。原因：只要有 dart:io `Process` 在跑，dart:io 會回收**任何**結束的子行程，包括 core 用 `posix_spawnp` 起的 git。
  - 實測 2026-10-11（`dart run`，FFI 呼叫 libc `system("sleep 0.01")`）：沒有 Dart Process 時 0/100 回傳 -1；有一個 `Process.start('sleep')` 在跑、同時 `Process.runSync('true')` 時，74/100 回傳 -1。
- 測試端：`_merging`（`Process.runSync git rev-parse MERGE_HEAD`）與 `_git rev-parse HEAD` 會在 app 執行 git 的同時輪詢。
  - 改成讀 `.git/MERGE_HEAD`，以及 `.git/HEAD` 加上它指向的 loose ref。
  - 修正後連跑 3 次，3 次皆 +5 全綠（修正前 3 次皆紅）。剩下兩處 `git log -1` 在 `pumpAndSettle` 之後才讀。
- 已知但未處理（報告給使用者，未裁定）：
  - `real_repo_harness.dart` 的 `runGit` 被其他裝置層檔案在 app 執行中使用，同樣的隨機紅風險在全 repo 都存在。
  - production 端：`update_installer.dart` 的 `Process.run` 在更新流程中跑時，core 的 git 可能拿到 -1。`desktop_launcher.dart` 用 `ProcessStartMode.detached`，不是 Dart 的子行程，不受影響。
  - core 端要根治，需要不靠 `waitpid` 取得退出碼（例如 macOS 的 kqueue `EVFILT_PROC`/`NOTE_EXITSTATUS`）。這是行程管理的設計變更，需另行規劃。
- 其他裝置層檔案逐檔重跑（2026-10-11，`lib` 未改動）：`commit_flow` +1、`conflict_flow` +1、`merge_current_flow` +1、`merge_squash_flow` +2，全綠。

### Slice D 最後 verifier（2026-10-11，`e6f1e49..0195db5`）

- **CONFIRMED**。重現：`flutter test` +3444 ~1、analyze 0、capi ctest 783／783（序列跑）。並行跑時 `graph_matches_git_on_generated_history` 紅過一次，單獨重跑綠，verifier 判定是兩個 ctest 同時跑造成，本輪未動 graph。
- ~~未處理的 advisory（P3／P4 預設延後，交使用者裁定）~~ 使用者 2026-10-11 裁定「三個都修」，見 Slice E：
  - ~~D1（P3）：`commitMetaReplySeq` 每個 `COMMIT_META_READY` 都加一，包括 History 列先前的請求。這種回覆若在 checkParent 之後到、又不含新 HEAD 的 oid，真的 app 外 merge commit 會被判為 noAnswer，框回到 merge 前的文字，而不是清空。不會遺失資料。~~ 已修（Slice E `cdd81c6`）。
  - ~~D2（P3）：`submitCommit` 中 prefs 寫入若丟例外，`.then` 不會執行，commit 不送出也沒有錯誤顯示。`_drain` 丟例外會卡住 `_inFlight` 是本輪之前就有的；本輪新增的影響是連 commit 也被擋下。~~ 已修（Slice E `879eba2`）。
  - ~~D3（P4，未重現）：checkHead 之前就開始讀、之後才發佈的 refs 會被當成新的，看到 HEAD 未動 → Abort 規則。~~ 已修（Slice E `4c60e76`／`2751cb6`／`eac76d2`）。「未重現」只是沒試著重現：focus 重新整理會先同步讀 RepoState，再請求 refresh，所以這條路徑確實走得到。

## Slice E — verifier advisories D1–D3（2026-10-11）

### Task

使用者 2026-10-11「三個都修」：D1、D2、D3。dart:io 回收子行程另開一輪（使用者裁定），push／PR 延後。

Plan readiness：三個 epoch。
- epoch 1 REVISE：`setHistoryFilter()` 是第二個 dispatch 點，它的 `fireNow()` 會吸收等待中的請求且不再補跑，計畫原本沒寫；Dart 欄位可能倒退。
- epoch 2 REVISE：寫入同步拋出時，`_drain` 的 `finally` 會在 `_inFlight ??= _drain()` 賦值之前就跑完。
- epoch 3（收尾審查）**READY**。使用者「continue」核准實作。

### Action

| commit | 內容 | mutations-run | tests-reddened |
|---|---|---|---|
| `4c60e76` F1 | core＋capi：`gbm_history_refresh` 回傳請求編號；REFS_UPDATED 帶 `{"coversRequest"}`；兩個 dispatch 點都在 `takePending()` 同一段鎖內記下 | 4 | 3／1／1／2 |
| `2751cb6` F2 | Dart：`refsCoverRequest`（只取最大值）、`refreshHistory()` 回傳編號 | 3 | 1／2／1 |
| `eac76d2` F3 | D3：HEAD 檢查等 `refsCoverRequest >= headCheckRequest`；請求改由草稿送出 | 3 | 1／2／8 |
| `cdd81c6` F4 | D1：`commitMetaReplySeq >= commitMetaRequestSeq` 才算沒有答案；解不開的回覆也計數 | 4 | 2／1／1／1 |
| `879eba2` F5 | D2：寫入失敗時照樣送出 commit、記 Log；`_drain`／`_drainRounds` 拆開讓 `_inFlight` 一定歸零 | 7 | 2／2／0／0／2／1／3 |

偏離計畫與自己的錯：

- F1 把 Dart binding 的簽章（`_HistoryRefreshNative` 改 `Uint64`）也放進 F1，不是計畫寫的 F2：header 一改，`gbm_capi_signature_parity_test.dart` 就要求 binding 同步，分開放的話 F1 這個 commit 會是紅的。驗證過：只留 native typedef 為 `Void`，parity 測試紅 1（`gbm_history_refresh`）。
- F1 第一批 mutation 有四次無效：三次被 `-Werror` 擋下沒編譯成功（未使用的 capture、shadow、未使用變數），M4 那次跑到的是 M3 留下的舊執行檔；M2' 的腳本先還原檔案才套用第二處修改。改寫成能編譯的版本後，四個都有效。
- F1 第一次跑完整 ctest 只有 783 個：ctest 用的是加測試前的清單。重新 build 後 786／786。
- F3 的 widget 層「過期 refs」測試第一版太弱：過期 refs 的 cover 等於舊值 0，監聽紀錄沒變，根本沒觸發 pass，P1 mutation 時它照樣綠。改成先多做一次 refresh，讓過期值是新的非零值，P1' 才紅 2。
- F5 的計畫寫「每次寫入都經 `Future.sync`」。實作後兩個 mutation 都存活：拿掉 marker 的 `Future.sync`（R3），以及補上 draft 同步失敗案例後拿掉 draft 的（R3'）。原因是 `_drain`／`_drainRounds` 拆開本身就讓同步拋出先被 `_drainRounds` 的 future 接住，`Future.sync` 是多餘的，已刪除。plan-verifier 要的驗收仍然成立：把迴圈放回單一函式加 `try/finally`（R5）時，只有 draft 同步失敗那個案例變紅。marker 寫入永遠排在 draft 寫入的 `await` 之後，所以計畫寫的「marker 同步失敗」這個案例本來就驗不到卡住問題，已在測試註解寫明。
- F4 的 COMMIT_META_READY 回覆計數移到 `finally`，payload 解不開時一樣計入：否則一個回覆漏算，「全部已回覆」就永遠不會成立。

### Result

- `flutter test` +3460 ~1、analyze 0、format 0。capi ctest 786／786。core 未改動。

- 裝置層：20 個檔案逐檔跑（`879eba2`，`lib` 未改動），18 個綠，包括 `prepared_message_flow` +5、`stage_lines_flow` +9、`history_filter` +2。
  - `update_check_flow` 紅 2：GitHub API 回 403，是外部網路因素。
  - `worktree_add_refresh` 不穩：在 `879eba2` 上共跑 4 次，綠 1 次。紅的 3 次中，1 次第二個測試沒跑完，1 次 tearDownAll 沒跑完，1 次第一個測試卡到 900 秒 timeout。
  - 對照：在本輪之前的 `d59a3be` 上跑 3 次，綠 1、紅 2（都是 tearDownAll 沒跑完）。所以不穩是本輪之前就有的。那次卡住只在 `879eba2` 出現過一次、沒有重現，記為「未重現」，不認定原因。沒有開 issue。
- 逐 commit 檢查（另開 worktree）：F1–F4 每個中間 commit 都是 analyze 0，`flutter test` 依序 +3444／+3449／+3451／+3457，全綠。
- 新增欄位與函式都有讀取者或呼叫者：`coversRequest`、`refsCoverRequest`、`commitMetaRequestSeq`、`recordDraftNotSaved`、`headCheckRequest`；`headCheckEpoch` 已完全移除。

### Slice E 最後 verifier（2026-10-11，`d59a3be..f638588`）

- **CONFIRMED**。重現結果：`flutter test` +3460 ~1、analyze 0、capi ctest 786／786（逐一跑）。
- Advisory 的處置（P3／P4 預設延後，交使用者裁定）：
  - ~~E1（P3）：commit 路徑上若拋的是 `Error` 而不是 `Exception`，commit 不會送出、也不記 Log。只接 `Exception` 是計畫刻意的選擇（Dart 規則：不接 `Error`），但程式裡沒有註解說明。延後。~~ 使用者 2026-10-11 選「E1+E2 小修」：行為不變，補上理由註解（`73d1c70`）。Error 代表程式本身錯，不送出、讓錯誤浮現。改成「照樣送出再 rethrow」的話，在 widget 測試裡無法驗證。
  - ~~E2（P4）：沒有 session 時 `refreshHistory()` 回 0，不是 null，所以 `?? refsCoverRequest + 1` 的 fallback 走不到，HEAD 檢查會用手上的 refs 立刻判斷；註解「a caller with no session」只說中了一半。要走到這裡得先在 view 還掛著時關掉 native session。延後。~~ 已修（`d3123cd`）：回 0 視為沒送出請求，改等之後的 refs。mutation「0 當成請求編號」紅 1。
  - E3（P4）：verifier 認為 header 寫「Not monotonic」太保守。駁回：`claimPublishLocked` 是在 `graphMutex_` 內做的，但 REFS_UPDATED 是在鎖外 emit。所以舊 generation 若先 claim、新的後 claim，舊的仍可能較晚 emit，到達順序確實可能倒過來，header 寫的沒錯。
  - E4（P4）：寫入失敗那一輪的 `_markerOnDisk` 等狀態在寫入之前就設好了，所以失敗後同一個 head 不會重寫 marker，直到 marker 被清掉；不會遺失資料。延後。
- E1／E2 修正後重跑：`flutter test` +3461 ~1；裝置層 `prepared_message_flow` +5、`commit_flow` +1（`73d1c70`）。另派一次 verifier 只審這兩個 commit，判定 **CONFIRMED**。它確認開著 session 時 core 的請求編號從 1 開始、只增不減，不會回 0。它附帶一個 P4：uint64 超過 2^63 會在 Dart 變成負數，實際不可能發生，不處理。
