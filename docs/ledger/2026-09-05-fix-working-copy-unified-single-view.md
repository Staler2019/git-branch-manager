# 2026-09-05 · fix/working-copy-unified-single-view — unified 合成一份清單，未追蹤檔案 unstage 回到 Untracked

使用者回報兩件事，一句話兩點：

> problems: 1. untracked, use line stage all, and unstage all back, the file should not
> leave in staged list 2. unified 可能本來就做錯了，應該是單一 view 檢視 stage/unstage
> scope and button. 而非還是拆成上下檢視。先更新spec再工作

第 2 點推翻的不是 spec，是**我自己上一輪畫的設計**。
[feat/working-copy-vertical-file-lists](2026-09-05-feat-working-copy-vertical-file-lists.md)
把 diff 預設改成 `unified`，而那個 `unified` 是兩個 `ScopedDiffView` 上下疊起來 ——
把使用者剛抱怨過的兩欄轉九十度，不是合併。

```
出貨的 unified                          這一輪的 unified
┌──────────────────────────────┐        ┌──────────────────────────────┐
│ ● Unstaged        [2 個scope]│        │ a.dart   2 未暫存 · 1 已暫存 │
│   @@ -1,4 +1,5 @@            │        │   @@ -1,4 +1,5 @@            │
│   ┃ 變更1        [Stage 1]   │        │   ┃ ● 變更1      [Stage 1]   │  ← index 1
│──────────────────────────────│        │   @@ -50,2 +50,3 @@          │
│ ● Staged          [1 個scope]│        │   ┃ ● 變更2      [Unstage 1] │  ← index 50
│   @@ -50,2 +50,3 @@          │        │   @@ -100,2 +100,3 @@        │
│   ┃ 變更1        [Unstage 1] │        │   ┃ ● 變更3      [Stage 1]   │  ← index 100
└──────────────────────────────┘        └──────────────────────────────┘
  兩個 view、兩個欄標頭                    一個 view、一份清單、依區域排序
  方向 = 你在上半還是下半                  方向 = 卡片自己的左緣色＋圓點＋動詞
```

## Phase A — 先更新 spec

使用者的程序要求跟上一輪同一句：「先更新 spec 再工作」。所以
`docs/claude-design-demo/working-copy-layout-spec.html` 加了兩節，發佈到同一個 URL
（`71df5909-…`），停下來等裁定。全頁另外照使用者要求改成中文
（「你幫我換中文可以嗎，這樣看有點痛苦」），只留程式碼識別字、pin 名稱與引述原文。

### §10 —— `unified` 其實還是兩個 view

就地劃掉 §02 自己畫的那張 Proposed mockup（`[CULT-correct-the-record]`），因為那張圖
就是上下兩段。九題待裁定，附建議。

**其中一題我自己的建議被同一次稽核推翻，過程留在頁面上。** U1（一份清單依什麼排序）
我原本建議「先全部 unstaged 卡片、再全部 staged 卡片」，但重讀
`[SPEC-demo-dom-is-the-spec]` 的 block 1 註解，它明文禁止的正是那個方向。頁面上把推導攤
開來寫，而不是默默換掉建議 —— 一個翻過盤的建議對讀的人價值比較高。

### §11 —— 未追蹤檔案的 unstage

**成因是量出來的，不是推出來的。** 計畫裡列了三種可能的落點，各自對應不同修法；在
scratchpad 開臨時 repo 逐步跑，落在 (a)：

| 步驟 | 結果 |
|---|---|
| `git apply --cached` 整份 patch | exit 0，porcelain `1 A. …` |
| 以 staged diff 建純 `a/<path>` 反向 patch，`git apply --cached --reverse` | **exit 0** |
| `git status --porcelain=v2` | 仍然 `1 AM …`，index 條目留著、blob 是空的 `e69de29` |
| `git rm --cached`（計畫裡提的修法） | **exit 1，被拒絕** |
| `git restore --staged` | exit 0，回到 `?` |

所以計畫自己提的 `git rm --cached` 被量掉了。

## 裁定

使用者一句帶過其餘八題，另外劃了一條範圍線：

> u1我覺得修改一下，我要對其的不是行號，是git判斷出的區域變更，每個區塊會是一個scope，
> 然後unstage, stage必定是不同scope

> 其他照建議，u9不應動，照既有模式維持。這次只改unified內

> 我沒講清楚，u8影響樣式應該要跟2 file模式相同，所以應該要一起動，這是唯一會影響到2file的

U1 這句同時解掉了我解不掉的一個矛盾：block 1 禁止**硬對齊**，是因為把兩份 diff 的
*列*對齊等於宣稱它們是同一行；而排序**區域**只宣稱某個區域排在另一個之前，這件事在兩份
diff 本來就共用的 index 座標裡是真的。所以既不必退回分組（那會把對同樣幾行的兩次編輯用
整個檔案的長度隔開），也沒有製造出 block 1 擔心的錯覺。

第三句是對第二句的更正，所以 §10 的 U6「一行都不改」也照
`[CULT-correct-the-record]` 就地劃掉重寫成「版面與行為一行都不改」—— 那句已經被引用過一
次，悄悄換字會讓引用它的人讀到一個從沒存在過的裁定。

