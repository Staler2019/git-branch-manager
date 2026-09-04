# Worktree Dialogs spec 的 G2–G8：對話框共用 shell / 欄位樣式重新設計

分支 `feat/worktree-dialogs-shell-redesign`，從 `fix/prune-stale-comment-and-recovery-choice-copy`
（已推送為 PR #135）切出。

## 起因

使用者回報「阿你 add worktree 的樣式還是沒改啊」。查證後發現
`docs/claude-design-demo/worktree-dialogs-spec.html`（「Worktree Dialogs」）
是一份完整、已經多輪裁決的重新設計 spec，但它的工作清單（section 06）
G2–G8 八項——雖然只掛在 Add Worktree 底下——其實影響全部 30 個對話框共用
的 `GbmDialogShell` 與欄位樣式。G1（文案改中文）已經在稍早的回合完成，
但排在最後的「spec 通過才開工」關卡一直標著 open，G2–G8 從未真正實作。
使用者裁定：全部依 spec 工作清單做完。

三個 Explore agent 先把現況逐檔核對過（file:line 對照），才寫出
`prune-remote-branches-enumerated-piglet.md` 這份計畫，逐項拆成可各自
revert 的 commit 執行。

## G2：Add Worktree 補上「來源」群組標籤

radio 群組（checkout 既有分支／建立新分支）本來是全對話框唯一沒有標籤的
欄位群組。新增測試不只斷言標籤存在，還用 `tester.getTopLeft` 比較 y 座標
證明它真的在 radio 群組「上方」——[FLU-finder-proves-existence-not-position]
的教訓：一個 finder 只證明存在，從不證明位置。

## G3：對話框欄位標籤改用 P6 樣式，含一次就地更正

四處欄位標籤（分支／從哪裡分出／檔案／還原成）原本套的是面板區段標題
（`.mklbl`：semibold + letterSpacing 0.5 + textTertiary）的樣式，是誤用。
改成 spec 第 662 行要的 11px / textSecondary / sentence case，拿掉
semibold 跟 letterSpacing。

**就地更正**：第一個 commit 聲稱「只有 3 個檔案 4 處」，是錯的——
`rename_branch_dialog.dart` 的私有 `_Label` widget（三處用例）也是同一種
欄位標籤，卻沒被抓到，因為原本的 grep pattern 是 `textXs + letterSpacing`
的組合，而 `_Label` 一開始就沒有 `letterSpacing`（顏色本來就已經是
`textSecondary`，只差 `fontWeight: semibold` 一項）。依標準規則「錯的紀錄
要就地更正」，這是獨立一個 commit，不是夾在下一批裡。順手核對了全部 12
個含 `weightSemibold` 的對話框檔案，確認只有這一處是漏網之魚。

## G4：`.gbm-input` 高度統一 30px

新增 `gbmInputDecoration()`/`gbmMultilineInputDecoration()`
(`lib/widgets/gbm_input_decoration.dart`)，統一 padding/radius(r6)/
focusedBorder；高度用 `SizedBox(height: GbmSpacing.inputHeight)` 包住
`TextField`（照 `GbmButton` 自己的做法），不靠 `contentPadding` 湊，因為
那會隨字型度量在 test font 與真實字型之間漂移（[TEST-canvas-is-800x600]）。

分五批套用（G4b–G4e，12+3=15 個檔案，19 個 TextField + 3 個
`DropdownButtonFormField`）。**與 spec 原數字「43/27」的落差**：spec 的
工作清單數字涵蓋全 repo（含十二個管理面板與側邊欄的 filter 欄位），這次
改動範圍取 spec 第 01 節自己限定的「dialogs」目錄，如實記在 commit 訊息
而非悄悄套用。三個 Dropdown 延伸套用同一個 helper 是實作判斷（spec 字面
只寫「.gbm-input」沒提 Dropdown，但兩者是同一顆視覺方框）。

## G5：拿掉 GbmDialogShell 的 ✕ 關閉鈕

