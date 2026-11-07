# feat/crash-and-dart-error-log — Windows 未處理例外與 Dart 錯誤寫進同一個 log

## Situation

[feat/native-error-channel](2026-11-05-feat-native-error-channel.md) 讓 C++ 攔到的例外進 log 檔、狀態列與每個 Log。
兩種錯誤還走不到那裡：

- Windows 上沒被攔的 SEH 例外（null 寫入、access violation）讓行程直接消失，檔案裡什麼也沒有，#207 的 CP950 crash 就是這樣。
- Dart 的 `FlutterError.onError` 與 `PlatformDispatcher.onError` 只印到 console，release 版沒人看得到。

## Task

使用者同意的順序 A → B → C → D 的 B。裁定：

- 對話框只有 OK，標題 `git-branch-manager`；只在還沒有可見視窗時出現，有視窗時只寫 log。
- 計畫「核准，開始做」；執行模式 AUTO，含 commit、push、開 PR，不合併、不發版。
- 上一輪 ledger 的 31% 是沒量過的估計，本輪更正。

不做（計畫的非目標，經 security-reviewer 確認）：minidump（會把 askpass 輸入的憑證與 repo 內容寫進磁碟）、Dart 載入 DLL 之前的 crash、`__fastfail`／`abort()`（刻意繞過 SEH filter；`std::terminate` 已由 `onTerminate` 記錄）、下次啟動的復原（C）、卡住的等待（D）。

## Action

```
Dart                                      Windows 原生
FlutterError.onError ─┐                   SetUnhandledExceptionFilter（gbm_capi 載入時安裝）
PlatformDispatcher ───┤                     │ 只用靜態緩衝區，不配置記憶體
  DartErrorReport     │ 型別決定 summary    ├─ 寫一行：code、module 檔名 + offset、thread
  DartErrorLimiter    │ 2 s 重複合併、60 s 20 筆├─ 沒有可見視窗、非 askpass、非 stack overflow
  │                   │                     │    → 預先啟動的 thread 顯示 MessageBoxW（只有 OK）
gbm_report_external_error                   └─ 交回先前的 filter（沒有就 CONTINUE_SEARCH，WER 照跑）
  │
reportExternalError ── 檔案 → logMessage → sink（同 reportCurrentException 的三步，各自 guard）
                                              │
                                   狀態列紅字、視窗 Log、每個 repo 的 Log
```

| commit | 內容 |
|---|---|
| `2cf03b80` | core `reportExternalError(where, summary, detail)`；`screenSummary` 抽出 UTF-8 驗證與 2 KiB 上限，`reportCurrentException` 共用 |
| `9fdb5b3a` | capi `gbm_report_external_error`（null 讀成空字串）與 Dart binding |
| `a7f9ec38` | `DartErrorReport`／`DartErrorLimiter`、`installDartErrorHandlers`（串回先前的 handler，回傳 restore）、`bootstrapApp`（bindings 只開一次，handler 與 provider 共用） |
| `4a0c9cd4` | `CrashFilter`、`shouldShowCrashDialog`、`gbm_crash_now` 子程序測試、`GBM_CRASH_NO_DIALOG` |

Dart summary 會出現在每個 repo 的 Log，所以只放型別知道不帶資料的部分：`FileSystemException`、`SocketException`、`TlsException` 只放型別與 `(os error N)`，`ProcessException` 放 errorCode，`HttpException` 只放型別，`ArgumentError`/`RangeError` 放 `name` 不放值，其他是型別加 `toString()` 第一行，最後一律過 `redactUrlCredentials`。detail 是完整文字加 stack，遮罩後上限 16 KiB，只進檔案。

### Security review 的處置

