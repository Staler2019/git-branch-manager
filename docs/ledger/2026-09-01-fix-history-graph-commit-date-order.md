# 2026-09-01 · fix/history-graph-commit-date-order — 列序照時間、lane 0 真的留給 HEAD、最上方多一列未提交變更

使用者的原話：

> 現在 git history graph 不是將 commit 時間為基礎去排序，有可能會出現 merge 全都集中在最上方的情形

追下去牽出三件事，三件都是真的沒實作，而且共用同一條 lane 0 的線。

## 我一開始的前提是錯的，而且是自己抓到的

我第一版的判斷是「`--topo-order` 會把 merge 擠在頂端」。實際量了以後是**反過來**：
git 的**預設**排序（commit-date priority queue）才會擠，topo 與 date 在 PR 形狀的
repo 上輸出常常一模一樣。我在寫任何 code 之前停下來把這件事回報，而不是照著錯的
理由往下做。

使用者的回答是「實際看到了」。於是改用**可證偽的量測**在使用者自己的 repo 上重跑，
指標是「相鄰兩列的 committer date 逆序次數」：

| 排序 | 列數 | 時間逆序 | 其中落在 merge 列 |
|---|---|---|---|
| `--topo-order`（現況） | 835 | **15** | 7 |
| `--date-order` | 835 | **0** | 0 |

這才是「merge 全擠在最上方」的真身：不是 merge 被搬到頂端，是 topo 為了走完一條
分支，把較新的 trunk commit 排到較舊的支線 commit **下面**，而 merge 列是分支切換
點，所以逆序最容易落在它們身上。

過程中我還說錯過一次——「在你自己的 repo 上，這個改動看不出任何差別」。那是只比對了
前 25 列得出的，全長比對後是上表。就地更正，不繞。

決定性的理由是欄位：History 的 Date 欄畫的是 `row.commitTime`（`commit_row.dart`），
而它來自 rev-list 的 `--timestamp`，就是 committer date。`--date-order` 排的正是那個
數字。原本的狀態是「有 Date 欄、但列序不照 Date 欄」。因此**不用
`--author-date-order`**——它排另一個時間戳，會讓兩者以更難察覺的方式再度脫節。

```
現況 --topo-order                    改成 --date-order
*   00:10 MERGE feat2                *   00:10 MERGE feat2
|\                                   |\
| * 00:08 f2-b                       * \   00:09 MERGE feat1
| * 00:05 f2-a                       |\ \
* |   00:09 MERGE feat1              | | * 00:08 f2-b
|\ \                                 * | | 00:07 m4
| * | 00:06 f1-b                     | * | 00:06 f1-b
| * | 00:03 f1-a                     | | * 00:05 f2-a
* | | 00:07 m4   <- 00:07 排在       | |/
| |/                00:03 下面       |/|
|/|                                  * | 00:04 m3
* | 00:04 m3                         | * 00:03 f1-a
|/                                   |/
* 00:02 m2                           * 00:02 m2
* 00:01 m1                           * 00:01 m1

列序 10,8,5,9,6,3,7,4,2,1            列序 10,9,8,7,6,5,4,3,2,1
     ^^^^ 時間亂序                        等於 Date 欄顯示的時間
```

## 舊註解給的兩個理由，量完都不成立

`HistoryProvider.cpp` 原本寫著「never `--date-order`」，理由有兩條，兩條都檢查過：

**一、streaming**。假的。四組實測，差距全在雜訊內：

| Repo | commit-graph | topo 首列 | date 首列 | topo 全走完 | date 全走完 |
|---|---|---|---|---|---|
| 線性 60,000 commits | 無 | 0.160s | 0.157s | 0.200s | 0.210s |
| 線性 60,000 commits | 有 | **0.010s** | **0.010s** | 0.060s | 0.063s |
| 31,500 commits / 1,501 refs / 1,500 merges | 無 | 0.230s | 0.237s | 0.263s | 0.257s |
| 31,500 commits / 1,501 refs / 1,500 merges | 有 | **0.163s** | **0.160s** | 0.183s | 0.187s |

