# fix/issue-169-inkwell-hover — 九處手寫 InkWell 的 hover：照規格逐站核實，不一律套 surfaceHover

## Situation

#169 列出 9 處手寫的 `InkWell`，都沒有指定 `hoverColor`。它們會沿用 `ThemeData.hoverColor`，約 4% 的灰，在實機上看不見。issue 的假設是「一律改用 `surfaceHover`」。逐一讀過程式碼後確認，9 處外層都沒有提供 hover 的 wrapper。

## Task

依 G1：先派 spec-auditor，讓每個要畫的值都追溯到規格引文；把設計交給使用者裁定後才實作。每一處都要以 identity 斷言 token，並做 mutation。

## Action

- **spec-auditor**：稽核草稿 21 個值，12 符合、2 不符、7 無出處。我自己抽查三個做決定用的事實：
  - repo 彈窗列表列是 `gbm-menu-item`，不是 `gbm-row`。
  - 觸發鈕在 P2 兩處 mockup 都是行內 `height:26px`。
  - Preferences 選中項的 class 是 `active`，規格沒有對應的規則。

  三項都屬實。
- **規格並不是一律 `surface-hover`**：
  - `.gbm-tab:hover` 只把文字變成 `--text-primary`，沒有底色。
  - `.gbm-menu-item:hover` 是 accent 底色加 `--text-on-accent` 文字。
  - 選單列項目、觸發鈕、分頁關閉鈕、衝突區塊單行，規格都沒有畫 hover。
- **使用者裁定（2026-10-05）**：
  1. repo 彈窗列照規格做成 menu-item 的 accent 樣式。
  2. 沒有出處的四處比照最接近的元件：
     - 選單列、觸發鈕 → 按鈕的 `surfaceHover`。
     - 關閉鈕 → `.gbm-iconbtn`。
     - 單行 → 列的 `surfaceHover`。
  3. Compare 分頁照 mockup 的行內 `color:text-tertiary`，hover 不變色。理由：「這個tab是可以關的，所以預期行為不同」。
  4. 小的相鄰不符本輪修；衝突檔案列的結構（規格是單行 27px、沒有三個小按鈕）另議。
- **arch-suggester**：兩個 tab strip 需要同一個 `.gbm-tab`，所以把剛改好的 `_Tab` 提升為 `lib/widgets/gbm_tab.dart` 的 `GbmTab`（refactor 獨立成一個 commit）。padding 與字重由呼叫端傳入，不改任何畫面。
- **commits**：

  | commit | 內容 | mutation |
  |---|---|---|
  | `84c2982` | 衝突檔案列；選中列 hover 透明，因為 ink 畫在 Material 底色之上，而 `.gbm-row.selected` 勝過 `:hover` | 2 個，各紅 1 個 |
  | `b8f5233` | Preferences 左側導覽 | 1 個，紅 1 個 |
  | `eb59a46` | repo 彈窗列改為 accent 樣式：底色、名稱、icon、尾端標籤（`.gbm-menu-shortcut` 的 0.8） | 4 個，各紅 1 個 |
  | `d05ecc0` | workspace 分頁 | 3 個，各紅 1 個 |
  | `373525f` | refactor：`GbmTab` | 既有 76 個測試照綠 |
  | `d4b75c6` | Repository Settings 分頁條改用 `GbmTab` | 整檔改回裸 InkWell，紅 1 個 |
  | `8344940` | 沒有出處的四處 | 5 個，各紅 1 個 |
  | `7dfda47` | 觸發鈕 26px／padding 7、關閉 icon 12px／textSecondary、選單列文字 textSecondary | 5 個，各紅 1 個 |

- **過程中的修正**：
  - 觸發鈕的測試先寫成 dark 主題，結果實作前就綠了。原因是規格的 dark 主題 `--surface-panel-raised` 與 `--surface-hover` 同為 `#161b22`（`[TEST-fixture-cannot-disagree]` 第 5 型：兩個值對斷言來說無法區分）。改用 Light IDE 後才紅。
  - 關閉鈕的 icon 色會做動畫，hover 當下仍是舊色，要等 `pumpAndSettle` 後才斷言。
  - repo 彈窗列的測試原本以 `Offset.zero` 當作「離開」，但那一點仍在列內，改成畫布角落。
- **掃描**：改過的檔案裡所有 `InkWell(`／`GestureDetector(` 都已有 hover。剩下的 `GestureDetector` 只是包住 InkWell 的右鍵 wrapper，或是自己用 `MouseRegion` 畫 hover 的 `_FooterAction`。

## Result

- 9 處都有 hover，值都追溯得到規格或使用者裁定。每個新測試都經過 mutation，紅的範圍精準。
- **已知限制**：觸發鈕在 dark 主題下 hover 沒有可見變化，因為規格本身讓兩個 token 同值。
- **另議**：衝突檔案列的結構。規格是單行 27px，沒有 Take Ours／Take Theirs／Mark Resolved 小按鈕。範圍大，留給使用者決定，本輪未開 issue。