Spec 的 title bar mock 沒有 ✕，理由寫著「Esc already closes」——但這句話
在這個 repo 裡從來沒有測試釘住過：`gbm_dialog_shell.dart` 完全沒有
Escape/Shortcuts 相關程式碼，`dialog_route.dart` 自己的文件註解只是宣稱
一致的 Esc/返回關閉，程式碼只設了 `barrierDismissible: true`。**拿掉唯一
的關閉手段前必須先證實**，所以先寫一則 integration 層測試
(`dialog_escape_dismiss_test.dart`)，對三個有代表性的對話框（Create Tag、
帶 TextField 的 Rename Branch、帶巢狀 RadioGroup 的 Checkout）逐一驗證
Escape 真的能關。**結果是綠的**——機制是 Flutter 框架自己的
`_ModalScope` 幫每個 `ModalRoute` 綁 `DismissIntent`，`barrierDismissible`
關掉了才啟用這條路徑。把「Esc 已經能關」從假設變成有測試釘住的事實後，
才拿掉 ✕ `IconButton`。

**G5b**：抽出 `GbmKbdChip`（`lib/widgets/gbm_kbd_chip.dart`），消除
`keyboard_shortcuts_dialog.dart` 與 `preferences_dialog.dart` 的
`_ShortcutsSection` 各自實作快捷鍵 chip 樣式的重複
（[CULT-single-source-of-truth]）。`GbmDialogShell` 新增可選的
`GbmActionId? actionId`：13 個有唯一對應快捷鍵的對話框補上這個參數，其餘
維持不傳（`null`）——如實記錄哪些對話框沒有快捷鍵可綁，不是每個呼叫點
都要動。

## G6：標題列改用 P6 全尺寸 mock，含一次 token 命名撞名的修正

Shell 底色從 `surfaceOverlay`（dark 下 `#1C2128`）改成
`surfacePanelRaised`（`#161B22`，量測後確認是真的不同顏色，不是誤差），
補上 1px `border-default` 外框；標題列改用帶 `border-bottom` 的
`Container`，padding 16/12（最接近 spec 的 15/12）。

**修正落差**：計畫原訂「新增 `GbmTypography.textMd = 13`」，但
`tokens.dart` 裡已經有一個 `textMd`，值是 **15**，是 `gbm_theme.dart` 的
`bodyLarge` 和 `undo_last_dialog.dart` 標題共用的既有欄位。盲從計畫會
悄悄把這兩處既有的 15px 縮成 13px。改成新增一個不同名字的 token
`GbmTypography.dialogTitleText = 13`，doc comment 記下撞名的原因，避免
下一個讀到這個名字的人以為 `textMd` 本來就是 13。

## G7：動作列改用 border-top，按鈕統一小尺寸

Spec 要求動作列兩顆按鈕都是 `.gbm-btn-sm`（h24），目前 `GbmButton` 預設
是 `normal`(30)，34 個呼叫點沒有一個傳 `size: sm`。**設計判斷**：不逐一
改 34 個呼叫點的每一顆按鈕建構式，而是新增 `GbmButtonSizeScope`
（`InheritedWidget`），`GbmButton.size` 改成可選 `GbmButtonSize?`，解析時
`size ?? GbmButtonSizeScope.maybeOf(context)?.size ?? GbmButtonSize.normal`
——`??` 保留呼叫端明講尺寸時的優先權。`GbmDialogShell` 的動作列用
`GbmButtonSizeScope(size: sm, child: OverflowBar(...))` 包住 `actions`，
只改 2 個檔案（`gbm_button.dart` + `gbm_dialog_shell.dart`）就讓全部 30
個對話框的動作列按鈕變小。同一個 commit 順手清掉 24 個檔案裡 25 處呼叫端
手動塞的按鈕間 `SizedBox`（現在 `OverflowBar.spacing` 已經接手）。

## G8a：新增 GbmDialogReadOnlyField / GbmDialogWarnField，含一次引擎限制撞牆

`ro`/`warn` 兩種欄位在 app 裡都不存在，現有唯讀列全部是裸 `Text`。
`GbmDialogWarnField` 實作時撞到 Flutter 引擎的真實限制：
「A borderRadius can only be given on borders with uniform colors」——三邊
`border-subtle` 加一邊較粗的 `--warning` 色不是均勻色，跟 `borderRadius`
放進同一個 `BoxDecoration` 會在 paint 時丟例外，不是設計選擇。改用外層
`Container` 帶均勻 `border-subtle` + r6（合法組合）+
`clipBehavior: Clip.antiAlias`，警示色的 2px 左側色條變成獨立的
`Container` 放在 `Row` 裡。

## 這一輪（收尾階段）新發現並修掉的缺陷：`GbmDialogWarnField` 在真對話框裡炸高度

G8a 的兩個新元件只在獨立的 `Center` 測試環境驗證過。套用到 checkout /
restore file / clean untracked / add worktree / remove worktree 五個
對話框後（G8b 的第一批動作），跑起 11 則測試全部丟出
「BoxConstraints forces an infinite height」，錯誤指向 `Row`。

