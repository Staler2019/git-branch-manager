# Prune 過期例外註解 / 救援選項字串改 Dart 端組

分支 `fix/prune-stale-comment-and-recovery-choice-copy`，接在上一輪 G1（`923de26`
「G1c」）之後。使用者這輪一次交了三件事，裁定順序是**任務一 → 任務三 → 任務二**：
任務一（Prune remote branches 過期註解）最小，先做掉；任務三（救援選項字串）
理順了「文案到底該放哪一層」，任務二（G1 剩餘對話框）要等這個地基乾淨才做，避免
在一個已知要重寫的欄位上再疊 17 個對話框的文案。任務二這輪尚未開始，本檔案先記
任務一跟任務三；任務二完成後在本檔案續寫，不另開新檔（同一分支＝同一輪）。

## 任務一：Prune remote branches 的過期例外註解

`96cdc9d` 已經修好一個真的會在每次打開對話框時炸掉的 bug：`preview?.remote ==
_selectedRemote` 這個判斷式在兩邊都是 `null` 時也成立（`?.` 的空值傳播對
`null == null` 一樣回 `true`），下一行的 `preview!` 就對著 `null` 解包炸掉。
`_selectedRemote` 是在 `initState` 的 `Future.microtask` 裡才指派，代表**每一次
打開對話框的第一個 frame** 它都是 `null`——不是「沒設定 remote 的 repo 才會中」
的邊角情況，是每次都中。使用者看到的是閃一格的 Flutter 錯誤框，因為下一個 frame
`_selectedRemote` 賦值後畫面就正常了，錯誤不會持續顯示。

問題是 `96cdc9d` 修完 bug 之後，描述這個 bug 的註解沒有跟著更新——測試檔頭和
`prune_remote_branches_dialog.dart` 的行內註解都還用現在式寫「this dialog threw
every single time it was opened」，其中一段還寫「Recording the wrong prediction
rather than quietly deleting it」，像是刻意把一個「預期會炸」的斷言留在測試裡當
文件。使用者的原話：「那個錯誤預期我留在測試註解裡沒刪⋯這個修掉，不是留註解。」
——即不是要把敘述改成「過去式」就交差，是要真的檢查測試本身有沒有還在斷言一個
已經不該發生的行為，並且刪掉。

**核對結果**：兩個測試本身的斷言（`expect(tester.takeException(), isNull)` +
標題斷言）從 `96cdc9d` 起就是對的，沒有斷言「應該要炸」——過期的只有*描述性*
註解，不影響測試本身的正確性。`ac3e3d5` 把檔頭跟行內註解都改寫成精簡、過去式、
對應目前程式碼的說明（guard 現在長什麼樣、為什麼要 `preview != null &&` 而不是
`preview?.remote ==`），不改行為，兩個測試維持綠燈。

## 任務三：救援選項字串該放哪一層

上一輪把這個列成 blocker 先擱置。這輪追查發現問題比原本想的更深。

### 追查過程

`OperationChoice`（`OperationRunner.h`）當時是 `{ Kind kind; std::string label;
std::string explanation; bool destructive; }`，`label`/`explanation` 從 C++ 端
組好的英文字串，經 `JsonCodec.cpp` 原封不動送上 wire，Flutter 端的
`checkout_recovery_dialog.dart`／`delete_branch_recovery_dialog.dart` 直接畫
`choice.label`／`choice.explanation`。

第一個發現：**spec 引用的按鈕文案跟 core 目前送出的對不上**。`DLGS`「Checkout
blocked」note 全文核對後是「三個選項都給：Stash and checkout（主）、Discard and
checkout（danger）、Cancel」，而 `CheckoutOp.cpp` 當時送出的是「Stash changes and
switch」／「Discard changes and switch」。說明文字則被要求用中文——意味著
**沒有一個地方真的在「照抄 wire 內容」畫東西**：wire 送英文，畫面卻要跟 spec 對齊
（英文按鈕、中文說明），這在字串直接從 core 搬到畫面的架構下無法同時成立。

