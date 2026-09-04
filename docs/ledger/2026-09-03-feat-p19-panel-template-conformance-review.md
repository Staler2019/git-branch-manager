# Worktree 面板的五個回報，以及查證時多掉出來的三個

同一支分支 `feat/p19-panel-template-conformance`、同一個 PR #131 的**第二輪**。
上一輪（[十二個管理面板照 P19 樣板統一](2026-09-02-feat-p19-panel-template-conformance.md)，
50 個 commit）把面板統一成 P19 的樣板；使用者實際用過一遍之後回報五件事，這一輪
是 C50–C60 這十一個 commit。

使用者同時下了一條新的作業規則，它決定了這一輪的形狀：

> **按鈕按下去如果需要使用者確認、或是操作，都應該要有設計稿。先設計給我看，
> 而不是把功能做出來卻沒有設計。**

所以這一輪的主體文件是**設計稿**（D1–D7），實作計畫壓在最後一節，核准之後才動
第一行 code。

## 五個回報，逐條查證

| # | 回報 | 查證結果 | 修在 |
|---|---|---|---|
| 1 | `current` 不該有底色、也不是 button | 確認。spec mockup 的 DOM 是 `<span style="font-size:9px;color:var(--text-tertiary)">`，一段純文字；當時是 `GbmBadge`（藥丸 + 底色） | C51 |
| 2 | Worktree 分頁應該常駐 | 確認。`PanelTabsNotifier` 只在 `open()` 被呼叫時才有分頁，沒有種子 | C59 |
| 3 | Add worktree 沒辦法選 branch | 確認，而且**比回報的更嚴重**——見下面 A | C52、C55 |
| 4 | Add worktree 沒有預設位置 | 確認。`_pathController` 起始為空 | C55 |
| 5 | 選資料夾沒辦法彈出 Finder / Explorer | 確認，而且**能力早就有了**——見下面 C | C56 |

## 三個查證時才浮出來的東西

依 [CULT-standing-rules] 第 1 條「撞到就要修」，三個都修了，沒有一個被留成
「本輪不做」。

### A. `New branch from here…` 根本沒開那張 dialog

`branch_row_actions.dart` 的 `createBranchFrom()` 叫的是 `promptText()`——一個只有
「Branch name」單一欄位的通用輸入框。spec P17 明確定義的四個欄位（名稱／從哪裡分
出／建立後 checkout／同時 push 並設為 upstream）**一個都沒到**，起點是什麼也看不
見。真正那張 `NewBranchDialogContent` 存在、可路由，只是側邊欄 05-B 這條路徑繞過
了它。

修法分成三刀：C52 抽出可搜尋的 ref picker 並接上起點欄（在那之前那顆自由輸入的
`TextField` **沒有 controller、沒有 initialValue**，所以從 commit 列帶進來的 hash
存在 `_startRef` 裡卻兩個框都是空的）、C53 讓 05-B 改開真正的 dialog 並帶
`startPoint`、C54 補上缺席的第四個欄位。

### B. `Remove worktree…` 是 danger、帶刪節號、而且完全沒有確認

按下去直接 `removeWorktree(path)`，把一個工作目錄從磁碟移除。P17/P18 的共用外殼
寫得很白：破壞性 dialog 的主按鈕用 danger 且**必須複述具體對象**。

**這是這一輪最嚴重的一個，而且不在使用者回報的五項裡。** C57。

### C. 一句過期的註解替一個缺陷擋了子彈

`file_selector: ^1.1.0` 早就在 `pubspec.yaml` 裡，`file_save_picker.dart` 的
`pickDirectory()` 已經有三個呼叫端。但 `preferences_dialog.dart` 還留著：

> A plain path field rather than a native folder picker — this app has no
> file-dialog plugin (see pubspec.yaml)

`log_drawer.dart` 已經就地更正過同一句話，這裡沒有。[CULT-scrutinise-the-comment]
的活標本。C56 把兩個現場（add-worktree 與 preferences）一起接上，並**就地更正**那
句話而不是只加按鈕。

## C57 的裁決：量到的行為推翻了設計稿給的兩個選項

設計稿把 locked worktree 的處理標成待實測：「量完 git 對 locked 的真實行為後，再
決定 UI 是同一顆 checkbox 講兩件事、還是鎖定時另給一句 warn + 第二次確認。」

在一個丟棄式的 scratch repo 上量到的四件事：

