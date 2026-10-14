# Release 改發 MSI，Windows app 內更新改由 msiexec 完成

## Situation

`release.yml` 的 Windows leg 發的是平坦 zip（`Compress-Archive .../Release/*`），app 內更新在
Windows 上由 PowerShell 腳本做「rename `.gbm-old` → `Copy-Item` → 失敗回滾」。使用者要求：release
改發 MSI 取代 zip portable，並確保 app 內更新能正確更新。

使用者裁定（2026-10-14）：

- **Per-user** 安裝（`%LocalAppData%\Programs\Git Branch Manager`），更新不跳 UAC。
- **直接停發 zip**：舊 zip 版的 `selectAssetFor` 只認 `-windows-x64.zip`，新 release 沒有它，舊版落到既有的「此 release 無 windowsX64 下載 → 請到 release 頁」，使用者手動裝一次 MSI。
- msiexec 用 **`/passive`**。
- 解除安裝保留 `%AppData%` 下的設定（Windows 慣例；刪設定需要 custom action，security review 不建議）。

## Task

1. release 的 Windows 產物改為 per-user MSI（WiX 5.0.2），zip 停發。
2. app 內更新在 Windows 改把驗證過的 MSI 交給 msiexec。
3. 在真的 Windows 機器上把安裝、升級、失敗路徑、解除安裝跑過一次——[DRIFT-updater-windows-untested] 記的「PowerShell 半邊從未被執行」。

## Action

### 核准前審查

- `security-reviewer`：無 P0/P1。處置——F1 引號注入（P2）FIX：路徑一律單引號字面值、msiexec 參數串成單一字串；F2 `perUserOrMachine` 可能變 per-machine（P2）FIX：`Scope="perUser"`、無 custom action、無 `RemoveFolderEx`、無 Burn；F3 簽章 pfx 落在工作區（P2）FIX：解到 `$RUNNER_TEMP`、`trap` 刪除、上傳前檢查 `dist/` 只有一個 `.msi`；F4 驗證到 msiexec 之間的 TOCTOU（P3）FIX：digest 一路帶到腳本，`stage()` 與腳本各重驗一次——改放 `%LocalAppData%` **DEFER**；F5 標記檔太弱（P3）FIX：改比對 HKCU `InstallFolder`；F6 裸名 `msiexec.exe`（P3）FIX：`$env:SystemRoot` 絕對路徑；F7 未驗 Authenticode（P3）**DEFER**（沒有憑證）；F8 3010/1641（P3）FIX：exit 7、不 relaunch；F9 asset 名當本機檔名（P4）**DEFER**；F10 版本鎖：WiX 鎖 5.0.2。
- `plan-verifier`：第一輪 REVISE 三項——F4 沒有落點、測試與驗收仍是被取代的設計（標記檔、3010 當成功）、沒有發佈後的 rollback。重寫後收尾審查 READY。
- `arch-suggester`：計畫的 `StagedUpdate` 改名 `PreparedUpdate`（`lib/data/models/prepared_update.dart`），另有 `downloaded_asset.dart`、`install_location_registry.dart`；腳本產生器留在 `update_installer.dart`，因為 `_psQuote` 是 private。

### Commits（`feat/release-msi-installer`）

| # | commit | mutations-run | tests-reddened |
|---|---|---|---|
| 1 | `refactor: stage() 改回傳 PreparedUpdate` | 1 | 1 |
| 2 | `feat: SHA-256 帶入安裝流程並於 stage 前重驗` | 3 | 8 |
| 3 | `feat: 由安裝檔登錄的副本絕不走目錄置換` | 5 | 5 |
| 4 | `feat: Windows app 內更新改由 MSI 與 msiexec 完成` | 8 | 21 |
| 5 | `fix: detached 啟動的腳本從未執行，改 Start-Process 轉接` | 2 | 4 |
| 5a | `test: 等 stage() 讀完 bundle 再結束 installing 測試`（verifier A1） | — | — |
| 6 | `build: WiX 5 安裝檔與 build_msi.ps1` | 2 | 3 |
| 7 | `ci: release Windows leg 改發 MSI` | — | — |
| 8 | 本檔與規則 | — | — |
| 9 | `refactor: Windows relay 移至 detached_process.dart` | — | — |
| 10 | `fix: Windows relay 一律由 PowerShell 啟動目標` | 7 | 8 |
| 11 | `fix: DesktopLauncher 在 Windows 改走 Start-Process relay` | 7 | 7 |
| 12 | 規則、本檔與註解的 console／GUI 更正 | — | — |
| 13 | `fix: relay 的工作目錄跳脫萬用字元，引號內結尾反斜線加倍`（verifier F1/F2） | 2 | 5 |
| 14 | `test: relay 測試的暫存目錄改為重試刪除` | — | — |
| 15 | 本檔 F3 更正與第三次 verifier 紀錄 | — | — |