第二個發現：追這條線時翻到 `retryCheckoutWithChoice`／`retryDeleteBranchWithChoice`
（`repo_session_repository.dart`）對 `retry`／`removeLock` 兩個 kind 的 dispatch
是空的 `break`——這兩個 choice 會被 `OperationRunner::preflight()` 在 index.lock
場景下 push 進 `choices`（跟 checkout/delete-branch 共用同一條
`_handleOperationOutcome` 派送路徑，見 `OperationRunner.cpp:62-97`），按鈕因此
**畫得出來，點下去卻沒有任何反應**——一個獨立於文案問題之外的死按鈕 bug，且
`removeLock` 當時連對應的 capi 都不存在。

第三個發現：核對 `_handleOperationOutcome` 的 switch 之後，merge／rebase／
cherry-pick／revert／pull（`RemoteOps.cpp`）五個檔案建構的 `OperationChoice`
**從一開始就沒有 Dart 端讀者**——`_handleOperationOutcome` 只有
`PendingOperationKind.checkout`／`.deleteBranch` 兩個 case 會把 `choices` 存進
`RepoSessionState`，其餘 kind 落進 switch 但沒有任何 case 保留它們。這是
`[CULT-orphan-wiring]` 的又一個實例。

`spec-auditor` 稽核 `DLGS` 時另外發現一則「Pull blocked」條目（三顆按鈕、danger
在第二顆，跟「Checkout blocked」同型），代表 spec 確實構想過 pull 失敗的救援
畫面——但這條從沒有對應的 Dart 對話框接上，記進 `[DRIFT-no-pull-dialog]`。

### 兩個裁決依據

這輪問使用者兩個 `AskUserQuestion`：

1. **Retry / Remove index.lock 兩個死按鈕怎麼處理？** 裁定「兩個都補（含新增
   removeLock 的 capi）」——不是把死按鈕拿掉了事，是把承諾的行為做出來。
2. **`OperationChoice` 的 wire 格式怎麼設計？** 裁定「推廣成統一設計，wire
   精簡到只剩 kind+destructive」——不只是修 checkout/delete-branch 這兩個有
   讀者的路徑，是把「wire 只帶語意值、文案由消費端依語意值組」這個原則推廣到
   整個 `OperationChoice`，包含拿掉那五個從無讀者的檔案裡的建構。

### 六個 reversible commit

由外而內（Dart 消費端 → capi wire → C++ struct），每個 commit 各自綠燈：

1. `6e92d9a` **`feat(flutter): checkout/delete-branch 救援對話框改用 Dart 端依
   kind 組的文案`**——新增 `recovery_choice_copy.dart`，checkout 側套 spec 引用
   的三個文案，delete-branch 側沿用既有英文＋中文說明；兩個對話框的 body 列表
   比照按鈕列表濾掉 `abort`（修掉重複畫 Cancel 的既有瑕疵）。
2. `70ec409` + `d4e1436` **`feat(flutter): 補上 Retry / Remove index.lock 兩個
   救援選項的真實動作`**——`retry` case 直接重送原始請求；新增 core 端
   `OperationRunner::removeStaleIndexLock()`，**伺服端重新驗證**鎖確實逾
   `kStaleLockSeconds`（不信任前端「反正使用者按了」），新 capi 進入點
   `gbm_operation_remove_stale_index_lock`，FFI binding 到
   `RepoSessionController.removeStaleIndexLock()`；TDD 補了 C++ 端「鎖逾時被
   刪」「鎖未逾時拒絕」兩個 red-first 測試，capi 一則，Dart 端 `retry`／
   `removeLock` 兩個 case 的 dispatch 各一則。
3. `ac2cf64` **`refactor(flutter): OperationChoice 的 label/explanation 不再
   讀 wire`**——`OperationChoice` model 拿掉兩個欄位，`fromJson` 只解
   `kind`/`destructive`；修掉五個測試檔案裡的 fixture 跟斷言。這裡另外補了一則
   釘住「checkoutChoices 和 lastError 是否真的一起發布」的 reducer 測試——原本
   `dialog_copy_test.dart` 想直接寫一則用到 `controller.emit`／
   `handleTestEvent` 的測試，這兩個 API 在 `FakeRepoSessionController` 上並不
   存在（先讀原始碼才發現，沒有先跑測試才發現），改放到
   `repo_session_operation_outcome_test.dart`，用真正存在的
   `debugRecordCheckout`／`debugHandleOperationOutcome` 驅動真正的
   `_handleOperationOutcome`。
4. `121a931` **`refactor(core): OperationChoice 的 JSON 只送 kind 跟
   destructive`**——`JsonCodec.cpp` 的 `operationChoiceJson()` 拿掉兩個 key。
