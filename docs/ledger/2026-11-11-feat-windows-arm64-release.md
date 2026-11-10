# feat/windows-arm64-release — Release 加入 Windows arm64 MSI

## Situation

這台開發機是 Windows 11 ARM64，release 卻只發布 Windows x64 MSI。`release_asset.dart` 把 `Abi.windowsArm64` 列為「沒有發布」，所以 arm64 機器的 updater 只能請使用者去 release 頁面。

## Task

使用者裁定「也發布arm版本」。另外裁定「單獨推打包ci上去 失敗了調整直到打包沒問題 實際合併時 force push 正常 ci 流程」：先用暫時的 probe workflow 證明 release-only 的步驟可行，開 PR 前把 probe 拿掉，PR 只跑原本的 `ci.yml`。計畫經 plan-verifier 審到第 4 版 READY。

## Action

- C1 `release_asset.dart`：`Abi.windowsArm64` 對應 `-windows-arm64.msi`。測試先紅：`github_release_gateway_test.dart` 加上兩種情況，arm64 主機選 arm64 MSI；兩種 MSI 都在時，arm64 和 x64 各自只選自己的。
- C2 `build_msi.ps1`：新增 `-Arch` 參數（預設 `x64`，可選 `arm64`），同時決定 Release 目錄和 `wix build -arch`。`Package.wxs` 不動，維持 per-user、同一個 UpgradeCode。
- C3 `release.yml`：matrix 加上 `{ name: Windows arm64, os: windows-11-arm, arch: arm64 }`。`msvc-dev-cmd`、signtool 路徑和發布前檢查的 glob 都改用 `matrix.arch`。
- probe（`arm64-package-probe.yml`，只在這個分支的 push 觸發）照 C3 之後的 release.yml 步驟原樣跑，版本號用 99.0.0，不簽章、不發布。
  - 第 1 次（run 42644015804）紅：`subosito/flutter-action` 在 `windows-11-arm` 上找不到 3.47.4。Flutter 沒有發布 Windows arm64 的預建 SDK。
  - 修正 `76aa424c`：arm64 這一路改成 `git clone --branch 3.47.4` flutter，跟 arm64 開發機上 fvm 的做法相同；其他三路照舊用 flutter-action。這是自己獨立的 commit，拿掉 probe 後仍保留。
  - 第 2 次（run 42644430180）綠：WiX 安裝、Release build、`dist/git-branch-manager-99.0.0-windows-arm64.msi`、發布前檢查全部通過。
- 拿掉 probe：先用 `git branch probe-backup` 保留原分支（`8c473d75`），從 `origin/main`（`a5f858a4`）重建，cherry-pick C1、C2、C3 和修正這四個 commit。重建後的 patch 與原分支扣掉 probe 檔後逐字相同（`diff` 無差異），`git log origin/main..HEAD -- .github/workflows/arm64-package-probe.yml` 為空，HEAD 也沒有這個檔。

### 追加：測試平行化（使用者要求「217順便做test平行跑調整」）

- 這推翻了 plan 的 non-goal「ci.yml 不動」，是使用者的明確要求。
- 先 rebase 到合併 #216 之後的 main（`1de553b2`），沒有衝突，INDEX 兩行都保留。
- ctest：test preset 的 `tbase` 原本沒有 `jobs`，是循序跑。在本機（Windows ARM64、4 核）量 `capi-only`：
  - 循序 575 s；`-j 4` 三次 241 / 242 / 229 s，1085 個測試全過。
  - 第 4 次改用 preset 的 `"jobs": 4`、不帶 `-j`：237 s，preset 確實生效，但 `SubmoduleApiTest.DeinitSubmoduleEmptiesTheWorkTree` 失敗，`waitFor` 等了 10 秒沒收到 `GBM_EVENT_SUBMODULES_UPDATED`。
  - 這個測試循序時 7.8 s，`-j 4` 時 13.9 / 14.2 / 14.0 s，原本就貼近上限。第 4 次 ctest 依前幾輪的耗時把最慢的測試排在最前面，一開場 4 個 submodule／git 重操作同時跑，所以超時。
  - `EventLog` 在 `tests/capi/` 的 35 個檔案裡各自複製一份，`waitFor` 都寫死 10 秒，只有 `CancelOperationApiTest` 是 30 秒。用 md5 比對共有 19 種寫法，差異包括：`clear()`、`payloadsOfType()`、`snapshot()`、`hook`、只存 type 的版本、`waitForSquash` 和 `waitForReady` 這類專用 wait，以及註解和換行。
  - 使用者裁定：合併成共用 helper，但「之後別輪再做」；ctest `-j 4` 先拿掉，等 helper 那一輪再開。已從分支移除該 commit，原 commit 保留在本機分支 `ctest-j4-backup`。