## X1 —— 未追蹤檔案 unstage 之後回到 Untracked

`PartialStageOperation` 在「index 報 Added」且「這次選取涵蓋每一條變更」時改走
`restoreStaged()`，那個 helper 同時是 `UnstageFilesOperation` 走的路，兩條路徑因此收斂到
同一個終態而不是各自發明一個。三個新的真 repo 測試，斷言 porcelain 的 `?`。

**Mutation 跑 2 個，變紅的測試 1 個。**「拿掉每一條變更那一半」紅 1；
**「拿掉 `kind == Added` 那一半」紅 0**，全套仍 503 綠。

第二個是這一段最有價值的東西：**我在註解裡寫「兩半都吃重、都量過」，那句是錯的。**
對已追蹤檔案來說 `restore --staged` 與反向 patch 都落在 `.M`，所以那個對照測試根本分不出
來（`[TEST-fixture-cannot-disagree]`）。查過每一個到得了這裡的 kind 都是這樣收斂的
—— Modified/Deleted 的 index 條目是被**還原成 HEAD 內容**而不是清空，所以沒有孤兒；
rename 也不是反例，因為 diff 是用單一路徑的 pathspec 要的，git 配不成對，新側一樣報
Added。所以 `kind == Added` 是**刻意的收窄，不是被釘住的不變式**，註解與測試註解都就地
改成這樣寫（`[CULT-scrutinise-the-comment]` 反過來用：先有正確的觀察，錯的是我給的原因）。

留著它的理由是：這個特例只為一個量過的形狀存在，默默放寬會讓下一個**真的**會發散的 kind
被送進 `restore --staged`，而不會有任何東西發現。

## X2 —— `ScopedDiffView` 改成吃一串來源

純重構，兩個模式都還是各自建自己的 view，只是每個都傳一個只有一項的清單。方向、
`file`、`onStageScope`、`onDiscardScope`、`emptyLabel`、`loading`、`truncated` 全部收進
`ScopedDiffSource`。

選取的 row key 從 `hunk:line` 改成 `source:hunk:line`。**這不是整潔問題**：兩份 diff 帶著
同樣的 hunk 與行號，兩部鍵會撞成同一把，而撞的結果不是畫錯而是 framework assert —— 兩個
`SelectionListener` 共用一個 notifier（`[FLU-selectionarea-gives-a-string]` 陷阱 1）。

`selection_touch_test.dart` 因此有改，那是**簽章改動逼出來的**，不是行為改動；widget 與
integration 層一個字沒改就綠，那才是這個 commit 真正的驗收。

## X3 —— `unified` 變成一份合併清單

`indexPositionOf()` 讀兩份 diff 共用的 index 座標，逐**區塊**排序，
**排序而不是合併**（「unstage, stage 必定是不同 scope」）。同位置的 tie-break 是 unstaged
先，而且排序整段對單一來源直接跳過 —— 所以 `2 file` 在結構上不可能被它重排。

方向由卡片自己說：動詞、早就逐張帶著的 3px 左緣色，加上從欄標頭搬下來的 8px 圓點。
欄標頭在 `unified` 拿掉，改在標題列寫「2 未暫存 · 1 已暫存」。

**我在這一步造出了一個回歸，而且是既有測試抓到的。** 第一版把 placeholder 寫成「所有來源
都沒內容才畫」，結果一側被拒絕、另一側有卡片時，「Diff too large to display」整個消失 ——
正是 `[CPP-parse-refuses-over-cap]` 說的「每個 consumer 都欠使用者一句話」。改成
loading / refused / binary 逐來源就地畫一個 `_Notice`（帶自己的圓點與方向名，因為欄標頭沒
了就沒別的東西說是哪一側），只有純粹的「這側沒東西」才靜音 —— 那句話標題列已經說了。

**Mutation 跑 3 個，變紅的測試 4 個。**

| Mutation | 紅 |
|---|---|
| 拿掉區域排序 | 1（unified orders cards by index region） |
| `indexPositionOf` 一律讀舊側 | 2（單元 + 排序） |
| `showDirectionDot` 恆 false | 1（column heads / card heads） |

第二個**一開始只紅 1 個**，而那是 fixture 的問題不是實作的問題：staged 那側的加行
`oldLine` 是 0，`indexPositionOf` 走的是初始值那條路（初始值本來就讀對邊），迴圈根本沒被
考。補上一列 **context**（唯一同時帶兩個行號的 kind）之後才紅 2 個。這是
`[TEST-fixture-cannot-disagree]` 的又一個形狀：fixture 讓有缺陷的那條路無法被執行到。

順帶就地更正兩個舊測試的名稱與理由：它們的 fixture 兩側都落在 index 第 1 行，所以釘住的
是 tie-break，不是排序本身 —— 它們在合併前後都是綠的，不是證據。

## X5 —— Unstage 按鈕的第二種樣式，本輪唯一跨到 `2 file` 的一項