| ID | 嚴重度 | 處置 |
|---|---|---|
| S1 在出錯的 thread 上開 MessageBox | P2 | 修：預先啟動的 helper thread，先寫 log，stack overflow 不開 |
| S2 askpass 子行程 | P2 | 修：askpass 不開對話框，`where` 標 `askpass:` |
| S3 Dart summary 帶資料 | P2 | 修：依型別的 summary 規則；detail 的殘餘風險 P3 接受 |
| S4 洪水／UI thread 成本 | P2 | 修：依型別合併、全域上限、detail 16 KiB |
| S5 loader lock | P3 | 修：安裝時只填緩衝區、建 thread、裝 filter |
| S6 stack overflow | P3 | 修：全部靜態緩衝區，先寫 log |
| S7 開檔旗標 | P4 | 採用建議 |
| S8 行內容 | P4 | 採用建議：只寫 module 檔名，不寫目錄、位址、暫存器 |
| S9 WER dump／CI 對話框 | P4 | WER 是既有行為，接受並記錄；測試子程序用 `SEM_NOGPFAULTERRORBOX` 與 `GBM_CRASH_NO_DIALOG` |

### Mutation

「跑了幾個」與「紅了幾個測試」分開記；沒編過的不算。

| commit | 跑了 | 紅的測試 | 備註 |
|---|---|---|---|
| 1 reportExternalError | 5 | 7 | 一個 no-op 對照不計 |
| 2 capi 匯出與 binding | 5 | C++ 3（各 1）、Dart 2（parity 測試紅，real-library 檔載入失敗） | 兩個沒編過的改加 `(void)` 重做 |
| 3 Dart handler 與 bootstrap | 12 | 19 | `noReentrancyGuard` 第一次存活：測試裡 reporter 丟的是同型別，被 limiter 當重複吞掉；改成 `FormatException` 後變紅 |
| 4 本機：`shouldShowCrashDialog` | 4 | 4（各 1） | `overflowIgnored` 第一版改成 `code != 0`，`kStackOverflow` 變成未使用，`-Werror` 編不過，不計；改成 `kStackOverflow + 1` 後變紅 |
| 4 Windows：`CrashFilterApiTest` | 5 | 5（各 1，同一個測試） | 行號是 `4a0c9cd4` 的檔案。每個紅在自己的斷言：拿掉 `Handle.cpp` 的安裝 → 沒有那行（:63/64/66）；不呼叫先前的 filter、改回傳 `EXCEPTION_EXECUTE_HANDLER` → 只有 marker 是空的（:70）；寫完整路徑 → 只有 module 欄位（:69，`D:\a\…\gbm_crash_now.exe`）；忽略 `GBM_CRASH_NO_DIALOG` → 子程序 30 秒沒結束（:60，`WAIT_TIMEOUT` 258）。回傳 `EXCEPTION_EXECUTE_HANDLER` 時結束碼（:73）沒有紅，和計畫說的「結束碼分不出是否串接」一致；之後重寫測試時這個只做健全性檢查的斷言拿掉了 |

Windows 那列在暫時分支 `scratch/crash-mut-win` 上跑：一個只有 Windows job 的 workflow，建一次，逐一套用 mutation、增量重建、只跑 `CrashFilter` 測試，結束後刪掉分支。

## Result

- 本機：ctest 1068/1068；`flutter analyze` 0 個問題；`flutter test` 通過 4564 個、跳過 14 個。
- Windows：`CrashFilterApiTest` 在暫時 workflow 的基準與還原都綠（run 42255997616、42257521093；第一次沒有印出失敗斷言，第二次補印才確認每個紅都夠窄）。PR #210 的第一輪 CI（run 42259254607）：Linux、Windows 的 capi 與 Flutter UI、兩個 sanitizer 與 cq 全綠；macOS arm64 的兩個 job 因 GitHub 沒有可用 runner（「The job was not acquired by Runner of type hosted even after multiple attempts」）排 15 分鐘後被取消，一步都沒跑。

### 和計畫不同的地方