**根因**：`RenderFlex`（`Column`）給非 flex 子項的是**無界主軸高度**，不
論 `Column` 自身是否有界——這正是 `Column` 會 overflow 的原因（它必須先
量出子項的自然高度才知道要不要 overflow）。`GbmDialogWarnField` 內層的
`Row` 用了 `CrossAxisAlignment.stretch`，需要有界的 cross-axis 限制才能
撐開子項；每個真實呼叫端都把它放在 `Column` 裡（對話框 body 的形狀），
於是撐向無限高，丟出例外。G8a 自己的測試用 `_pump` 把元件包在
`Scaffold(body: Center(child: ...))` 裡，`Center` 給的是有界約束，看不到
這個缺陷——`[TEST-fixture-cannot-disagree]` 的第 4 種形狀「fixture 無法
表達失敗條件」的又一個實例。

**修法**：把 `Row` 包進 `IntrinsicHeight`——先量出子項本身的高度，再把
這個有限值當成 tight 限制交給 `Row`。新增一則迴歸測試，把元件直接放進
`Column`（每個真實呼叫端的形狀）而非 `Center`，並用 mutation-check 確認
拿掉 `IntrinsicHeight` 後只有這則新測試會紅（`+7 -1`）。獨立一個
`fix:` commit，因為 G8a 本身已經進了歷史，這是對已提交元件的修正，不是
G8b 呼叫端遷移的一部分。

## G8b：套用到既有欄位

- `checkout_dialog.dart` 的「目前」列、`restore_file_dialog.dart` 的
  「檔案」／「還原成」兩列 → `GbmDialogReadOnlyField`。
- `clean_untracked_dialog.dart`、`add_worktree_dialog.dart`（路徑衝突
  警告）、`remove_worktree_dialog.dart`（待提交變更／鎖定兩則警告）、
  `rebase_onto_dialog.dart`（已 push 警告）、`delete_branch_dialog.dart`
  （沒有 upstream 警告）→ `GbmDialogWarnField`，取代原本裸
  `GbmWarningBanner` 呼叫或 `colors.warning` 文字。

  `delete_branch_dialog.dart`「已完整推到 upstream」那個分支刻意留著純
  `Text`——那是資訊性文字，不是警告，套同一個警告框會誤導使用者以為
  一切正常的狀態也是個警示。

- `gbm_ref_picker.dart` 的搜尋框改用 `gbmInputDecoration()`，是 G4 批次
  沒涵蓋到（picker 早於那批）的唯一一處裸 `TextField`，補上 accent 色
  `focusedBorder`，即 spec 的 `focus` 欄位種類收尾。

**計畫原訂「6 個對話框」，實際落地是 7 個對話框檔案**（漏算
`delete_branch_dialog.dart`）；如實記在 commit 訊息裡而非悄悄照搬計畫的
數字。`GbmWarningBanner` 本身與它僅存的 4 個螢幕級呼叫端
（`welcome_screen.dart`、`workspace_screen.dart`、`worktrees_panel.dart`、
`update_dialog.dart`）不動。

## 驗證

- `flutter analyze --no-pub`：0 issue。
- `flutter test`：全數 2824 則通過（1 則既有 skip，與本輪無關）。
- 裝置層：本輪改動的是 `GbmDialogShell`（全部對話框共用）與
  `GbmButton`（所有動作列按鈕），但 `integration_test/` 裡只有兩個檔案
  命中對話框相關的 `GbmActionId`／widget 名——`worktree_pending_counts_test.dart`
  只開 Worktrees 面板本身，不碰任何對話框；`rename_branch_flow_test.dart`
  會真的開 `GbmDialogShell`、輸入 `gbmInputDecoration()` 套用過的欄位、
  點動作列按鈕。跑了後者：`-d macos`，2/2 綠燈（"Failed to foreground
  app" 那行不是失敗信號，[TEST-foreground-line-is-not-a-failure]）。
- Golden test（`gbm_widgets_golden_test.dart`）：21/21 綠燈，
  `GbmWarningBanner` 本身沒被這輪改動，符合預期。
- `scripts/check-rule-pins.py`：172 條規則、70 個交叉引用，懸空 0。

## 本輪沒有動、也沒有新開的缺口

G2–G8 依計畫全數做完，沒有產生新的 `DRIFT-` 項目。
