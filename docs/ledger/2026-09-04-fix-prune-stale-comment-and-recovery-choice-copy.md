# Prune 過期例外註解 / 救援選項字串改 Dart 端組

分支 `fix/prune-stale-comment-and-recovery-choice-copy`，接在上一輪 G1（`923de26`
「G1c」）之後。使用者這輪一次交了三件事，裁定順序是**任務一 → 任務三 → 任務二**：
任務一（Prune remote branches 過期註解）最小，先做掉；任務三（救援選項字串）
理順了「文案到底該放哪一層」，任務二（G1 剩餘對話框）要等這個地基乾淨才做，避免
在一個已知要重寫的欄位上再疊 17 個對話框的文案。三項任務均已完成，含使用者另外
點名的「兩個落差也修掉」（Checkout mock delta、Rebase onto capi 旗標）；本檔案記
完整敘事，同一分支＝同一輪，不另開新檔。

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

### 兩個裁決落差關閉：Checkout 的「目前」列/radio、Rebase onto 的 capi 旗標

G1d 那輪把 Checkout 跟 Rebase onto 對照 DLGS mock 的結構性落差記成
`[DRIFT-checkout-dialog-mock-delta]`／`[DRIFT-rebase-onto-missing-capi-flags]`
兩條 pin，先文案轉中文、結構不動。使用者原話「兩個落差也修掉」是這輪最早
收到的指示之一，兩條在 G1e 前後被個別關閉——不是同一個 commit，順序是
Checkout 先關（`f4da321`，在 G1e 之前），Rebase onto 後關（跨四個 commit，
G1e 之後）：

- **Checkout**（`f4da321`）：補上 DLGS mock 的唯讀「目前」列（目前分支＋
  未提交變更數）跟 radio-on/radio 雙選（帶著變更切過去／先 stash），逐字
  引用 DLGS 條目；radio 對映既有的 `_stashFirst` bool，不需要動
  capi/controller。mock 的 warn 欄位（兩邊都改到的檔案會阻止 checkout）
  刻意不畫——這從未被這條 pin 記成落差的一部分，checkoutChoices／
  checkout-recovery 對話框已經在處理這個情境。Pin 原地改寫成
  「— 已關閉」，不是刪掉重開。
- **Rebase onto**：這條需要 capi 先加欄位，分四個 commit 由下而上接通：
  1. `e99e64b`（core）：`RebaseRequest` 加 `rebaseMerges`/`autosquash`
     兩個旗標，`RebaseOps.cpp` 轉成 `--rebase-merges`/`--autosquash`。
     `--autosquash` 能否在非互動模式下運作先在 scratch repo 量過（git
     2.55.0）：`git rebase --autosquash <upstream>`（沒有 `-i`）直接
     fold fixup commit、exit 0，跟 git 官方文件「uses the --interactive
     machinery internally, but can be run without an explicit
     --interactive」一致。四個新 `RealRepoTest`（兩個測開啟時的行為，
     兩個測預設關閉時不變），2 個 mutation 各窄紅 1 個測試。
  2. `81c9aa7`（capi）：`gbm_rebase_start` 新增第 4、5 個參數送這兩個
     旗標過邊界。新增兩個 capi 層測試
     （`PlainRebaseWithAutosquashFoldsAFixupCommit`／
     `PlainRebaseWithRebaseMergesPreservesAMergeCommit`）——
     `[TEST-ffi-matches-symbol-only]` 記著只有這一層能抓到「第 5 個參數
     被漏掉或排錯」，跟 core 層測的是 `--autosquash` 本身的 git 行為不同。
  3. `f44e09d`（flutter）：FFI typedef 補兩個 `Int32`，
     `RepoSessionController.startRebase()` 補兩個具名 bool 轉發給
     bindings，`FakeRepoSessionController` 補一個會記錄進
     `commandLog` 的 override（原本的 null-session guard 會靜默吞掉
     沒 override 的呼叫，測試分不出「關閉了」跟「接到空氣」）。對話框
     依 DLGS 補 `chk-on`「保留 merge commit（--rebase-merges）」預設
     勾選、`chk`「自動 squash 標記過的 fixup commit」預設不勾、以及
     「此分支已 push」警告（讀 `remoteCounterpartOf()`，跟
     `delete_branch_dialog.dart` 同一個單一來源，不重新從
     `hasTrackingInfo`/`upstream` 推導）。內容變多後跟 Checkout／New
     branch 一樣包一層 `SingleChildScrollView`。新增
     `rebase_onto_dialog_test.dart` 驗證 Start rebase 實際 dispatch 的
     值跟畫面勾選狀態一致；兩處 mutation-check（dispatch 寫死值、
     `hasRemoteCounterpart` 寫死 false）各 1 個 mutation、各窄紅 1 個
     測試。
  4. `d94b700`（docs）：pin 原地改寫成「— 已關閉」，記錄 capi→FFI→Dart
     controller→UI 整條鏈，`scripts/check-rule-pins.py`：170 條規則、
     65 個交叉引用，懸空 0。