**稽核當時寫錯了，實作時量出來。** §10 的 U8 寫「app 只實作了 accent 那顆，兩側按鈕畫出來
一模一樣」。實際上 `scoped_diff_view.dart` 從最早那個 scope 卡片 commit（`7abb728`）就寫著
`kind: staged ? GbmButtonKind.secondary : GbmButtonKind.primary`，而 `secondary` 給的正是
`surface-panel-raised` 底與 `text-primary` 字 —— 三個屬性有兩個本來就對。**真正差的只有邊
框一個 token**：app 是 `border-default`，變體 B 寫的是 `border-strong`。spec 頁面上那句
已經劃掉重寫。

所以做的是給 `GbmButton` 一個 `borderColor` 覆寫、在兩個呼叫點傳 `borderStrong`；直接改
`secondary` 這個 kind 會動到全 app 每一顆次要按鈕，遠超出範圍。

兩個模式各驗一次 —— U8 的整個理由就是一致性，只驗一個模式等於沒驗。

**Mutation 的護欄擋下一次錯誤的變異**：兩個呼叫點的縮排不同，短的那條是長的那條的子字
串，所以 `count(old) == 1` 的斷言直接失敗。這正是
`[TEST-mutation-check-every-test]` 要求那道護欄的原因，這一輪它真的擋了一次。

## 記錄

- `[STRUCT-two-column-switches]` 的 Working Copy 那一列拆成兩列：`2 file` 的位置仍然代表
  方向，`unified` 的位置只代表區域在檔案裡的先後。
- `[STRUCT-working-copy]` 的 diff 段落就地劃掉「unified 把兩側疊成一欄」。
- 新 pin `[GIT-reverse-patch-cannot-unadd]`，並在 `[GIT-new-file-patch-needs-dev-null]` 的
  「不要改 unstage 方向」旁邊補上這次量到的邊界 —— 那句話**還是對的**，只是現在知道整份
  unstage 根本不是標頭問題。
- 新 pin `[FLU-merged-diff-keys-by-source]`。

## 驗證

裝置層 macOS，逐檔跑，跑前 `pkill` 並 `scripts/build_capi.sh`（X1 改了 C++，
`[TEST-stale-dylib-is-silent]`）：

| 檔案 | 結果 |
|---|---|
| `history_filter_test`（對照組，本輪沒碰） | 2/2，57s |
| `stage_lines_flow_test` | **7/7**，1m48s |
| `untracked_unstage_flow_test`（新） | **1/1**，24s |
| `working_copy_line_counts_test` | 1/1，7s |
| `context_menu_flows_test` | 5/5，41s |
| `commit_flow_test` | 1/1，9s |

其餘各層：`flutter analyze` 0，`dart format --set-exit-if-changed` 乾淨，
`flutter test` **2875 綠**，`ctest` **667 綠 / 2 skipped**（150s），
`scripts/check-rule-pins.py` 187 條規則、112 個交叉引用、懸空 0。

五個受影響的檔案是照 `[TEST-grep-misses-intent-driven-device-tests]` 選的 —— grep
`ScopedDiffView` / `WorkingCopyDiffMode` / `WorkingCopyBoard` / 按鈕標籤 / `unified` /
`2 file`，不是只 grep 這輪改到的字串。`commit_flow_test` 上一輪結尾是紅的
（`[TEST-geometric-drop-point-is-axis-bound]`），這輪綠不是本輪修的：父分支的
`f43a025` 已經把那個落點改成往下了。

「`Failed to foreground app; open returned 1`」六次都出現，六次後面都跟著計數 ——
`[TEST-foreground-line-is-not-a-failure]`。

## 追加：沒寫出來的那條驗收，蓋著一個真缺陷

`flutter test` 2875 綠、六個裝置層檔案全綠、每一條 pin 都對得上之後，這一輪本來
要收掉。把 §12 的驗收清單逐條對回程式碼時，發現其中一條**從頭到尾沒有被寫成測
試**：

> 一次跨過 staged 卡片與 unstaged 卡片的拖曳，只把先碰到的那個方向放進一次性
> scope，斷言在產生出來的按鈕自己的標籤上。

補寫它，它就紅了。

### 缺陷

X3 讓 `_wellChildren` 依 index 區域排序才畫，`_rowsInRenderOrder` 卻仍然照
source → hunk → line 走。兩份順序只要區域交錯就不一致 —— 而交錯正是排序存在的
唯一理由：

```
    畫面（_wellChildren，排序後）        _rowsInRenderOrder（source 順序）
    ┌──────────────────────────┐        1) 0:0:*   unstaged  ← 永遠先被走到
    │ ● staged  @@ 10  ← 先畫  │        2) 1:0:*   staged
    ├──────────────────────────┤
    │ ● unstaged @@ 100        │
    └──────────────────────────┘
```

`resolveTemporaryScope` 的契約是「取第一個碰到的**變更**列」，而它走的是右邊那
份。所以一個從 staged 卡片往下拖到 unstaged 卡片的選取，方向會判成 stage ——
U5 的裁定被實作成了它的反面。同一份清單還有第二個讀者：`_extendByRow` 與
`_adoptRangeFromTouched`，也就是 Shift+↑/↓，它跨的是螢幕上不存在的順序，正是
`[SPEC-range-follows-paint-order]` 記過的形狀，只是這次換一個顯示模式復發。