| 情境 | 指令 | 結果 |
|---|---|---|
| 乾淨 + 鎖定 | `worktree remove` | exit 128 |
| 乾淨 + 鎖定 | `worktree remove --force` | exit 128，**錯誤訊息與上一列完全相同** |
| 乾淨 + 鎖定 | `worktree remove --force --force` | exit 0 |
| 髒 + 未鎖 | `worktree remove --force` | exit 0 |
| 髒 + 鎖定 | `worktree remove --force` | exit 128 |
| 路徑已從磁碟消失 | `worktree remove` | **exit 0**（只是把管理紀錄丟掉） |

git 檢查鎖**先於**檢查未提交變更，而且它自己的錯誤訊息逐字點名了兩條出路：

```
fatal: cannot remove a locked working tree;
use 'remove -f -f' to override or unlock first
```

關鍵在於 `gbm_worktree_remove()` 的 `force` 是 `int32_t` 轉 `bool`，
`RemoveWorktreeRequest::force` 也是 `bool`——**capi 送不出第二個 `--force`**。所以
設計稿給的**兩個選項都會做出一顆兌現不了的控制項**，與 [REF-fetch-auto-prunes]
記載的 `autoFetchPrune` 開關同型。

採用的是量測讓第三個選項成立：鎖定時不提供任何 force 路徑，把鎖講出來，指向面板裡
早就存在的一鍵 `Unlock`（git 自己點名的另一條出路）。

> ⚠️ **這是實作者在授權範圍內的判斷，不是使用者裁定。** 設計稿說「量完再從 A、B
> 裡選」，量的結果是 A、B 都做不出誠實的控制項，於是選了 C。未來如果 capi 改成帶
> force 等級（`int` 而非 `bool`），A/B 就重新成立，那時要問使用者。**不要把這一段
> 讀成 user-ratified。**

「路徑已消失 → exit 0」這一列也決定了另一件事：面板對 prunable worktree 停用
`Remove worktree…` 是**一個 UI 動線選擇**（走 Prune），不是 git 拒絕。這一句寫進了
按鈕自己的註解，免得下一輪讀成後者。

## isMain / isPrimary 誤用的第二個實例

C57 修 Remove 按鈕的 gate 時，`isMain`（這個 session 開在哪個 worktree 上）與
`isPrimary`（這是不是 repo 的主 worktree）被分開，並在按鈕上留了註解。C58 才發現
**旁邊的 Lock/Unlock 按鈕犯的是一模一樣的錯**，而且五行之遙。

量測：

```
$ git worktree lock .            # 主 worktree
fatal: The main working tree cannot be locked or unlocked
exit=128
$ git worktree lock ../linked    # 從主 worktree 內對 linked 下
exit=0
```

所以開在 linked worktree 上時，舊的 gate 會**拒絕使用者正站著的那一列**（git 樂意
鎖）而**提供主 worktree**（git 拒絕）——與 Remove 的病徵完全對稱。

值得記下來的是**怎麼發現的**：不是靠 grep，是因為 C58 本來就要改寫那顆按鈕的
`onPressed`。一個修好的實例在它自己的註解裡描述了病徵，隔壁那個實例仍然活著——
[CULT-scrutinise-the-comment] 是從註解找 bug，這一次的方向相反：**從修好的 bug 找
還沒修的同型現場**。

## [CULT-orphan-wiring] 這一輪的第十、十一、十二例

| # | 孤兒 | 狀態 |
|---|---|---|
| 10 | `FileSavePicker.pickDirectory()` 對兩個資料夾欄位而言 | C56 接上，關閉 |
| 11 | `createBranch(setUpstream:, upstream:)`——參數存在，零個呼叫端傳 | C54 接上，關閉 |
| 11 | `lockWorktree(path, {reason})`——同上，明細還畫著「鎖定原因」那一列，永遠是空的 | C58 接上，關閉 |
| 12 | `RemoveWorktreeOperation` 的 `outcome.choices` | **仍然開著**，見下 |

第十二例是**生產端**的孤兒，和前面幾個方向相反。`WorktreeOps.cpp` 在移除失敗時
push 兩個 `OperationChoice`（`ForceDiscard` / `Abort`），`JsonCodec` 照序列化，然後
沒有任何東西讀它：

- `removeWorktree` 走 `submitWorkingCopyOperation`，事件是
  `workingCopyOperationFinished`，而 Dart 這一側只讀 `succeeded` / `error`；
- 讀 `choices` 的 `_handleOperationOutcome` 掛在 `operationFinished` 上，而且只對
  `checkout` / `deleteBranch` 兩個 `PendingOperationKind` 有 arm——**列舉裡根本沒有
  worktree remove 這一項**。

C57 之後它更死了一層：髒的情況現在在 dialog 裡先問過（force checkbox），鎖定的情況
根本不會 dispatch。**沒有開 issue**（[CULT-standing-rules] 第 3 條），記在這裡與
`docs/rules/ops-repo-culture.md` 裡。

