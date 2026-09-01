# 2026-09-01 · claude/windows-uncommitted-changes-5z40sr — History 未提交列的 HEAD 連線在 Windows 上永遠不畫

使用者的原話：

> on windows uncommitted changes have no lines connect to current local branch

問了兩個問題確認範圍：連線是每次都斷，還是偶爾斷；Windows 上是否還有別的工具同時碰這個
repo。回答是「every time」，以及「fork and ide other」——連線每次都不見，同時開著 Fork
（另一套 git GUI）和 IDE。Working Copy 重新整理、commit 列表本身都正常，只有這條連線
永遠不畫。

這條連線是 [STRUCT-history-uncommitted-row] 記的那個功能：History 最上方那顆代表未提交
變更的空心菱形，往下接到 HEAD 那顆 commit 圓點的線。畫不畫完全由
`commit_list_render.dart` 的一個布林值決定：

```dart
connectsToHead:
    showWorkingCopyRow &&
    visibleRows.isNotEmpty &&
    visibleOids.isNotEmpty &&
    visibleOids.first == refs.head.target &&
    graph.rows[visibleRows.first].lane == 0,
```

## 排除 Dart 端

兩輪 Explore agent 分別查了：CRLF 有沒有可能讓 `head.target` 帶上一個殘留的 `\r`（沒有——
`ProcessRunner.cpp` 的 `LineSplitter` 在每一個 `\n` 前面都會去尾的 `\r`，三個平台共用同一
段程式碼，沒有 `#ifdef`）；有沒有平台條件式碰到 ref 讀取、排序或 lane 分配（grep 遍
`Platform.isWindows`/`#if defined(_WIN32)`，命中的全是路徑處理、DLL 檔名、選單樣式，沒有
一個碰 History 這條路徑）；connector 的線寬、DPI 有沒有已知的 Windows 渲染問題（沒有
ledger 紀錄可查）。第二輪還發現一個有用的反證：如果 `head.target` 整體壞掉，History 的
HEAD ref chip（`graph_ref_chips.dart` 的 `isHead`）應該也會跟著錯位，但使用者沒回報這
個——這把懷疑的方向從「字串本身壞了」推向「兩次讀到的不是同一個時間點」。

## C++ 端找到的兩個真缺陷

**缺陷一（TOCTOU）**：`Session::dispatchRefresh()`（`src/capi/Session.cpp`）在同一次背景
工作裡依序跑三個獨立的 git 行程——`refStore_->load()` 內部的 `readHead()`
（一次 `rev-parse --revs-only HEAD --symbolic-full-name HEAD`），接著同一個 `load()` 裡的
`for-each-ref`，最後才是 `history_->walk()` 自己的 `rev-list`。`query.trunkTip` 原本直接
沿用第一步讀到的 `head.target`，但 `rev-list` 用的 seed 是 `historySeedRefs()` 給的**分支
名稱**（`refs/heads/main`），會在自己真正執行的當下重新解析成當時的 tip。兩次讀取之間，
只要分支 tip 被別的東西移動過（另一個工具碰這個 repo），`GraphBuilder::add()` 的
`oid == options_.trunkTip` 就會對不上，lane 0 的保留位永遠等不到真正的 tip 來認領，連線的
兩個條件（oid 相等、lane == 0）會同時失敗——這正好對得上「連線整條消失」而不是「斷一半」
的症狀。這個時間窗在任何平台都存在，但 `docs/reports/windows-process-cost.md` 量過：
Windows 上開一個 git 行程比 Linux/macOS 貴了大約兩個數量級，窗口自然寬得多。

**缺陷二（readHead 的失敗語意）**：`RefStore::readHead()`（`src/core/git/RefStore.cpp`）
原本的判斷是 `if (resolved && !resolved->out.empty())`——把「指令真的跑失敗」和「指令跑
成功、但空 repo 沒有 HEAD 可解」混成同一條路徑。前者理當是 `GitResult` 失敗，後者才是
`--revs-only` 文件本來就講的正常狀態。一旦第一種情況發生，`head.target` 會被永久靜默地
留在 null，往後每次 refresh 都一樣，操作紀錄裡完全看不出任何線索。

兩個缺陷都值得修，不管哪一個才是這次回報的真正成因。

## 修法

**修法一**：在 `dispatchRefresh()` 裡，`query.trunkTip` 改成緊接在 `history_->walk()` 之前
再讀一次 `refStore_->readHead(token)`，把 `for-each-ref` 那整段時間從窗口裡拿掉，只剩
「背靠背的 rev-parse 和 rev-list，中間沒有其他事情」。這次重讀失敗時退回原本快照的值，
不讓一個純粹裝飾連線的重試把整趟 history walk 也賠進去。`refs_`／`REFS_UPDATED`（給
sidebar、Working Copy 面板看的）完全不受影響，只有內部用來 seed walk 的值換了來源。