**二、first-parent 連續性被破壞**。也是假的。lane 佔用靠的是 `laneRefCount_` 的
pending-edge 計數，parent 還沒發出前那一欄一直被佔著；中間插進別的列只會讓線變長，
不會讓它斷。

`docs/ledger.md:1841` 的舊裁定與這兩條同源，一併推翻。
`[GIT-topo-order-unconditional]` 就地改寫：它禁止的是**拿掉** flag，不是在兩個
flag 之間選——兩者都保證 parent 絕不早於 children，`isLinearWalk()` 的 bridge 前提
不變。

## lane 0：spec 寫了，`GraphBuilder.h` 抄了，但沒有人實作

spec P02〈Graph 連線規則〉第一句：

> 目前開發中的分支永遠佔 lane 0，且是一條從頭到尾不轉折的直線。其他分支一律往右
> 配置，轉折全部發生在支線那一側，主線不會為了讓路而歪掉。

`GraphBuilder.h` 的三條不變式是這句的逐句轉述，**第 2 條沒有實作**。實測四種組合：

```
seedRefs 列 feat2 在前，但 main tip 較新 → 第一列是 main   (topo 與 date 皆然)
seedRefs 列 main  在前，但 feat2 tip 較新 → 第一列是 feat2  (topo 與 date 皆然)
```

**決定第一列的是「最新的 tip」，不是參數順序。**所以 `historySeedRefs()`、
`GraphBuilder.h`、`CoreBasicsTest` 三處寫的「the graph builder gives lane 0 to the
first tip it sees, which is how the trunk stays leftmost」當時就是錯的，跟排序改動
無關。三處一起更正。

修法是**保留**而不是搶：`GraphOptions::trunkTip` 在建構時就 `lanes_.reserve(0)`，
`used_` 的 bit 0 一設起，`lowestFreeAtOrAfter()` 自然跳過，不需要新增 `reserved_`
遮罩。`add()` 認領時**兩條路徑都要**——只改 `chooseLane()` 會漏掉真正麻煩的情形：
人在 `main`、有一條比 main 新且是 main 後代的 feature 分支時，HEAD 的 tip 會**帶著
來自 lane 1 的 first-parent 邊**抵達，`chooseLane()` 回 1，lane 0 就永遠沒人認領。

`trunkTip` 只在 `includeRefs` 為空時帶入（`Session.cpp`）：`includeRefs` 非空時
HEAD 的 tip 不保證在結果裡，而一個到不了的保留就是一條永遠空白的欄。那個 if 必須
放在 stale-ref 過濾迴圈**之後**——refs 全部過期的過濾器會退回無過濾走訪。

代價使用者已裁定接受（「照 spec 字面實作」）：**HEAD tip 不是最新時，lane 0 空白的
列數 = 比 HEAD tip 新的 commit 數**。「其他分支一律往右配置」排除了「讓別人暫時
佔用」的做法。

## 為什麼這一段從來沒被審查過

`docs/reports/spec-conformance-matrix.md` 的段落標題是
`## Page 02 — History (16 numbered items)`。審查單位是那 16 個編號元件，而
〈Graph 連線規則〉是同一頁的**散文區塊**，在單位之外。grep 整個 `docs/reports/`
找 `lane 0` / `連線規則` / `永遠佔` 是零命中。

這是 `[SPEC-cell-names-capability]` 再上一層：那裡是格子的證據拿錯東西，這裡是
根本沒有格子。新增 `[SPEC-audit-unit-is-not-the-page]`。

## 未提交變更列

使用者在我準備收尾時說：「lane 0 目前如果有 working copy 佔一個虛擬 commit 在最
上面」。查了：**它不存在**，spec 也沒有（搜過 `未提交` / `虛擬` / `uncommitted` /
`工作區`，命中全在 dialog、pull 錯誤、分頁 badge；`spec_logic.js` 的 History mock
第一列是真 commit）。使用者裁定「本輪一起做」，點擊行為裁定「可選取，但只顯示摘要」。

它和 lane 0 互補：工作區髒的時候，lane 0 從最上面一路是一條**實線**而不是一段空白。

