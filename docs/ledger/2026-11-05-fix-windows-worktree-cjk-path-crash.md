# fix/windows-worktree-cjk-path-crash — 中文路徑的 linked worktree 讓 Windows 版啟動即 crash（#207）

## Situation

#207：系統代碼頁 950 的 Windows 上，最近開啟的 repo 若是路徑含中文的 linked worktree，
`gbm_flutter.exe` 在視窗出現前以 `0xC0000409` 結束。0.61.0 正常，0.62.0 起壞。app 每次啟動都重開
上次的 repo，所以使用者只能手改 `shared_preferences.json`。

## Task

使用者 2026-11-05 要求修掉這個 crash，並從 MSI 移除 MS DLL。裁定（看過下方 DLL 的證據後）：

- MS DLL **保留**。
- 例外攔截：「c++函式都要包，接近底層務必容錯及debug訊息需要做到最多」。
- `activeCodePage=UTF-8`：加。
- 可以 push 並開 PR。

## Action

### 根因

`fde0824e`（0.62.0）讓 `Session::open` 解析 `.git` 指標檔，走進 `RepoClassifier::resolveGitDirFile`：

```
gbm_session_open(<worktree>/.git)
  └ RepoClassifier::resolveGitDirFile
      └ path(std::string)   ← 窄字元建構，MSVC 依系統代碼頁解碼 git 寫的 UTF-8
          └ std::system_error(1113) → 沒有 handler → abort → 0xC0000409
```

一般 repo 的 `.git` 是目錄，不經這條路，所以 #207 的對照組正常。`resolveCommonDir` 有同一個寫法。

### 為什麼既有防線沒擋下

- `check-narrow-path-conversions.py` 只抓 `path(...)` 與 `.string()`，抓不到 `path target(text)` 與 `exe->string()`。兩種都補上。
- `Utf8PathApiTest` 只從主 repo 開 session，沒走過指標檔。
- CI 是代碼頁 1252：同樣的 bytes 只會解成亂碼，不會拋例外。

### 窄字元轉換的全面盤點

腳本的 docstring 寫明它抓不到隱式轉換，所以另做一次盤點：複製 libc++ 的 `__filesystem/path.h`，讓
`path(string)`、`path(string&&)`、`operator/=(string)`、`.string()` 等全部標成 `[[deprecated]]`，再對
`compile_commands.json` 的 109 個 `src/` 編譯單元跑 `-fsyntax-only`。第一版漏了右值 `std::string`，連
`RepoClassifier` 都沒抓到，補上 `path(string_type&&)` 後才出現，這就是這份盤點可信的依據。

| 位置 | 處置 |
|---|---|
| `RepoClassifier.cpp` 兩處 | 修（根因） |
| `AskpassHelper.cpp` 兩處 `exe->string()` | 修：以代碼頁編碼，`ProcessRunner` 卻以 UTF-8 解回；使用者目錄含中文時路徑錯誤，表示不了的字元則拋例外 |
| `dir / std::string(kFile)` 共 11 處、`RebaseOps.cpp:56` | ASCII 常數，安全 |
| `GitExecutable.cpp` 兩處 | 窄 `getenv` 配窄建構子，同一代碼頁，既有 ALLOWED |

`_WIN32` 區塊這個方法編譯不到，只用 grep 看過。

### 例外防護

- **`ExceptionDiagnostic`（core/base）**：型別、what、error code 與 category、檔案路徑，保證是合法 UTF-8
  （Dart 的 `utf8.decode` 是嚴格的，MSVC 的 what 可能是代碼頁 bytes，錯誤回報本身不能變成第二個 crash）。
  寫入 log sink 與 `<temp>/gbm-native-errors.log`：**`Log::setMessageSink` 在 `lib/` 與 `src/capi/` 都沒有呼叫者**，
  所以 release 版的 `logMessage` 什麼都不會留下，檔案才是 bug report 拿得到的東西。
- **`guardedThread`**：所有執行緒由它建立，lint 禁止直接建立 `std::thread`。
- **160 個 export**：function-try-block，主體不必重新縮排。回傳值的 41 個呼叫 `reportNativeException`；void 的 119 個只呼叫 `reportCurrentException`——wiring-auditor 指出 void export 之後沒有人讀 staging buffer，那筆錯誤只會留給下一個讀者，lint 已禁止。回傳值走 `gbm_capi.h`
  的慣例（狀態 `-1`、指標 `nullptr`）；長度與旗標類（`gbm_last_result_json_len`、`gbm_graph_snapshot_*`、
  `gbm_has_commit_graph`）回 `0`，`gbm_history_refresh` 回 `0`，`gbm_askpass_main` 回 `1`。
- **`guardCall` 只活了一個 commit**：第一版用 lambda 包 `gbm_session_open`；要包全部時改用 function-try-block。
- **lambda 不能用 function-try-block**：文法只接受 compound-statement，第一版建置失敗，因此才有 `guardedThread`。

### 把 crash 換成 hang 的陷阱

mutation m5 讓 `onDone` 的 catch 重新拋出，例外被 `guardedThread` 接住，worker 結束，`drain()` 永遠等不到：
測試行程卡了 36 分鐘（CPU 0%），使用者問了才發現——**我的 mutation 腳本沒有 timeout**。這不只是腳本問題：
只要例外漏出 `OperationRunner::workerLoop`，所有後續操作與 `~Session` 都會無聲卡死。修法是每輪都接住
（`runQueued`）、尚未送出結果就送失敗（`failUndelivered`）。原本的 `guardedPreflight` 與 `onDone` 的內層 try 因此
多餘，已移除。之後的 mutation 腳本都設 60 秒 timeout，超時算紅。