`_rowsInRenderOrder` 自己的註解寫著「由**同一份**版面清單回答，而不是第二次走
訪」。那句話在寫下的當下就不成立 —— 它自己就是那第二次走訪
（`[CULT-scrutinise-the-comment]`）。

### 修法

把區塊的建立與排序抽成 `_orderedBlocks`，兩個讀者都從它推導。不是「讓第二份順
序也排序一次」——那只是把同一個分岔往後推一格；是讓順序只有一個來源
（`[CULT-single-source-of-truth]`）。

### fixture 為什麼要不對稱

staged 側落在 index 10、unstaged 側落在 100，排序因此把 **staged 畫在上面**。
兩側位置相同的 fixture 分不出 source 順序與畫面順序，會對兩種實作都給綠
（`[TEST-fixture-cannot-disagree]`）。另加一條守門測試斷言畫面順序真的是反過來
的 —— 少了它，主測試可能因為排序根本沒生效而通過。

mutation 2 條，紅 1 與 3 條（進度列的 `-N` 親眼讀的）：

| mutation | 紅 |
|---|---|
| `_rowsInRenderOrder` 改回 source 順序 | **-1**，只有 U5 那條 |
| 區域排序整段停用 | **-3**，U5 兩條 ＋ 既有的 `unified` 排序那條 |

### 順帶清掉的孤兒

X3 之後 `hunkSegments` 的 `firstOrdinal` 與 `DiffScopeSegment.ordinal` 在 `lib/`
下沒有任何呼叫者或讀者（`[CULT-orphan-wiring]`，兩個方向都 grep 過）。處置是
**刪除而不是接回去**，因為那個承諾已經無法兌現：合併清單會先排序再畫，而
`hunkSegments` 一次只看一個 hunk，它在排序前發出的號碼會被排序打散。號碼必須
在排序之後才給，也就是 `_wellChildren` 自己的計數器。同一條 pin 的第十二個案例
也是這樣判的 —— 問「這個讀者做得到它承諾的事嗎」。

被刪掉的單元測試所主張的「號碼跨 hunk 連號」沒有消失，搬到它現在發生的地方：
U5 那條測試斷言 staged 卡片是 `scope-card-1`、unstaged 是 `2`，也就是反過來的
source 順序（`[CULT-nothing-silently-dropped]`）。

### 順帶：每一幀少排序一次

抽出 `_orderedBlocks` 之後 `build()` 走了它兩次 —— 一次經 `_rowsInRenderOrder()`，
一次在 `_wellChildren` 裡。`hunkSegments` 沒有像 scope 切割那樣被快取，而這條路
徑在拖曳時每一幀都會跑（`[CULT-measure-before-caching]` 記過同一個面上 197µs/幀
的前例）。改成 `build()` 算一次交給兩邊，鍵盤處理維持自己排序 —— 它們是事件，
沒有幀可以共用。順序仍然只有一個來源。

### 裝置層，以及一次沒有重現的 hang

| 檔案 | 結果 |
|---|---|
| `stage_lines_flow_test`（第一次，已中止） | 約 5 分鐘沒有進展，主執行緒停在 event loop（不是在空轉），手動中止 |
| `stage_lines_flow_test`（重跑） | **7/7，1m46s** —— 逐測試的秒數與上一輪全綠那次幾乎一致 |
| `untracked_unstage_flow_test` | **1/1，23s** |
| 對照組 `fb3e547`（這一段開工前那一顆），整份 | 6/7 —— 第 1 個測試 `a scope card button stages only that card's lines` 在 **16m54s** 之後 `[E]`，全檔 18m29s |
| 對照組 `fb3e547`，`--plain-name` 只跑那一個測試 | **1/1，15s** |

**誠實的結論是「沒有重現」，不是原因**，而對照組把它收得更緊了一點。

同一個測試在**兩顆不同的 commit** 上各卡過一次，兩次都在重跑時綠掉。`fb3e547`
那一組尤其有話講：紅的那次與綠的那次之間，**程式碼一個 byte 都沒有動**，動的只有
行程狀態（重跑前 `pkill`）。所以「這一段的改動造成了 hang」被排除，而「這一段的改
動修好了 hang」同樣被排除 —— 父 commit 沒有這段改動也自己好了。剩下的解釋落在環境
那一側，`[TEST-hang-is-not-yet-a-defect]` 講的就是這個。

不過那不是一次乾淨的 A/B：紅的那次跑整份七個測試，綠的那次用 `--plain-name` 只跑
一個，累積的行程狀態不一樣。所以它是**一個反例**，不是一個對照實驗。

