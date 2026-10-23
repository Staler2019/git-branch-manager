# fix/windows-bundle-vc-runtime — Windows bundle 隨附 VC++ runtime

## Situation

回報：某台 Windows 電腦上的 v0.62.0 MSI「雙擊後完全沒反應」，以前可以，最近才壞；該機無法取證。
開發機上留有一筆舊版（0.57.2 zip）的 WER crash 紀錄，提供了線索：

```
錯誤模組   MSVCP140.dll
例外代碼   c0000005
已載入     gbm_capi.dll
```

發佈的 bundle 只放 exe、flutter、plugin、gbm_capi，沒有 VC++ runtime，所以 runtime 從 System32 取。

## Task

不靠出問題的那台電腦，在開發機證明根因，再修正並讓打包流程擋住回歸。

## Action

- 重現：把已安裝的 v0.62.0 資料夾複製兩份，exe 旁各放一份 `msvcp140.dll`
  （exe 目錄優先於 System32，等同「System32 是這個版本」）：

  | msvcp140.dll | 結果 |
  |---|---|
  | 14.29.30037.0（舊版 x64） | 8 秒內結束，exit `0xC0000005`，沒有視窗；WER：Faulting module `MSVCP140.dll 14.29.30037.0` |
  | 14.51.36247.0 | 視窗出現，載入的是 exe 目錄那份 |

  與「新 STL 的 `std::mutex`（constexpr 建構）在舊 msvcp140 上 crash」的已知問題吻合。
  沒有視窗的原因：runner 只在第一個 frame 後才 `Show()`，而 v0.60.0 起 root 層的 `CloneJobListener`
  在第一個 frame 前就載入 gbm_capi。
- 評估過的修法：app-local runtime（採用）；`_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR`（只修 mutex，flutter engine 管不到）；
  `/MT`（runner 與 flutter_windows.dll 仍是 `/MD`，兩套 CRT）；MSI 內附 vc_redist（要系統管理員權限，違反 perUser、不放 custom action）。
- `test:` `build_msi.ps1` 在 Release 目錄缺 `msvcp140.dll`／`vcruntime140.dll`／`vcruntime140_1.dll` 時 throw。
  紅：對沒有 runtime 的 v0.62.0 bundle 回 `No msvcp140.dll in …`。mutation：三個檔案各拿掉一個，mutations-run 3，tests-reddened 3，
  每次的訊息都點名被拿掉的那個檔案。
- `fix:` `windows/CMakeLists.txt` 以 `CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP` + `InstallRequiredSystemLibraries` +
  `install(PROGRAMS …)` 放到 exe 旁。開發機 build 帶進 8 個 DLL（`msvcp140*`、`vcruntime140*`、`concrt140`），版本同其 toolset。

## Result

- `flutter build windows --release` 成功；`build_msi.ps1` 通過；`msiexec /a` 解開的 MSI 內有全部 8 個 runtime DLL。
- 修正後的 bundle 正常開啟，`msvcp140.dll`／`vcruntime140.dll`／`vcruntime140_1.dll` 都從 bundle 目錄載入。
- PR 階段未驗證：release.yml 的 Windows leg 只在 merge 後跑（`ci.yml` 不建 MSI）。
  plan-verifier（事後補跑）REVISE：PR CI 測不到；runner 的 redist 由 `ilammy/msvc-dev-cmd` 的 toolset 決定，與開發機不同；
  release 的 tag 先於 build 推出，失敗只能 fix-forward。處置 FIX：改寫驗收如下。
- Merge 後驗收（v0.62.1，release run `39932291873`）：`flutter build windows`、`Package (Windows)`、兩個簽章步驟與
  dist 檢查皆 success。以 `msiexec /a` 解開發佈的 `git-branch-manager-0.62.1-windows-x64.msi`：`msvcp140.dll`／`vcruntime140.dll`／
  `vcruntime140_1.dll`（及其餘 5 個 runtime DLL）皆 14.51.36247.0；build log 的 `VCToolsVersion` 為 14.51.36231，
  DLL 版本 ≥ toolset，通過。
- 這也說明了「最近才壞」：runner 的 toolset 已到 14.51；STL 越新，System32 舊 runtime 不相容的機會越大。
  出問題那台電腦上的實測尚待回報。
- 計畫原本要加一條 `CI-` rule，最後沒加：`ops-toolchain-ci.md` 的開頭規定，由檢查強制的規則只寫在檢查點的註解，
  而 `build_msi.ps1` 的檢查與 `windows/CMakeLists.txt` 的註解已涵蓋。
- 已知取捨：app-local runtime 不會被 Windows Update 修補，要靠每次 release 重新帶入 runner image 的版本。

## Review

- plan-verifier（事後補跑）：第一次 REVISE（PR CI 測不到 release 打包），FIX 改寫驗收；收尾審查 READY。
- verifier：CONFIRMED，五項全部通過（含以 14.29 的 msvcp140 重現 0xC0000005、修正後 bundle 從自身目錄載入 runtime）。
- verifier P4：註解「14.51 build」把系統 runtime 版本誤當編譯器版本；FIX，已更正。
