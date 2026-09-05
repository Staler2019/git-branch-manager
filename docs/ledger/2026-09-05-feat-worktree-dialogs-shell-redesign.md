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

## ~~本輪沒有動、也沒有新開的缺口~~（訂正：本輪自己開的一個缺口，已在同一輪修掉）

~~G2–G8 依計畫全數做完，沒有產生新的 `DRIFT-` 項目。~~ 這句話錯了，訂正如下：
**G4b 自己就開了一個缺口，使用者事後回報「新增worktree的位置沒有預設了」**，見下一節。
~~修掉之後才是真的沒有新開的缺口。~~ **這句話又錯了一次**，而且錯在同一個地方：
上一段訂正只涵蓋了 `labelText`，但 G4b 那個固定高度的 `SizedBox` 其實一次帶進
**四個**缺陷，`labelText` 只是最先被看見的那一個。剩下三個要等真的把 app 跑起來
截圖才看得到，記在本檔最後的〈追加二〉。訂正的教訓不是「再補一句」，是
[CULT-correct-the-record] 的另一面——**一個原因造成的缺陷，修掉看得見的那個之後
要回頭問還有沒有同源的**，而不是把第一個修好就當作整組結案。

## 追加：G4b 自己造成的迴歸——`labelText` 的浮動標籤放不進固定 30px 的框

PR #136 開出、CI 全線通過之後，使用者回報 Add Worktree 的「位置」欄位「沒有預設
了」。查證前先讀 `_computeDefaultPath()`：邏輯沒變、既有三則斷言 `controller.text`
的測試全綠——問題不在算出來的值，而是**畫出來的樣子**。

**根因**：`InputDecoration.labelText` 是 Material 的浮動標籤，需要框的上方留白；
G4b 把每個單行欄位包進 `SizedBox(height: GbmSpacing.inputHeight)`（30px）之後，
這塊留白就沒有了。寫兩個對照用的 scratch widget test（未提交,量完即刪）量出來：

```
有 labelText：label rect  Rect.fromLTRB(36.0, 14.9, 59.3, 26.1)
             value rect  Rect.fromLTRB(36.0, 20.0, 764.0, 43.0)
             field rect  Rect.fromLTRB(20.0, 20.0, 780.0, 50.0)
             -- label 的頂端 14.9 比 field 自己的頂端 20.0 還高，畫到框外，
                且與 value 文字前 ~6px 重疊。
無 labelText（僅 hintText）：
             value rect  Rect.fromLTRB(36.0, 20.0, 764.0, 43.0)   -- 同一個值
             field rect  Rect.fromLTRB(20.0, 20.0, 780.0, 50.0)   -- 完全落在框內
```

同一個預設值兩種畫法：有 `labelText` 時被自己的標籤蓋住開頭幾個字元，使用者一眼
看去像是空的或亂碼；拿掉 `labelText` 之後同一個值乾淨地落在框內。這就是回報的
「沒有預設」——值一直都在，只是視覺上被蓋住了。errorText 另外量過（`新分支名`
場景）：落在 y=33–50，仍在 field 自己的 20–50 之內，沒有溢出、沒有例外，判斷為
不受影響，此輪不動。

**範圍**：`gbmInputDecoration(...labelText:...)` 在 `lib/` 底下有 **9 處呼叫、
橫跨 7 個檔案**——不只使用者回報的那一個。全部改掉，不是本輪不做的縮減：

| 檔案 | 欄位 |
|---|---|
| `add_worktree_dialog.dart` | 新分支名、位置 |
| `new_branch_dialog.dart` | 名稱 |
| `credential_dialog.dart` | 帳號 / Token / 密碼（依 `obscure` 而定） |
| `lock_worktree_dialog.dart` | 原因 |
| `repository_settings_dialog.dart` | 名稱（僅限此 repository）、Email（僅限此 repository） |
| `preferences_dialog.dart` | `_NumberField`（4 個呼叫端共用一個定義：每隔／記憶體中保留／記錄檔保留）、全域 gitignore 檔案路徑 |

**修法**：每一處都改成 G3 既有的外部標籤樣式（`Text('label', style:
TextStyle(fontSize: GbmTypography.textXs, color: colors.textSecondary))` 疊在
欄位上方，`gbmInputDecoration()` 呼叫改成只帶 `hintText`），而不是給
`InputDecoration` 加 `floatingLabelBehavior: never`（後者一有值就整個標籤消失，
把 identity/`_NumberField` 這種本來就有預填值的欄位變成永遠沒有標籤）。這個方向
是 spec 自己畫的：`worktree-dialogs-spec.html` 的「Proposed」區塊（613/618 行）對
「新分支名稱」「目標路徑」用的正是 `fld__label` 外部標籤，跟本輪已經套用在
「分支」「來源」上的樣式一模一樣——不是另闢蹊徑，是把同一個既有樣式套滿。