Commit 4 的 mutation h（launch 時只檢查「有登錄」不比對資料夾）一開始 **0 紅**——補上 `refuses when the registration names another folder` 後才 1 紅。Commit 3 刻意與 MSI 切換分開：revert 4+7 時它留著，已用 MSI 安裝的副本因此被導向 release 頁，不會被目錄置換弄壞 Windows Installer 的註冊。

本機 Flutter 是 3.47.5（CI pin 3.47.4），依 [CI-formatter-version-drift] 只格式化動到的檔案，每次核對 diff。

### 實機發現一：Windows 上 `ProcessStartMode.detached` 的~~子行程~~ console 子行程從來沒跑

E2E 第一次走真實路徑：`launchUpdater` 回報 `updater started`，`gbm-update.ps1` 寫在 temp，`gbm-update.log` 之後**一行都沒有**，0.0.1 沒被升級。同一支 `.ps1` 前景執行 → exit 0、升到 0.0.2、app 重啟。

逐一排除：

| 探針 | 子行程是否執行 |
|---|---|
| `dart run`，detached `powershell -File` | 否 |
| 同上，`detachedWithStdio` | 否 |
| AOT exe，detached，父行程活 8 秒 | 否 |
| AOT exe，detached `cmd.exe /c type nul > file` | 否 |
| AOT exe 由 WMI `Win32_Process.Create` 建立（不在工具的行程樹）| 否 |
| 父行程是否在 job object | 否（`IsProcessInJob` = False） |
| `tasklist` 追 detached 回傳的 pid | t+0s 起就不存在 |
| `normal` / `inheritStdio` | 是 |
| AOT exe，detached GUI 程式（`charmap.exe`、`wt.exe`、`explorer.exe`）（追加量測） | **是** |
| normal 啟動 PowerShell，由 `Start-Process -WindowStyle Hidden` 啟動真正的腳本，父行程 1.5 秒後結束 | 是，且活過父行程 |

這就是 2026-09-01 那份 Windows 回報的全貌——「temp 裡有 `gbm-update.ps1`、旁邊沒有 `gbm-update.log`、app 還在」——當時歸因於 app 沒走到啟動那一步，實際上是**啟動了、子行程沒跑**。~~（任何子行程）~~ 追加量測更正：失敗的是 console 程式（`powershell.exe`、`cmd.exe`），GUI 程式照常執行。修法：`startUpdaterProcess`（後改名 `startDetachedProcess`，移到 `detached_process.dart`）在 Windows 改用 Start-Process 轉接並**等轉接結束**，非 0 結束或 15 秒逾時都算啟動失敗，帶 PowerShell 自己的訊息。`update_detached_start_test.dart`（後改名 `detached_process_test.dart`）的 `a started updater actually runs` 要求腳本留下標記檔，舊實作在 Windows 主機上紅。

### 實機發現三：DesktopLauncher 在 Windows 上開檔、開網址、PowerShell 終端機從未執行

發現一之後追量：`DesktopLauncher` 的預設 starter 也是 detached。AOT 探針結果：`cmd /c start` **否**、`powershell.exe` 備援 **否**、`wt.exe` 是。受影響的是 Open file（05-F）、Help → Documentation／Report an issue，以及更新對話框的「到 release 頁」——三者都回報成功、什麼都沒開。使用者裁定「本分支一併修」。