```
HEAD tip 不是最新時（例如剛 fetch 完）

  只做保留              加上未提交列
  lane: 0   1          lane: 0   1
        |   * feat-c         ◇   |          <- 未提交列，佔 lane 0
        |   * feat-b         |   * feat-c
        *   | main-tip       |   * feat-b
        *   | main-1         *   | main-tip <- HEAD
                             *   | main-1
        ^ lane 0 空白         ^ lane 0 是連續的線
```

**沒有走 C++ 合成列。**工作區一變動就要重跑 `publish`，而 publish 是 O(rows)，存檔
時會持續抖動。固定表頭直接吃 `RepoSessionState.workingCopyStatus`，不需要任何走訪，
也因為它不進 `ListView` 而完全不動既有的列索引——`UnfilteredRowIndices` 的 O(1)
恆等視圖正是靠「索引就是列號」成立的。

**選取沒有做成 sealed `HistorySelection`**（計畫的 C6）。實作前先看了一次
`selectedCommitProvider`，發現它**早就**是從 `commitSelectionProvider` 的 anchor
推導出來的了，不是獨立可寫的 provider。所以一個哨兵值
（`kWorkingCopySelectionId`）就保住了單一真相來源，而且遇到它時
`selectedCommitProvider` 回 `null`，既有的 `== null` 閘門一次全部關掉，不需要第二個
誰都可能忘記加的判斷式。C6 因此跳過，churn 少很多。

**搜尋進行中不畫這一列。**查詢一開，`CommitRowColumnPlan.drawsGraph` 就是 false、
底下每一列只剩 12px 空白而沒有 lane（`graph.edges` 連的是未過濾快照的相鄰列）。
此時再畫一顆點與一條往下的連線，正是這顆點自己的註解所禁止的那種假邊。計數在
Working Copy 分頁 badge 上仍在。這一條是 review 時才發現的，不在原計畫裡。

**往下的連線只在清單最上面那一列真的是 HEAD 的 tip 時才畫**——實作者判斷，非使用者
裁定。畫一條連到無關 commit 的線是假的邊，而這裡沒有 `isLinearWalk()` 那種「線段
只代表下一列」的明文授權。

**單純的 ↑/↓ 是新綁的**（`GbmMoveSelectionIntent`）。原本 History 只綁 Shift+↑/↓，
沒有任何單鍵方向鍵移動——全 repo 都沒有。未提交列是繪製順序的第 0 列，所以第一個
commit 按 ↑ 走得到它、按 ↓ 回得來。Shift+↑/↓ 刻意不含它：跨越它的範圍不是 git
重放得了的範圍。spec P13 的 `MULTIKEYS` 沒有單鍵方向鍵那一列，所以這是追加，不是
conformance 項目——與這一列本身同一個身分。

## 計畫裡有一句是錯的，測試檔頭記著

計畫寫「選取未提交列後…cherry-pick / revert / reset here 全部 disabled」。實際
grep `selectedCommitProvider` 的讀取端只有兩個，都是面板。Cherry-pick / Revert /
Reset here 是 commit **右鍵選單**的項目，帶著被右鍵那一列自己的 oid
（`commit_menu_items.dart`），不讀這個 provider——而且那是對的，右鍵指名的是那一列。
真正消失的是全部 05-K 動作，因為它們掛的檔案清單被佔位說明取代了。

後續：這句錯的宣稱曾經被寫進 `history_repository.dart` 的註解裡（列出
「Cherry-pick, Revert, Reset here, Create branch, Create tag, blame, Compare」
七個），已依 [CULT-correct-the-record] 就地更正而不是刪掉——刪掉的話下一輪會從同樣
的直覺再推導一次。順帶查清楚那三個在 spec 的位置，因為「spec 有沒有畫」被質疑過：
**p5「Context menu — 9 種目標、兩層」**的 05-E 頂層 `Cherry-pick` 與 `More actions`
子選單 `Reset branch to here…` / `Revert commit`、**p13「Branch rename dialog 與
多選」**的 `MULTIACTS`（`Cherry-pick / Revert / Squash` 僅連續範圍可用；
`Reset here / Create tag / Create branch` 需要單一目標 commit）、**p6「Dialogs」**
的 `grp: 'B2'` 兩張（`Cherry-pick 4 commits`、`Reset to a1b2c3d`）。三頁都有。