**`gbmInputDecoration()`／`gbmMultilineInputDecoration()` 拿掉了 `labelText` 參數**
（[CULT-orphan-wiring] 的反向：不是找不到呼叫端才刪，是刪掉以後才能保證沒有第十
個呼叫端重蹈覆轍——參數不存在，編譯期就擋掉）。連帶查過
`gbmMultilineInputDecoration()` 的三個呼叫端（`merge_dialog.dart`／
`create_tag_dialog.dart`／`cherry_pick_dialog.dart`），本來就沒有一個傳
`labelText`，一併拿掉參數。

**測試**：`find.widgetWithText(TextField, '<label>')` 這個既有斷言模式在標籤搬出
`TextField` 之後全部失效（因為 `widgetWithText` 找的是「這個型別的 widget 底下有
沒有這段文字的後代」，外部 `Text` 不再是 `TextField` 的後代）——grep 全部 9 個字串
只中 `add_worktree_dialog_test.dart`（12 處）、`new_branch_dialog_test.dart`
（2 處），改用 `find.byKey(const Key('...'))`（本檔既有慣例，如
`history-search-field`），新增穩定的欄位 key。`dialog_copy_test.dart`／
`lock_worktree_dialog_test.dart`／`preferences_dialog_test.dart` 三個檔案的既有
斷言原本就沒有依賴 `widgetWithText`，改完全綠，不用動。

新增的迴歸測試是**用矩形斷言**，不是量高度或比對 `controller.text`——
[FLU-finder-proves-existence-not-position] 的教訓：`find.text('位置')` 存在只證明
有這段文字，不證明它畫在哪裡。斷言外部標籤的 `rect.bottom <= field rect.top`
（標籤完全在欄位上方，不重疊），並斷言 `field.decoration?.labelText` 為
`null`。Mutation-check：把 `add_worktree_dialog.dart`「位置」的外部 `Text` 連同
`SizedBox` 一起刪掉（模擬「標籤消失」這個可觀察缺陷），跑
`add_worktree_dialog_test.dart` 得到 `+26 -2`——只有這兩則新測試（矩形斷言、樣式
斷言）變紅，其餘 26 則全綠；同樣手法對 `new_branch_dialog.dart` 的「名稱」得到
`+22 -2`。兩次都用 scratchpad 副本復原，`diff` 確認逐位元組相同，沒有用
`git checkout --`。

**驗證**：`flutter analyze --no-pub` 0 issue；`flutter test` 全數 2829 則通過
（比追加前的 2824 多 5——新增的 rect 斷言測試）；`dart format
--set-exit-if-changed .` 0 changed；golden test 21/21；
`scripts/check-rule-pins.py` 176 條規則、74 個交叉引用，懸空 0；grep
`integration_test/` 底下這 7 個對話框／`_NumberField`／相關 `GbmActionId`，
沒有命中，裝置層無需重跑。

**未驗證**：這輪的證據全部來自 `flutter_test`（真實的 layout/paint pipeline，
但沒有實體視窗）。使用者實際在 `-d macos` 上點開 Add Worktree、選一個分支、肉眼
確認路徑欄位不再被標籤蓋住——這一步沒有做，比照
[STATE-refresh-entry-point]「未在真實硬體驗證」的記法，如實記下而不是假裝做過。

~~**未驗證**~~ **訂正：已驗證，而且驗證本身找到了三個新缺陷。** 上面這段寫的時候
是實話；後來補做了——`flutter run -d macos --release`、`cliclick` 點開 Add
Worktree、`screencapture -R` 只截該視窗（不截全螢幕，遵守標準規則）。標籤確實不再
蓋住路徑，這一半確認了。**但同一張截圖也讓使用者一眼看出另外三件事**，見〈追加二〉。

這件事本身值得記：**「用 widget test 證明」跟「跑起來看」找到的不是同一類缺陷**。
`flutter_test` 有真的 layout/paint pipeline，所以它能量到的東西是真的；問題是我
那時候量錯了對象（量 widget 的 rect，不是畫出來的框），而**肉眼不會量錯對象**。


## 追加二：實機截圖之後使用者回報的三件事

使用者看完那張實機截圖，回了三句：

> 那我沒選分支之前，應該把選位置那邊鎖起來，我剛剛一直以為可以直接選位置用了。
> 另外隔壁的瀏覽button畫面與瀏覽textbox高度不同，所以spec你沒有照做
> 而且dialog內的畫面底色也不對

三件事，一件是裁定，兩件是缺陷。

### 一、位置在選分支之前要鎖起來（裁定）