**修法二**：把 `readHead()` 的判斷拆開——`resolved` 為假就 `return fail(...)`，只有
`resolved` 為真但輸出是空的，才算是真正的「還沒有 commit」。`Session::open()` 從不呼叫
`readHead()`／`load()`（只有非同步的 refresh 路徑會），所以讓這個失敗真正傳播出去，不會
擋到 repo 的開啟；`dispatchRefresh()` 本來就有「`load()` 失敗就發 `GBM_EVENT_ERROR_OCCURRED`
然後跳過這輪 walk」的路徑，這只是多一個會走到那條路的原因。

## 改測試時，兩個既有前提都撞到了

改完才發現，`tests/unit/RefStoreHeadTest.cpp` 的 `AFailedGitStillLeavesAUsableUnbornHead`
斷言的正是修法二要推翻的行為，註解寫著「a repository that cannot answer still has to
open」。追了 `readHead()` 的三個呼叫點（`RefStore::load()`、
`OperationRunner::recordUndoPoint()`、`UndoOps.cpp`），沒有一個是在 `Session::open()`
的同步路徑上——這個前提在目前的架構下不成立。就地改寫，不是刪掉：改名為
`AFailedRevParsePropagatesAsAFailureRatherThanUnborn`，斷言翻成 `ASSERT_FALSE`，並補上
`ATimedOutRevParsePropagatesAsAFailure`。

同一輪還測出 `tests/unit/ProcessRunnerTest.cpp` 的 `RefStore.TreatsAnUnbornHeadAsANormalState`
也撞到——它的 fixture 用 `exitCode = 1` 模擬「HEAD 解不出來」，但 `--revs-only` 的真實行為
是 exit 0、空輸出，`exitCode = 1` 其實是在測「指令真的失敗」，只是套著錯的標籤。改成
`FakeProcessRunner::Response{}`（exit 0、空輸出）之後，測試繼續驗證原本要驗證的事（空
repo 能正常開），只是 fixture 誠實了。

## mutation test 抓到自己寫壞的第三個測試

照 [TEST-mutation-check-every-test] 的規矩，把兩個修法各自還原一次，確認新測試會變紅。
修法一還原後，`RefreshReReadsHeadFreshImmediatelyBeforeTheWalk` 從 2 掉到 1，如預期。

修法二還原後，`RefStoreHeadTest.cpp` 的兩個新測試正確變紅；但我原本規劃的
capi 層測試——把 `.git/HEAD` 搬走，期待只有 `readHead()` 失敗——在修法二還原之後**仍然
綠燈**。動手用真的 git repo 探了一次才知道為什麼：

```
$ mv .git/HEAD .git/HEAD.bak
$ git rev-parse --revs-only HEAD --symbolic-full-name HEAD
fatal: not a git repository (or any of the parent directories): .git
$ git for-each-ref --format='%(refname)'
fatal: not a git repository (or any of the parent directories): .git
$ git symbolic-ref --quiet HEAD
fatal: not a git repository (or any of the parent directories): .git
```

HEAD 檔案一旦不見，git 判定整個 `.git` 目錄不是一個合法的 repo，三個指令全部同樣失敗——
不存在「只有 rev-parse 失敗、for-each-ref 還活著」這種狀態可以靠真的 repo 造出來。也就是
說，這個 capi 測試不管修法二在不在，都會因為 `for-each-ref` 自己的失敗路徑（修法二之前就
已經存在、正確運作的路徑）而通過，它從頭到尾沒有在測我以為自己在測的東西。

就地更正，不是刪掉：改名為 `ALoadFailureDuringRefreshEmitsAnErrorAndRecoversNextCycle`，
註解誠實寫明它驗證的是「`load()` 失敗不會卡死 refresh」這個更通用、確實有價值的性質，
而修法二本身的字面行為（rev-parse 失敗、for-each-ref 還正常）只有
`RefStoreHeadTest.cpp` 那兩個用 `FakeProcessRunner` 的單元測試才測得到，因為只有那裡才能
把兩個指令的回應分開腳本化。

## 驗證

`gbm_core_tests`：465 個測試，462 通過、3 個環境限定跳過（無關）。
`gbm_capi_tests`：147 個測試全數通過。兩個修法互相還原時，對應測試如預期變紅。

## 留白

這一輪沒有、也無法在這個環境裡於真正的 Windows 機器上重現原始症狀——診斷完全建立在讀
程式碼、量測 `docs/reports/windows-process-cost.md` 記的數字、以及對真實 git repo 動手驗證
之上。兩個修法都是獨立成立的正確性/穩健性修正，但要確認這就是使用者回報的成因，還是得
請使用者在 Windows 上（Fork、IDE 都開著）重新試一次。

另外記錄一個範圍外、比較少見的殘留：如果 HEAD 在 refresh 中途被切換到**完全不同**的分支
（不只是同一分支多了新 commit），`query.seedRefs` 的 HEAD 項目本身也可能跟不上——這不是
這次症狀的成因，修起來要動到 `historySeedRefs()` 選 trunk 名稱的邏輯，不只是一個 oid，
留給之後有需要再處理。