**使用者裁定**：未提交列底下 05-K 不給 dialog、不給功能，「之後有需要再設計」。
這與目前實作一致，記在 [STRUCT-history-uncommitted-row] 裡。

## discard 之後那一列的選取狀態，是一個沒被測到的缺陷

使用者問「有沒有測試把目前 working copy discard 後，wip commit 會移除」。沒有——
八則 widget 測試各自 pump 一個固定的 `pendingFiles`，列在任何一則裡都不可能*停止*
存在，是 [TEST-fixture-cannot-disagree] 第 4 種形狀（cannot shrink）；乾淨那一則是
**另外 pump 一次**，不是同一棵樹上的轉換。

補上兩則之後：「列會消失」本來就綠（行為對，只是沒測），「選著那一列時 discard」
**紅**。`workingCopyRowSelectedProvider` 只看 anchor 是不是哨兵值，所以列被抽走之後
兩個面板繼續替一個乾淨的工作區畫「0 changed files」與 Open in Working Copy。改成
純推導（anchor 是哨兵 **且** `pendingChangeCount > 0`）。不從 widget 清選取，因為
那是在 build 外寫 provider（[FLU-never-write-provider-in-build]），而且會多一個之後
的介面可能忘記加的判斷。搜尋刻意不列入條件：過濾把列藏起來並不會讓摘要變成假的。

## 使用者回報：那條線連一半就斷掉

「uncommit changes 那個 graph 線會連一半斷掉，沒有連線到目前分支的 head」。

一列的 segment 全部由 `graph.edges` 推出來，分數是列高的比例：往下 0.5→1.0、
往上 0.0→0.5、穿過 0.0→1.0。未提交列畫的是**自己那個框**的 0.5→1.0，而它下面
那一列是圖上的第一列，**沒有任何 incoming edge**——畫面上沒有東西是它的 child。
所以 0.0→0.5 從來沒人畫：

```
未提交列   ┌──────────┐
          │    ◇     │  0.5        菱形
          │    │     │  0.5 → 1.0  有畫
          ├──────────┤
commit 0  │          │  0.0 → 0.5  沒人畫 ← 斷掉的那一半
          │    ●     │  0.5        HEAD
          │    │     │  0.5 → 1.0  有畫（連到 parent）
          └──────────┘
```

修在 painter 加一個 `connectsUpToUncommitted`，不是合成一條 `GraphEdge`：假邊的
`childRow` 不存在，而且會流進 `edgesSpanning`、span index 與 ASCII 參考實作，
那三個都不該知道什麼是工作區。

**真正的教訓是那兩個條件本來是各自推導的。**未提交列讀
`visibleOids.first == refs.head.target`，commit 列什麼都沒讀——兩個消費者、兩份
真相，於是各畫各的一半。現在是一個 `connectsToHead` 餵兩邊
（[CULT-single-source-of-truth]）。條件也補上 lane 0：菱形固定在 lane 0，而過濾
中的走訪不帶 `trunkTip` 保留（`Session.cpp` 的閘門），HEAD tip 在別欄時連過去
等於畫一次沒發生的換欄。

**為什麼測試抓不到：兩個 fixture 都沒設 `refs`。**`head.target` 一直是空字串，
所以 `connectsDown` 在原本八則裡全部是 false——這條線有畫的那一半和沒畫的那一半，
兩邊都不被任何測試涵蓋。補上四則之後，四種突變（畫布不畫、只畫到上緣、只給
commit 列、只給 WIP 列）各紅一則，其中「只給 WIP 列」就是原本的缺陷。

**這一輪最有價值的發現是 fixture 本身。**第一版的「列會消失」看起來是綠的、也真的
測到了東西——但把列的 `ref.watch` 突變成 `ref.read`，整檔仍然全綠。原因是 `_state()`
每次呼叫都造一個新的 `GraphSnapshotView`，`repoGraphProvider` 選的就是那個物件，於是
重建是 graph 觸發的，跟工作區無關。把 graph 與 metaCache 提成共用實例、讓兩個狀態
**只有** `workingCopyStatus` 不同之後，同一則突變才紅，而且只紅那一則。這是
[TEST-fixture-cannot-disagree] 的第 10 種形狀，已經寫進表裡。

## 測試

