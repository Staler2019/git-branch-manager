# flutter-upgrade — CI 的 Flutter 釘版統一到 3.47.4（#151）

## Situation

本機 Flutter 3.47.4 / Dart 3.13.3，CI 三個 workflow 與 `session-start.sh` 釘 3.44.9（Dart 3.12.2），
`pubspec.yaml` 為 `sdk: ^3.12.2`。`dart format` 隨 SDK 漂移，#150 發現 `worktrees_panel_test.dart`
在兩版間來回翻。本機 golden 12 紅，`2026-09-28-chore-accept-toolchain-bump` 已量證是 SDK 造成
（macos-26 + 3.44.9 全綠）。

## Task

照 #151 清單：四處釘版改 3.47.4、全庫 format 獨立 commit、analyze 0、golden 處置、評估 sdk 下限、
就地更正三條 CI 規則。使用者裁定 sdk 下限升到 `^3.13.0`。

## Action

- 確認 3.47.4 存在於 `releases_linux.json`，Dart 3.13.3；Linux tarball HTTP 200。
- **先量後決定**（HEAD 5a1b063，本機 3.47.4）：pub get 不改任何 tracked 檔（lock 與
  `analysis_options.yaml` 已在 accept-toolchain-bump 接受過 3.47 的結果）；analyze 0；
  format 6 檔差異；`flutter test` +2989 ~1 −12，`test/goldens` 單跑 +9 −12 → 非 golden 0 紅。
- 回滾契約經 plan-verifier 兩輪 REVISE 修正：C1/C2/C5 互相綁版本，**只有「C1–C5 一起退」與
  「只退 C6」是 CI 綠的回滾**，反序逐一退的中間狀態都紅。
- C1 釘版。C2 下限 → lock 只改 `sdks.dart`；language version 變 3.13 後 format 差異 **6 → 61 檔**。
- C3 `dart format .`：61 檔，去除空白與逗號後逐字相同（52 檔含尾逗號變動），純格式。
- C4（lint 修正）**略過**：analyze 全程 0。
- C5 `--update-goldens`：正好 12 張 PNG 變動。mutation：換回舊圖 +9 −12，新圖 21 綠。
- 每個 commit 的閘門：

| Commit | analyze | format 差異 | flutter test |
|---|---|---|---|
| C1 釘版 | 0 | 6 | +2989 ~1 −12（goldens） |
| C2 下限 | 0 | 61 | +2989 ~1 −12 |
| C3 format | 0 | 0 | +2989 ~1 −12 |
| C5 goldens | 0 | 0 | +3001 ~1，全綠 |

- C6 就地更正 `[CI-dart-sdk-floor]`、`[CI-formatter-version-drift]`、`[CI-newer-flutter-dirties-tracked-files]`。
  `arch-testing.md` 的「Flutter 3.47.5」是一次歷史量測，保留；`cq.yml` 的 3.12.2 註解是在說明
  lint 為何存在，保留。

- **CI 第一輪：macOS 紅 3**（2998 過），全是 `GbmIconButton` 三主題，各 6px、0.00%。本機 21 綠。
  計畫的停止點觸發，停下回報。使用者選 A：暫時加 `upload-artifact` 步驟取回失敗圖（ea7fbd2，
  之後 revert 628dc23，artifact 已刪）。
- 中途 PR 因 `docs/ledger/INDEX.md` 判 CONFLICTING 而 CI 未啟動：本機 `merge=union` 自動合，
  GitHub 不吃 `.gitattributes` merge driver。merge main（6d07087）後恢復。
- **差異量測**：三主題同座標 y=302、x=187/198、394/405、601/612，每通道差 ≤2/255；位置是方框
  字形內框下緣兩個反鋸齒角點。方框是 `Icon(Icons.add)` 在 flutter_test 沒有 Material Icons 字型時
  的 tofu —— 這 3 顆 golden 原本比對的根本不是圖示。同批 9 張（button/panel/tag_chip）兩機一致。
- 使用者問能否不測光柵化差異 → **D**：golden 改用正式程式使用的 `LucideIcon`（SVG 路徑）。
  舊圖 −3（red）；mutation 換圖示名 +18 −3；我先加的 `runAsync` 等待拿掉結果相同 → 非負重，刪除。
- 操作失誤：`git revert -q` 不支援 `-q` 而失敗，接著的 `--amend` 改到未推送的 merge commit 訊息；
  tree 相同，`reset --soft` 回 6d07087 後重做 revert，無內容損失。

- **追加：CI 時間**（使用者：capi 的 build 結果沒沿用到 flutter build）。量測：`flutter-ci` 不下載
  `capi-build` 的 artifact；它的 `build_capi.{sh,ps1}` 產物 `build/native/` 在 `flutter test` 之後無人讀，
  `flutter build` 又經 Phase B 自編 gbm_capi。使用者裁定只動 `ci.yml`（不做 prebuilt 選項，保住 PR 階段的 Phase B 覆蓋）。
  - 31df5fc 刪 `build_capi` 步驟。`build_capi`+`flutter build`（秒）：Linux 100 → 39、Windows 368 → 349、
    macOS 100 → 164（Xcode phase 改為冷編；同輪 `flutter test` 也 336 → 547，runner 偏慢，單次量測）。使用者接受 macOS +64。
  - 2c9f733 拿掉 `flutter-ci` 的 `needs: capi-build`（無資料傳遞，只是排隊）。整輪 wall：

| run | 變更 | wall (s) |
|---|---|---|
| 37174303497 | 48f0396，基準 | 1472 |
| 37176476465 | 刪 build_capi | 1735 |
| 37178065808 | 拿掉 needs | **872** |

  最長路徑由「capi Windows → Flutter Windows」變成 Flutter Windows 單獨 869s。`build_capi.ps1` 自此無 CI 呼叫，
  仍是本機 `flutter test` 前的開發腳本。`[CI-two-workflows]` 的 needs 那條就地更正。

## Result

四處釘版、下限、格式、golden 全部對齊 3.47.4，本機 analyze 0、format 0、+3001 全綠；
CI 第三輪（48f0396）13 個 check 全綠，含 macOS golden。

就地更正 2026-09-28 ledger「和硬體、字型、機器無關」：字形光柵化與機器有關。
蒸餾為 `[TEST-golden-no-glyphs]`。CI 規則已就地寫進上述三條 pin：**升版時四處釘版、sdk 下限、format、
golden 必須同一輪一起動**。
