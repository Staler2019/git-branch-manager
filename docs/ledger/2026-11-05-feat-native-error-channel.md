# feat/native-error-channel — void export 失敗時讓使用者看得到，並記進 log 檔

## Situation

#207 之後每個 C API 匯出都包了 function-try-block。回傳值的匯出把錯誤放進 staging buffer，Dart 讀得到；
void 匯出（119 個）與執行緒入口只寫 log 與 `<temp>/gbm-native-errors.log`，Dart 收不到任何訊號。
`Log::setMessageSink` 在 `lib/` 與 `src/capi/` 都沒有呼叫者，所以使用者什麼也看不到。

同一輪的 security-reviewer 另外指出：`OperationRunner` 把 `describe()` 當 `where`，
`AddSubmoduleOperation::describe()` 帶完整 URL，token 會以明文進那個檔案。

## Task

使用者問「void export 失敗時 Dart 收不到訊號，要怎麼讓使用者知道，以及記錄在 log file」。裁定：

- 顯示方式：沿用狀態列紅字加 Log drawer，不加對話框或 toast（「同意你說的log顯示方式」）。
- log 檔移到每位使用者自己的目錄，盡力移除舊的 temp 檔。
- 每個開啟中 repo 的 Log 與視窗 Log 都收到這行；UI 文字不含 repo 路徑，檔案系統錯誤只顯示型別與 code。
- plan review 到達上限仍未 READY（三次 REVISE），使用者選「套用修法後動工」：不再做 plan review，實作後跑一次 fresh `verifier`。

後續 PR 不在本輪：B（Windows `SetUnhandledExceptionFilter` 與 Dart `onError` 寫 log，主視窗出現前才用 `MessageBoxW`）、C（下次啟動的復原）、D（卡住的等待狀態，等本輪的 log 指出哪些函式重要再決定）。順序 A → B → C，都是使用者同意的。

## Action

```
core 例外
  │ reportCurrentException(where)          各步驟各自 guard，檔案優先
  ├─ appendToLog                           完整描述含路徑，ISO 時間，跳脫控制字元，超過 1 MiB 轉 .1
  ├─ logMessage                            既有 log sink
  └─ NativeErrorSink                       在鎖內執行；summary 不含路徑，上限 2 KiB
       │ gbm_set_native_error_callback     malloc 的 JSON {whenEpochMs, where, summary, logPath}
       ▼
GbmNativeErrorEvents                       NativeCallable.listener，複製後釋放，遮蔽憑證，跳脫控制字元
       │ reports
       ▼
NativeErrorCoalescer                       第一筆立刻送，重複合成 (repeated xN)
       │
NativeErrorLogListener（app.dart）
  ├─ windowLogProvider                     視窗 Log（Welcome）
  └─ OpenRepoSessions.recordAppLogToAll    每個 repo 的 Log；error 等級點亮狀態列紅字
```

關閉順序：`OpenRepoSessions.closeAll()` 先關所有 session，再跑 after-close hook 清掉 native callback。session 關閉時仍可能回報，而呼叫已關閉的 `NativeCallable` 會 abort（[FLU-close-session-before-callable]）。ordinary quit 與自我安裝都走這條路。

### 安全審查的處置

| 編號 | 嚴重度 | 內容 | 處置 |
|---|---|---|---|
| S1 | P1 | 只在 Dart 遮罩不夠，token 原文會進磁碟 | FIX：`where` 改用型別名，`describe()` 不帶 URL |
| S2 | P1（Linux）／P3 | temp 目錄固定檔名、權限看 umask、會跟隨 symlink | FIX：搬到使用者目錄，目錄 `owner_all`、檔案 0600 |
| S3 | P1（新引入） | process-wide callback 沒有 rendezvous | FIX：sink 在鎖內跑，清除即等待 |
| S4 | P2 | 一個 repo 的資訊進別的 repo 的匯出 Log | FIX，使用者裁定形狀：全部 repo，UI 不含路徑 |
| S5 | P2 | `where`、`logPath` 未消毒，嚴格解碼時整筆遺失 | FIX：入口過 `validUtf8` |
| S6 | P2（新引入） | 無節流、無長度上限 | FIX：coalescer 與 2 KiB 上限 |
| S7 | P3 | 換行與控制字元可偽造檔案行 | FIX：檔案與 Dart 兩端都跳脫 |
| S8 | P3 | `redactUrlCredentials` 對部分密碼字元與 query token 無效 | DEFER：S1 讓這條路徑不再依賴它；沒有寫第二份 C++ 遮罩，兩份只會各自漂移 |
| S9 | P3 | `logPath` 帶使用者名稱 | 接受：S1、S2 完成後保留 `(details: …)`，`Opened repository` 已帶類似資訊 |
| S10 | P4 | Undo 對話框顯示 token（既有） | 隨 S1 的來源修正解決 |
| N1 | 無發現 | askpass、環境變數、檔案內容、argv 目前到不了 `what()` | 不動；見 [CPP-exception-text-reaches-the-screen] |