**那個 `[E]` 的錯誤本文我沒有留下來，這是我自己弄丟的。** 第一次對照組的指令接了
`grep -E '^[0-9]{2}:[0-9]{2} \+|All tests passed|Some tests failed'`，只留下進度
列，把錯誤本體整段濾掉了 —— 跟下面那個 `| tail` 是同一種錯，`[TEST-device-runs-one-file]`
的「不要把裝置層輸出縮成 `tail -1`」講的也是同一件事。重跑時錯誤沒有再出現，所以
這份紅到現在**只有時間與測試名，沒有本文**。第一次之所以看不出跑到哪裡，是因為指
令尾巴接了 `| tail`，它會把整份輸出 buffer 到結束；重跑改成串流，這才看得到逐測試
的進度。**下次裝置層一律不要接 `tail`，也不要接只留進度列的 `grep`。**

第 6 個測試 `Shift+Down builds a range the button then stages` 是這次改到的第二個
讀者（`_extendByRow`），它綠了。

### 這一輪的教訓

**沒有寫出來的驗收不是還沒驗，是沒有驗。** 六個裝置層檔案全綠、2875 個測試全
綠，都不會替一條不存在的斷言說話。驗收清單本身要逐條對回測試檔，才算走完 —— 這
一條現在也寫進 §12 了。

### 收尾時，在分支頂端重跑一次的數字

追加這一段又動了 `lib/`（`6a5634e`、`e7ee1c9`、`d5e095a`），所以上面 188 行那組
數字只代表當時那顆 commit。分支頂端重跑：

| 檢查 | 結果 |
|---|---|
| `flutter analyze` | 0 issue |
| `dart format --set-exit-if-changed .` | 533 檔，0 改動 |
| `flutter test` | **2876 綠 / 1 skipped** |
| `scripts/check-rule-pins.py` | 187 條規則、115 個交叉引用、懸空 0 |

`ctest` 沒有重跑：這一段五顆 commit 動到的八個檔案全在 `app_flutter/` 與 `docs/`
底下，`src/` 一個字都沒有碰（`git diff --name-only fb3e547..HEAD | grep '^src/'`
是空的），所以 188 行那組 **667 綠 / 2 skipped** 仍然是當前 `src/` 的數字。

## 追加二：未追蹤檔案把中間那一行 stage 起來，只畫了兩張卡

使用者回報：

> problem: for example my current untracked file, i stage the middle line
> (document...) and it should split into 3 scope, but its only 2 scope

先在暫存區開一個真的 repo 量，不是推論。五行的未追蹤檔案，把第三行
`document` 單獨 stage 起來之後，兩份 diff 長這樣：

```
unstaged（index → worktree）        staged（HEAD → index）
  + alpha      (old 0, new 1)         + document   (old 0, new 1)
  + bravo      (old 0, new 2)
  . document   (old 1, new 3)  ← 這一行就是 staged 那一行
  + delta      (old 0, new 4)
  + echo       (old 0, new 5)
```

然後用一顆丟棄式的 widget probe 確認畫出來的東西，而不是只讀程式碼：

```
BUTTONS(2): [Stage 5 lines (4 changed), Unstage 1 line]
rows "document": 2
每一列的 indexPosition 都是 1
```

**一個回報底下是三個缺陷**，而且修掉任何一個，另外兩個都還在：

| # | 缺陷 | 症狀 |
|---|---|---|
| 1 | gap 規則把 staged 那一行當成普通的未變更行吞掉 | 四個 `+` 併成一張卡，`Stage 5 lines` |
| 2 | 同一個 index 行兩側各畫一次 | `document` 出現兩列 |
| 3 | `indexPositionOf` 把插入的列算成「前面那一行」 | 六列全部回報 1，排序沒有東西可排 |

第 3 個最容易漏：它要等前兩個修好才看得見。把區域切對了，仍然沒有任何東西
可以把它們排出先後 —— 未追蹤檔案的每一列都在同一個 index 位置上。

### 設計問到使用者才動手

G1：把三個缺陷、量到的證據、以及一個真的要裁定的問題寫出來給使用者看，才碰
`lib/`。那個問題是：合併清單裡，一側畫成未變更、另一側畫成變更的那一行，要
畫兩次（A）還是只畫一次（B）。**使用者裁定 B**，同一句話裡順便要求把
`origin/main` merge 進來。

### 座標從一段變成兩段

`IndexPosition` 現在是 `({int line, int offset})`：`offset 0` 表示這一列
**就是** index 的第 `line` 行，`offset 1` 表示它夾在第 `line` 行和下一行之間。
hunk 第一個 index 行之前的列拿 `start - 1` 配 offset 1，所以空 hunk 的退路要
減一。比較一律走 `compareIndexPositions`，不在呼叫端逐欄位比。

**追蹤中的檔案看不見這件事**：它的 context 列有真的 index 行號，offset 永遠
不必扛任何東西，一段式的座標在每一列上都答對（[TEST-fixture-cannot-disagree]）。

### 硬邊界

`splitHunkIntoScopes` 多一個 `barriers`：被指名的未變更行不可以被吞進 scope。
規則寫成「不可以吞掉邊界」而**不是**「碰到邊界就結束 scope」—— 它只作用在同
一側兩個變更**中間**的未變更行，落在 gap 以外的邊界什麼都不改，這是所有單一
來源的 fixture 一個字都不用動的原因。

