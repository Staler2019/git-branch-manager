# 十二個管理面板照 P19 樣板統一，worktrees 當參考實作

使用者的話是「let's follow the spec to implement worktree tab and right click
menus」。稽核之後範圍變成兩件事，並經過三輪確認裁定：

1. **十二個面板全部重新稽核**，不是只修 worktrees —— P19 指定 `manage-worktrees`
   當樣版實例，其餘十一個「只換欄位不換造型」，所以只修一個等於沒修。
2. **不做右鍵選單。** 使用者原話：「worktree好像沒有設計right click menu，所以
   舊照spec把detail完成就好」。P19 規則 2 的另一半（明細區動作列）照做。#71
   （05-K catalog 少一項）使用者裁定不併入：「my badm #71 is not worktree work」。

50 個 commit（前 46 個是原本的範圍，後 4 個是使用者推翻三個裁決之後補的）。

## 為什麼六條規則從來沒有被實作

Tier 6c（PR #91）把十二個面板從 dialog 移植成分頁，落實的是〈工具列 + 左清單 +
右明細〉這個**骨架**。P19 的六條**樣板規則**是同一頁上骨架以外的 prose，而
`docs/reports/spec-conformance-matrix.md` 裡連 P19 這一節都不存在。

這正是 [SPEC-audit-unit-is-not-the-page] 記錄過的失效模式，第二次發生：稽核單位
是表格的列，表格以外的 prose 沒有人讀。上一次是 P02〈Graph 連線規則〉那四句話，
這一次是 P19 的六條規則。**兩次都不是「讀錯了」，是「根本沒有讀到」** —— grep
整個 `docs/reports/` 找 `樣板規則` / `P19` 都是零筆。

## 稽核量到的落差（Phase 0，commit 9009f4e）

| 規則 | 規格原文 | 稽核當下 |
|---|---|---|
| 1 | 各自記憶捲動位置與 splitter；`Ctrl/Cmd+W` 關閉 | `panel_page.dart` 完全沒有 Ctrl/Cmd+W；切分頁重新掛載，捲動位置全丟；`storageId` 是每*種*面板一個 |
| 2 | 工具列固定四段…**破壞性動作不放工具列** | 12 個面板有 **8 個**把 danger 按鈕放在工具列 |
| 2 | 右端固定是 filter | 12 個面板**全部沒有** filter |
| 3 | 左清單下限 **220px** | `splitterPanelList.minExtent` = **180** |
| 3 | 行高 **36px** | `PanelListRow` = 34 + 12 = **46** |
| 4 | 右明細一律 **78px 標籤 + 值** | 標籤*疊在*值上面的直式 Column |
| 4 | 動作列在明細底部，danger 靠右 | 沒有這個位置 |
| 5 | 例外狀態用面板內 banner | shell 沒有 banner 槽 |
| 6 | 狀態列一律寫實際數量與耗時 | shell **沒有狀態列** |

## 排序策略：先加槽，最後才強制

「改殼 → 再修十二個面板」會讓十一支測試檔在同一個 commit 變紅，這既破壞「每個
commit 各自綠」，也讓 mutation check 的「紅要窄」失去意義 —— 一次十一支紅，你分
不出哪一支是真的在講話。

所以四段式工具列以**第二個 optional 參數**與舊的 `toolbar: List<Widget>` 並存，
`assert` 兩者恰好一個非 null，面板一個一個搬。**C32（e8faec2）刪掉舊參數的那一刀
才是把「可用」變成「必用」的那一刻**，而它刻意不加新測試：它的證明就是十二支面板
測試檔在舊參數消失後仍然全綠。revert 它是乾淨地退回雙 API，不是退回十二個壞掉的
面板。

暫時的雙 API 對 [CULT-single-source-of-truth] 是真實成本。它被限制在十二個 commit
之內，而且是不整批變紅的代價 —— 這個取捨要記下來，因為下一輪遇到同型的殼改造時
會再面對一次。