### 過程中被測試抓到的錯

- `jsonAppendEscaped` 自己會加引號，第一版 `nativeErrorJson` 重複加，payload 是 `"where":""gbm_x""`。capi 測試斷言完整欄位形狀才看到。
- `noBoundary` mutation 存活：`std::runtime_error: ` 長 20 bytes，2048 − 20 剛好被 3 整除，fixture 永遠切在字元邊界。改成三種前綴長度。
- `legacyThrows` mutation 存活：檔案不存在時 `remove()` 不會丟例外，沒有測到移除失敗的路徑。改用非空目錄佔住舊路徑。
- `noClose` mutation 存活：`_callableClosed` 旗標不管有沒有 close 都會設定。改成讀 `nativeFunction`，關閉後會丟 `StateError`（文件寫「不得讀取」，實作會丟，這只在 `@visibleForTesting` getter 用；行為若變，測試會紅）。
- `whenEpochMs` 超出範圍會丟 `RangeError`，原本只接 `FormatException`、`TypeError`，寫 Dart 通道時補上。

## Result

Mutation 分開記兩個數字（跑的次數、變紅的測試數）。沒編過的不算，基準本身紅時跑的也不算：

| Commit | Mutations | Tests reddened | 備註 |
|---|---|---|---|
| 1 來源修正 | 2 | 2 | |
| 2 使用者目錄 | 5 | 7 | |
| 3 ISO 時間、跳脫、.1 | 9 | 9 | 一次沒編過的重做；第一批因 fixture 用 `find('Z')` 撞到時間字尾而全部作廢 |
| 4 core sink | 16 | 29 | `noBoundary` 存活一次，改測試後變紅 |
| 5 capi | 9 | 17 | `legacyThrows` 存活一次，補測試後變紅；`noUserData` 只看到前 5 個名字，輸出被截斷 |
| 6 Dart 通道 | 16 | 49 | `noClose` 存活一次；4 次基準紅的結果作廢重跑 |
| 7 coalescer | 16 | 33 | |
| 8 接線 | 14 | 29 | |
| 9 真實 library 測試 | 2 | 2 | 一次沒編過的重做 |
| 10 Windows 目錄比對 | 2 | 2 | 紅色證據是 PR 的 Windows CI，本機重現不了 |

- commit 6 的測試與實作是一起寫的，**沒有先看到紅**，紅色證據只來自 mutation。其他 commit 都先看到編譯失敗。
- TSan、ASan 跑過 commit 4 的 sink 測試與 commit 5 的 capi 測試，都綠。本機 `build/asan-ubsan` 是舊路徑留下的目錄編不起來，改在暫存目錄另建。
- `flutter test` +4536、~12 skipped（本機 Flutter 3.47.7，CI 釘 3.47.4）。

### 跨 FFI 的驗證範圍

```
C++ 例外 ──> callback              gbm_capi_tests，三個 OS
callback ──> GbmNativeErrorEvents  單元測試餵相同 JSON
真實 library ──> Dart              native_error_real_library_test.dart，capi-build，三個 OS
Dart ──> 每個 Log                  真實 GbmApp，FakeGbmBindings
```

真實 library 這段放在 `capi-build`，因為該 job 剛建好的就是含測試用匯出的 library：`flutter-ci` 的 Flutter build 關掉測試，要另外編；另開 job 則多了等待與傳檔，Flutter 安裝一樣要做。#208 的 run 量到 Windows 的 `flutter-action` 108 秒、`pub get` 40 秒，所以估計 Windows `capi-build` 多約 3 分鐘。~~實際數字待本 PR 的 CI。~~ PR 的 run 42066419130 量到 Flutter 安裝、`pub get`、測試三步合計 Windows 142 秒（92+40+10）、macOS 119 秒（88+10+21）、Linux 80 秒（62+7+11），三個 OS 的 log 都是 `1 test passed`。最早寫的是 macOS 專用的裝置測試，裝置測試不在 CI，等於沒驗到 Windows；使用者看過後裁定要加，於是改成這樣，裝置測試的版本沒有提交。

### PR 的第一次 CI 紅在 Windows

run 42063348728 的 `capi (FFI) - Windows` 1047 個測試紅 1 個，後面的真實 library 步驟因此被跳過：

```
log.parent_path().parent_path()          ...\Temp\gbm-proc-7144
std::filesystem::temp_directory_path()   ...\Temp\gbm-proc-7144\
```

Windows 的 temp 路徑帶結尾分隔符，`path` 比較會把它算成多一個元素。是測試寫錯，產品碼沒動。macOS 與 Linux 測不出來；verifier 的 CONFIRMED 也只涵蓋 macOS。改成比對 `temp / "native-error-logs"` 後，run 42066419130 全綠，含三個 OS 的真實 library 測試。