邊界是誰，由 `changedIndexLines(otherFile, staged:)` 決定，再由
`barrierLineIndices` 翻成那個 hunk 自己的列號。**加號那一半不算邊界**：
unstaged 的新增行 old 側是 0，staged 的刪除行 new 側是 0，它們夾在 index 行
**之間**，那個座標上沒有東西可以撞。

### 裁定 B 的實作，和它唯一會紅的那個 mutation

`hunkSegments` 多一個 `hiddenLines`，而關鍵不是「跳過那一列」，是
**把那一段未變更的跑馬燈從那裡切成兩段**。只跳過不切，上下兩段 context 會
悄悄併成同一個區塊；`a hidden line inside a longer context run breaks it in
two` 就是為了這一個 mutation 存在的。

### 標題列的數字說了另一個數（收尾時才發現）

四顆 commit 之後補查 `working_copy_diff_pane.dart`，發現
「N 未暫存 · M 已暫存」走的是**另一條**路徑：它有自己的 `DiffScopeCache`，
呼叫 `scopesOf(file)` 時不帶方向也不帶邊界。所以在使用者回報的那個案例上，
卡片是三張（兩張 Stage、一張 Unstage），標題列寫的是 **「1 未暫存 · 1 已暫存」**
—— 修好的東西上面掛著一個沒修好的數字。

那段 doc comment 自己寫著：

> The title bar's own scope counts (U3) go through the same
> `splitDiffFileIntoScopes` the cards do -- one function, two memos, so the
> chip cannot say a number the list disagrees with.

「同一個函式」是必要而不充分的：卡片這一輪改成帶邊界切，這個數字沒有，於是
那句保證在卡片改掉的那一刻就失效了。就地劃掉改寫，不是另外補一段
（[CULT-scrutinise-the-comment]）。

修法不是在 pane 裡再算一次邊界 —— 那會是第二個推導法，也就是這個缺陷本身的
形狀。`ScopedDiffView` 私有的 `_barrierMemo` 抽成純層的 `DiffBarrierMemo`
（`93334d5`），兩邊共用同一個（`d70b5d6`）。抽出來的時候 key 多了一欄
`DiffSide.staged`：同一個 `DiffFile` 換一個方向讀，回報的 index 行就不同，
只比對檔案 identity 不是整把鑰匙。

**原本的 chip 測試永遠看不見這件事**：它的兩個 hunk 相隔 50 個 index 行，
任何一側的邊界都不會落進另一側的 gap 裡，沒有邊界的數字剛好是對的
（[TEST-fixture-cannot-disagree]）。新測試用的是實測出來的那個案例本身。

### fixture 自己不會反對的那一顆，是 mutation 抓到的

`changedIndexLines` 的測試第一版寫成 `(added, 0, 2)` / `(removed, 2, 0)`，
兩側都答 `{2}`。把函式改成「永遠讀舊的那一側」，**全綠**。改成
`(added, 0, 5)` / `(removed, 9, 0)`（期望值 `{5}` / `{9}`）之後才紅 1 顆。
這是這一輪自己撞上的 [TEST-fixture-cannot-disagree]，而抓到它的是 mutation
檢查，不是覆蓋率。

### 兩個誠實的失手

- 有兩個 mutation **根本沒套用上去**：`python3 -c` 裡嵌多行字串噴了
  `SyntaxError`，而那次的「綠」等於沒有意義。改用 `python3 - <<'PY'` heredoc
  重跑，其中一個就紅了 1 顆。**REDS=0 先要證明 mutation 真的落地。**
- C3 的排序測試第一版是紅的，但**紅錯理由**：`find.text('document')` 當時還
  匹配到兩個 widget（正是 C4 要移除的那個重複），`getRect` 直接丟例外。改成
  量 `find.widgetWithText(GbmButton, 'Unstage 1 line')` 對上兩列唯一的文字
  （[FLU-finder-proves-existence-not-position]）。

### merge origin/main

同一句話裡的第二件事。`origin/main` 38 顆 commit（含 PR #138 的
`e7d1e27`）merge 進來，只有一個尾端衝突：`docs/rules/drift-open.md` 兩邊都往
檔尾 append 了一條新規則。兩條都留，main 的 `[DRIFT-cancel-capi-unwired]` 在
前、HEAD 的 `[DRIFT-list-tree-mode-scope-undecided]` 在後 —— 這正是
`docs/rules/README.md` 說「append 到同一個檔只會在尾端衝突，保留兩邊即可」的
那個情況。merge 之後兩個工具鏈都先驗過才往上疊。

### 這一段的數字

| commit | 內容 | mutation 數 / 各紅幾顆 |
|---|---|---|
| `d4b7765` | index 座標改兩段 | 2 / 3、1 |
| `9751084` | gap 規則接受硬邊界 | 3 / 2、1、1 |
| `083998c` | 檔案層翻成 hunk 行號 | 3 / 1、1、1 |
| `6c4f97f` | unified 接上邊界 | 3 / 2、1、1 |
| `3ec2e82` | 裁定 B，不畫兩次 | 3 / 1、1、1 |
| `93334d5` | memo 抽到純層 | 4 / 1、1、1、3 |
| `d70b5d6` | 標題列的數字接上 | 2 / 1、1 |