## 實測數字

全部在這台機器、這個 repository 上真的跑出來的：

| 量的東西 | 數字 |
|---|---|
| per-worktree status 讀取（`--untracked-files=normal`，20 次取平均，熱） | **13.4 ms** |
| 同上換成 `-uall` | **20.9 ms**（貴 56%） |
| `flutter test` 全套 | 62–75 s，**2547 passed, 1 skipped**（推翻三個裁決前是 2530） |
| `flutter analyze` | 0 issues |

`-uall` 的對比要看清楚它證明了什麼：這個 repo 的輸出目錄都在 `.gitignore` 裡，
所以 `-uall` 在這裡**沒有**爆炸，只是貴了 56%。[GIT-zero-means-unmeasured] 記的
那個真正的成本（把沒建置的輸出目錄整個列出來）需要一個沒被忽略的輸出目錄才會發
生。**56% 是這個旗標選擇的下界，不是它的理由。** 真正的理由是「9 個未提交變更」
數的是*變更*，一個未追蹤目錄算一個。

`掃描 X ms` 這一格在這個 repo 上實際會顯示成 **掃描 13 ms** 左右，因為
`git worktree list` 這裡只有一筆（主 worktree 自己）。要看到多筆的數字得先
`git worktree add`。

## 裝置層：在分支尖端重跑過

```
✓ Built build/macos/Build/Products/Debug/gbm_flutter.app
Failed to foreground app; open returned 1
00:00 +0: the worktrees panel reports a linked worktree's real count
00:04 +1: (tearDownAll)
00:04 +1: All tests passed!
```

`Failed to foreground app` 那一行照 [TEST-foreground-line-is-not-a-failure] 讀
過去看後面的計數：`+1`，exit 0。

**為什麼要在尖端重跑而不是信 c37c6b8 當時的綠**：那次綠是 20 個 commit 之前的
事，而 C32 之後每一個面板掛載經過的殼都被改寫過、C33 又重新給 `PanelPage` 的子樹
上了 key。[TEST-ffi-matches-symbol-only] 說 `dart:ffi` 只比對符號名、從不比對簽
章，所以這條邊界只有裝置層跨得過去。跑之前 `pkill` 掃過殘留 process
（[TEST-stale-process-blocks-tier]）、`build_capi.sh` 重建過 dylib
（[TEST-stale-dylib-is-silent]），並確認過 dylib 真的帶著這一輪的東西：

```
$ nm -gU app_flutter/build/native/libgbm_capi.dylib | grep pending_counts
000000000003dc2c T _gbm_worktree_request_pending_counts
```

## mutation check 找到的兩個真洞

這一輪每一支新測試都做過 mutation check。絕大多數如預期地紅，**兩個沒有**，而
那兩個都是同一種形狀：[SPEC-cell-names-capability] ——「一個機制被註解點名了，卻
沒有任何斷言握住它」。這兩個只有 mutation 找得到，讀程式碼讀不出來。

### M62：唯讀面板「沒有 primary 段」是兩則註解的主張，沒有斷言

共用斷言 `expectPanelTemplate()` 原本只檢查**被點名的**按鈕存在、樣式正確、順序
正確。它對「沒有人點名的那顆按鈕」一句話都沒說。

mutation：在 `blame`（唯讀面板）的工具列上加一顆假的 primary 按鈕。**全綠。**

而 `panel_toolbar_spec.dart` 與 `blame_panel.dart` 兩則 doc comment 都寫著「唯讀
面板本來就沒有建立動作，所以 primary 段是空的」。那句話當時是真的，但握住它的是
沒有東西。

修法是加一行「工具列上的按鈕總數等於三段宣告的總數」：

```dart
expect(
  find.descendant(of: toolbar, matching: find.byType(GbmButton)),
  findsNWidgets(primary.length + maintenance.length + external.length),
  reason: 'the toolbar has a button that no segment declares -- rule 2 fixes '
      'what is on it, not only the order of what is named here',
);
```

