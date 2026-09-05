# 2026-09-05 · fix/partial-branch-delete-no-refresh — 部分成功的刪除不刷新，只有側邊欄按鈕那條路看得到

使用者的原話：

> sidebar branches, when use the button on the side bar (not in the branch context) would
> not refresh after delete is affect

一句話裡有兩個關鍵字，而且都是對的：**button**（不是右鍵）跟 **after delete is
affect**（刪除真的生效了）。這兩個字合起來就是整個缺陷。

## 不對稱在哪裡

兩條路走的是同一個 controller method：

```
側邊欄多選 Delete 按鈕 ──→ /dialogs/delete-branches ──┐
                                                      ├──→ notifier.deleteBranch(names: […])
分支右鍵 Delete branch… ─→ /dialogs/delete-branch  ──┘
```

同一個方法、同一個 capi、同一個 operation。所以差別不可能在派送，只可能在**結果的形狀**：

- 單一分支刪除是**全有全無**：成功就刷新，失敗就什麼都沒刪。
- 多分支刪除會**部分成功**，而部分成功在核心裡被算成失敗。

`git branch -d` 是 per-name 的，這件事 [GIT-branch-d-partially-succeeds] 早就記了。本輪
在 scratch repo 重新量一次，確認形狀沒變（git 2.x，merged + unmerged 各一）：

```
$ git branch -d merged-branch unmerged-branch
error: the branch 'unmerged-branch' is not fully merged
Deleted branch merged-branch (was cdefaf2).      ← 真的刪掉了
exit=1                                            ← 但整體 exit 1

$ git for-each-ref --format='%(refname:short)' refs/heads
main
unmerged-branch                                   ← merged-branch 不在了
```

## 證據鏈四段，每一段都在原始碼裡

```
git branch -d a b          a 刪掉、b 拒絕、exit 1
        │
        ▼
DeleteBranchOperation      before/after 探測算出 deleted={a}
(ops/BranchOps.cpp)        ── 但只拿去寫 summary「Deleted a. b: …」
                           outcome.succeeded 仍然是 false
        │
        ▼
Session::submitOperation   refreshWorkingCopy();                    ← 無條件
(capi/Session.cpp)         if (succeeded && refreshHistoryOnSuccess) ← refs/graph 卡在這
                               refreshHistory();
        │
        ▼
Dart operationFinished     _readRepoState() / _readUndoJournal()
(repo_session_repository)  沒有任何 refs 刷新
        │
        ▼
側邊欄                      繼續畫著 git 已經刪掉的分支
```

核心**知道**哪些分支真的沒了——`deleted` 這個 vector 就在那裡——只是那個知識只走進了
訊息字串，沒走進刷新決策。

## 修法：把既有的探測結果多用一次

`OperationOutcome` 加一個 `mutatedRefs`，`DeleteBranchOperation` 依 `!deleted.empty()`
設定，`submitOperation` 改讀 `succeeded || outcome.mutatedRefs`。

三個刻意的選擇：

1. **證據導向，不是推測**。`deleted` 為空有兩種意思——「什麼都沒刪」或「探測本身失敗、
   看不出來」——兩種都不構成「repo 變了」的宣稱。這是
   [STATE-never-guess-what-git-would-say] 用在刷新決策上的同一條紀律。
2. **不序列化**。決策發生在 `toJson(outcome)` 之前、Session 自己的 completion callback
   裡，Dart 端沒有讀者。放進 wire 就是 [CULT-orphan-wiring] 第九例（`ParsedDiff.truncated`）
   的重演——一個跨過 FFI 邊界、對面沒人讀的欄位。欄位註解裡寫死了這句話。
3. **保留與 `refreshHistoryOnSuccess` 的 AND**。本來就不刷新歷史的操作種類，不會因為
   多了這個旗標就開始刷新；`mutatedRefs` 只能讓「本來成功才刷」變成「有變動就刷」。

被否決的作法（使用者裁定）：

- **Option B — 任何操作失敗都無條件刷新**。一行改完、涵蓋所有未知的部分失敗（含 rebase
  衝突移動 HEAD），代價是每次失敗都多付一次 refs+history walk，而換到的覆蓋是推測性的、
  沒有任何回報。裁定：否決，只修 delete-branch。
- **遠端刪除那半一起補 probe**。`git push origin --delete a b c` 同樣會部分成功，但那條
  路沒有 before/after 探測，拿不到證據；補 probe 要多一次網路往返。裁定：這輪只修本地，
  遠端留待日後，並就地記進 [GIT-branch-d-partially-succeeds] 免得被下一輪當成漏掉的。

