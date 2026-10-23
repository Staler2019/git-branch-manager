# fix/windows-bundle-vc-runtime — Windows bundle 隨附 VC++ runtime

## Situation

使用者回報公司 Windows 電腦上的 v0.62.0 MSI「雙擊後完全沒反應」，以前可以，最近才壞；公司電腦無法取證。
本機（裝 v0.62.0）可以正常開啟，但 WER 封存裡有一筆 10/14 的 crash（0.57.2 zip 版）：

```
錯誤模組   MSVCP140.dll 14.51.36247.0
例外代碼   c0000005
已載入     gbm_capi.dll
```

發佈的 bundle 只放 exe、flutter、plugin、gbm_capi，沒有 VC++ runtime，所以 runtime 從 System32 取。
使用者的公司電腦裝過舊版 VS 工具鏈。

## Task

不靠公司電腦，在本機證明根因，再修正並讓打包流程擋住回歸。

## Action

- 重現：把已安裝的 v0.62.0 資料夾複製兩份到 scratchpad，exe 旁各放一份 `msvcp140.dll`
  （exe 目錄優先於 System32，等同「System32 是這個版本」）：

  | msvcp140.dll | 結果 |
  |---|---|
  | 14.29.30037.0（EqualizerAPO 隨附） | 8 秒內結束，exit `0xC0000005`，沒有視窗；WER：Faulting module `MSVCP140.dll 14.29.30037.0` |
  | 14.51.36247.0（本機 System32） | 視窗出現，載入的是 exe 目錄那份 |

  與「新 STL 的 `std::mutex`（constexpr 建構）在舊 msvcp140 上 crash」的已知問題吻合。
  沒有視窗的原因：runner 只在第一個 frame 後才 `Show()`，而 v0.60.0 起 root 層的 `CloneJobListener`
  在第一個 frame 前就載入 gbm_capi。
- 評估過的修法：app-local runtime（採用）；`_DISABLE_CONSTEXPR_MUTEX_CONSTRUCTOR`（只修 mutex，flutter engine 管不到）；
  `/MT`（runner 與 flutter_windows.dll 仍是 `/MD`，兩套 CRT）；MSI 內附 vc_redist（要系統管理員權限，違反 perUser、不放 custom action）。
- `test:` `build_msi.ps1` 在 Release 目錄缺 `msvcp140.dll`／`vcruntime140.dll`／`vcruntime140_1.dll` 時 throw。
  紅：對沒有 runtime 的 v0.62.0 bundle 回 `No msvcp140.dll in …`。mutation：三個檔案各拿掉一個，mutations-run 3，tests-reddened 3，
  每次的訊息都點名被拿掉的那個檔案。
- `fix:` `windows/CMakeLists.txt` 以 `CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS_SKIP` + `InstallRequiredSystemLibraries` +
  `install(PROGRAMS …)` 放到 exe 旁。本機 build 帶進 8 個 DLL（`msvcp140*`、`vcruntime140*`、`concrt140`），版本 14.44.35211.0。

## Result

- `flutter build windows --release` 成功；`build_msi.ps1` 通過；`msiexec /a` 解開的 MSI 內有全部 8 個 runtime DLL。
- 修正後的 bundle 正常開啟，`msvcp140.dll`／`vcruntime140.dll`／`vcruntime140_1.dll` 都從 bundle 目錄載入。
- 未驗證：公司電腦本身（無法取證）。release.yml 的 Windows leg 要到下次 release 才會實際跑這條路徑（`ci.yml` 不建 MSI）。
- 計畫原本要加一條 `CI-` rule，最後沒加：`ops-toolchain-ci.md` 的開頭規定，由檢查強制的規則只寫在檢查點的註解，
  而 `build_msi.ps1` 的檢查與 `windows/CMakeLists.txt` 的註解已涵蓋。
- 已知取捨：app-local runtime 不會被 Windows Update 修補，要靠每次 release 重新帶入 runner image 的版本。