規則 2 固定的是**工具列上有什麼**，不只是被點名的那些的順序。這一行之後 M62
REDS=1。

### M68：line-history「選取是釘在未篩選的索引上」也是註解說了算

`line-history` 的選取狀態存的是未篩選清單的索引，所以 filter 藏掉別的項目時被選
的那一項仍然選著。這件事寫在註解裡，測試沒有。

mutation：把選取改成釘在**篩選後**的索引上。**全綠** —— 因為沒有一支測試在選了
東西之後才打字。

補上 `'a selected step stays selected when the filter hides others'` 之後
REDS=1。

## 計畫的前提有三次沒有活過原始碼

照 [SPEC-correct-the-issue-in-place]，就地更正並記下證據：

1. **C32「不需要改測試」是錯的。** 有三支測試檔在用舊的 `toolbar` 參數，刪掉它
   們才綠。
2. **C31 的 filter 停用前提不成立。** 計畫把 `line-history` 跟 `blame` 歸為同一
   類（左清單是檔案內容、沒有可篩的名字）。但 `LineHistoryChunk` 帶著 oid、
   author、subject —— 那是具名集合，filter 是活的。真正該停用的只有 `blame`
   （真的是檔案內容）與 `interactive-rebase`（規則 3 的可寫入清單，篩過的順序不
   是真的順序）。`panel_filter_field.dart` 的 `disabledReason` doc **就地更正過
   兩次**，`bisect` 與 `line-history` 都曾被列進去又拿掉，每次都留下更正與理由
   （[CULT-scrutinise-the-comment]）。
3. **C29 / C28 的「跳出去」段判準要先講清楚。** 見下一節。

## 四個偏離計畫的裁決（計畫核准之後才做的判斷）

計畫的表格是核准過的，這四處偏離了它。每一處都寫進了該面板自己的 doc comment
與 commit 訊息，這裡集中列出來：

| # | 偏離 | 理由 |
|---|---|---|
| C28 | `Checkout` 從「跳出去」移到**維護段** | 「跳出去」收的是**結果落在這個面板之外**的動作 —— 剪貼簿、檔案總管、磁碟上的檔案、或導航到別的介面（History、Compare 分頁）。`Checkout` 在這個 repo 裡移動 HEAD，結果就在這裡 |
| C29 | `Previous revision` 同樣移到維護段 | 它就地重新 blame，沒有離開這個面板 |
| C31 | line-history 的 filter **是活的**，不是停用 | 上一節第 2 點 |
| C34 | 三個 per-subject 面板改 `panel.<kind>:<path>` | 既有的持久化 key 因此孤兒化。**使用者其後推翻了它留下的例外**——見〈三個被推翻的裁決〉 |

前兩項是同一句話的兩個實例，而 `PanelToolbarSpec` 自己的 doc 本來就拿「跳到一個
commit」當例子 —— 這個判準是把既有的話說完整，不是新發明的。

**C34 的代價要說清楚**：既有使用者存過的 `panelLayout.panel.blame` 之類的 key
會變成**讀不到**（回到預設寬度），不是**讀錯**。與 [FLU-splitpane-axis-change]
換軸時要求的取捨同型。當時九個 singleton 面板的 key 刻意沒動，理由是它們只可能
有一個分頁、per-kind 與 per-tab 是同一件事。**那個理由到現在仍然成立，但它留下
的東西被使用者推翻了**——見下面〈三個被推翻的裁決〉第三項。

## 破壞性的邊界畫在哪裡

規則 2 說「破壞性動作不放工具列」，但沒有定義破壞性。這一輪用的判準是：**毀掉使
用者拿不回來的東西**。

| 搬進明細動作列 | 留在工具列 |
|---|---|
| `Drop`（stashes）、`Remove`（remotes）、`Deinit`（submodules）、`Untrack`（lfs）、`Remove worktree…` | `Pop`（stashes）、`Prune`、`Abort`（interactive-rebase）、`Reset`（bisect） |