**mutation 跑了幾個、測試紅了幾顆，是兩個數字**，所以上表分開列
（[TEST-mutation-check-every-test]）。

| 檢查 | 結果 |
|---|---|
| `flutter analyze` | 0 issue |
| `dart format --set-exit-if-changed .` | 534 檔，0 改動 |
| `flutter test` | **2914 綠 / 1 skipped** |
| `scripts/check-rule-pins.py` | 198 條規則、140 個交叉引用、懸空 0 |

`ctest` 沒有重跑：這一段七顆 commit 動到的檔案全在 `app_flutter/` 與 `docs/`
底下（`git diff --name-only 4b16f2e..HEAD | grep '^src/'` 是空的），所以
`src/` 的數字仍是 merge 之後那次的 **687 綠 / 2 skipped**。

裝置層兩個檔逐檔重跑（先 `pkill`）。輸出**接了 `tail -60` / `tail -30`，完整的
逐測試結果列都在裡面**；沒有接 `tail -1`，也沒有接只留進度列的 `grep` —— 這是
上一段自己寫下的教訓。就地把原本那句「輸出沒有接 `tail -1`」改精確：那句話為真，
但這一段的教訓是「一律不要接 `tail`」，而我確實接了（只是接得夠寬，沒有濾掉東西）
—— 照 `[TEST-foreground-line-is-not-a-failure]` 的同一個要求，把數字讀出來而不是
把敘述講得比實際寬鬆：

| 檔 | 結果 |
|---|---|
| `stage_lines_flow_test.dart` | **7/7 綠，1m49s** |
| `untracked_unstage_flow_test.dart` | **1/1 綠，23s** |

這兩個檔是刻意挑的，不是掃到就跑：兩個檔裡的 finder 都直接數合併清單裡的卡片
（`findsNWidgets(2)` 兩處、`find.text('Stage 3 lines')` 一處），而這一段改的正
是「一份清單裡有幾張卡、每張叫什麼」。`_paneWith(staged:)` 在 `unified` 底下
兩個 getter 解到**同一個** view，所以那些數量斷言數的就是卡片本身。

`Failed to foreground app; open returned 1` 兩次都印了，兩次都全綠
（[TEST-foreground-line-is-not-a-failure]）。

## 追加三：樹狀模式改成 VS Code 語意，資料夾才堆疊名稱

使用者在驗收 W10（上一輪 `feat/working-copy-vertical-file-lists` 的
`leafBuilder(context, item, label)` 契約）時回報：

> w10我覺得共用沒錯，但是需要修一下，樹狀模式下，我想要的是像vscode一樣，folder
> 可以堆疊名稱，但是檔案不會有folder。我現在驗收看到這個：
> ▾ docs / ledger/2026-09-05-feat-worktree-dialogs-shell-redesign.md /
> rules/fn-flutter-layout.md

**「共用沒錯」是對 W10 範圍的裁定 —— 那個共用元件留著。** 要改的是行為。

```
驗收看到的                                          要的
▾ docs                                              ▾ docs
    ledger/2026-09-05-feat-worktree-…-redesign.md     ▾ ledger
    rules/fn-flutter-layout.md                            2026-09-05-feat-worktree-…-redesign.md
                                                      ▾ rules
                                                          fn-flutter-layout.md
```

### C1 —— 收合停在資料夾

`_collapseIfSingleChild` 上一輪連「單一子項是**檔案**」也一起串接進去
（commit `7f37f55`）。`docs` 底下兩個資料夾各只有一個檔案，於是兩個資料夾整個
消失，只剩兩列帶前綴的檔案 —— 摺成樹狀付了縮排卻沒買到東西，和 W10 修掉的症狀
是同一句話，只是換成從模型這一端造成的。

改成只在單一子項本身是資料夾時才遞迴。**這推翻的是上一輪自己的延伸，不是 spec**：
P03 item 10 的例子「只有一個子項的資料夾會自動串接成 `lib/app/views` 一列」講的是
三層**資料夾**，那半邊原封不動（`collapses a full single-child chain (lib -> app
-> views)` 全程綠）。VS Code 的 `explorer.compactFolders` 就是這條規則。

遞迴刻意 gate 在 `!childData.isLeaf`，不是把舊分支刪掉了事：讓它遞迴進一個 leaf，
會走到函式底部回一個「名字是檔名的空資料夾」，檔案從樹上**和 `getAllLeafPaths()`
一起消失** —— 而 `getAllLeafPaths()` 正是 Working Copy 拖整個資料夾在讀的東西。

### C2 —— 資料夾的展開鍵本來就會撞，而 C1 放大了它

`FileTreeList` 用 `node.displayPath` 當展開／收合的鍵，而資料夾的 `displayPath`
只是**從它自己這一層**累積起來的前綴。`lib/` 與 `test/` 底下各一個 `features`
都拿到 `'features'`，共用一個鍵，展開一個另一個跟著開。