**C1 的 fixture 必須刻意包含「topo 下會逆序」的兩列。**全線性的 fixture 兩種排序
輸出相同，測了等於沒測——本輪一開始就踩到：本 repo 幾乎線性，topo 與 date 前 25 列
完全一樣。最後的 fixture 是交錯時間戳 + 兩個 merge，斷言各列 `commitTime` 單調不增。

**C3 的 fixture 若讓 trunk tip 當第 0 列，改動前就會綠**（`[TEST-fixture-cannot-disagree]`
第 1、5 種形狀）。所以 `trunkTip` 指的是**不是**第 0 列的 commit，並且另有一則讓它
帶著 incoming 邊抵達。

**容器接縫是靠整合測試才蓋到的。**先寫的兩則面板測試是手餵參數的
（`CommitDetailPanelCore` / `ChangedFilesPanelCore`），只證明兩張臉畫得出來，不證明
有任何東西產生得出那些參數。把 `ChangedFilesPanel` 的 `workingCopySelected` 釘成
`false`、把 `CommitDetailPanel` 的 `uncommittedChangeCount` 釘成 `null`，兩次突變
都**只紅整合測試，widget 層照樣全綠**——這正是 `[TEST-new-gate-needs-integration]`
講的那條縫。

**佔位說明靠的是旗標不是空清單。**`commitFilesProvider` 這時還留著上一個 commit 的
檔案清單（History 不會對一個沒有 oid 的列去要 diff-tree），所以整合測試刻意讓那份
清單非空，再斷言它被藏住。

**一次突變沒套用上，被 `count(old) == 1` 擋下來。**`dart format` 把
`workingCopySelected: ref.watch(...)` 重排成一行，我照原始縮排寫的 anchor 因此匹配
零次。那一輪的「All tests passed」其實是未突變的 code 跑出來的，等於什麼都沒驗到。
`[TEST-mutation-check-every-test]` 早就寫了先斷言命中數——這是它第二次救場。

九則新突變全部窄紅（各只紅 1–2 則，且紅的就是該則）。全套 2,368 綠、
`flutter analyze` 零問題。

## 改了什麼

| 檔案 | 動作 |
|---|---|
| `src/core/git/HistoryProvider.cpp` | `--date-order`；改寫「never `--date-order`」整段理由；`walk()` 改用 `GraphBuilder builder(GraphOptions{...})` |
| `src/core/git/HistoryProvider.h` | **刪** orphan 的 `bool dateOrder`；新增 `HistoryQuery::trunkTip`；`seedRefs` 與 `isLinearWalk()` 的註解更正 |
| `src/core/graph/LaneAllocator.h` | 新增公開 `reserve(LaneId)` |
| `src/core/graph/GraphBuilder.h` | `GraphOptions::trunkTip`；第 2 條不變式補上 spec 出處 |
| `src/core/graph/GraphBuilder.cpp` | 建構時 `reserve(0)`；`add()` 三條路徑 + 外提的釋放迴圈 |
| `src/capi/Session.cpp` | `query.trunkTip = refs->head.target`，僅在 `includeRefs` 為空時，且在 stale-ref 過濾之後 |
| `app_flutter/lib/data/models/working_copy_status.dart` | 新增 `pendingChangeCount`，收斂三個呼叫端 |
| `app_flutter/lib/data/repositories/history_repository.dart` | `kWorkingCopySelectionId`、`workingCopyRowSelectedProvider`、`selectedCommitProvider` 認哨兵 |
| `app_flutter/lib/features/history_graph/widgets/working_copy_row.dart` | **新增** `HistoryWorkingCopyRow` |
| `app_flutter/lib/features/history_graph/commit_graph_view.dart` | 表頭掛在 `ListView` 上方；`_moveSelection` / `_revealListIndex`；搜尋時抑制 |
| `app_flutter/lib/actions/gbm_selection_gesture.dart` | 新增 `GbmMoveSelectionIntent` |
| `app_flutter/lib/features/history_graph/widgets/commit_detail_panel.dart` | 摘要狀態 + 「Open in Working Copy」 |
| `app_flutter/lib/features/history_graph/widgets/changed_files_panel.dart` | 指向 Working Copy 的佔位說明 |
