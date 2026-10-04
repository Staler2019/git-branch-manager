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

## Result

四處釘版、下限、格式、golden 全部對齊 3.47.4，本機 analyze 0、format 0、測試全綠。
三 OS CI 結果見 PR。可蒸餾的規則已就地寫進上述三條 pin：**升版時四處釘版、sdk 下限、format、
golden 必須同一輪一起動**。