## 測試放在 capi 層，因為別的層表達不出這個失敗條件

Dart 的 fake seam 根本不跑 C++（[TEST-fake-session-seam]），任何 widget／integration 測試
都無法表達「C++ 沒有發出刷新事件」——這是 [TEST-fixture-cannot-disagree] 第 11 種形狀
（fixture 表達不出失敗條件）在另一個語言邊界上的同一件事。

`BranchApiTest.APartiallySuccessfulDeleteStillRefreshesRefs` 的形狀：

```
merged-branch（已合併）+ unmerged-branch（未合併）
        │
gbm_history_refresh(session_)        ← 先墊一次刷新，否則「有沒有 refs 事件」在派送前就成立
        │
gbm_branch_delete([both], force=0)
        │
斷言前提：succeeded=false ∧ merged-branch 已不在 ∧ unmerged-branch 還在
斷言主張：REFS_UPDATED 出現在 OPERATION_FINISHED 之後
```

**順序才是能夠反對程式碼的那一半。** 只斷言「log 裡有 REFS_UPDATED」不行，因為測試自己
先發了一次；能夠翻紅的是「在 operation 完成之後又來了一次」。

寫測試時我先假設 `gbm_session_open` 自己會發一次 REFS_UPDATED，第一次跑就紅在
`waitForInitialRefsUpdated()` 上——core 根本不會在 open 時刷新，是 Dart 那層開完 session
之後自己要一次的。前提錯了就地改掉，註解也一併改成事實。

紅燈那一跑，三個前提斷言全綠、只有最後一句紅——紅得剛好落在缺陷上，沒有寬到別的東西上。

### Mutation check

兩次 mutation，各紅 1 個測試（**mutations-run = 2，tests-reddened = 1 + 1**）：

| # | Mutation | 位置 | 紅 |
|---|---|---|---|
| 1 | `changedRefs = succeeded \|\| outcome.mutatedRefs` → `= succeeded` | 消費端 | 1（161 中 160 綠） |
| 2 | `outcome.mutatedRefs = !deleted.empty()` → `= false` | 生產端 | 1（161 中 160 綠） |

第一次的 mutation 我寫成直接把 `changedRefs` 換掉不用，結果 `-Werror` 的 unused
variable 讓建置失敗，跑到的是**沒有 mutate 過的舊二進位檔**，還回報了「161 全綠」。
建置那行 `ninja: build stopped: subcommand failed` 就印在測試輸出上面。改成仍然使用該變數
的形式之後才是真的 mutation。**建置有沒有成功，是讀 mutation 結果之前要先看的東西**——
這是 [TEST-mutation-check-every-test]「REDS=0 不等於測試是空的」的另一面：REDS=0 也可能
只是跑到舊的二進位檔。

### 全套結果

- `gbm_capi_tests`：161 / 161 綠
- `gbm_core_tests`：500 綠，2 skip（LFS 兩個，機器上沒有 git-lfs，既有狀態）

## 順手查過但不是缺陷的

- **側邊欄選取殘留**：refs 刷新後那些列會消失，`_selection` 卻還握著已刪的名字。查過
  `sidebar_panel.dart` 已有 `prunedSelection`，這條已經處理，不用動。
- **Dart 端要不要也補刷新**：不需要，也不應該。刷新是 core 的責任，在 Dart 再補一次會變成
  兩個來源（[CULT-single-source-of-truth]），而且 Dart 讀不到 `deleted`，只能猜。

## 沒有做的

- **裝置層**：`app_flutter/integration_test/` 沒有任何檔案走到分支刪除。照
  [TEST-grep-misses-intent-driven-device-tests] 從四個方向 grep——widget／label
  （`Delete branch`）、controller method（`deleteBranch`）、action id
  （`branchDeleteBranch`）、route（`delete-branch`）——全數無命中；`delete` 的命中全是
  fixture 的 `deleteTempGitRepo` teardown。所以沒有現成裝置測試可跑或可延伸，照
  [TEST-device-tier-not-in-ci] 記下來，而不是留成「應該沒影響」的默認。
- **實機確認**：這輪的驗證止於 capi 測試。要在真的 app 上看到症狀消失，需要 merged +
  unmerged 混選的 repo；沒有做，也不宣稱做過。
