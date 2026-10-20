# Worktree 自訂開啟方式，以及錯誤改寫進 Log、status bar 照 P10 mock

## Situation

Worktree 面板只有 `Open in terminal`。使用者的實際流程是先開 terminal，再打
`rider .`、`explorer .`、`open .`、`code .`。他們要一個可自訂的應用清單，從
terminal 按鈕展開。

裁定（AskUserQuestion，2026-10-18）：

- 範圍：「只有 worktree 面板」
- 形式：「Split button」
- 編輯位置：「Preferences 新分頁」，全域設定
- 執行方式：「經由使用者的 login shell」

設計稿 `docs/claude-design-demo/open-with-apps-spec.html` 記錄了 D1–D6 與 Q1–Q8 的裁定。

## Task

1. 新增 `ExternalAppEntry`（DDD factory）與 `AppPreferences.externalApps`，持久化並在讀取時驗證。
2. 新增 `DesktopLauncher.openExternalApp`：
   - POSIX 經 `$SHELL -lic`，路徑以 `$1` 傳入，不進 shell 字串。
   - Windows 經 `cmd.exe /d /s /v:off /c`，`{path}` 換成 `.`。
3. 在 Preferences 新增 External apps 段，並支援 `initialSection`。
4. Worktree 面板的 split button。
5. 中途追加的範圍，全部由使用者裁定：
   - 所有錯誤 SnackBar 改寫進 Log（「所有錯誤」）。
   - status bar 第 3 區改成紅色摘要加 Log 入口（「spec p10-3那個不是嗎。目前紅色badge亮起來不符合spec，要移除」、「這個分支做」）。
   - 整條 status bar 照 P10 mock（Q2「這個分支整條 bar 改成照 mock」、Q7「S1–S8 全做」）。

## Action

### 執行與安全（security-reviewer F1–F6）

- F1：`psQuote` 原本沒有跳脫 PowerShell 的智慧單引號 U+2018–U+201B。已修，這是既有的問題。
- F2：原本的 Windows 設計（`{path}` → `"path"`）一定會被 relay 拒絕，而且 `%…%` 可以跳出引號。改成換成 `.`，並拒絕 UNC 路徑與含 `"` 的指令。
- F3：`$SHELL` 白名單限 sh、bash、zsh、dash、ksh、mksh、yash、ash，其他一律改用 `/bin/sh`。
- F4：寫成 `"{path}"` 或 `'{path}'` 時正規化；`{path}` 若在其他引號內則拒絕。
- F5：`wt.exe -d <path>` 的 `;` 分頁分隔問題，**DEFER**。要不要開 issue 由使用者決定，本輪沒有開。
- F6：拒絕相對路徑與以 `-` 開頭的指令。
- D3 失敗偵測：最多等 5 秒看結束碼。stderr 只保留最後一行，上限 512 字元，5 秒後繼續 drain。這只在 POSIX 有效：Windows 的 relay 看不到 cmd 的結束碼。
- D6：用 `-lic`，stdin 立即關閉。已知代價：`.zshrc` 裡若有 `exec tmux` 一類的寫法，指令不會執行。

### 設計錯誤：SnackBar

原本的 commit 6 用 SnackBar 回報失敗，完整測試因此轉紅：
`panel_exception_state_parity_test.dart` 的「no panel reaches for a SnackBar」。

先前跑完整測試時把輸出接到 `tail`，外層的 exit code 是 0，紅燈幾乎被看漏。

SnackBar 同時違反兩條 spec：

- P10 #3：「不使用會自動消失的 toast——錯誤必須留到使用者看過」
- P19 規則 5：「例外狀態用面板內 banner，不用 dialog、不用 toast」

使用者也指出既有的 `!` badge 不符合 P10 #3。設計稿已在原處更正（加刪除線並註明更正），並新增畫面 3。

`workspace_screen.dart` 的 `_openInTerminal` 原本的 doc comment 就寫著
「reported into the operation log」，程式卻是 SnackBar。這是一則被程式違反的註解（[CULT-scrutinise-the-comment]）。

### 錯誤顯示（Q1–Q8）