這個缺陷 C1 之前就在了，不是 C1 造成的；但 C1 讓「單一子項是檔案」的資料夾重新
長出自己的列，會放大它的觸及面，所以照 standing rule 1 同一次推送一起修，分成
自己的 commit。改法是把兩件事拆開：`name` 是這一列畫出來的字（含摺疊鏈，例如
`app/views`），`displayPath` 從根算起（`lib/app/views`），全樹唯一。

`FileTreeNode.displayPath` 的讀者只有兩個 —— switcher 的 `byPath` 查表（只查
**檔案**，檔案的 displayPath 沒變）與 `FileTreeList` 的展開鍵。`FileTreeFolderRow`
畫的是 `node.name`，Working Copy 的資料夾列讀的是 `node.name` 與
`getAllLeafPaths()`，所以**畫面上的字一個都沒動**。

### 鑑別 fixture

| 主張 | 看不見它的 fixture | 看得見它的 |
|---|---|---|
| C1 | 收合鏈結尾是**資料夾**（W10 自己的 `lib/app/views` 就是） | 結尾是檔案，也就是使用者回報的那一個 |
| C2 | 父節點只有一個子項 —— 會被 C1 摺成 `lib/features`，前綴順帶被錨定，缺陷就消失了 | 兩個父節點**各有多個**子項 |

C2 那一列是 [TEST-fixture-cannot-disagree]「fixture 沒辦法表達失敗條件」的形狀，
而且它同時是 [STRUCT-leaf-label-from-switcher] 原本那句「鑑別 fixture 需要一個
有多個子項的資料夾」的**新用途**：那句話對 C1 已經不成立（現在任何巢狀檔案都分得
出兩個模式），對 C2 才成立，所以就地改寫成兩句而不是刪掉。

### 數字

| | mutations run | tests reddened |
|---|---|---|
| C1 | 2 | 5 + 5（同一組五個，含新測試） |
| C2 | 1 | 2 |

C1 的兩次 mutation：一是拿掉 `!childData.isLeaf` 讓它遞迴進 leaf（檔案消失），
二是把上一輪那個「串接到檔案」的分支整段裝回去。兩次都紅同樣五個，其中包含新測試。
C2 的 mutation 是把 `displayPath` 改回 `label`（即把缺陷放回去），紅 2 個。
數字是**用眼睛讀進度列的 `-N`** 讀的（`+18 -5`、`+24 -2`），不是 grep 出來的
（[TEST-mutation-check-every-test]）。

四個前提被推翻的測試**就地改寫**，劃掉舊主張再寫新的，不是刪掉重寫一份：
`single file in deeply nested single-child folders`、
`a folder holding one file collapses into it, prefix and all`（連標題一起改成
`… keeps its own row`）、`leaf node reports correct displayPath`、
`a partly-collapsed tree reports the right leaves at every level` 的 `modelsLeaf`
那一半。加上 `viewsNode.displayPath` 由 `'app/views'` 改成 `'lib/app/views'` ——
那一行紅正是 C2 落地的證據。

### 就地更正的紀錄

- `[STRUCT-leaf-label-from-switcher]` 第二條 Rule（「檔案那一支要保留整段前綴」）劃掉
  重寫；同一條 pin 的「鑑別 fixture 需要多子項資料夾」那條 Do 也已經過期，改寫成
  「對 C1 不再成立、對 displayPath 那條才成立」；新增一條 root-anchored displayPath 的
  Rule。
- `docs/reports/spec-conformance-matrix.md` P03 item 10 那一列的 `_collapseIfSingleChild`
  那半句，補上 2026-09-06 的裁定與現在的判準。
- `docs/ledger/2026-09-05-feat-working-copy-vertical-file-lists.md`「同一個 note 裡還藏著
  第二個缺陷」那一節，加一段就地更正的引言。

### 驗證

`flutter analyze` 0 issue、`dart format` 無變更、全套 **2916 綠**。

裝置層：`pumpRealAppOn` 會清掉 `fileListViewMode`（[TEST-pumprealappon-clears-prefs]），
所以每個 device test 都跑在 **list 模式**，而 list 模式在 `FileListModeSwitcher` 裡
是早退的那一支，根本不會建 `FileTree`。照
[TEST-grep-misses-intent-driven-device-tests]「跑一次比論證便宜」，還是跑了
`commit_flow_test.dart` 當對照組：**1/1 綠，9s**，`Failed to foreground app` 照樣
印了而後面接著結果列（[TEST-foreground-line-is-not-a-failure]）。

推送前 PR #140 在前一個 head 上 **11 個 check 全綠**（Windows capi 10m13s、
Flutter UI 10m3s）。這一輪的四顆 commit 推上去之後重跑，**11 個 check 再次全綠**
（`3677b84`，Windows capi 10m55s、Flutter UI 9m40s）。

上機目視檢查由使用者跑完並裁定通過（「看過ok」），第三輪列在「沒做的」旁邊的那項
待辦到此關閉。這一行是在 CI 綠了之後補的，所以它自己會再觸發一次 CI。

## 沒做的

- U9（模式切換器的 `檢視方式` 標籤與兩個 11px SVG 圖示）—— 使用者裁定「不應動，照既有模
  式維持」。這是一句維持現狀的裁定，不是延後，所以不留待辦。