- `Pop` 是「破壞性相鄰」—— 它 apply 之後會刪掉 stash，但東西進了工作樹、透過
  reflog 拿得回來。`Drop` 拿不回來。
- `Abort` 與 `Reset` 回復**先前的狀態**而不是毀掉工作，而且是各自面板唯一的逃生
  口 —— 搬到明細區等於把出口藏在「要先選一個東西」後面。

`Abort` / `Reset` 留在工具列這件事**在測試裡是一個明講的宣告，不是一個放寬**。
`expectPanelTemplate()` 新增的 `dangerOnToolbar` 參數的語意是：沒被點名的 label
照它所屬段的 kind 檢查，**被點名的 label 一定要是 `danger`**。所以它不能被拿來
偷渡一顆隨便的 danger 按鈕上工具列 —— 你必須指名道姓，而指名道姓這件事在 code
review 裡看得見。

## 「建立於」的四個 caveat，一個都沒有假造

來源是 `<commonDir>/worktrees/<name>/logs/HEAD` 的第一行。git 在
`git worktree add` 當下寫進去，撐得過 `git worktree repair` 與 `git worktree
move`（那兩個改寫的是 `gitdir`，不是這個檔案）。

它**無法**知道的四件事，全部寫在 header 註解裡，UI 一律畫「git 未記錄」而不是
猜：

1. **目前／主 worktree 根本沒有 `worktrees/<name>/` 這個目錄。** 它自己的
   `logs/HEAD` 第一筆是這個 repository 的第一次 checkout —— 同一個標籤下的不同
   事實，所以回報為缺席。
2. `core.logAllRefUpdates` 可以關（bare repo 預設就是關）→ 沒有 `logs/HEAD`。
3. **`git gc` 會過期 per-worktree 的 HEAD reflog（預設約 90 天）。** 過期之後第
   一筆*倖存*的記錄會冒充建立時間：看起來合理、實際是錯的、從裡面偵測不出來。
   **這一條是唯一一個不寫下來就會變成安靜謊言的。**
4. **不做 mtime 後備。** `gitdir` 的 `last_write_time` 會給出第二個可能默默出錯
   的來源 —— [CULT-single-source-of-truth] 的正字標記失效形狀。**缺席勝過大致正
   確。**

而**那一列照畫**：規則 4 說明細*一律*是 78px 標籤 + 值，少一列會讓面板形狀隨項
目而變，正是規則 4 禁止的。

## 順帶修掉的既有缺陷

- **`isMain` 的意思跟名字相反**（f46d696）。`WorktreeOps.cpp` 比對的是**這個
  session 自己的**工作目錄，所以 `isMain` 真正的意思是「**目前所在**的
  worktree」。因此 Remove 閘門在使用者從 linked worktree 開啟 gbm 時是錯的 ——
  它擋住你正站著的那個，卻放行真正的主 worktree。修法是用 `git worktree list`
  的序位得到真正的 `isPrimary`，不必新增任何 git 呼叫。原本的 `isMain` 剛好就是
  mockup 那顆 `current` 徽章的正確來源，所以兩個都留著，各司其職。
- **`Open` 開錯東西**。mockup 寫 `Open in terminal`，程式呼叫的是
  `openInFileManager`。終端機能力**早就存在**（`desktop_launcher.dart` 有 P02
  `TERMINALS` 表的完整候選鏈），只是面板接錯。
- **`GbmSplitPane` 讀回持久化寬度時不夾下限**（63a8748）。`initState` 直接
  `_currentFlexes = stored;`，而 build 期的夾只夾**上界**。所以把面板清單拖到
  190px 的使用者，下限提到 220 之後**永遠停在 190**。夾要加在 `initState`，
  **不能**加在 `_clampedFixedExtent()` —— 後者每一幀都跑，會把
  `collapsedByDefault` 的抽屜（`splitterMainLog`，存值 0）強行撐開到 minExtent。
  抓這個「夾錯地方」的就是「存值 0 要留在 0」那一案。