## D7 為什麼是「種一個釘住的分頁」而不是第三個 fixed tab

兩種做法都能讓 Worktrees 常駐。選前者的理由是**整輪 P19 的成果原封不動地重用**——
路由、面板殼、`panelStorageId()`、每分頁的捲動與 splitter 記憶——而且路由樹一行都
不用改。做成 fixed tab 要再複製一份 `PanelPage`。

啟動時不付代價：分頁只是一列 chip，`PanelPage` 要被導覽到才 mount，所以
`refreshWorktrees()` 與待提交數依然等使用者去看才跑。

種子走 `open()` 而不是直接 push 一個 spec，是為了讓種出來的分頁與使用者自己開的
沒有分別：id 取自同一個 counter，而 `Tools → Worktrees…` 靠既有的 singleton dedupe
就會聚焦到它。

拒絕關閉的**單一真相在 `PanelTabsNotifier.close()`**，不在兩個呼叫端
（[CULT-single-source-of-truth]）——TabRow 不畫 ⨯、PanelPage 的 Ctrl/Cmd+W 提早
return，但之後多出來的第三個呼叫端不需要記得這條規則。

**⨯ 是不畫，不是畫了再 disable。** 這是本 repo 刻意偏離
[FLU-menu-enabled-is-visual-only]「隱藏會讓人以為功能不存在」的一處：那條規則假設
功能存在只是此刻不可用，而這裡功能真的不存在，一顆死掉的 ⨯ 只會招來它不會兌現的
點擊。

## 種子讓一整類斷言變得空洞

D7 一落地，三支既有測試檔紅了，而**紅的方式比「數字加一」更值得記**：

`workspace_tools_menu_test.dart` 對每個 Tools 選單項斷言的是
`expect(tabs, hasLength(1))`——「按下去正好開了一個分頁」。有了種子之後這句話對一個
**什麼都沒開**的選單項也會通過，因為種子就坐在那裡被數。把它改成
`_tabsOfKind(pumped, kind)` 才回到原本的主張。

`panel_tab_close_shortcut_test.dart` 是同一件事的另一面：「這個分頁關掉了」原本寫成
`expect(tabs, isEmpty)`，而分頁列從此永遠不空。

這是 [TEST-fixture-cannot-disagree] 的一個新形狀——**不是 fixture 錯了，是環境多了
一個常駐項，讓一個原本精確的計數斷言變成籠統的**。三支都改成濾掉 pinned 再數，而
不是把 1 改成 2。

## mutation check

C51 起每一個 commit 都做，紅的條數逐條用眼睛讀進度列的 `-N`
（[TEST-mutation-check-every-test]：這個 repo 已經被 grep / helper / 迴圈騙過三次）。
每一次都用 scratchpad `cp` 備份與還原，**沒有用 `git checkout -- <file>`**。
C51–C57 的各自次數記在各自的 commit message 裡。

**就地更正兩個數字**：這一節原本寫「C56–C59 共十一次」和「C58 與 C59 的八次」，
兩個都是把**紅的條數**當成 mutation 的**次數**在數——11 正好是下表七列的紅加總
（1+1+1+1+2+1+4），8 正好是 C59 那四次的紅加總（1+2+1+4）。C56 的 commit message 是同一個
替換（寫「三次」，列出兩項、紅共 3）。C58 的**不是**：它寫「四次」，而列出的三項紅
也是 3，兩邊都對不上——那一個就只是多算一，手上的證據解釋不了，不要替它編一個。
**三處都以列出的項目為準**：紅的條數本來就可以多於 mutation 的次數，一次
mutation 紅兩條以上正是[TEST-mutation-check-every-test]要你去讀的東西，把兩者混為
一談會讓「紅得窄不窄」這個唯一的問題失去意義。

C58 與 C59 的七次，共紅 11 條：

| mutation | 紅 | 是哪一條 |
|---|---|---|
| Lock 的 gate `isPrimary` → `isMain` | **1** | 「opened on a linked worktree, Lock follows primary and not current」 |
| dialog 的 `.trim()` 拿掉 | **1** | 「trims leading and trailing whitespace from the reason」 |
| prune 說明段落改成 placeholder | **1** | 「states what locking protects against」 |
| `close()` 拿掉 pinned guard | **1** | 「a pinned panel close refuses it」 |
| `TabRow` 的 `closable: !isPinned` → `true` | **2** | 兩條新的 TabRow pinned 測試 |
| `PanelPage` 拿掉 pinned 提早 return | **1** | 那條 Ctrl/Cmd+W 測試 |
| 種子整段停掉 | **4** | 四條全部是 D7 的測試 |