### `[skip ci]` 卡住合併

這段 ledger 第一次用 `[skip ci]` 推上去，想省 runner 時間，結果 PR 變 `BLOCKED`：`main` 沒有 branch protection，但有 ruleset 要求 status checks，沒跑過 check 的 HEAD 不能合併。我先前說「`main` 沒有保護」是只查了 protection API，查 `rules/branches/main` 才看得到。接著 force-push 回 `3aacbbef`，並告訴使用者這樣不耗 runner，這也是錯的：force-push 同樣觸發 `synchronize`，整組 CI 在同一個 SHA 重跑。使用者於是裁定把 ledger 推回來，本 commit 不帶 `[skip ci]`。見 [CI-required-checks-need-a-run]。

### 裝置測試

27 個檔一次跑一個，都在 macOS。`full_file_stage_flow_test.dart` 以外全過。

| 分支上的第幾次 | 結果 | 當時 |
|---|---|---|
| 1 | app 開著 20 分鐘、CPU 0%，手動停掉；輸出被 `tail` 吃掉，不知道停在哪 | 同時有其他工作 |
| 2 | `Shift+Down walks across fill rows` 紅（`git diff --cached` 為空），`autoscrolling drag` 卡過 5 分鐘上限 | 同時有 `gh` 查詢 |
| 3–6 | 全過 +7 | 機器閒置 |

`main` 上 4 次全過。分支這 2 次異常**原因未確定，也沒有排除是本分支造成的**。已知：`~/Library/Logs/GitBranchManager` 那時不存在，所以沒有 native error 發生，channel 沒有走到回報路徑；之後連續 4 次全過。工作負載造成的時序問題是推測，沒有量過。

### 順帶的 CI 清理

`gbm_capi-*` artifact 自從拿掉 `needs: capi-build` 就沒有讀取端，本輪停止上傳。使用者裁定刪掉既有的 626 個（5.87 GB），artifact 總量從 12.2 GB 降到 6.3 GB。依路徑跳過 job 與 `package-*` 保留天數留給下一個 PR（使用者裁定），估計省約 31% runner 分鐘，尚未實測。

## 已知缺口

- **macOS release 的 dylib 含 `gbm_test_raise_native_error`**：Xcode build phase 固定用 `capi-only` preset，它的 `GBM_BUILD_TESTS` 是 ON。沒有 Dart binding 走得到，能呼叫它的行程本來就能執行任意程式碼，所以沒有擋；動工前的 plan 寫「只在測試建置編入」，對 macOS 不成立。
- 500 ms 與 2000 ms 是提案值，沒有量測。
- 退出前還在排隊的回報，以及 coalescer 尚未送出的計數會被丟棄；檔案裡每筆都有。
- `closeAll` 是同步的，某個 session 的 close 永遠卡住就到不了 hook，這條路徑本來就卡在同一處。
- session 開啟前發生的回報只進視窗 Log，不會補進之後開啟的 repo。
- `std::terminate` 只寫檔不呼叫 sink，下次啟動才有機會讓使用者知道，屬於後續 PR C。
- 舊 log 只有 app 啟動註冊時移除；askpass 子行程不註冊，也不會移除。
- 回報發生時等事件回覆的呼叫端仍可能一直等：本輪讓使用者看得到，沒有解開等待（後續 D）。
- #207 的 CP950 例外 CI 重現不了，仍需繁中 Windows 實機確認，#207 維持開啟。

### verifier 的結果

CONFIRMED，只在 macOS arm64 實際執行；Linux、Windows 是讀碼，要看本 PR 的 CI。以下都是 P3／P4，記錄不修：

- **`what()` 裡的憑證仍以明文進檔案**（P3）。S1 修的是 `where`；這條路靠 [CPP-exception-text-reaches-the-screen] 約束，目前 `src/` 沒有帶資料的 `throw`。檔案是 0600。
- **截斷會讓憑證逃過遮罩**（P3）。`what()` 超過 2 KiB 且 URL 跨過邊界時，`@` 被切掉，`redactUrlCredentials` 原樣返回；前提同上，目前走不到。
- C1 控制字元（如 U+009B）沒有跳脫（P4），部分終端機會解讀。
- `appendToLog` 的 function-local `std::mutex`（既有）會在行程結束時析構，sink slot 則刻意不析構，兩者對 exit 期間的回報保護不一致（P4，未重現）。
- A、B 交替的回報不會合併（P4），Log 有筆數上限。

裝置測試的異常，verifier 同意不應收窄：沒有 native error 只排除回報路徑，不排除每次啟動都會跑的部分（listener、`NativeCallable`、舊檔移除）。