- `flutter test`：package:test 預設用一半核心（test_core-0.6.18 `values.dart:14`），4 vCPU 的 runner 只同時跑 2 個。本機量：預設 333 / 307 s，`-j 4` 217 / 211 s，4576 個全過。`ci.yml` 純 Dart 那一步改成 `flutter test -j 4`。real library 那一步只有兩個檔案、共用同一個 log 目錄，不改。
- device 層（`integration_test/`）不能平行：flutter_tools 在 integration test 一律把 jobs 設成 1（`commands/test.dart:538-548`）。

## Result

- 本機驗收（這台 ARM64 機器，MSI 取自 probe 的 artifact）：
  - 乾淨安裝：`msiexec /i` 回傳 0，以 per-user 註冊（context 2），版本 99.0.0。`gbm_flutter.exe`、`gbm_capi.dll`、`flutter_windows.dll` 和 VC runtime 都是 arm64（PE machine 0xAA64）。app 能啟動，視窗有回應，關閉時 exit 0。
  - `vcruntime140_1.dll` 的 header 是 0x8664，但 `dumpbin` 顯示它是 ARM64X（PDB 路徑在 `arm64ec`），來自 Microsoft arm64 redist 的原檔（VS 18 的 `14.51.36231\arm64\Microsoft.VC145.CRT` 裡就是這樣）。安裝目錄裡沒有任何 exe 或 dll import 它，所以不是缺陷。
  - 模擬 ABI：在這台機器上裝 x64 的 v0.71.1，從 About → Check for updates 檢查（只擷取 app 視窗，用 PrintWindow），對話框顯示 0.73.1 可用，並提供 **Download and install**，沒有 blocked reason。v0.71.1 的程式把 `windowsArm64` 對應到 null，所以如果它讀到的是主機的 ABI，不論最新版是哪一版，都應該顯示「This release has no download for Abi.windowsArm64」。也就是說，在模擬環境下 `Abi.current()` 回傳的是**編譯時的 ABI（x64）**，裝 x64 的使用者靠 updater 只會一直拿到 x64 版。這次不自動把 x64 使用者改成 arm64（計畫的 non-goal）。
  - 跨架構手動升級：x64 的 0.71.1 還裝著時，`msiexec /i` arm64 MSI 回傳 0。log 顯示 `WIX_UPGRADE_DETECTED` 為 0.71.1 的 product code，接著 `RemoveExistingProducts`。升級後只剩一個 product（99.0.0），exe 和 DLL 都是 arm64，app 能啟動。
  - 最後解除安裝：product 剩 0 個，安裝目錄已刪除，沒有殘留的 process。
- 發布前檢查的 glob mutation：計畫原本要在 CI 上讓 probe 變紅一次，**但 probe 只跑了上述兩次，CI 上沒有做這個 mutation**。改在本機用同一段 bash 對 probe 的 MSI 重現：正確的 arm64 情況 exit 0；glob 改回 x64、多一個雜檔、兩個 MSI 這 3 個 mutation 都是 exit 1。
- 單元測試：C1 的測試先紅後綠。重建後補做 mutation，執行 2 次，變紅的測試數分別為 2、1：
  - arm64 的後綴改回 `-windows-x64.msi`：紅 2 個。
  - arm64 改成回傳 null（回到「沒有發布」）：紅 1 個。