- **worktrees 選取時沒有去要 HEAD 的 commit subject**（1874d24）。
- **`af030b8`：「URL 空白就不送出」原本是一個空的斷言。**

## 六次 unscoped `find.byType(TextField)`，其中兩次是安靜的

工具列右端加上 filter 之後，每個面板的樹裡都多了一個 `TextField`。六支既有測試
用沒有範圍限定的 `find.byType(TextField)` 去打字，其中**兩支照樣是綠的**，因為
它們的斷言在兩種情況下都成立：

- **remotes**：字打進了 filter，測試斷言「`addRemote` 沒有被派送」—— 打進哪個欄
  位都成立。
- **bisect**：`.first` / `.last` 會把 `HEAD` 打進 filter、讓 bad ref 留空，而測
  試斷言「`startBisect` 有被派送」—— 同樣兩種情況都成立。

這是 [TEST-fixture-cannot-disagree] 第 8 型（斷言太弱而不是 fixture 太弱）與新
增一個 `TextField` 這件事的交叉。**一個面板長出新輸入欄位的那一輪，就擁有 grep
自己改到的檔案裡每一個 `find.byType(TextField)` 的責任**，跟
[FLU-hand-rolled-inkwell-hover] 那個「掃過本輪改動檔案裡每一個 `InkWell(`」的
grep 是同一種收尾動作。

## 兩個假警報，各記一筆

- **`updateScrollOffset` 不是孤兒。** 我的 grep pattern（`recordScroll|
  scrollOffset:`）沒有比中呼叫端，它其實接在 `compare_page.dart:138` 的
  `_onScrollEnd` 裡。
- **`ComparePage` 沒有同樣的捲動遺失問題**，而 `compare_tabs_repository.dart`
  的那則 doc 原本寫「任何不持久化到 widget tree 之外的東西都會歸零」，讀起來像
  「PageStorage 對分頁行不通」，C33 證明它行得通。就地改成活著的那半句：per-route
  的 bucket 會跟著 route 死掉，所以 bucket 要刻意往上提。

## 刪掉了一個沒有測試能證成的東西

C33 一開始寫了一個 shell 自己持有的 `PageStorageBucket`。mutation M70 把它拿掉
**沒有任何測試變紅** —— 因為外層 route 早就提供了一個活得比分頁切換更久的
bucket（Flutter 的 `widgets/routes.dart:1194` 把 `ModalRoute._storageBucket`
餵給 `PageStorage`）。

先確認了測試 harness 的 ShellRoute 巢狀結構與 production 一致，再把它刪掉。
[CULT-orphan-wiring]：沒有任何測試能證成的程式碼就是孤兒接線在等著發生。

## 一個工具上的教訓，值得寫進規則

**`flutter test` 的「Failing tests:」清單在第 4 筆截斷**，後面接
「... and N more」。我用 `grep -c` 去數它，於是把 8 個紅讀成 4 個 —— 而「紅是不
是窄的」正是 mutation check 唯一的判準。**紅的數量要從進度行的 `-N` 讀**，不是
從那份摘要。修正過的計數器放在 scratchpad 的 `reds.sh`。

## 殘留（本輪之後仍然補不起來的）