- Q1：不另開錯誤視窗。P10 #5 是必要條件，不是一定要開；repo 也沒有這個元件。
- 未讀 error 的判斷：比對「最新一筆 error 的物件身分」，不比 `operationLogRevision`。revision 對每一行都會前進，info 也算。running row 被 outcome 取代後是新物件，所以「執行中 → TIMEOUT」仍然會亮。
- 點紅色摘要：用 `open()`，不用 toggle；篩選看不到那一筆時切回 All；捲到該筆並置中，該列底色 `diffDelBg`。Log 入口則是 View → Log 的同一個 closure（Q6）。
- ~~Clone 失敗不寫進 Log，因為 git 的訊息可能帶有含憑證的 URL（Q4，LOGRULES「不記什麼」）：~~
  - ~~從清單 footer 觸發：footer 下方常駐紅字（Q5）。~~
  - ~~從 File 選單觸發：重新打開對話框並顯示錯誤（Q8）。~~
- **更正（2026-10-20）**：上面三行已被使用者推翻。R1 推翻 Q4，Clone 的記錄照樣寫進 Log；R6、R7 改成在來源處遮掉憑證；R14 撤掉 Q5、Q8。現在 Clone 是一般的背景 git 作業，失敗或取消時寫進發起視窗的 Log，成功時跟著搬到新 repo 的 Log（R12）。見 [ledger: clone 背景作業](2026-10-20-feature-make-user-can-customize-open-apps-clone.md)。
- 仍是 SnackBar 的只剩三個成功提示：`Saved to …`、`Copied to clipboard`、`Log saved to …`。

### 跳到該筆：靠實際執行才發現的兩個缺陷

1. 新打開的 Log drawer 停在 90px 最小高度，list 的 viewport 只有 16px。原本「一次移動一個 viewport」的步進在 200 列內就用完 100 次嘗試。
2. 用 `itemBuilder` 記錄建過哪些 index：lazy list 保留下來的列不會重建，所以 index 範圍會是空的（debug trace 中 `built=1073741824..-1`）。

改法（algorithm-chooser）：

- 改用 `_MountedRow` 的 mount 註冊表，記錄目前實際掛載的 index。
- 搜尋改成先加倍、再對半的區間搜尋。
- 曾用平均列高先估一次位置，後來移除：沒有它也在幀數上限內，只是一個最佳化。

`pumpAndSettle` 的回傳值就是幀數，測試用它限制搜尋步數（< 25）。

### status bar 照 P10 mock（S1–S8）

- 尺寸：高 26、左右 padding 0 / 10、項目間距 9、整條 10.5px textTertiary。新增 `GbmTypography.statusBarText`，比照 `dialogTitleText` 取字面值。
- 第 1 區寫成 `main ↑2 ↓0`：箭頭在前，0 也顯示。
- 新增 1×12 分隔線。
- 進度區改成單行：loader 12、名稱含千分位數字、74×4 進度條、Cancel 為 textLink 文字並與 `+N task` 並存。
- `+N task` 改成 textTertiary。
- mock 沒畫的項目（commit 數、selection 摘要、upstream gone、衝突標籤）保留，字級跟著整條。

## Result

### Commits

| # | commit | 內容 |
| --- | --- | --- |
| 0 | c03a89fb | 設計稿；修前例頁多畫的 16px |
| 1 | e91d7471 | psQuote 智慧單引號（F1） |
| 2 | 2a625b2c | ExternalAppEntry |
| 3 | 300380ab | AppPreferences.externalApps |
| 4 | 8113a023 | openExternalApp |
| 5 | 5bfb01ac | Preferences External apps、initialSection |
| — | bfd93780 | 設計稿更正 SnackBar；畫面 3；Q1–Q7 |
| 6a | ba91f118 | AppLogEvents 錯誤事件、record 方法 |
| 6b | 0a56e608 | split button，失敗寫 Log |
| 6c | c2d937b9 | status bar 照 mock（S1–S7） |
| 6d | f19778ce | 紅色摘要、Log 入口、跳到該筆 |
| — | facb9210 | 設計稿 Q8 |
| 6e1 | 4e74d2cb | terminal、匯出、存 Log、New repository 改寫 Log |
| 6e2 | d8449edd | Clone 失敗：footer 紅字與對話框（~~現行~~ 已由 2026-10-20 那輪移除，R14） |
| — | 5cd29fd1 | 註解改指向 onOpenError |