- 計畫說 `FakeGbmBindings` 要加記錄用的 override；實際沒加。integration 測試用的是 `app_native_error_log_test.dart` 自己的 `_Bindings`，它已經能透過註冊的 callback 送 JSON，沒有測試需要 `FakeGbmBindings` 計數。
- 狀態列只用 error 等級的那筆 Log 間接確認（PR A 的 `recordAppLogToAll` 讓 error 等級點亮紅字），沒有另外斷言 `StatusBar` 畫出的文字。
- 計畫說 `GBM_ASKPASS_MODE` 與 `GBM_CRASH_NO_DIALOG` 在安裝時讀；實作改成 crash 當下讀，`GetEnvironmentVariableW` 寫進靜態緩衝區，不配置記憶體。這樣測試不必在載入 DLL 之前設好環境變數。
- 計畫寫的「實測 7–10%」重算不出來，以本輪重算的 7.4%／16.0% 為準，方法見上一輪 ledger 的更正。

### 已知缺口

- **Windows 的程式碼本機編不了**。macOS 上只用 `windows.h` stub 做 `-fsyntax-only`，gtest 測試連 stub 也檢查不到；Windows CI 是唯一證據。
- ~~**對話框沒有任何自動化測試看得到**：CI 一律設 `GBM_CRASH_NO_DIALOG`。~~ 更正：見下方「追加」，對話框現在有 4 個 Windows 測試。仍未驗證的是：出錯的 thread 握著 `EnumWindows` 需要的鎖時會怎樣；helper 5 秒內沒出現對話框就放行、行程照樣結束的那條路徑。
- Dart 載入 DLL 之前的 crash 不會被記錄（計畫的非目標）。
- limiter 的 2 s／60 s／20 筆是提案值，沒有量測。退出前還沒送出的重複計數會被丟掉，和 PR A 的 coalescer 相同。
- detail 的遮罩沿用 `redactUrlCredentials`，它的已知缺口也適用於這個檔案；Flutter 的診斷樹可能帶 widget 文字。檔案只在使用者自己的目錄。
- #207 的 CP950 例外仍需繁中 Windows 實機確認，#207 維持開啟。

### verifier 的結果

CONFIRMED，只在 macOS arm64 實際執行；Windows 部分是讀碼加上暫時 workflow 的兩次 run（與 PR head 的 `src`、`tests` 相同）。以下記錄不修：

- **`app_bootstrap_test` 在設了 `GBM_CAPI_LIBRARY_PATH` 時會紅**（P3）。「開不了 library 就不 override provider」那個案例用「provider 讀取時會 throw」來證明沒有 override；環境變數讓 provider 自己開得到 library，就不 throw。產品行為正確；CI 只對 real-library 那個檔案設這個變數，不受影響，本機合併執行會看到假紅。
- **limiter 的 timer 路徑上 reporter 丟例外會被回報一次**（P3）。`_flushRepeats` 與 `_endCapWindow` 的 `_emit` 不在 `send` 的 try/catch 內，例外跑到 `PlatformDispatcher.onError` 被當新錯誤回報；第二次的例外被吞掉，不會循環。正式的 reporter 是 C 端全部攔住的 void FFI 呼叫，幾乎走不到。所以「回報時丟的例外不會再回報」只對同步路徑成立。
- **後來的 `SetUnhandledExceptionFilter` 會蓋掉這個 filter**（P4，推測）。~~沒有查 Flutter engine 或之後載入的 DLL 是否會裝自己的 filter。~~ 已查證並加測試，見下方「追加」。
- 狀態列紅字只由 error 等級的 Log 推論，沒有測試看 `StatusBar` 畫出的文字（同上方「和計畫不同的地方」）。

## 追加：P4 查證與對話框的自動化測試

使用者要求「p4 去查，然後對話框如果可以建立自動化測試覆蓋，就加」。

### P4：沒有東西在之後換掉 filter