- 重建後在新的 main（`a5f858a4`）上跑完整 `flutter test`：4576 通過、30 略過、0 失敗。`dart analyze` 0 issue，`dart format` 0 changed。
- 規則分類（memory-steward）：
  - `Abi.current()` 是編譯時的 ABI：判定 ENCODE，寫成程式碼註解。使用者裁定加註解，見 C6。
  - flutter pin 要一起改：判定 ENCODE，擴充 lint。理由是現有規則 `[CI-dart-sdk-floor]` 只寫「四個 pin」，cq.yml 的 lint 也看不到 release.yml 新增的 `--branch` pin，這個缺口是這一輪造成的。
    - 使用者裁定擴充，並問一致性檢查是否該放 ci.yml。查證：ci.yml 的 job 都是建置和跑測試；cq.yml 的 `lint` job 放的是只讀檔案的靜態檢查，現有的 pin lint 就在那裡；plan 也寫了 ci.yml 不動。使用者因此裁定放在 cq.yml 現有 lint 旁，見 C5。
  - arm64 redist 的 `vcruntime140_1.dll` 是 ARM64X：判定 L2，只記在 ledger。目前沒有任何架構檢查會被它誤判。
- C5 `cq.yml` 新增「every Flutter pin names the same version」：收集 workflows 的 `flutter-version:`、flutter clone 的 `--branch`、`session-start.sh` 的 `FLUTTER_VERSION=`，版本不只一個、clone 沒帶 `--branch`、或 hook 找不到 pin 時就失敗。
  - 本機實際的樹找到 6 個 pin，都是 3.47.4，exit 0。
  - Mutation 在複製出來的暫存樹上做：ci.yml 的 pin、release.yml 的 `--branch`、hook 的 pin 各改成 3.48.0，拿掉 `--branch`，hook 的 pin 改名，共 5 次，5 次都是 exit 1，各自印出對應的 `::error`。
  - 第一版在 hook 的 pin 消失時，被 `set -e` 直接中斷，沒有印出錯誤訊息；每個 grep 補上 `|| true` 後才印出正確訊息。
  - 放進 yml 的版本與測過的 script 只差在把 `; exit 1` 拆成兩行，用從 yml 抽出來的版本重跑同樣 5 個 mutation，結果相同。
- C6 `update_repository.dart` 的 `_abi` 補上 doc comment，純註解。
- `[CI-dart-sdk-floor]` 的 Do 欄改寫：`ops-toolchain-ci.md` 原本就有 6,061 字元，超過 6,000 的上限；改寫後會變成 6,147，`memory.py` 拒絕寫入。memory-steward 規劃重排，使用者裁定先查證這些說明實際寫在哪裡，再照規劃套用。查證結果：
  - 舊的 Do 用刪除線留在原處，改寫成 pin 的完整位置和新的 lint step。pin 位置：`ci.yml:74,155`、`cq.yml:267`、`release.yml:97,109`、`session-start.sh:15`；lint step 在 `cq.yml:179`。
  - 刪掉 `[CI-formatter-version-drift]` 裡講 format-cpp.sh 的 Do。同樣的內容已寫在 `format-cpp.sh:2-5`。
  - `[CI-windows-detached-never-runs]` 的量測清單改成指標。同一份清單在 `detached_process.dart:36-47`。
  - 第一次 dry-run 被拒：formatter 這個 block 量到 1,224 字元，超過單一 block 1,200 的上限。steward 手算估 1,150，差了 74 字元。
  - 再拿掉這個 block 裡、指向已刪除那段 Do 的 ledger 連結（`2026-11-04-chore-clang-format-post-edit-hook.md`，ledger 檔本身還在）。最後檔案是 5,816 字元。
- verifier（release 風險觸發規定的實作後驗證）：CONFIRMED，沒有 P0～P2。驗的是 C1～C3 加修正與移除 probe，C5 和 C6 是驗證之後才加的。另有兩個 P4 意見：
  - fixture 裡 x64 MSI 排在 arm64 MSI 前面，所以如果把 x64 的後綴放寬，x64 的測試看不出來。
  - release.yml 的 arm64 這一路本身還沒在 CI 上跑過。
  - 依 P3/P4 預設處理，兩個都只記錄。
- 還沒驗證：release.yml 的 YAML 沒有在本機驗證；arm64 這一路要等下一次 release 才會真的跑。下一次 release 後，要確認 assets 和 `sha256sums.txt` 裡有 `-windows-arm64.msi`，並在這台機器上跑 `update_check_flow_test.dart`。
- 沒有開 issue。

- 測試平行化：只有 `flutter test -j 4` 進這個 PR，本機 1.5 倍。ctest 維持循序，留給 EventLog 共用 helper 那一輪，到時候用 `-j 4` 連跑數次確認不再超時，再把 `"jobs": 4` 加回 `tbase`。