`ddda853` 是這段中間跑全套 `flutter test` 才發現的收尾：G1d／G1e 各自
改動過的三個對話框（`new_branch_dialog.dart` 姓名欄位、
`delete_branch_dialog.dart`／`delete_branches_dialog.dart` 的勾選框），
它們各自的專屬行為測試檔案（不是 `dialog_copy_test.dart`）從未更新，
一直斷言已經被改掉的英文字串——10 個測試全部集中在這三個檔案，只改測試
裡的期望字串，不改被測程式碼。這是本輪第二次因為「先看某個測試檔案綠燈
就以為完工」而漏掉別的測試檔案的教訓，跟後面 G1f/g/h 每批都堅持跑
**全套** `flutter test`（不只是被改動對話框自己的測試）直接相關。

### 任務二：G1e（`delete_branch` / `delete_branches`，`4475621`）

依計畫引用表轉中文：Delete branch 的確認句、有無 upstream 的說明、
「同時刪除遠端」勾選框（標題與副標題）、分支選擇器的提示與空狀態訊息；
Delete branches 的「本地分支」／「遠端分支」段落標題、每行未推送 commit
數的說明、兩個勾選框。標題與主按鈕維持英文。`dialog_copy_test.dart` 新增
兩組共 10 則測試，Delete branch 用 `overrideState` 補一個有遠端對應
（同名 unambiguous match，不靠 upstream config）的分支測「同時刪除」勾選
框；Delete branches 另補一個帶 upstream/ahead 的分支測「N 個未推送的
commit」與遠端段落。5 個字串逐一 mutation-check，各自窄紅。

### 任務二：G1f（`discard_changes` / `restore_file`，`a71bdbd`）

`discard_changes_dialog.dart`：新增 `_dangerLabel(int, List<String>)`
實作 DLGS 的「主按鈕寫出實際數量；兩個檔案以下改成寫檔名」——1 個檔案寫
檔名、2 個檔案用 `, ` 接兩個檔名（這個接法本身不是 spec 逐字值，是這個
對話框自己的讀法，記在文件註解裡）、3 個以上才寫數量；intro 文案、
未追蹤檔案提示、不可復原警告轉中文；包一層 `SingleChildScrollView`。
`restore_file_dialog.dart`：補上 DLGS `ro` 列原本完全沒有標籤文字的兩個
label（「檔案」／「還原成」）；warn 文案改寫成貼合這個對話框真正擁有的
布林能力（`_hasUncommittedChanges`），不是照抄 mock 裡一個這個對話框
量不到的行數；同樣包一層 `SingleChildScrollView`。

**核對 DLGS 全文時發現 spec 其實有兩張「Restore file」對話框**——
「Restore file to this state」（已實作，就是這個檔案）跟「Restore file
to before this state」（完全沒做，需要新對話框/路由/05-K 子選單/
parent-oid 查詢/可展開 diff/`還原前先 stash` 勾選框）。這不是任務二列的
17 個對話框裡任何一個的範圍，也不是使用者點名要關的「兩個落差」之一，
所以新增 `[DRIFT-restore-before-this-state-missing]` 記錄它，明確寫
「stays open pending a ruling」，不是本輪不做的沉默省略。

11 則新測試（5 Discard Changes + 6 Restore File）；`discard_changes_dialog_test.dart`
兩則因按鈕文案改變而跟著改的既有斷言（tap target 從 `'Discard 2 files'`／
`'Discard changes'` 改成新的檔名式標籤）。

**就地更正**（`81a8d0a`）：上一個 commit（`d94b700`）關閉
`[DRIFT-rebase-onto-missing-capi-flags]` 時寫「`RebaseApiTest.cpp` 是唯一
真的跨過 dart:ffi 邊界的那一層」——重讀 `[TEST-ffi-matches-symbol-only]`
自己的措辭（「only a device-tier test crosses that seam」）確認這句話
是錯的：`RebaseApiTest.cpp` 直接從 C++ 呼叫 `gbm_rebase_start`，從未經過
Dart 的 `lookupFunction`，看不到那一側的參數缺漏。四個 grep pattern 確認
`integration_test/` 完全沒有碰 rebase 的檔案，所以 ffi 那道邊界本身其實
從未被驗證過——就地改寫，補一條 Note 記這個未驗證的缺口，不是刪掉重寫。