### Mutation（mutations-run / tests-reddened）

| 範圍 | 結果 |
| --- | --- |
| commit 6（壓縮前） | 13 / 13 |
| 6a | 12 / 12 |
| 6b | 3 / 3 |
| 6c | 21 / 21 |
| 6d | 28 / 26 |
| 6e1 | 6 / 6 |
| 6e2 | 6 / 6 |

commit 1–5 的數字只留在 session 對話裡，沒有搬進這份 ledger。這裡不補寫，以免寫出沒有核對過的數字。

**存活與未跑的 mutation，照實記錄：**

- 6d L10（把對半搜尋換成固定步進）存活：目前的 fixture 一找到上界，區間就已經很窄。
- 6d L12（重用列時更新 index）存活：沒有 fixture 讓同一個 element 換 index。
- 6b：worktree 面板的型別守衛 `result is! ExternalAppLaunchFailed` 若被拿掉就無法編譯，所以沒跑。
- 6e1：T2 第一次寫成編譯錯誤，不計，改寫後重跑才轉紅。
- commit 4：5 秒逾時後繼續 drain 的 mutation 無法寫成單點的文字替換，沒跑。
- 測試沒有用 `fake_async`，因為它不是依賴；改用可注入的短 `exitWait`。

**先寫實作再補測試的地方：** commit 2 的 `edit` 測試在實作之後才寫，沒有先看到紅燈。用 mutation M8 補驗。

### 測試

- 每個 commit 前都跑完整 `flutter test`。最後一次：+3655 ~8，全綠。
- `flutter analyze` 零問題。
- 裝置層（macOS，逐檔執行）：在 `integration_test/` 依改動到的文字、元件與 provider grep 出 7 個檔案，全部通過，共 17 個測試：
  - `status_bar_cancel_flow_test`
  - `worktree_add_refresh_test`
  - `worktree_pending_counts_test`
  - `prepared_message_flow_test`
  - `operation_log_benign_exit_test`
  - `context_menu_flows_test`
  - `update_check_flow_test`
- Orphan-wiring 兩個方向都 grep 過：新增的 symbol 都有定義也有讀取者；被移除的 `hasUnreadLog`、`onOpenLog`、`_lastSeenOperationLogRevision` 只剩一則註解還提到，已在 5cd29fd1 修正。
- Hover 檢查：本分支新增 3 個 `InkWell` 或 `GestureDetector`。
  - split button 的 ▾ 段用 `surfaceHover`，有測試。
  - 紅色摘要與 Log 入口刻意不畫 hover 底色，只換游標：mock 只寫 `cursor:pointer`。這點列在設計稿的推測值裡。

### verifier（outcome review）

**CONFIRMED**，HEAD 5cd29fd1。

- verifier 自己重跑：`flutter analyze` 零問題，完整測試 +3655 ~8。
- 另寫拋棄式 probe（已刪除）：12 個亂數種子 × 5 個目標位置，600 列、高度隨機。中間位置全部置中，用了 6–16 幀；兩端的目標在捲動範圍的盡頭仍看得到。

三個 P4 advisory，全部 **DEFER**，記在這裡，沒有修：

- A1：File → New repository… 失敗寫進 Log 的接線，只靠讀程式確認，沒有整合測試鎖住。
- A2：用拖曳 splitter 關掉 Log 時，`_logFocus` 不會被清掉；下次打開時，那一列的底色還在。
- A3：worktree 面板若在 launcher 還沒回應前就卸載，`!mounted` 會讓這次失敗沒有寫進 Log。

### 偏離計畫的地方

- 命名：計畫寫 `OpenWithApp` / `openWith` / `openWithApps`，實作是 `ExternalAppEntry` / `openExternalApp` / `externalApps`。
- 設計稿第一版的儲存 key `appPrefs.openWithApps` 已在原處更正。

### 尚未決定

- F5：`wt.exe` 的 `;` 問題，要不要開 issue 等使用者決定。
- status bar 的 Cancel 是 TextButton，hover 時會出現預設的 overlay；mock 沒有 hover 樣式，這點沒改。
- 歡迎畫面本身和 spec 不同，使用者說之後會改（Q5 的附註）。