- relay 原本是「目標自己 `Start-Process` 自己」，只對 PowerShell 成立。改為一律由 `%SystemRoot%` 的 Windows PowerShell 啟動目標，新增 `RelayWindow`（更新腳本 hidden，使用者要看的東西 normal）。
- 量到兩件 relay 引號的事：`cmd.exe` 收到 `"/c"` 什麼都不執行，所以參數只在空字串或含空白時加引號（與 `Process.start` 相同規則）；explorer 收到整段加引號的 `"/select,C:\a b\f.txt"` 會開「文件」資料夾、不選任何東西——舊的 detached 版本對含空白的路徑**本來就壞**，relay 讓不含空白的也壞了。改為 `/select,` 與路徑兩個參數，兩種路徑都選中檔案。
- `openFile`／`openUrl` 直接把路徑或 URL 交給 `Start-Process`，依關聯開啟，不再經 `cmd`。PowerShell 備援拿掉 `-Command 'cd "$path"'`：雙引號字串會插值，資料夾名 `$(calc)` 會被執行；改用 working directory。
- 實機 E2E（真的 `DesktopLauncher`，路徑 `gbm e2e o'b $(calc) & x`，以可見視窗 handle 計數）：wt 終端機、PowerShell 備援終端機各出現一個新視窗；Open file 以關聯程式開啟（`/` 分隔的路徑）；file manager 開在該資料夾並選中 `note.txt`；URL 在 Firefox 開出 release 頁；不存在的檔案回 `false`。
- 視窗樣式 normal→hidden 的 mutation 單元測試看不到（m1 存活），只有上面的視窗計數證明。
- #184（dart:io 回收子行程）只發生在 POSIX 的 `waitpid`；relay 的 `Process.run` 只在 Windows 執行，macOS／Linux 仍是 detached，不受影響。2026-10-09 ledger 的對應句已原地加註。
- ~~relay 需要 PowerShell 冷啟動，每次開啟多約 1 秒（未精確量測）。~~ 量測更正（verifier F3）：`startDetachedProcess(cmd.exe /c exit)` 連續 8 次，中位數 264 ms、第一次（冷）942 ms；直接 detached 啟動中位數 2 ms。本機、n=8。
- 未處理：路徑含逗號時 explorer `/select,` 的行為未量測。

### 第三次 verifier（`ca8f44f..de66cee`）：REFUTED，三項