### 任務二：G1g（`rename_branch`，`4cf4170`）

`DLGS` 沒有這個對話框的條目，引用來源是 `DIALOGS` 陣列的 note 跟 P13-A
全尺寸 mock。`branch_name_validation.dart`（New Branch／Rename Branch
共用的驗證函式）三則錯誤訊息轉中文；對話框本身：兩個 `ro` 標籤（目前
名稱／新名稱）、欄位 hint、可用性提示、遠端連帶處理整段（label + 兩個
radio 選項的說明文字，逐字引用 P13-A：「push 新名稱，再刪除
$remote/$remoteBranch」／「新分支的 upstream 會清空」）、兩種情境的警告
文字、mid-conflict 拒絕訊息（RENAMEVALID 第 5 列）全部轉中文。
`rename_branch_dialog_test.dart` 7 處既有英文斷言改對應中文；
`integration_test/rename_branch_flow_test.dart` 有一處裝置層 grep 才
抓到的殘留英文引用（`'只改本地，保留遠端舊分支'` 那顆 radio 的文案），
一併修掉。

### 任務二：G1h（`repository_settings`，`f7cd89f`）

四個分頁（General／Remotes／Identity／Performance）的 section header
與內文轉中文；四個分頁名稱本身維持英文——`DIALOGS` 的 note 原文就是用
這四個英文字直接嵌在中文句子裡（「四個分頁：General / Remotes /
Identity / Performance。」），照抄這個既定用法而非另譯。
`COMMIT GRAPH`／`COMMIT-GRAPH` 刻意保留英文，理由跟 `GIT 身份` 一樣：
這是 git 內部物件的專有名稱，不是一般英文詞組。這個對話框先前完全沒有
測試覆蓋，`dialog_copy_test.dart` 新增 6 則涵蓋四個分頁。

### 任務二：G1i（`preferences`，`0128eea`）

六個分頁中五個（Shortcuts 除外）逐段轉中文：section header、
`_SettingSwitch` 的 title/subtitle、`_NumberField` 的 label/suffix、
空狀態文字、tooltip、狀態列文字。六個分頁名稱（`PREFNAV` 已核對與 app
現狀相符）、Close 按鈕、其餘所有按鈕（Add folder…／Rescan now／Clear
list／Check for updates now／Stop skipping／瀏覽…）維持英文。三個主題
名稱（Dark technical／Light IDE／Neutral professional）刻意維持
英文——跟 `theme_switcher_buttons.dart` 的 tooltip 是同一組字面值，那個
檔案不在 G1 的 30 個對話框範圍內，只翻這裡會讓同一組名稱一半中文一半
英文。

「自動 FETCH」段落的文案照 `[DRIFT-auto-fetch-unwired]` 的事實寫，不照抄
spec P11 item 9 那段描述成品行為的 prose，也不照抄舊英文（同樣把功能講得
像已經在動）：改寫成「設定會存，但還沒有計時器真的去執行 fetch」的誠實
語氣——這是 CLAUDE.md 誠實回報的標準規則在文案上的套用，不只是翻譯。
`auto_update_check.dart` 的 `lastAutoCheckLabel()` 一併轉中文（Preferences
直接渲染它的輸出）。CODE 分頁改名「程式碼」後，
`docs/rules/arch-structure.md` 的 `[STRUCT-soft-wrap-preference]` 原本
引用「Preferences → Appearance → CODE」這個字面路徑，跟著就地更新註明。

新增 `[DRIFT-shortcuts-copy-excluded]`：`keyboard_shortcuts_dialog.dart`
跟 Preferences 的 Shortcuts 分頁沒有自己的字面字串，全部從 `gbmMenus`
衍生，翻譯等於翻譯整個選單列（含 macOS 原生選單），是個獨立的裁決，
不屬於 G1 範圍——`dialog_copy_test.dart` 直接斷言這個分頁「維持英文」是
刻意的。

`dialog_copy_test.dart` 新增 'Preferences' group 7 則測試。Mutation-check
兩個實作檔案：`preferences_dialog.dart` 1 個 mutation 窄紅 1 個測試；
`auto_update_check.dart` 1 個 mutation 窄紅 3 個測試（兩個直接呼叫
`lastAutoCheckLabel` 的單元測試 + 一個間接渲染它的 widget 測試，三個都
直接斷言被改動的字串，合理的一對多）。