### activeCodePage=UTF-8 的連帶影響

加了之後 `GetACP()` 在本行程回 65001，但子行程仍是系統代碼頁。`Process.run` 預設以 `systemEncoding` 解碼，
所以 `reg.exe` 的 CP950 輸出會解錯：使用者名稱含中文時，已安裝的副本會被判定為非安裝版、更新被導向 release 頁。
由程式碼推論，未實機量測。`install_location_registry.dart` 改用 `RegGetValueW`，順帶解掉 2026-10-14 的 P4。

未處理：`startDetachedProcess` 與 `_runToCompletion` 的 stderr 同樣以 `systemEncoding` 解碼，只影響失敗訊息的文字，
中文訊息可能變亂碼。未量測，不影響行為。

### MS DLL：為什麼保留

使用者的理由是「不再需要」。證據一半成立：2026-10-23 那份「v0.62.0 雙擊沒反應」的症狀與 #207 吻合。但 14.29 的
`msvcp140.dll` 放在 exe 旁會 `0xC0000005` 是當輪獨立重現、verifier 也重現過的另一個 crash，與 #207 無關；
移除後 System32 runtime 太舊的機器會再次無視窗 crash，per-user MSI 又不能裝 vc_redist。
[Flutter 的部署文件](https://docs.flutter.dev/platform-integration/windows/building)也要求確保使用者有 redistributable。
使用者看過後裁定保留。

### Commits

| # | commit | mutations-run | tests-reddened |
|---|---|---|---|
| 1 | `fix: linked worktree 的 .git 與 commondir 改以 UTF-8 解碼` | 6 | 5 |
| 2 | `fix: GIT_ASKPASS 的 exe 路徑改用 UTF-8` | 無（lint 紅 2 筆後修綠） | — |
| 3 | `fix: gbm_session_open 攔下 C++ 例外`（`guardCall` 版，後被 5 取代） | 3 | 4 |
| 4 | `feat: 新增 ExceptionDiagnostic` | 11 | 14 |
| 5 | `fix: 所有執行緒入口攔下例外` | 14 | 14（含 1 個以 hang 呈現的紅；m5 後因內層 try 移除而失效） |
| 6 | `fix: 全部 C API export 攔下 C++ 例外` | 6 | 8（第一次跑兩個存活：`l6` 補測試後轉紅，`l7` 的條件已移除） |
| 7 | `fix: install location 改以 RegGetValueW 讀取` | 無：只在 Windows 能跑 | — |
| 8 | `feat: Windows 行程改用 UTF-8 active code page` | 測試先紅 1 個 | 1 |
| 9 | `fix: void export 不再寫沒人讀的 staging buffer` | 2 | 2（第一次 `m-any-export` 存活，補「回傳值的 export 可以寫」的測試後轉紅） |

存活過一個值得記的：`m5-overlong3` 第一次 0 紅（測試沒有 overlong 三位元組的案例），補案例後才紅。

### `SeparateDefinitionBlocks` 改成 `Leave`

160 個 function-try-block 上了之後，`scripts/format-check.sh` 回報 160 筆，每個 export 的 `} catch (...) {` 各一筆，
但 `clang-format <file> | diff` 是空的：v18 在 `SeparateDefinitionBlocks: Always` 下會產生一個內容與原文相同的替換，
`-i` 不改任何字，`--dry-run --Werror` 照樣算違規。CI 的 `jidicula/clang-format-action@v4.13.0` 也帶 `--Werror`，
不處理就會紅。

| 試過的寫法 | 回報數 |
|---|---|
| 維持 `Always`，`catch` 行尾或第一行加註解 | 1 / 1（單檔樣本） |
| 維持 `Always`，用 macro 包 catch | 5（單檔樣本） |
| `Leave` | 0（`src/` 198 個檔） |

代價：格式工具不再替定義之間補空行。既有檔案不變，新程式碼的空行改靠人。另一條路是把 160 個 export 改成函式內 try，
全部主體要重新縮排，所以沒選。

## Result

- macOS：`ctest` 1020 個全過；`flutter test` +4499、~12 skipped（本機 Flutter 3.47.7，CI 釘 3.47.4）。
- **中文路徑相關測試在 macOS 上修前修後都是綠的**，它們的紅只會出現在 Windows CI。
- **CP950 的例外本身 CI 重現不了**（CI 是 1252）；要繁中 Windows 實機確認。
- `activeCodePage` 與 `RegGetValueW` 的實際行為沒有 CI tier 跑得到：manifest 測試只驗原始碼文字，
  registry 測試只在 Windows host 跑，而且測試行程本身沒有這個 manifest。

## 已知缺口

- void export（共 119 個）失敗時只有 log 與 `gbm-native-errors.log`，Dart 收不到回傳值；等事件回覆的呼叫端可能一直等。
- `AskpassPoller` 執行緒若因例外結束，該次 git 操作的密碼提示不會出現，只能等 git 自己的 deadline。
- `CloneJob` 的例外分支（`CLONE_FINISHED`）沒有測試：找不到可注入例外的接縫，只有 lint 確認入口有包。
- `ProcessRunner` 的三條 Windows 執行緒在 macOS 上編譯不到，只有 Windows CI 驗。