位置的預設值來自 `_computeDefaultPath()`，而它在分支名為空時回傳 `null`——所以
在選分支之前，那個欄位**只可能是空的**，卻長得可以用。使用者先伸手去按的是旁邊的
「瀏覽…」，所以兩半用同一個條件一起鎖。

條件就是 `_computeDefaultPath()` 自己 null 掉的那一個（`effectiveBranchName`
非空），不是另外再推導一次（[CULT-single-source-of-truth]）。兩種模式的條件不同
是重點：checkout 既有分支看 `_picked`，建立新分支看**打進去的名字**——後者在
picker 預設停在 HEAD、`_picked` 已經非 null 但名字還沒打的時候仍然該鎖，那一則
單獨寫了測試釘住，否則「有選到東西」跟「有名字可以組路徑」會被當成同一件事。

Mutation：`pathEnabled` 常數化成 `true` → `-2`；只解開按鈕那一半 → `-1`。

### 二、瀏覽 button 跟 textbox 不一樣高

**這是本輪 G4b 自己造成的，而且跟 `labelText` 同源**：`SizedBox(height: 30)` 框住
的是 widget，不是 Material 畫出來的框。

`_RenderDecoration.performLayout` 把框畫在

```
containerHeight = min(max(contentHeight, minContainerHeight), maxContainerHeight)
```

`isDense: true` 把 `minContainerHeight` 設成**文字自己的高度**，而 `SizedBox` 只
提供了 `maxContainerHeight`——所以 `min` 落在文字高度上，框比它的外殼矮。實機截圖
量到 **23px 對按鈕的 30px**；widget test 的字型下是 24 對 30，同一個缺陷、不同
數字。

改成 `isDense: false` 之後那個下限變成 `kMinInteractiveDimension`(48)，`min` 就落
在外殼的 30，**任何字型都一樣**——這是不必拿 `contentPadding` 去對字型算數的原因，
也是這個 helper 的 doc comment 本來就拒絕做那件事的原因。代價是它從此**依賴外面
那個 `SizedBox` 真的存在**：沒有上界的話同一條式子給的是 48。`gbm_ref_picker.dart`
的搜尋框是全 app 唯一沒有包 `SizedBox` 的單行呼叫端，一併補上。

**為什麼第一次探這個 bug 什麼都沒找到**：我量的是 `getRect(find.byType(TextField))`，
回來是 30.0，跟按鈕一樣——因為那是 `SizedBox` 加上去的尺寸。框是
`_RenderDecoration` 底下**另一個 child RenderBox**，tight 到它自己算出來的
`containerHeight`。唯一能跟這個缺陷唱反調的斷言，是量那個 child 的那一種：

```dart
find.descendant(of: find.byType(InputDecorator), matching: find.byType(CustomPaint))
```

這就是 [TEST-fixture-cannot-disagree] 第 14 列再深一層——那一列講的是
`controller.text` 是「模型」的代理，這裡是 widget 的 rect 是「畫出來的東西」的代理。
兩者都真、都被測試、都跟使用者看到的東西不同一件事。

### 三、底色不對

兩處，都是同一句話的兩半：

