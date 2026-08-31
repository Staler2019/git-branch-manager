# 2026-08-31 · docs/split-rules-for-parallel-rounds — 讓兩條分支不再改到同一行

使用者的原話是「cause cannot parallel contribution because of the raw texts of
string」。症狀是每輪都在同兩個檔案上撞車，而這件事這份 ledger 自己記錄過，在
「Sidebar continuation」那一節：

> The only conflict was `docs/ledger.md`, and it was structural rather than
> semantic: both branches append a new section at the end, so git saw one
> region replaced two ways.

## 起點的量測

| 檔案 | 行數 | 大小 | 形狀 |
|---|---|---|---|
| `CLAUDE.md` | 1,742 | 116 KB | 硬斷行散文（中位 74 字元、p90 78），Invariants 一節就 916 行 / 62 KB，111 條 bullet 帶 988 行接續行 |
| `docs/ledger.md` | 5,923 | 378 KB | 101 輪，全部 append 在檔尾 |

三個彼此獨立的衝突機制，分開修才修得掉：硬斷行讓一個字的改動變成整段重排；
單一巨檔讓兩條分支必然改到同一個區域；ledger 只有一個 append 點。

## 使用者的兩個裁定，以及它們推翻了什麼

計畫原本是「原文照搬、只改斷行」。使用者的回答改掉了兩件事：

1. **三層結構**：`claude.md > {function/arch/...}.md > ledger{date,branch}.md`，
   而且「branch name 太隨機，不好紀錄，應該加上日期標注」，由中層規則檔向下連接
   決策紀錄。
2. **「規則要集中存放，不跟決策的長紀錄混在一起。然後剪短書寫、精確語意，並且
   reference 決策紀錄。」** —— 這一條推翻了原文照搬：規則要**改寫成短句**，長篇證據
   留在 ledger。

pin 形式使用者沒選，實作採語意 slug（`[FLU-postframe-no-frame]`）而非流水號：
流水號只是把衝突從內文搬到編號上，兩條分支同時新增各自都會拿到 `036`。

## 結果

`CLAUDE.md` 1,742 → **104 行**，內容全部搬進 `docs/rules/` 的 16 個檔案，共
**145 條規則**，每條四欄（Rule / Consequence / Do / Evidence）。

## 每一步都被驗證過，而驗證抓到了東西

**`@import` 是先驗證才繼續的。** 這是整個計畫最壞的失敗模式：靜默失效等於整份規則
從所有未來 session 消失。放一個 `_probe.md`、commit、用無頭 session 問：

```
$ claude -p "Quote the Rule line of [PROBE-import-works] verbatim..."
已載入。[PROBE-import-works] 的 Rule 行逐字如下：...
```

載得到才往下搬，確認後刪掉探針。

**不失真檢查抓到一個真的疏漏。** 每個類別搬完都跑一次腳本：把舊小節裡所有具體事實
（code span、檔名、版號、issue 號、量測數字）抽出來，每一個都必須在新規則檔或
`docs/ledger.md` 裡找得到。refs／git 那一節第一次跑是「缺 1」——
`RepoSessionController.refreshRepoStatus()` 的類別前綴被我寫掉了。補回後缺 0。
七個類別合計檢查 640 個具體事實。

**檢查腳本自己也錯過兩次，兩次都是誤報。** 第一次：原文是硬斷行的，
`edge.lane ==\n  rows[parentRow].lane` 這種被折成兩行的 code span 被判成弄丟了，
比對前要先正規化空白。第二次：README 的格式範例寫在 ```markdown 圍籬裡，
`[FLU-036]`（一個「不要這樣做」的示例）被當成真的規則定義，判成重複 pin。
兩次都是工具太天真，不是內容有問題——但如果沒有回頭重跑修好的腳本，
就會把「缺 1」當成事實留在紀錄裡。

**arch-\* 不套剪短紀律，而且這是刻意的。** 路由樹、`RepoSessionState` 欄位表、
34 個 FFI 事件表是現況參照，不是證據型敘事：沒有對應的 ledger 句子可回查，
也沒有敘事可以剪。這兩檔整塊搬、表格不重排，改用逐行比對驗證
（結構 193 行、狀態機 232 行、UX 41 行，全部與搬移前逐行相同）。
如果硬把紀律套上去，有三分之一的 commit 會拿到一條做不到的規則。

## 剪短時做的判斷

不是機械地砍字，幾處是把原文裡本來就存在、但被埋住的結構拉出來：

- **九種「無法反駁程式碼的 fixture」改成表格。** 原本是一條 40 行的 bullet，
  一句接一句堆到第九種。表格一種一列，新增第十種就是加一列——兩條分支各發現一種，
  也只碰各自那一列。每列保留「案例」與「為什麼會綠」，那才是能認出同型錯誤的部分。
- **`SelectionArea` 的三個 trap 各自一行**，後面接原文自己寫下、但被埋在段尾的更正
  （「不要把 trap 2 讀成固定槽位的理由，那不是設計」）。
- **拆開兩條結論相反的規則**：「觸控板」與 `dragDevices`，一條講輸入裝置種類、
  一條講 Scrollable 會不會跟拖曳搶手勢，原本連在同一段。
- **05-C 只適用 remote-only 列**從 context-menu 那一大段裡拉出來獨立成條——
  它是被記過的實際缺陷，不該藏在別條的段落中間。

## 拆檔逼出來的交叉引用

原文有兩處靠排版順序才成立的相對引用（「see the counterpart entry below」、
「the fetch auto-prune entry above」），拆檔後必然失效，改成 pin。
另外還有一批「像側邊欄那次一樣」「和 `isActionEnabled()` 當證據是同型錯誤」——
這種跨條目的類比原本靠讀者記得，現在靠 pin 撐著。最後 145 條規則、13 個交叉引用、
懸空 0。

過程中自己也製造過一個懸空引用：`ops-ux-rubric.md` 引了 `[CULT-filing-rule]`，
但那條規則的家其實在 CLAUDE.md 的「Where a round's write-up goes」，pin 從來不存在。
是 pin 檢查腳本抓到的。

## 明寫的取捨

**舊的 101 輪凍結在 `docs/ledger.md` 原地，沒有搬。** 衝突來自 append 點而不是既有
內容，歷史不會再被 append，所以它不會再衝突。而這份檔案的前言把兩件事講成載重的：
「a record you can checksum」與「above/below 相對交叉引用只在順序完整時才解析」，
拆檔會同時打斷這兩件。已用 diff 驗證 101 輪 byte-identical，只有「Adding a round」
一節被改寫成「不在這裡了」。

**`UX Goals` 的分數軌跡移出 CLAUDE.md**，因為依 CLAUDE.md 自己的收納規則，
「Round 0 假設了什麼、Round 1 改了什麼」只有在「第 N 輪發生什麼」的語境下才成立。
新的 ledger 檔用真實日期，不是編出來的：`git log -S'Score trajectory'` 指出是
2026-08-13、commit `9b3ff16`、PR #34。

## 沒有動到的東西

`app_flutter/`、`src/` 一行都沒改。49 個引用 `CLAUDE.md` 的原始碼註解全部保留：
它們寫的是「CLAUDE.md records X」，沒有行號，而 CLAUDE.md 仍然是自動載入的規則集合，
只是內文改由 `@import` 帶入。CLAUDE.md 檔尾補了一段 redirect 說明這件事——
比照這份 ledger 當初從 CLAUDE.md 搬出來時留下的同形段落。