- **F1（P2，38920c9 引入）**：`Start-Process -WorkingDirectory` 以萬用字元解析、沒有 literal 形式，repo 路徑含 `[1]` 時 wt 與 PowerShell 兩個候選都失敗，Open in terminal 回 `false`。FIX：路徑先經 `[WildcardPattern]::Escape`；實測 `br[1] b`、``tick`x [z]``、`o'b $(x)` 三個目錄未跳脫時前兩個 exit 1、跳脫後全部執行。
- **F2（P3）**：加引號的參數以 `\` 結尾時，最後一個反斜線跳脫了收尾引號，後面的參數全被併入。FIX：結尾反斜線加倍（同 `Process.start`）。
- **F3（P4）**：上面那句未量測的「約 1 秒」，已量測並原地更正。
- 修 F1/F2 時重現了 `a started updater actually runs` 的偶發紅（6 次 1 次）：tearDown 刪暫存目錄時，被啟動的 PowerShell 仍以它為工作目錄（errno 32）。測試來自 commit 5，非本次修正引入；teardown 改為 15 秒內重試刪除；修正前 6 次 1 紅，修正後 15 次 0 紅。

### 實機發現二：per-user MSI 的「解除安裝」項目在 HKLM

~~驗收「Uninstall 項只在 HKCU（HKLM 無）」~~——這條驗收的前提錯了。實測：Windows Installer 不論 context 都把 ARP 顯示項寫在 `HKLM\...\Uninstall\{ProductCode}`；判斷 per-user 的正確依據是 `ProductsEx` 的 `Context = 2`（userUnmanaged），實測即為 2。F2 擔心的 per-machine context 未發生。

### ICE 驗證

`wix msi validate`：ICE38 錯 50、ICE64 錯 12、ICE91 警告 50、ICE60 警告 8。四者都是「per-user profile 內的元件」的已知組合，關係到漫遊設定檔；`%LocalAppData%` 不漫遊。`wix build` 不跑 ICE。以實測取代：解除安裝後安裝資料夾、捷徑、HKCU 鍵全數消失。

### 實作後審查（`verifier`）：REFUTED，三項

- **P1** `wix build` 預設在 `-o` 旁產生 `.wixpdb`，release.yml 的 dist 檢查會讓 Windows leg 每次都紅、publish 不跑（tag 已建）。本機 E2E 的 scratch 目錄其實也有 `.wixpdb`，當時沒有注意。FIX：`build_msi.ps1` 加 `-pdbtype none`；重驗：空的 `dist/` 只剩 `.msi`，檢查片段 exit 0，人工放一個 `.wixpdb` 進去則 exit 1。
- **P3** `update_controller_test.dart` 的 `does nothing once installing has begun` 偶發紅：15 次中 2 次，訊息是 tearDown 的 `deleteSync` 遇到 errno 32（檔案仍被使用）。原因是 commit 2 讓 `stage()` 先用 `openRead()` 重算 hash，`pumpEventQueue()` 回來時 hash 不一定讀完。FIX：測試改等 unpack 被呼叫（hash 已讀完並關檔）；重驗同一組指令 15 次，0 次紅。
- **P3** `build_msi.ps1` 在 Windows PowerShell 5.1 未傳 `-ReleaseDir` 時失敗：5.1 綁定 param 預設值時 `$PSScriptRoot` 還是空的。FIX：預設值移到 body；重驗：5.1 不帶 `-ReleaseDir` 建置成功。
- P4（未處理，報告）：`reg.exe` 輸出以 system encoding 解碼，系統 ACP 表示不了的使用者名稱會比對失敗——結果是被擋下導向 release 頁（fail-safe），未實測。

## Result

本機 Windows 11 實機 E2E（2026-10-14，0.0.x 測試版，結束後已解除安裝）：

| 項目 | 結果 |
|---|---|
| 安裝 0.0.1（`/passive`） | exit 0、無 UAC、落點 `%LocalAppData%\Programs\Git Branch Manager`、開始選單捷徑、HKCU `InstallFolder` 帶尾斜線、context 2 |
| 0.0.2 → 0.0.3，經 `selfInstallBlocker` → `stage` → `launchUpdater` → 轉接 → 腳本 → msiexec | msiexec 0、exit 0、註冊只剩一筆 0.0.3、app 自動重啟 |
| 0.0.3 → 0.0.4，MSI 放在 `o'brien $(calc) & x\gbm 0.0.4.msi` | exit 0、`$(calc)` 留在 log 裡當字面值 |
| digest 不符（檔案存在） | exit 6、未安裝、重啟舊版 |
| 檔案已不存在 | exit 6（`unreadable: …`） |
| 截斷的 MSI（digest 配合） | msiexec 1620、exit 5、仍為 0.0.3、重啟 |
| 已安裝資料夾複製到別處執行 | blocker 指向 release 頁 |
| 解除安裝 | exit 0；資料夾、捷徑、HKCU 鍵皆消失；`shared_preferences.json` 解除安裝前後雜湊相同 |

`shared_preferences.json` 的雜湊在 E2E 過程中有變——是執行中的各版本 app 自己寫入設定，不是安裝或升級造成；檔案全程存在。

延後與觀察（未在本輪處理，需使用者決定是否開 issue）：

- F4 後半：下載目錄與腳本改放 `%LocalAppData%`。
- F7：設定憑證後在腳本加 `Get-AuthenticodeSignature` 釘 thumbprint。
- F9：本機檔名不用 `asset.name`。
- `ci.yml` 不建 MSI：`Package.wxs` 或 `build_msi.ps1` 壞掉，要到 merge 後 release 才會發現。
- 觀察到 `update_controller_test.dart` 的 install 測試會把行寫進**真的** `<systemTemp>/gbm-update.log`（`UpdateController.install` 固定用 `Directory.systemTemp`）。
- 下一次真正 release 後，以 GitHub 上的 N → N+1 做一次 app 內更新（gateway 寫死 GitHub API，merge 前做不到）。
