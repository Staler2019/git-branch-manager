# feat/add-color — dim-gray 灰色深色主題，以及 token 清理

## Situation

使用者回報：「current the dark is too dark for windows user to view texts」。`dark-technical` 的 panel 是 `#0d1117`，`--text-tertiary #6e7681` 在上面只有 4.12:1。盤點 token 時另外找到三件事：

- `scrollbarThumb` 三個主題都有定義但沒有讀者；所有 `Scrollbar` 畫的是 Material 依 `onSurface` 算出的灰。
- `dangerHover`、`diffAddStrong`、`diffDelStrong` 有定義、零讀者；spec 裡也沒有任何 `.gbm-*` 規則讀它們。
- `light-ide` 的 `textLink`／`accentHover` 是 `#1857b8`，spec `colors.css` 是 `#1f6ce0`。來源：#32（`4474d550`）把 Qt `ThemeTokens.cpp` kLightIde 第 80/82 行的 `#1f6ce0` 寫成 `_accent700`，沒有裁定支持。

亮暗判斷原本寫成 `variant == GbmThemeVariant.darkTechnical`（`gbm_theme.dart` 的 brightness、`GbmEffects` 陰影），新增第二個暗色主題會被默默歸成亮色。

## Task

使用者裁定（2026-11-12、2026-11-15）：

- dim-gray 色值照設計稿 `docs/claude-design-demo/dim-gray-theme-spec.html` 的 token 表；圖示 `brightness_4`。
- light-ide 照 spec 修。
- `diff*Strong`／`dangerHover`：「沒用到，那就移除」。
- 選取行 overlay 維持 `accent×0.18`（方案 A），72 尺標維持 `textTertiary×0.5`；兩處低於 4.5 的格子（neutral add 4.39、light-ide ctx 4.44）接受、不處理。
- 7 個 commit 的計畫經 plan-verifier READY，使用者選「核准，AUTO」。

## Action

```
375600d3 chore     設計稿（G1：三輪 spec-auditor，缺陷全修，artifact v4）
b7f5f8b6 refactor  GbmThemeVariant.isDark；GbmEffects.shadow*(Brightness)；刪 context.gbmThemeVariant
6a6288c0 fix       light-ide textLink/accentHover → #1f6ce0
ada621b6 refactor  移除三個零讀者 token 與 _red600
154e678e feat      ThemeData.scrollbarTheme.thumbColor = scrollbarThumb
a301c2eb feat      dimGray：色盤、tokensFor、_readSaved、切換按鈕、偏好設定 label、7 張 golden
(本 commit) chore  本文件、tokens-reference.md 三段 Departure
```

- 陰影改吃 `Theme.of(context).brightness`：5 個 lib 呼叫端、1 個測試呼叫端。
- View → Theme 沒有每個主題的子選單（`gbm_menu_model.dart` 只有 submenu parent），handler 依 `GbmThemeVariant.values` 循環，dimGray 自動加入；整合測試 `view_theme_cycle_test.dart` 走 macOS 選單項目，讀的是同一張 handler map（[ACT-one-handler-map]）。

## Result

- dimGray 對比（`tokens-reference.md` 的表）：panel 上 primary/secondary/tertiary/link = 13.25/8.51/5.49/6.21；selected 上 = 11.50/7.39/4.76/5.39；ref chip 對 selected 1.87。
- Mutation（a301c2eb）：跑 9 個、9 個轉紅；紅掉的測試共 10 個。lane 0 那個 mutation 另外紅了既有的 30° 色相測試，其餘都只紅預期的那個。全套 +4653 ~19 綠，analyzer 0。
- Mutation（154e678e）盲點：換成 `borderDefault` 的 mutation 存活，因為每個主題的 `scrollbarThumb` 都等於 `borderDefault`（dimGray 也是 `#4f5966`）。改用 `textTertiary` 與「不設定」兩種 mutation 補驗，commit 訊息有註明。
- ~~每個 commit 單獨 checkout 跑全套：沒有逐一做。commit 4 提交前全套 4607 綠、commit 5 提交前 4653 綠；commit 1–3 單獨 checkout 的結果沒有紀錄，算未驗。~~ 每個 commit 單獨 checkout 跑全套（暫時 worktree）：b7f5f8b6 +4603、6a6288c0 +4604、ada621b6 +4604，皆 ~19 skip、analyzer 0；154e678e 提交前 4607 綠、a301c2eb 提交前 +4653 綠。
- 自己更正的錯誤陳述（設計階段）：text-tertiary 對 selected 4.498 誤寫為 4.50；「dim-gray 選取行較淡」實測各主題都在 1.18–1.25；合成色沒把字也疊色，實際 neutral add 4.39、light-ide ctx 4.44；停用圖示底色應為 `surfacePanelRaised`；Material scrollbar 預設 alpha 亮 0.1、暗 0.3；「接錯」應為「未接線」。
- 未處理（非目標）：`dialog_route.dart:20` 的 `Colors.black54` barrier、`gbm_dialog_shell.dart:77` 的黑色 0.3 陰影、Material tooltip 與文字選取子主題。
- ~~Golden 只在 macOS 跑；本機 Darwin 27，CI macos-26，新 PNG 是否與 CI 一致未驗證。若 CI golden 腿對 dimGray PNG 轉紅，從 CI artifact 重新產生。~~ Golden 只在 macOS 跑；本機 Darwin 27 產生的 7 張 dimGray PNG，在 PR #223 的 CI「Flutter UI - macOS (arm64)」（run 43717164940）比對通過。
- 沒有蒸餾新 rule：亮暗單一來源已由 `isDark` 與 `gbm_theme_test.dart` 編碼。