### 任務二：G1j（`about` / `update` / `manage_base_folders`，`5ac38c4`）

三個對話框都沒有 `DLGS`/`DIALOGS` 可逐字引用，文案自組、語氣比照已核對
過的其他對話框。`about_dialog.dart`：tagline、版本列、技術說明段落轉
中文，`C++ core`／`gbm_capi FFI`／`Flutter UI`／`Riverpod`／`go_router`
等技術詞維持英文。`update_dialog.dart`：`_headline()` 十個狀態、
`_progressLabel()` 三種進度文案全部轉中文。`manage_base_folders_dialog.dart`：
空狀態文字、離線 tooltip、Remove tooltip 轉中文——跟
`preferences_dialog.dart` 的 `_BaseFolderRow` 是各自獨立的私有類別，兩邊
原本的英文離線提示措辭本來就不完全一樣，維持各自措辭。`update_dialog.dart`
刻意不在 `dialog_copy_test.dart` 重複建置覆蓋——它需要複製
`UpdateController` 的假物件跟一整套 provider override，而
`update_dialog_test.dart` 本身已經是 25 個測試、逐狀態斷言精確文案的
專用檔案，這輪已經更新過且全數綠燈；在別處重建同一套機制只是重複驗證。

Mutation-check 三個實作檔案：`about_dialog.dart`／`manage_base_folders_dialog.dart`
各 1 個 mutation 窄紅（分別 2 個、1 個測試）；`update_dialog.dart` 第一次
mutation（句尾加一個字元）完全沒紅——`textContaining('Development
build')` 只檢查子字串存在，句尾修改不影響比對，這是斷言太鬆而不是程式碼
沒有測試，換一個真正落在比對範圍內的 mutation（改動「開發版本」四字
本身）後窄紅 1 個測試。

### 任務二：G1k（`lock_worktree` / `remove_worktree` 殘留收尾，`2126194`）

這兩個檔案本來就已經 80% 中文化，只收尾各自殘留的兩處英文片段：
「This worktree is no longer in the list.」→「這個 worktree 已經不在
清單裡了。」（用字比照同檔案已有的 `worktreeLockWarning()` 句型）；
`Text.rich` 開頭的 `'Worktree  '`（雙空白代替冒號的標籤）改小寫
`'worktree  '`，跟同一個對話框其餘 Chinese prose 裡「worktree」一律
小寫、不譯的既有慣例對齊，而不是發明一個新的中文詞彙——這個字沒有既有
翻譯可查，貿然選一個詞有跟其他地方再度用語不一致的風險。`add_worktree_dialog.dart`
依計畫只需要交叉核對：grep 過殘留的英文字面值只剩按鈕、hint 範例值、
以及 `HEAD` 這個 git 符號 ref 名稱本身，三者都正確維持英文。兩處
mutation-check 各 1 個 mutation、各窄紅 1 個測試。

至此 G1（30 個對話框逐元素中文化）批次 G1a–G1k 全部完成，兩個裁決落差
（Checkout mock delta、Rebase onto capi 旗標）也已關閉。

### 三項任務全部完成：收尾驗證

- `flutter analyze --no-pub`：0 issue（G1k 收尾後重跑仍 0）。
- `flutter test`：G1k 收尾後 2760 通過，0 失敗。
- `python3 scripts/check-rule-pins.py`：172 條規則、70 個交叉引用，
  懸空 0（G1i 新增 `[DRIFT-shortcuts-copy-excluded]` 之後跑過）。
- 核心／capi 測試套件：任務三動到 core/capi，已在任務三自身的驗證段落
  記過（C++ 498/496+2 skip、capi 158/158）；G1 系列（G1d–G1k）只動
  Dart 層文案與少數測試檔案，沒有再次觸碰 core/capi 原始碼，所以沒有
  在每一批之後重跑那兩個套件——這是一個判斷，不是遺漏：唯一動到
  core/capi 的是 Rebase onto 那四個 commit（`e99e64b`／`81c9aa7`／
  `f44e09d`／`d94b700`），它們各自的 commit 已經記錄了自己那次的 C++／
  capi 測試結果（RealRepoTest、capi 層兩則新測試），G1 系列本身沒有
  義務再重跑一次沒被自己改動過的層。
- `integration_test/`：每一批各自 grep 過被改動的字面字串（`grep -F`
  精確比對）與相關 `GbmActionId`／類別名稱，無殘留英文斷言、無裝置層
  引用需要更新。