- **欄位框沒有底色**。spec `.box` 寫 `background: var(--gbm-surface-panel)`
  (#0D1117)，實作沒有 `filled`，所以殼的 `surface-panel-raised`(#161B22) 直接透
  上來——欄位讀起來跟對話框齊平，而不是陷進去。
- **ref picker 的清單區也沒有底色**。spec `.box--list` 是
  `background: var(--gbm-surface-sunken)`。

順帶量到第三件沒人回報過的：**邊框是純黑**。裸 `OutlineInputBorder()` 帶的是裸
`BorderSide()`，也就是 `Colors.black` 1px——不是 theme 的顏色。截圖裡量到
`(0,0,0)`，而旁邊按鈕的邊是 `(48,54,61)` = `#30363D` = `border-default`。三個狀態
現在各自明寫，因為欄位**會停在 disabled**（位置預設就是鎖的），把黑框留在那個狀態
等於留在使用者第一眼看到的那一格。

### 四、順著量到的第四個：有錯誤的欄位框只剩 10px

沒人回報，是修高度時量出來的。`errorText` 是畫在框**下面**的 subtext，而
`SizedBox(30)` 夾的是「框 + subtext」——所以一個有錯誤的欄位，框被壓到 **10px**。
`add_worktree`（重複分支名）、`new_branch`、`rename_branch` 三處會遇到。

訊息改成框下面的外部 `Text`（`gbmFieldError()`，spec 的 `.fld__hint` 形狀），
helper 只收 `hasError` 換邊框色。**跟這輪稍早把 `labelText` 移到框外是同一個決定**
——一個固定高度的框裝不下 Material 想放在它上面或下面的東西，兩次都是。

`rename_branch_dialog_test.dart` 有三則斷言讀 `field.decoration!.errorText`，正是
第 14 列的形狀（讀模型，不讀畫面），改成斷言畫出來的那一行——用顏色（`danger`）認
而不是用文字認，否則別處剛好寫一樣的字也會過。

### 驗證

`flutter analyze --no-pub` 0 issue；`flutter test` 2843 則全綠（追加一是 2829，
多出來的 14 則是這次的新斷言）；`dart format --set-exit-if-changed .` 0 changed；
golden 21/21。

Mutation-check 共 **5 次**，reddened **8 則**（4 / 1 / 1 / 1 / 1）：`isDense` 改回
true → `-4`；單行 helper 的 `filled` 關掉 → `-1`；`resting` 改成黑色 → `-1`；
picker 清單底色改成 `surfacePanel` → `-1`；picker 搜尋框外殼 30 改 48 → `-1`。

**其中一次第一版是無效的**：`filled: true` 那個 anchor 在單行與多行兩個 helper 裡
各出現一次，`count(old)==1` 的斷言擋下來了，回報的是 `matched 2x` 而不是一個假的
全綠。這正是 [TEST-mutation-check-every-test] 要求先斷言出現次數的原因，如實記下
——第一次跑出來的「All tests passed」不是證據，是沒改到。

裝置層：`integration_test/` 底下只有 `worktree_pending_counts_test.dart` 命中
（照 [TEST-grep-misses-intent-driven-device-tests] 用 `GbmActionId`、面板名稱、
`GbmRefPicker`、`gbmInputDecoration` 一起 grep，不只 grep 改動到的字串）。跑過，**1/1，4 秒**。`Failed to foreground app; open returned 1` 照樣印出來，但後面
接著測試結果行——[TEST-foreground-line-is-not-a-failure] 說的就是這件事。

### 實機驗證（這次是真的做了，而且量了像素）

`flutter run -d macos --release`，`pkill` 過確定沒有 stale process
（[TEST-stale-process-blocks-tier]），並且用**跑起來的那個 build 自己的 History
畫面**確認它帶著這三個 commit——比對 mtime 不可靠，看它畫出來的東西才可靠。
`screencapture -R` 只截該視窗。

截圖轉 BMP 逐像素掃邊界（`sips` + 自寫的 BMP parser，沒有 PIL），量「位置」那一列：

| | 修之前（上一輪的截圖） | 修之後（鎖住） | 修之後（解鎖） |
|---|---|---|---|
| 輸入框高度 | 23 | **30.0** | **30.0** |
| 瀏覽鈕高度 | 30 | **30.0** | **30.0** |
| 上下緣 | 不齊 | **完全對齊** | **完全對齊** |
| 邊框色 | `(0,0,0)` 純黑 | **`(48,54,61)` = #30363D** | 同左 |
| 框內底色 | 無（透出 #161B22） | **`(13,17,23)` = #0D1117** | 同左 |

對話框自己的底 `(22,27,34)` = #161B22 = `surface-panel-raised`，本來就對，spec 也是
這個——所以「底色不對」指的是**欄位沒有底色**，不是殼的底色錯。這點值得寫下來：
回報說「底色不對」的時候，錯的可能是缺一層，而不是那一層畫錯。

## 追加三：選了 origin/… 就建不出 worktree

使用者回報，附上完整指令與 git 的回話：

> i can select origin worktree, but cannot create worktree from it.
> `… worktree add -b feat/worktree-dialogs-shell-redesign …/origin-feat-worktree-dialogs-shell-redesign origin/feat/worktree-dialogs-shell-redesign`
> exit255
> `fatal: a branch named 'feat/worktree-dialogs-shell-redesign' already exists`

### 先量，再改

scratch repo、git 2.55，三種情況分別跑兩種指令：

| 本地 `feat/x` | `add -b feat/x <p> origin/feat/x` | `add <p> feat/x` |
|---|---|---|
| 不存在 | 建出追蹤分支，exit 0 | 不適用 |
| 存在、沒被佔用 | `fatal: a branch named 'feat/x' already exists` | exit 0 |
| 存在、已被 checkout | 同樣 fatal | `fatal: 'feat/x' is already used by worktree at …` |

第一次量的時候把「存在」跟「已被 checkout」混在一起了（前一個 case 建出來的 worktree
就佔著那個分支），三列裡有兩列其實是同一列。**重量一次**，讓「存在但沒被佔用」是真的
沒被佔用，才看得出中間那一列的 `add <p> feat/x` 是 exit 0——也就是修法。

### 兩個缺陷，不是一個

1. **`_submit` 對每個遠端選擇都送 `-b`。** 所以上表中間那一列是硬失敗，而那是最常見
   的情況：一個你本地已經有、只是從清單的遠端那半邊點下去的分支。
2. **`_entries` 完全沒有 gate 遠端列。** 本地 `feat/…` 那一列會變灰、標「已在
   git-branch-manager」，旁邊的 `origin/feat/…` 卻是可選的——同一個分支，兩種畫法。
   使用者踩到的是這一列，所以他看到的錯誤訊息還講錯了問題（說分支已存在，實際上是
   已經被別的 worktree 佔著）。

只修 1 的話，第三列會從「講錯問題的 fatal」變成「講對問題的 fatal」，還是 fatal；
只修 2 的話，第二列照樣壞。兩個都要。

順帶第三件：**預設路徑用的是遠端全名**，所以提議
`…/worktrees/gbm/origin-feat-x`，但那個 worktree 的分支其實叫 `feat/x`。使用者貼的
指令列裡就有。路徑現在跟著「真正會被 checkout 出來的那個分支」走。

### 雙胞胎

照 [GIT-primary-not-current-worktree] 的「修完一個就去 grep 它的雙胞胎」，
`checkout_dialog.dart` 有一模一樣的 `createBranch: _selectedIsRemote`，量過同樣是
`fatal: a branch named … already exists`。連帶那行文案「建立本地分支「X」，追蹤 Y。」
也承諾了不會發生的事——現在只在真的會建立時才畫。

**這條規則上次是反方向用的**（修好一個、去找還沒修的同款）；這次是同一條的正向：一個
回報進來，先問「還有誰是這個形狀」，而不是只修被指到的那一個。

### 一句被記了一半的註解

原本 `_submit` 的註解寫「`git worktree add <path> origin/feat/x` 會自己建追蹤分支
(measured)」。重量之後：**那只在本地還沒有 `feat/x` 時成立**，一旦有了，同一道指令改成
**detach**。註解記的是量到的那一半，讀起來像通則——[CULT-scrutinise-the-comment] 的
標準形狀，已在原處改掉。

### fixture 本來說不出自己要測的事

Add Worktree 的 fixture 只有一列遠端 `origin/release/0.5`，而它**有**本地對應分支
`release/0.5`；偏偏那則測試叫「checking out a remote-**only** branch creates a tracking
local」，斷言 `createBranch: true`。也就是說：**測試的名字描述的情況，fixture 表達不
出來，而且斷言釘住的正是缺陷本身**。`-b`-always 能活到現在，這則測試是主要原因。

兩邊的 fixture 都補到能分辨三種情況（Add Worktree 三列遠端、Checkout 兩列），每一列
對應上表的一行。

「已在 gbm-lfs」那則舊測試的 `findsOneWidget` 也失效了——遠端列現在合法地帶同一個字串。
照 [TEST-fixture-cannot-disagree] 第 12 列，改成只看它要的那一列，不是把 1 改成 2
（把 1 改成 2 的話，光是遠端那列就滿足了，本地那列不畫也會綠）。

### 驗證

`flutter analyze --no-pub` 0 issue；`flutter test` 2849 全綠；`dart format` 0 changed。
Mutation-check **5 次**，reddened **6 則**（1 / 1 / 1 / 2 / 1）：`localExists` 常數化
→ `-1`；遠端列的 `taken` 常數化 → `-1`；路徑保留遠端前綴 → `-1`；checkout 的
`_createsLocalBranch` 回 true → `-2`；checkout 的 `target` 送遠端名 → `-1`。

新增一條 pin：[GIT-remote-pick-b-only-when-absent]，把上表連同「遠端列的佔用等同它本地
對應分支的佔用」一起記下來。

## 追加四：View → Log 沒有 toggle 效果

> log沒辦法隱藏，view>log那個沒有作用，沒有toggle的效果

`GbmActionId.viewLog` 只呼叫 `GbmSplitPaneController.open()`，而 `open()`
（`_openToMinimum()`）在已經開著時直接 return——所以**第一次按之後每一次按都完全沒有
反應**。往下一層看，controller 整個類別只有一個方法：

```dart
class GbmSplitPaneController {
  void open() => _state?._openToMinimum();   // 就這樣
}
```

抽屜是單向門。開了之後唯一的回頭路是去拖那條分隔線，而那條線在抽屜關著的時候貼在視窗
最底部，本來就不好找——這就是為什麼使用者的描述是「沒辦法隱藏」而不是「按了沒反應」。

補上 `close()` / `isOpen` / `toggle()`，`_openToMinimum()` 與 `_collapse()` 收斂成同一
個 `_setExtent()`（兩邊都要 persist、都要 `onFlexChanged`，分開寫就是等著漏一個）。

~~**關掉寫 0 而不是 minExtent**，因為 0 正是 `collapsedByDefault` 的意思，所以關起來的
抽屜重開 app 還是關的。[FLU-splitpane-stored-extent-ignores-min] 那條規則的 initState
clamp 特地 guard 在 `stored[0] > 0`，理由正是「使用者刻意收起來的抽屜不能被 clamp 撐
開」——這次是同一個決定的另一端，寫進去的那個 0 要能活下來。~~

**訂正（追加五）**：上面那段的機制描述是錯的，而且錯的方向剛好讓這一輪自己變成使用者
下一個回報的來源。「關起來的抽屜重開 app 還是關的」只在**存的值真的是 0** 時成立，而
`collapsedByDefault` 當時的實作是 `stored == null && collapsedByDefault`——只要開過一
次就存進了非零 extent，`stored` 再也不是 null，旗標整條分支就走不到了，所以真正會發生
的是「**開過一次之後每次啟動都是開的**」。追加五把這個修掉：那個數字改成只代表高度，
開/關狀態一律由旗標決定，收合時不再寫 0。`_collapse()` 仍然收到 0（不是 minExtent），
這一半沒有變。細節見 [FLU-collapsed-drawer-stores-height]。

`_collapse()` 收到 0 這一半有 mutation 釘著（改成 `minExtent` 會變紅），所以不是註解裡
的宣稱而已；被訂正掉的是它後面那段對「重開 app 之後會怎樣」的推論，而那件事**當時沒有
任何測試在看**——既有那則測試 pump 的是乾淨 profile，看不到差別。

### 兩個入口，兩種語意，不是不一致

狀態列那顆 badge 維持 `open()`。它的意思是「給我看 log」，把正在讀的抽屜關掉是跟它自
己的字面相反；選單那一列叫「Log」，跟旁邊的「Status bar」一樣是檢視開關。

原本的註解寫「so the menu item and the status bar agree on what "open the log" means」
——那句話在只有 `open()` 的世界裡是對的，但它把「兩個入口做同一件事」當成目標，而其實
它們該做的是不同的事。已改寫。

實務上 badge 還是一次性的：它只在 `hasUnreadLog` 時才畫，一開就清掉了，所以「連按兩下
badge」這個情境根本到不了。我本來寫了一則測試釘它，發現前提不成立就刪掉，沒有為了讓
測試跑得動而去 production code 加一個 key——**測不到的路徑不值得為它改介面**。

`_lastSeenOperationLogIndex` 只在「要開」的那一半更新：關閉不揭露任何東西，不該把使用
者沒看過的紀錄標記成已讀。

### spec 沒有這一列

P04 的 `MENUS` 檢視選單是 Toggle sidebar / History 與 Working copy / Commit detail /
Status bar / Graph columns / File list as tree——**沒有 Log**。所以這是 app 自己加的項
目，比照 [STRUCT-no-topbar] 記的 `View → Refresh`。行為對齊旁邊的 Status bar，而兩者
都沒有打勾記號（`GbmMenuItemModel` 根本沒有那個欄位），所以這一輪沒有任何新的「要畫的
值」，不需要 G1 的 spec-auditor。

驗證：analyze 0；`flutter test` 2850 全綠；mutation 2 次、各 1 則變紅。

## 追加五：log 不預設打開

> log不預設打開，使用者toggle才開

追加四把 `View → Log` 修成真的 toggle，使用者用了之後回報的下一件事。這兩件事是同一個
機制的兩面，而且**是上一輪讓每個人都踩得到它**。

### 旗標只在乾淨 profile 上生效

```dart
final double initialExtent =
    (stored == null && widget.spec.collapsedByDefault) ? 0.0 : widget.spec.defaultExtent!;
```

`collapsedByDefault` 的條件裡多了一個 `stored == null`。但抽屜只要被打開過一次，
`_setExtent()` 就會 `_persistFlexes()` 寫進一個非零 extent——從此 `stored` 永遠不是
null，這條分支再也走不到，旗標形同不存在。

也就是說旗標的實際語意是「**沒開過的人預設收合**」，而它的名字說的是「預設收合」。這兩
句話在第一次開啟之前完全一致，之後永久分歧，中間沒有任何錯誤訊息。

### 那個數字是高度，不是狀態

裁定照字面實作：`collapsedByDefault` 的 pane **每一次啟動都是收合的，與存了什麼無關**。
於是存的那個數字只剩一個意思——「重新打開時要回到多高」：

| 位置 | 改動 |
|---|---|
| `initState` | `collapsedByDefault` 直接起始於 0；clamp 過的 stored extent 收進新的 `_reopenExtent` |
| `_persistFlexes` | 這種 pane 的 **0 不寫入** |
| `_openToMinimum` | 回到 `_reopenExtent`，不是 `minExtent` |
| `_resetToSpecDefault` | 一併清掉 `_reopenExtent` |

第二列是自己長出來的：既然啟動時忽略存的狀態，那把 0 寫進去就只有壞處——它會把使用者拖
出來的高度洗掉，下次打開只能回到 minExtent(90)。第四列同理，View → Reset panel sizes
已經清了 storage，記憶體裡那份不清就會在同一個 session 內把它救回來。

非 drawer 的 extent pane 一行行為都沒變，包含「stored 0 維持 0」——那個 0 在那些 pane
上仍然只可能來自 `_collapse()`（拖曳 clamp 在 `minExtent`），是刻意的收合。

### 已經卡住的人不需要 migration

存著 300 的 profile：數字原封不動留著、啟動時被忽略、第一次 toggle 就回到 300。修好的
同時把他們拖過的高度也還了。

### 乾淨 profile 的測試看不到這個缺陷

既有那則「starts collapsed and the shortcut expands it」從頭到尾是綠的，而且**它是對
的**——旗標在乾淨 profile 上本來就正常。能問出問題的 fixture 得先 seed「上次開過」留下
的狀態，所以 `pumpWorkspace` 加了 `initialPrefs`，測試 seed
`panelLayout.main.log: '[200.0]'`。這是 [TEST-fixture-cannot-disagree] 的
「fixture 無法表達失敗條件」形狀，不是斷言太弱。

新測試三個斷言各釘一件事，mutation 逐一驗過（3 次 mutation，各紅 1 則）：

| Mutation | 預期 | 實測 |
|---|---|---|
| 拿掉 `collapsedByDefault` 啟動覆寫 | 啟動變 200 | 紅 1 則 |
| 拿掉 `_reopenExtent` 還原 | 重開變 90 | 紅 1 則 |
| 拿掉不寫 0 的 guard | storage 被洗成 0 | 紅 1 則 |

第三個斷言讀的是 storage 本身（`container.read(panelLayoutRepositoryProvider).read('main.log')`）
而不是畫面高度——「關閉之後高度還記得」在同一個 session 內從畫面上看不出來，重 pump 一次
又會被 `setMockInitialValues` 洗掉。

### 兩份被推翻的紀錄，就地訂正

追加四那段「關掉寫 0，所以關起來的抽屜重開 app 還是關的」已就地劃掉並改寫（見上）。
[FLU-splitpane-stored-extent-ignores-min] 的 `stored[0] > 0` guard 原本的理由寫的是
「保護使用者刻意的收合」、並舉 `splitterMainLog` 為「stored value 0」的例子——兩句現在
都不成立了，而且第二句正是這個缺陷的根源。已就地加上 **Correction**，並新增
[FLU-collapsed-drawer-stores-height]。

驗證：analyze 0；`flutter test` 2851 全綠（+1）/1 skipped；`dart format` 0 changed；
`check-rule-pins.py` 181 條規則、90 個交叉引用、懸空 0。

## 追加六：log 拖到底關閉

使用者回報:「log可以從視窗下方拖起，卻不能關閉。幫她加上拖到底關閉」。

追加四給了 log 抽屜一個真的 toggle，追加五讓它不再預設打開。剩下的是手勢那一半：
分隔線往上拖可以把抽屜拉開，往下拖卻只會停在 90px，關不掉。

### 為什麼「門檻」不是一行就能加的

第一個看起來對的寫法是在 `_onDividerDelta` 裡把 `_currentFlexes[0] + adjustedDelta`
拿去跟一個門檻比。它不會動，而且不會動的理由不是門檻調得不對：

```
       clamp 之後才寫回 _currentFlexes[0]
                 |
  200 --20--> 180 --20--> 160 ... --20--> 90 --20--> 90 --20--> 90 --20--> 90
                                           ^         ^^^^^^^^^^^^^^^^^^^^^^^^
                                       觸底        指標還在往下走，但每一步都
                                                   從同一個 90 重算，超出量被丟掉

  raw:   90 - 20 = 70   90 - 20 = 70   90 - 20 = 70   ← 永遠是 70，不管拖多遠
```

一格 frame 的 delta 只有幾 px，而 clamp 是有損的：抽屜觸底之後，`_currentFlexes[0]`
就固定是 `minExtent`，所以那個算式看得到的「原始位置」永遠只差一格 frame。指標往下
走 300px 跟走 30px 對它來說一模一樣。

所以要的是第二個數字：`_dragRawExtent`，在 pointer drag 期間累積**未 clamp**的位移。

```
  _currentFlexes[0]  200  180  160  140  120  100   90   90   90    0   ← 畫出來的
  _dragRawExtent     200  180  160  140  120  100   80   60   40   20   ← 拖到哪裡
                                                              ^^^^
                                                        低於 minExtent/2 = 45 → 收合
```

`onDragStart` 開、`onDragEnd` **和 `onDragCancel`** 都關。cancel 也要關是因為留著
非 null 的話，下一次鍵盤方向鍵會走到 drag 分支上，對著指標離開時留下的位置去算。

累積值本身每一步也 clamp，只是下界看閘門：可收合時是 0，否則是 `minExtent`。兩件事
同時成立：往下多拖 300px 不需要再往回拖 300px 才跟得上指標；而**不能收合的 pane，
累積器逐字等於原本的算式**，所以既有的拖曳行為一格都沒動。

### 閘門：只有 `collapsedByDefault` 的 pane 能被拖關

理由是那個 flag 自己的意思。「每次啟動都關著」（追加五）就蘊含著「一定有把它打開的
入口」——log 抽屜是 `View → Log` / Ctrl+Shift+L。沒有這種入口的 pane 被拖到 0 就是
關掉之後回不來，所以它維持原本 floor 在 `minExtent`。

鍵盤刻意不動（`_dragRawExtent == null` 就走原路徑）：方向鍵是離散的一格，不是朝著
底邊去的手勢，而抽屜本來就有 toggle 可以關。使用者要的是「拖到底關閉」，做的就是這個。

### 留下的高度是 minExtent，而且刻意不去「修正」它

`_persistFlexes` 不寫這種 pane 的 0（[FLU-collapsed-drawer-stores-height]），拖著關
只是那個 0 的第二個來源，規則本身不動。但拖的過程會經過 clamp 區，所以最後寫進去的
高度是 90 而不是原本的 200——重開就是 90。真的有一格 frame 大到直接跨過整個 clamp 區
的話，留的是 200。

一度想過拖關時把 `_reopenExtent` 清成 null 讓它「確定性地」回到 minExtent。這反而更
不一致：清的只有記憶體，storage 還是 200，所以同一個 session 內重開是 90、重啟之後
重開是 200。現在這兩種結果各自自洽，如實記在這裡，不另外處理。

### 測試

三則，都在 `test/widgets/split_pane_test.dart` 的 `drag-to-close` group：

| 測試 | 釘住的東西 |
|---|---|
| a collapsedByDefault drawer dragged past the bottom closes | 拖到底真的收成 0 |
| closing by drag keeps a non-zero height to reopen to | 那個 0 沒有被寫進 storage（留下 `[90.0]`），而且還能再打開 |
| a pane that is not a drawer still floors at minExtent | 閘門 |

三則都用 12 次 20px 的 `moveBy`，不是一次 240px 的 `drag`。這是關鍵：**單一大步自己
就超過 clamp 的落差，沒有累積器也會綠**——多次小步才是唯一測得到累積器的形狀
（[TEST-fixture-cannot-disagree]、[TEST-draggable-is-not-a-drop] 的手勢配方）。

既有的「vertical extent mode: drag-down shrinks pane-0」用的正是 `splitterMainLog`
（唯一一個 `collapsedByDefault: true` 的 spec）：從 100 往下 30，raw 70 高於門檻 45，
仍然 clamp 到 90，斷言 `lessThan(100)` 不受影響——依 [TEST-fixture-cannot-disagree]
第 7 列「分組規則改了就要把所有編碼了間距／計數的 fixture 重讀一次」先核對過，不是
等它變紅才發現。

Mutation 3 次，紅的測試數分別是 1 / 2 / 2：

| Mutation | 紅 |
|---|---|
| 拿掉閘門（`canCollapse = true`） | 1（非抽屜那則） |
| 拿掉累積器（改回 `_currentFlexes[0] + delta`） | 2（兩則拖到底的） |
| 拿掉門檻分支 | 2（同上） |

### 沒有加 integration 層測試，以及理由

widget 層跑的就是真的 `GbmSplitPane`、真的 `GbmLayout.splitterMainLog`、真的
`fixedPaneEnd: trailing`——跟 workspace 用的是同一組 spec 與設定，機制那一半是滿的。
剩下「workspace 真的把這個 spec 接到 log 抽屜上」已經由追加四／追加五的三則
`workspace_log_drawer_reachability_test.dart` 釘住了。在 integration 層再寫一則會需要
在多個 `GbmSplitPane` 之間用 `find.descendant` 去岔開同名的 `gbm-split-divider-0`，
那個 finder 的脆弱程度高於它能加上的證據（[TEST-fixture-cannot-disagree] 第 5 列是
同一種「兩個 subject 對斷言無法區分」的形狀）。如實記在這裡，不是漏做。

驗證：analyze 0；`flutter test` 2854 全綠（+3）/1 skipped；`dart format` 2 files
0 changed。