| 項目 | 狀態 |
|---|---|
| worktrees 待提交數 | **關閉**（Phase 2–3） |
| worktrees 建立於 | **linked worktree 關閉**；三種情況缺席，caveat 全部記錄 |
| 待提交數量測失敗後無法重試 | ~~本輪新增的限制~~ **已推翻並實作**：明細動作列的 `重新量測`。原本的理由（「規則 2 的四段工具列沒有位置放它」）本身沒錯，錯在停在那裡——規則 4 的明細動作列才是每一列自己的動作該待的地方 |
| 其餘十一個面板的列圖示 | 規格對它們一個字都沒寫。`icon` 維持 optional，沒指定的就不畫 |
| 九個 singleton 面板的 splitter id | **已推翻。** 十二個都改由 `panelStorageId()` 產生，後綴規則由 `GbmPanelKind.isPerSubject` 推導——與 `open()` 去重用的是同一個屬性。九個 byte-identical，`interactive-rebase` 一個 re-key 孤兒化 |
| 側邊欄 stash 列高度 | 刻意保留 46，不跟著 `PanelListRow` 縮到 36。`sidebar_stash_section.dart` 那句「這是 `PanelListRow` 對同樣形狀用的高度」已就地改正 |
| `GbmBadgeKind.warning` 不存在 | **問錯了問題。** 使用者裁定：worktree 的 prune 跟遠端分支一樣背景做掉，所以「路徑失效」不是一個要挑徽章顏色的狀態。徽章與 banner 保留當 fallback（鎖住的 prune 不掉），用 `removed` |
| 耗時 只有 worktrees 有 | 其餘十一個面板一律不傳 `timing`。**跑一個指令、每列不量任何東西的面板，不會為了滿足規則裡的「耗時」兩個字去發明一個時間** |
| `makeMoveWorktreeOperation()` | [CULT-orphan-wiring] 的又一例：C++ 有、沒有 capi、沒有呼叫端。點名，**不修也不刪** |
| remotes 最後 fetch / submodules 預期 commit / lfs 大小 / bisect 剩餘步數與自訂測試指令 / file-history 欄位選擇器 | 仍在 #76 |

## 為什麼狀態列文字是一個函式而不是十二份拷貝

`panel_status_line.dart`（292d481）。抽出來的時候已經有**三份手抄**，後面還有八
個要抄。第十一份拷貝裡一個拼錯的「命中」，對每一支只讀自己那個面板字串的測試來
說是完全隱形的。

`setFacts` 與 `timing` 是兩個參數而不是一個 list，因為它們描述的東西不同：
`setFacts` 是關於同一個集合的另一個事實（「1 個路徑失效」），所以坐在總數旁邊；
`timing` 是關於**量測**而不是集合，所以放最後 —— 排在「命中」之後，因為「命中」
仍然是在講那個集合。

## 三個被推翻的裁決

原本的報告把三件事列成「使用者可能想推翻的裁決」。三件都被推翻了，而且每一件推
翻之後的東西都比原本好——所以這一節記的重點不是「改回來了」，是**每個原本的理由
錯在哪裡**。

### 一、量測失敗沒有面板內重試入口

原本的理由：「規則 2 的四段工具列沒有位置放它」。

**那句話本身沒錯，錯在把它當成結論。** 規則 4 給了明細動作列，而那正是屬於某一
列自己的動作該待的地方——而且就在寫著「量測失敗」的那一格正下方。看到問題的地方
就是解決它的地方。這是一個「找不到位置」被誤讀成「不該有這個功能」的例子。

閘門是選取那一筆的量測狀態：`failed` / `unmeasured` 可重試，`measured` 沒東西可
做，**`notApplicable` 不可重試**——它的意思是 bare 或 prunable，也就是指令根本跑
不起來而不是跑了沒跑成，在那裡給重試鍵是承諾一件按幾次都不會發生的事。

mutation M78 值得單獨記一筆：我在 `_remeasure` 的註解裡寫了「拿掉這兩行
eviction，每一支測試都還是綠的」，然後**真的跑了那個 mutation 去驗證這句話**，
REDS=0。註解裡的宣稱跟程式碼一樣要被檢查（[CULT-scrutinise-the-comment]），差別
只在它的檢查方式是 mutation 而不是斷言。

### 二、prunable 徽章該用哪個 `GbmBadgeKind`

**這是問錯了問題。** 使用者的裁決是：worktree 的 prune 跟之前處理遠端分支時說的
一樣——背景做掉，使用者不需要知道。所以「路徑失效」根本不是一個要挑顏色的狀態。