- 原始碼：Dart SDK（`b5493447902f`）唯一呼叫 `SetUnhandledExceptionFilter` 的是 `runtime/bin/platform_win.cc`，而且只在 `Platform::Initialize(true)` 時安裝；Flutter engine（`bc6e01a3ac69`）的 `runtime/dart_vm.cc` 呼叫 `Platform::Initialize(false)`。Windows embedder、`windows/runner`、本專案用到的 Windows plugin（`file_selector_windows`、`jni`）都沒有呼叫。
- 量測：`native_error_real_library_test.dart` 新增 Windows 案例，在 `flutter_tester`（engine 與 Dart VM 都已啟動）裡載入 library 後，用 kernel32 讀出目前的 filter 並問它在哪個 module，得到 `gbm_capi.dll`。拿掉 `Handle.cpp` 的安裝時只有這個案例紅（同檔另兩個照綠；失敗訊息沒有留下，暫時腳本在 cp1252 主控台印 `\ufffd` 時當掉）。
- 沒涵蓋：使用者電腦上注入的第三方 DLL（防毒、輸入法等）。這不在本專案控制內。

### 對話框測試

`CrashFilterApiTest` 從 1 個案例變 6 個；`gbm_crash_now` 加 `--window`、`--stack-overflow`、`--at-once`。對話框案例從測試行程用 `EnumWindows` 找子程序可見的 `#32770` 視窗，讀標題與 id `0xFFFF` 的內文，再按 OK。

第一次在 Windows 跑時，基準就紅：對話框出現、前面的斷言都過，但 `WM_COMMAND IDOK` 送出後行程 15 秒沒結束。改成找出 `Button` 子視窗、用它自己的 control id 送出後變綠。

同一輪的 mutation `boxBeforeLine`（先開對話框再寫 log）沒有紅在預期的斷言上，而是子程序 0.02 秒就結束、沒有對話框。原因是真的 race：helper thread 在 library 載入完成後才開始跑，`showDialog` 看到 `g_dialogThreadId == 0` 就直接放棄。原本 `writeLine` 的檔案 I/O 剛好讓出 CPU 給 helper，把它蓋住了。修法是只要 event 建好就送出請求，在原本的 5 秒等待裡讓 helper 接手（`b90a6daa`）。`--at-once` 把行程綁在單一核心、主 thread 設最高優先權，讓 crash 必定先於 helper；放回舊寫法時只有這個案例紅。

| mutation | 紅的測試 | 紅在 |
|---|---|---|
| 有視窗也開對話框 | 1 | `NoBoxWhenTheProcessAlreadyShowsAWindow`，15 秒沒結束 |
| askpass 也開 | 1 | `NoBoxInTheAskpassHelper…`，15 秒沒結束 |
| stack overflow 也開（兩處判斷都拿掉） | 1 | `AStackOverflowIsLoggedWithNoBox`，15 秒沒結束 |
| 標題改成 `Git Branch Manager` | 1 | 標題斷言 |
| 內文不帶 log 路徑 | 1 | 內文路徑斷言 |
| 先開對話框再寫 log | 1 | 「寫在對話框之前」斷言（修 race 之後） |
| 對話框前先交給先前的 filter | 1 | marker 已存在 |
| 放回 `g_dialogThreadId == 0` 就放棄 | 1 | `ABoxStillAppears…`，沒有對話框 |
| 不等對話框關閉 | 2 | 行程 0.5 秒內結束；`--at-once` 案例找不到對話框 |

跑了 9 個、紅 10 個測試。另有 1 個第一次沒編過（拿掉判斷後 `code` 未使用，MSVC C4100 視為錯誤），改寫後重跑，不計。Dart 1 個、紅 1 個。暫時分支 `scratch/crash-dialog-win`（run 42312981207、42314363763）跑完即刪。

仍未涵蓋：helper 5 秒內沒能顯示對話框的那條路徑；按 OK 以外的關閉方式。