5. `52cf08a` **`refactor(core): OperationChoice struct 拿掉 label/explanation，
   8 個建構式跟著簡化`**——`OperationRunner.h` 的 struct 定義只留
   `kind`/`destructive`；8 個建構位置（`OperationRunner.cpp` ×3、
   `CheckoutOp.cpp` ×3、`BranchOps.cpp` ×2、`MergeOps.cpp` ×2、
   `RebaseOps.cpp` ×2、`CherryPickOps.cpp` ×2、`RevertOps.cpp` ×2、
   `RemoteOps.cpp` ×2）拿掉字串參數；沒有讀者的五個檔案（merge／rebase／
   cherry-pick／revert／pull）改成**完全不再 push 這兩筆 choices**，只留
   `outcome.summary`/`outcome.error`（既有的失敗訊息路徑不變，「留 log」的
   部分本來就在運作）。`docs/rules/drift-open.md` 的 `[DRIFT-no-pull-dialog]`
   補一條記錄「Pull blocked」的 spec 條目跟這次刪除的關聯。
   `MergeOffersStashAndRetryWhenTheWorkTreeIsDirty` 這則舊測試斷言
   `hasStash == true`，是這次刪除的直接受害者，改名為
   `MergeReportsDirtyWorkTreeWithNoChoicesAndTheStashFirstRetryStillWorks`，
   斷言改成明確 `EXPECT_TRUE(outcome.choices.empty())`——比照
   `[CULT-orphan-wiring]` 第 12 例 `RemoveWorktreeOperation` 的做法，防止
   之後被誤接回去而不是被沉默遺漏。
6. 本 commit（docs）——蒸餾 `[ACT-recovery-choice-wire]`／
   `[ACT-index-lock-server-revalidates]` 兩條 pin，寫本檔案。

### 一處就地更正（commit 6 之內）

commit 3 新增的那則 reducer 測試，其文件註解原本寫「preflight failures carry no
formal GitError, so `_errorFromOutcomePayload` falls back to summary」，測試
payload 也只送了 `summary`，沒有送 `error`。重讀 `OperationRunner.cpp:62-97`
確認這句話是錯的：`preflight()` 的兩個分支**都**設了 `outcome.error`（index.lock
分支是 `GitError::Code::LockHeld`，sequencer 忙碌分支是 `Code::Conflict`）——
不存在「preflight 沒有正式 GitError」這回事。原本的測試 payload 因此走的是
`_errorFromOutcomePayload`的 fallback 分支，不是它自稱在測的 preflight 真實形狀。
按 `CLAUDE.md` 標準規則 4（「一份書面紀錄裡的錯誤陳述要就地訂正」），把 payload
改成帶完整 `error` map（`code: 4`／`codeName: 'LockHeld'`，其餘欄位對應
`GitError.fromJson` 需要的形狀），註解改寫成準確描述；13 則測試（含這則）重新
跑過仍全綠。

### 驗證

- C++ 核心測試：commit 5 完成後 498 題、496 通過、2 個既有 skip（machine 沒裝
  git-lfs），跟基準一致。
- capi 測試：158/158。
- `flutter analyze --no-pub`：0 issue（commit 6 就地更正後重跑仍 0）。
- `scripts/check-rule-pins.py`：166 條規則、56 個交叉引用，懸空 0（commit 5
  後跑過一次，commit 6 新增 pin 後需要再跑一次）。
- 每個 commit 的 mutation-check：narrow 且已用 scratchpad 備份/還原、`diff`
  確認位元相同，細節見各 commit 訊息與上面段落。

### 任務二：G1d（`checkout` / `rebase_onto` / `new_branch`）

commit 7（`719f080`）——三個對話框依計畫的 DLGS 引用表逐條轉中文，一次
commit：

- **Checkout**：搜尋提示（`可搜尋 branch / tag / commit`）、空清單訊息
  （`沒有可以切換的項目。`）、選到遠端分支時的追蹤說明（`建立本地分支
  「x」，追蹤 y。`）、stash 勾選框標題／副標題（`先 stash 未提交的變更`／
  `N 個檔案有未提交的變更。`）。
- **Rebase onto**：開場句（`重新安置 X 到：`）、下拉提示（`基於`）、
  衝突說明段落、同一組 stash 勾選框文案。