`[REF-fetch-auto-prunes]` 套到 worktree 上，形狀刻意對齊。差別只有一個：遠端那邊
要先跑 `--dry-run` preview 才知道哪些 ref 沒了，而 `git worktree list --porcelain`
直接就說了哪一筆 prunable，所以觸發點是 worktree 清單本身的發佈。

**迴圈安全是這裡的重點。** prune 之後 git 會再發一次 worktrees 更新，而 prune 不
掉的項目（鎖住的、或 prune 失敗的）在那份新快照裡**仍然 prunable**——「看到
prunable 就 prune」會就地變成無窮迴圈。閘門因此是「這個 path 這個 session 內還沒
被試過」，不是「這個 path 現在還 prunable」。跟 C18 把 `failed` 也寫進
`path@headOid` 快取完全是同一個教訓：**看 key 在不在，不要看值是不是空的。**

**要請使用者看一眼的一點**：`git worktree prune` 沒有 `--expire`（`git gc` 跑的
那個有 `3.months.ago`），所以磁碟沒掛載、路徑暫時不在的 worktree 在 git 眼中就是
prunable。唯一擋住「把還會回來的 worktree 丟掉」的是**鎖**——git 自己就拒絕 prune
鎖住的 worktree，而鎖起來正是使用者在說「這個留著」。徽章與 banner 保留當
fallback，因為鎖住的 prune 不掉，而且從刷新到 prune 落地之間有一個視窗。

### 三、九個 singleton 面板的 splitter id 刻意不改

原本留下的不是壞掉的行為，是一個**例外**：三種面板寫 `panel.<kind>:<path>`、九種
寫 `panel.<kind>`，十三個字串全部手寫散在十二個檔案裡，沒有任何東西檢查它們有沒
有撞號——而兩個面板共用一個 id 就是共用一個 splitter 位置，完全不會有人發現。還
有一支測試叫「a singleton kind keeps its unsuffixed id」，讀起來像一條被祝福的豁
免。

**推翻它的方式不是把九個都加後綴**（那只是把不一致搬個位置，還會把每個人存過的
寬度變成孤兒），而是讓十二個都從 `panelStorageId()` 拿 id，而那個函式的後綴規則
來自 `GbmPanelKind.isPerSubject`——`open()` 判斷「同一種面板能不能同時開兩個」用
的正是同一個屬性。於是「能不能有兩個分頁」與「id 分不分得開」變成同一個事實的兩
面。

**字面上最大的讀法（拿分頁 id 當 key）是錯的，而且有實據。** 分頁 id 是
`'${kind.slug}-${_nextId++}'`，一個記憶體裡的計數器，`PanelTabsNotifier` 沒有持久
化任何東西——拿它當 key 會讓 splitter 寬度跨重啟完全存不下來，更糟的是會撞號：這
次的 `blame-0` 下次可能是另一個檔案，於是繼承到別人的寬度。

stem 用既有的 `slug` 而不另開第二份命名 switch（那會在一個檔案裡重建正要從十二個
檔案裡拿掉的漂移）。代價是 `interactive-rebase` 一個 singleton re-key，存值孤兒
化；**九個 byte-identical**。

## 紅色計數這一輪騙了我三次

形式各不相同，全部記下來：

1. `grep -c` 數「Failing tests:」清單 → 把 8 個紅讀成 4 個（那份清單在第 4 筆截斷）。
2. 一個抓 `\+[0-9]+ -[0-9]+` 的 grep pattern 抓到了錯的行 → 把紅 3 讀成紅 1。
3. 一個包在 shell 迴圈裡的 `reds()` helper → 三個 mutation 都回報 1，其中兩個實際
   上是 7 和 2。

`[TEST-mutation-check-every-test]` 原本只寫了「從 progress 行的 `-N` 讀」。那不夠
——第 2、3 次都是在讀那一行，只是經過了自己寫的包裝。真正的教訓是**那個數字要親
眼看過原始輸出**，因為 mutation check 只問一個問題（紅得窄不窄），而答案完全由這
個數字決定。
