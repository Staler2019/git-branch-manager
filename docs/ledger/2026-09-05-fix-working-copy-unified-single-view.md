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

## 沒做的

- U9（模式切換器的 `檢視方式` 標籤與兩個 11px SVG 圖示）—— 使用者裁定「不應動，照既有模
  式維持」。這是一句維持現狀的裁定，不是延後，所以不留待辦。