- **New branch**：欄位標籤（`名稱`）、區塊標題（`從哪裡分出`）、同一組
  搜尋提示、兩個勾選框（`建立後直接 checkout`／`同時 push 並設為
  upstream` + 副標題 `會推送到 X。`）。標題與主按鈕（`Checkout`／
  `Cancel`／`Rebase`／`Start rebase`／`New Branch`／`Create branch`）維持
  英文不動，`branch_name_validation.dart` 刻意不動（計畫排進 G1g）。

**先用 advisor 定了一件事**：三個對話框裡有兩個（Checkout、Rebase onto）
對照 DLGS 的 mock 圖有結構性落差——不是漏翻譯，是整段控制項沒做（Checkout
少了「目前」列與兩個 radio；Rebase onto 少了兩個勾選框與一則警告）。
advisor 的判斷：translate-only 是對的，不要在文案 commit 裡順手補結構，
因為：(1) 計畫本身把 G1 定義成「文案轉換」，不是「照 mock 補齊」；
(2) `merge_dialog.dart` 等既有 G1 對話框的先例本來就是轉譯既有結構，不是
另起爐灶；(3) 在文案 commit 裡加 radio/勾選框會違反使用者自己定的 G1 設計
閘門（UI 結構要先設計、先給 spec-auditor 核過、再給裁決）。兩個落差的性質
也不同：Rebase onto 那兩個勾選框需要 capi 先加 `--rebase-merges`／
autosquash 旗標，屬於 `[DRIFT-absent-for-no-capi]` 那一類；Checkout 那個
純粹是呈現層級（既有的 stash 勾選框已經滿足 P06 本文的要求），照
`[SPEC-mockup-is-not-prose]` 的裁決原則本文優先於圖。兩者都寫進
`docs/rules/drift-open.md`（`[DRIFT-checkout-dialog-mock-delta]`／
`[DRIFT-rebase-onto-missing-capi-flags]`），不是「本輪不做」的沉默省略——
落差寫在案發現場（三個 doc comment 各自指回對應的 drift pin），且已回報
給使用者。

`dialog_copy_test.dart` 新增 `Checkout`／`Rebase onto`／`New Branch` 三組
共 12 則測試；`_pump()` 加了 `overrideState`（整包替換掉預設 session，
給需要遠端分支或單一 remote 的情境用）跟 `workingCopyEntries`（组一個
`WorkingCopyStatus`，觸發 dirty 狀態才會畫出來的 stash 勾選框）兩個可選
參數，不動任何既有呼叫點。

**Mutation-check**：8 個字串逐一還原成英文，每次跑
`flutter test test/features/dialogs/dialog_copy_test.dart`，讀
`+N -M` 這行的 `M`：

| 還原的字串 | REDS |
|---|---|
| Checkout stash 勾選框標題 | 1（僅該測試） |
| Checkout 追蹤說明 | 1 |
| Checkout 搜尋提示 | 1 |
| Rebase onto 開場句 | 1 |
| Rebase onto stash 勾選框標題 | 1 |
| Rebase onto 下拉提示 | 1 |
| New branch 欄位標籤 | 1 |
| New branch push 勾選框標題 | 1 |

8 次 mutation、8 次紅燈，每次都只紅該字串對應的那一則測試，沒有一次波及
其他組。每次 mutate 前都先 `cp` 到 scratchpad、`grep -c` 確認 anchor 唯一，
還原後 `diff` 確認位元相同（未曾用 `git checkout --` 還原）。

驗證：`flutter test test/features/dialogs/dialog_copy_test.dart` 41/41
綠燈；`dart format`／`flutter analyze --no-pub` 都是 0；
`scripts/check-rule-pins.py`：170 條規則、63 個交叉引用，懸空 0。

### 尚未開始：G1e–G1k

`delete_branch`+`delete_branches`（G1e）、`discard_changes`+`restore_file`
（G1f）、`rename_branch`（G1g）、`repository_settings`（G1h）、
`preferences`（G1i，`Shortcuts` 分頁明確排除，需要補一條 drift-open.md
記錄尚未寫）、`about`+`update`+`manage_base_folders`（G1j）、
`lock_worktree`/`remove_worktree` 殘留英文收尾（G1k）。完成後續寫本檔案，
不另開新檔。