三個值得記下來的觀察：

1. **「Lock stays disabled for the primary worktree」沒有跟著第一個 mutation 紅。**
   預設 fixture 的 primary 那一列同時也是 `isMain`，兩個屬性重合時測不出差別——這
   正是那條「開在 linked worktree 上」的測試存在的理由，也是 Remove 版本當初就寫了
   同一對測試的理由。
2. **拿掉 `PanelPage` 的提早 return 只紅一條，而且是被「路由」那半句抓到的。**
   notifier 依然拒絕關閉，變的只有導覽跑掉了——那正是註解裡說的「半個動作」。如果
   那條測試只斷言分頁還在，這個 mutation 會全綠。
3. **種子停掉紅 4 條、比前三個寬，是對的**（拿掉的是整個功能）。但
   「opening it again focuses the seeded tab」**沒紅**要如實記：沒有種子時 `open()`
   自己會開一個，那條測試釘的是 dedupe 不是種子。

## 驗證

```
flutter analyze                                     0 issues
dart format --output=none --set-exit-if-changed .   517 files, 0 changed
flutter test                                        2654 passed, 1 skipped
python3 scripts/check-rule-pins.py                  161 條規則、45 個交叉引用、懸空 0
```

上一輪收在 2547（那一輪自己記的數字），這一輪 +107。

**裝置層**：這一輪沒有新的 FFI symbol，所以不需要整批重跑；C51 動清單列、C59 動分頁
列，所以把 `integration_test/` 裡對這兩處有 finder 的檔案逐檔跑過。跑前
`pkill -f "gbm_flutter.app/Contents/MacOS/gbm_flutter"`（[TEST-stale-process-blocks-tier]）
與 `scripts/build_capi.sh`（[TEST-stale-dylib-is-silent]），並照
[TEST-foreground-line-is-not-a-failure] 讀 `Failed to foreground app` 那行**後面**的
計數：

| 檔案 | 結果 |
|---|---|
| `commit_flow_test.dart` | 1/1 |
| `working_copy_line_counts_test.dart` | 1/1 |
| `context_menu_flows_test.dart` | 5/5（這支會開 Compare 分頁，正好與新的釘住分頁同列並存） |
| `stage_lines_flow_test.dart` | 7/7 |
| `conflict_flow_test.dart` | 1/1 |
| `worktree_pending_counts_test.dart` | 1/1 |

**最後那一列是就地更正**。這一節原本寫「C57、C58 動的兩張 dialog 在
`integration_test/` 裡沒有任何 finder 命中（grep 過 `Remove worktree` /
`removeWorktree` / `WorktreesPanel` / `RemoveWorktreeDialogContent` / `Lock…` /
`LockWorktreeDialogContent`），所以裝置層不受影響」。**那些 grep 全都真的沒有命中，
而結論仍然是靠不住的**：`worktree_pending_counts_test.dart` 從頭到尾掛的就是這張面
板，它只是用 `Actions.invoke(GbmActionIntent(GbmActionId.toolsWorktrees))` 進去，再
用 `find.text('wt-linked')`（worktree 目錄名）和 `find.textContaining('個未提交變更')`
往下走——一個字都沒提到 widget 名字或這一輪動過的任何一段文案。而這一輪對它動的東西
不只一樣：C51 換掉它列出來的那些列的徽章、C57 加了 Remove 的閘、C58 把 `Lock` 改成
`Lock…`、C59 讓它 `toolsWorktrees` 進去時撞上的是一個**已經開好**的分頁而不是新開一
個。補跑，1/1、4 秒綠。

教訓寫成 [TEST-grep-misses-intent-driven-device-tests]。

## 蒸餾出來的東西

- [UX-ellipsis-promises-a-dialog]——這一輪同時撞到它的兩個方向：`Add worktree…`
  展開一個內嵌表單，`Remove worktree…` 直接執行。兩顆都帶著刪節號。
- [GIT-remove-locked-needs-two-forces]——上面 C57 那張表。
- [GIT-primary-not-current-worktree]——`isMain` / `isPrimary`，以及 git 對主
  worktree 的兩條拒絕。
- [STRUCT-worktrees-tab-is-pinned]——D7 的現況與它刻意偏離的那條規則。
- [TEST-fixture-cannot-disagree] 補了兩列：第 11 列（同步阻塞，
  [FLU-timeout-cannot-bound-sync] 早就引用它但表格裡從來沒有這一列）與第 12 列
  （常駐項讓精確計數變籠統）。
- [CULT-orphan-wiring] 追記第十到十二例。
