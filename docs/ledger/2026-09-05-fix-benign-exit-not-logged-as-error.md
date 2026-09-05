# 2026-09-05 · fix/benign-exit-not-logged-as-error — 「回答了否」和「被拒絕」，紀錄分不出來

使用者的原話：

> 修正log在refresh時一直出現的這個錯誤
> `"/usr/bin/git … config --local --get user.name" "exit 1"`

## 缺陷不在它看起來在的地方

第一直覺是 `ConfigOps` 忘了容錯。開檔一看，那一層**早就容錯了**，而且註解寫得很清楚：

```cpp
/// `git config --local --get <key>` exits 1 with empty stderr when the key is
/// unset -- not a genuine failure, just "nothing here".
```

UI 一切正常，identity 欄位是空的、沒有錯誤橫幅。壞的是**日誌層**：

```
ConfigOps::readConfigValue()          ← 吞掉失敗，回傳 ""，UI 完全正確
        ↑
        │  runner.run() 仍然 return fail(exit 1)
        │
ProcessRunner::execute()
        │
        └─ recordOperation()  ← 逐筆記下每次呼叫，只帶 exitCode，
                │                沒有任何欄位能說「這個 1 是答案」
                ▼
        OperationRecord{ exitCode: 1 }
                │  FFI JSON
                ▼
        Dart OperationRecord.level  →  exitCode != 0  ⇒  ERROR
```

那句註解只講給會用到它的人聽，從來沒講給紀錄聽。而 `OperationRecord.level` 自己的
doc 早就引了 spec P10 的 `LOGRULES`：error 保留給**真的被拒絕**的動作
（`git push … exit 1`）。`--get` 一個沒設的 key 是**回答了**。

實測（本 repo）：`--local --get user.name` exit 1、`--local --get user.email` exit 1。
每次 refresh 固定兩列紅字。

## 為什麼是一組 code 而不是一個 bool

翻出所有同形狀的呼叫點（`grep -rn "exitCode == 1\|exitCode != 1" src/` 加上 ConfigOps
的兩句註解就是全部），逐個實測：

| 呼叫點 | 「正常答案」的 exit | 仍然算真失敗 |
|---|---|---|
| `config --get`（key 未設） | **1** | 128 |
| `config --local --unset`（從沒設過） | **5** | 1、128 |
| `diff --no-index`（找到差異） | **1** | 128 |
| `merge-base`（無共同祖先） | **1** | 128 |

`--unset` 那一列是決定性的：它是 **5**。一個 `bool tolerateFailure`（「這裡非零都沒關係」）
會把四個 128 一起吞掉——設定檔壞掉、不是 repo、ref 解不出來，全部變成靜音。所以
`GitCommand::benignExitCodes` 是一組 code，由**呼叫端**宣告，因為只有它知道自己問了什麼。

事實過 wire、等級由 Dart 端組出來，是 [ACT-recovery-choice-wire] 的同一套紀律：C++ 送
`benignExit` 這個**事實**，三個嚴重度由 Dart 用它加上 `cancelled`/`timedOut` 合成，只有
一個地方決定一列有多嚴重。

## 第二個生產者：sink 提早收工

查 `ProcessRunner::execute()` 時掉出另一個同類缺陷。`LineSink` 回傳 `false` 會殺掉子程序，
`sinkStopped` 為真、`execute()` 回傳**成功**，但 `recordOperation()` 已經把殺掉留下的非零
code 寫進去了——一條成功的指令被記成 ERROR。現實中的產生者是 `HistoryProvider.cpp:238`
的 row cap，只有大到撞上限的 repo 會踩到，所以一直沒人回報。

它是 runner 端自己知道的事實，不是呼叫端宣告的，機制不同，所以攤給使用者裁定，
**使用者裁定：也修掉**。

共用 `benignExit` 而不是另開欄位，理由是**意思相同**：

| exit != 0 的來源 | `execute()` 回傳 | 該有的等級 |
|---|---|---|
| 被更新的 refresh 取代（`cancelled`） | fail | WARNING（本來就對） |
| 逾時（`timedOut`） | fail | ERROR（本來就對） |
| 呼叫端宣告的正常答案 | fail | INFO ← 本輪 |
| sink 收工（`sinkStopped`） | **success** | INFO ← 本輪 |
| 真的被拒絕 | fail | ERROR（本來就對） |

`sinkStopped` 長得像 `cancelled`、意思卻相反：`cancelled` 是**被丟掉**的工作，它是
**刻意提早收工**的工作。放進 WARNING 那一格會是照外觀分類而不是照意義。

## 兩個被砍掉的防護

實作過程中寫了兩個 guard，兩個都自己砍掉，理由相同：**沒有任何一層測得紅**。

- `recordOperation()` 不用 `!cancelled && !timedOut` 防護 `benignExit`——Dart 端在讀它
  之前就先判掉那兩個，所以那個分支改成什麼結果都一樣。
- 同理不限縮成 `exitCode != 0`——exit 0 在 Dart 端本來就是 info。

第二個是自己打自己臉發現的：我在它上面兩行才剛寫註解批評第一個 guard 是死分支。
一個函式裡自相矛盾比多一道防護糟。

## 三輪 plan-verifier，四個 blocker，全部成立

這輪的 Plan 送了三次獨立審查（序列化改動觸發強制審查），前兩次都 REVISE：

**第一輪**（兩個）：
1. Dart 加欄位會讓**四個測試檔 18 個直接建構點**編不過，我原本只寫了 `model_parsing_test.dart`
   那一個 raw-JSON fixture。
2. C++ 測試被我放進 `ProcessRunnerTest.cpp`，但那裡 17 個 `TEST(` 全是 `FakeProcessRunner`
   /`HistoryProvider`/`RefStore`——`FakeProcessRunner` 根本不建 `OperationRecord`、不碰
   `gbm::Log`，在那裡寫測試只能重寫一份同樣的邏輯再驗自己，就是
   [TEST-fixture-cannot-disagree] 第 1 種形狀。

**第二輪**（兩個，其實是同一個病）：**我提的每一個測試，前置條件都被 fixture 自己弄成假的。**
`RealRepoTest::SetUp()` 和 `OperationLogApiTest::SetUp()` 都執行 `git config user.name`
——**沒有 `--global`**，也就是寫進 `--local` scope。所以「一個沒有 local identity 的乾淨
repo」在這兩個 fixture 裡不存在，`--get user.name` 會 exit 0。外加 capi 那個檔唯一的
`TEST_F` 只叫 `gbm_history_refresh()`，而它根本不讀 identity config。

這是 [TEST-fixture-cannot-disagree] 在**測試還沒寫出來之前**就先發生了。

## 使用者否決了我的第一個修法

第二輪的處置我提「不要跟 fixture 對打，改探一個沒人會設的假 key（`gbm.test.absent`），
無條件 exit 1」。**使用者裁定：不行，我要完全依賴 git 狀態。**

這個否決是對的，而且理由比我原本的顧慮更強：假 key 測到的是**機制會動**，但這一輪的
主張是「**git 對未設 key 回 exit 1**」。哪天 git 改了這個行為，假 key 版本會繼續綠。

換成真實狀態之後，量測結果反而給出更好的安排：

```
SetUp() 已經做的:  config user.name Test          → --local 有值
  A  --get user.name                    exit 0
  B  --unset user.name                  exit 0     ← 安排
  C  --get user.name                    exit 1     ← 回報的條件，真的
  D  --unset user.name（再一次）         exit 5     ← ClearLocalIdentity 的條件，真的
  E  --get user.email（沒動它）          exit 0     ← 白賺：證明安排有界線
```

E 那一列是假 key 給不了的：同一個 repo 裡 `user.name`（exit 1）和 `user.email`（exit 0）
並存，測試自己就能證明「我只弄掉了一個 key，不是把整份 config 弄壞」。

至於我原本擔心的「日後有人改 `SetUp()`，測試就靜靜變成空測試」——用**斷言**解掉，不是
用假 key 繞開：每個 case 在斷言 `benignExit` 之前先 `ASSERT` 抓到的 `exitCode` 真的是
5/1/1。條件不成立就紅，不會綠得莫名其妙。

## 一次假的全綠

commit 4b 的第一次 mutation 想把 `sinkStopped ||` 整段拿掉，結果 `-Werror,-Wunused-parameter`
讓**建置失敗**，測試卻跑到**舊的二進位檔**，回報「9 PASSED」。這正是上一輪 ledger 才剛
記下的坑。改用會編過的突變（呼叫端傳 `false`）重做，才是真的紅 1。

同一輪還有一次 mutation 的 perl 沒套上（`grep -c` 顯示字串還在），依
[TEST-mutation-check-every-test]「anchor 沒中就是沒套上，REDS=0 不是證據」重做過。

## Mutation 統計（跑幾次 / 各紅幾個，兩個數字）

| # | 突變 | 紅 |
|---|---|---|
| M1 | `benignExit = false`（機制關掉） | 1 |
| M2 | `benignExit = !codes.empty()`（改成 bool 實作） | 2 |
| M3 | JsonCodec 不序列化這個 key | 1 |
| M4 | Dart `level` 不看 `benignExit` | 3 |
| M5 | Dart `failed` 不看 `benignExit` | 3 |
| M6 | drawer 圖示改回自己重推 `exitCode != 0` | 1 |
| M7 | `recordOperation` 呼叫端傳 `false` 而非 `sinkStopped` | 1 |
| M8 | 拿掉 `ConfigOps` 的 `{1}`（重建 dylib，device 層） | 1 |

M2 是「是一組 code 不是 bool」唯一的實證：沒有它，`!codes.empty()` 的實作全綠。
M6 是「level 說 INFO、旁邊卻是紅色 error 圖示」那個缺陷——`_iconFor` 本來自己重推
`exitCode != 0`，非零不再自動等於失敗之後就會分岔。

## 驗收

**就地更正（追加那一段的結論）：下面每一個數字都是真的量出來的，但全部是 macOS 的數字，而這一段
原本讀起來像「本輪已經驗完了」。它沒有——同一批 commit 的 Windows `capi (FFI)` job 卡了 81 分鐘，
卡在本輪自己新增的 `ASinkThatStopsEarlyIsRecordedAsBenign` 上。經過與原因寫在「追加」。**

device 層那一支是唯一把整條鏈接起來的：真 dylib、真 FFI JSON、真 Dart 解碼、真 LogDrawer。
它也順便問出一件事實——**開 session 本身不讀 local identity**，是這個測試在還沒加
refresh 之前紅在空清單上驗出來的，不是猜的。要 `refreshRepoStatus()`（F5 唯一的進入點，
[STATE-refresh-entry-point]）才會掃到，而那正好就是使用者說的「refresh 時」。

- `flutter test` 2865 綠 / 1 skip，`flutter analyze` 零問題
- `gbm_core_tests` 509 綠（2 skip 是 LFS 環境），`gbm_capi_tests` 162 綠
- device 層：`operation_log_benign_exit_test.dart` 1/1、`repo_lifecycle_test.dart`（也讀
  LogDrawer）1/1。device 層不在任何 CI job（[TEST-device-tier-not-in-ci]），都是人工跑的
- 跑之前先 `pkill` 舊 process 並 `build_capi.sh`，且用
  `strings libgbm_capi.dylib | grep benignExit` 確認 dylib 真的帶著這輪的改動
  （[TEST-stale-dylib-is-silent]）

## 記錄一個 commit message 的筆誤

`932b261` 的內文把 pin 打成 `[TEST-device-tier-not-in-ce]`，正確是
`[TEST-device-tier-not-in-ci]`。commit message 無法就地更正（要 rebase 改寫歷史），
所以更正記在這裡。`scripts/check-rule-pins.py` 只掃 docs，掃不到 commit message。

---

## 追加：Windows CI 卡 81 分鐘，而卡住的是本輪自己新增的測試

使用者的原話：

> 修正一下pr ci

PR #138 除了 `capi (FFI) - Windows` 之外全綠。那一顆在 `Build and test gbm_capi` 這一步不會結束。

拿到日誌本身就有一道關卡：**GitHub 不提供還在跑的 job 的日誌**（`gh run view --log` 回
「job is still in progress」，REST 的 logs endpoint 回 `BlobNotFound`）。所以第一個決定是攤給使用者
的——**使用者裁定：取消這個 run，把 log 沖出來**。沖出來之後兇手是指名的，不是推論：

```
08:18:35  326/669 Test #326: RealRepoTest.MergeBaseOfUnrelatedHistoriesIsRecordedAsBenign ... Passed 0.60 sec
08:18:35          Start 327: RealRepoTest.ASinkThatStopsEarlyIsRecordedAsBenign
09:39:46  ##[error]The operation was canceled.
```

本輪其他三個 benign 測試在同一顆 job 上都是綠的（0.47s / 0.44s / 0.60s）。`main` 的基準是
**9–11 分鐘 / 659 個測試 / 測試時間 239 秒**，最慢的單一測試 4.97 秒。

## 三個疊在一起的缺陷，只有最底下那個是「壞掉」

```
①  ProcessRunner Windows 端 terminate() 之後的 join 會永久卡住   ← 真正的病灶
       ↑ 之前從來沒有任何測試踩到它
②  ctest 完全沒有 per-test 逾時 → 卡死的測試不會被砍，也不會被指名
③  ci.yml 沒有 timeout-minutes  → 一路燒到 GitHub 的 6 小時上限
```

②③ 是護欄，先進去；①是病灶，後進去。順序是刻意的：護欄落地之後，任何殘留的卡死會變成
**指名道姓、十幾分鐘內結束的紅**，而不是一個上午。

## ① 這個洞比本輪老，而本輪是第一個踩到它的

`ASinkThatStopsEarlyIsRecordedAsBenign` 是**整個 repo 第一個讓 `LineSink` 回傳 `false` 的測試**。
現有的 cancellation 測試全部是**開跑前就 cancel**（`GitIntegrationTest.cpp:577,1532`、
`ProcessRunnerTest.cpp:56`），所以 `WindowsChild::terminate()` 在 Windows CI 上**從來沒有被執行過
一次**。

這件事上一段 ledger 其實已經寫過一次，只是寫的是另一個方向：`sinkStopped` 唯一的正式生產者是
`HistoryProvider` 的 row cap，「只有大到撞上限的 repo 會踩到，所以一直沒人回報」。同一句話同時解釋
了為什麼 CI 也一直沒踩到。**缺陷比測試老；測試是把它挖出來的東西。**

兩個平台的不對稱是可以直接從原始碼讀出來的：

| | POSIX | Windows |
|---|---|---|
| pump 結構 | 單一 `poll()` 迴圈，三個 fd 一起排 | stdout 在本執行緒 blocking `ReadFile`，stderr／stdin 各一條執行緒也是 blocking |
| sink 回傳 false | `terminate()` → `break`，**不 join 任何東西** | `terminate()` → `break` → **`stderrThread.join()`** |
| `terminate()` | SIGTERM → 最多 30×100ms `waitpid(WNOHANG)` → SIGKILL | 光禿禿一句 `TerminateProcess(process_, 1)` |

pipe 的 `ReadFile` 只有在**所有**寫入端關掉才返回，而 `TerminateProcess` 殺的是一個行程不是一棵樹。
`command.timeout`（測試裡設了 120 秒）救不了：Windows 的 pump 只在兩次 `ReadFile` **之間**驗
deadline，而 join 在 `break` 之後。

**「是誰握著 stderr pipe 的寫入端」沒有證實，這裡不假裝有。** spawn 端本身是對的（讀取端清掉
`HANDLE_FLAG_INHERIT`，parent 在 `CreateProcessW` 之後立刻關掉自己那份）。最像的候選是 git 的孫
行程：`GitExecutable::searchPath()` 在 Windows 上**第一個**候選是登錄檔
`SOFTWARE\GitForWindows\InstallPath` 底下的 `cmd\git.exe`（不是 `actions/checkout` 日誌裡那個
`bin\git.exe`），而那一支是不是 wrapper、會不會 re-exec，**在 macOS 上驗不了**。另一個候選是
`bInheritHandles=TRUE` 下的跨執行緒繼承競態（app 的 worker pool 會並行 spawn；ctest 一個測試一個
行程，所以**這一次**不成立）。

修法兩種可能都蓋掉，所以不必先分辨——而且 ② 落地之後，猜錯的代價從六小時變成十幾分鐘。

## 修法的兩層，以及一個被拿掉的旗標

**(a) Job Object 讓 `terminate()` 砍整棵樹。** `CREATE_SUSPENDED` 起 → `CreateJobObjectW` →
`AssignProcessToJobObject` → **`ResumeThread`**；`terminate()` 先 `TerminateJobObject` 再退回
`TerminateProcess`。`pi.hThread` 因此要留到 resume 之後才關，而且 job 的任何一步失敗都不可以讓
spawn 失敗——**留下一個 suspended 的孤兒比原本的卡死更糟**。

**設計裡拿掉的是 `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`。** 計畫原本帶著它（「反正正常路徑上子程序
早就被收掉了，是 no-op」）。不對：job handle 在**成功**路徑上也會關，那個旗標會連 git 正當留下的
東西一起殺掉——**簽章 commit 起的 `gpg-agent`** 就是具體的例子，它本來就該活過那一次 commit。
job 是用來放大 `terminate()`，不是用來收屍。

**(b) join 之前把 helper 從 `ReadFile` 裡拉出來。** `CancelSynchronousIo`，**重試**而不是只發一次
（執行緒還沒進到 I/O 時它回 `ERROR_NOT_FOUND`）；必然收斂，因為任何一次 read 失敗執行緒就 return。
兩個 helper（stderr 與 stdin）同形狀，一起改——[GIT-primary-not-current-worktree] 記過相反方向的
教訓：修好一個就去 grep 它的雙胞胎。

一個容易寫錯的地方：**不要先看「已經 terminate 了嗎」再決定要不要進迴圈**。cancel 是別的執行緒送
來的，可以剛好落在那個檢查之後——那就是同一個卡死又回來。所以是輪詢，正常路徑上 helper 早就 EOF
結束，第一次 wait 就返回，什麼也不會被 cancel。

**`detach()` 被否掉，而且理由比「會漏執行緒」重得多**：那條執行緒寫的是 `execute()` 的區域變數
`result.err`，lambda 還**以參考捕獲** `onProgress`——detach 是 use-after-free，而且是在 ASan 與
TSan 都不會編到的那個平台上。這一點寫進了程式碼註解與 pin 的 Do-not，否則日後會被當成「簡化」。

**POSIX 那半邊一行沒動。** 它結構上就沒有這個問題，為了對稱去改它只會製造沒有任何一層測得紅的
分支——就是本輪前半段「兩個被砍掉的防護」同一個道理。

## ② ctest 沒有逾時，是實證不是推測

根目錄 `CMakeLists.txt:46` 只呼叫 `enable_testing()`，沒有 `include(CTest)`，所以不會產生帶
`TimeOut` 的 `DartConfiguration.tcl`。**那個 1500 秒的預設值是 CTest *module* 的
`DART_TESTING_TIMEOUT`，不是 ctest 自己的**；沒有那個 module，就是完全沒有逾時。日誌上那 81 分鐘
就是證據。

放在 `CMakePresets.json` 的 `tbase.execution.timeout`（300 秒）而不是
`gtest_discover_tests(PROPERTIES TIMEOUT n)`：五個 testPreset 全部 `inherits: tbase`，一行蓋住每
一條路，包含以後新增的；gtest 那個形式只蓋兩個執行檔，蓋不到 `add_test()` 註冊的兩個 fixture 測試。
明寫的 `TIMEOUT` property 優先於 `--timeout`，所以那兩個自帶 `TIMEOUT 600` 的完全不受影響。
300 的依據是量測：整套在 Windows 上總共 239 秒，本機 674 個測試 134 秒、最慢的單一測試 4.13 秒。

## ③ 兩層護欄不是重複，它們回答不同的問題

`timeout-minutes` 的 kill 是**取消**，而 `if: failure()` 在取消時**不會觸發**——所以
`Upload test logs` 那一步在 job 逾時的路徑上根本到不了。**只有 ctest 那一層會留下指名的紅和證據**；
job 那一層封的是帳單。四顆 job 同一個 25，不逐 job 調校：`capi-build` 是 matrix job，逐 job 要在
`matrix.include` 多帶一個欄位，為了省十分鐘的上限多一個維度不划算。

代價也不只是那顆 job：`flutter-ci` 掛 `needs: capi-build`，所以整條分支從頭到尾**一次都沒跑過**
Flutter 那一段。

## Mutation：這一次的紅不用自己造，它已經在手上了

[TEST-mutation-check-every-test] 要的是「拿掉修正就會紅、而且紅得窄」。這裡兩者都有現成的：

| | 紅（修正之前） | 綠（修正之後） |
|---|---|---|
| 證據 | 被取消的那份 CI 日誌，run `33954549299` / job `101275356013` | run `33959613871` / job `101289076305`，`Passed 1.87 sec` |
| 紅在哪 | `Start 327: RealRepoTest.ASinkThatStopsEarlyIsRecordedAsBenign`，**1 個**，由 ctest 逐一指名而不是用數的 | — |

「紅得窄」在這裡是最強的形式：失敗的測試是被**點名**的，不是從一個數字推回去的。再花一顆 CI round
去重新推導一個已經有的紅沒有意義。

**同時要記住 [TEST-fixture-cannot-disagree]：這個測試在 macOS/Linux 上永遠是綠的。** 兩邊 pump 結
構不同，所以它對 Windows 的主張只有 Windows CI 能反駁——本機 674/674 綠**不是**這個修正的證據。

## 追加的驗收：Windows 綠了，而且 job object 的代價量得出來

run `33959613871` / job `101289076305`（commit `05146f4`）：

```
327/669 Test #327: RealRepoTest.ASinkThatStopsEarlyIsRecordedAsBenign ...  Passed   1.87 sec
100% tests passed out of 669
Total Test time (real) = 341.84 sec
capi (FFI) - Windows   10:03:18Z -> 10:15:05Z   （11m47s）
```

**81 分鐘變成 1.87 秒。** 這就是 mutation 表右半格的內容。

計畫第 6 步要求逐一確認另外幾個 benign 測試沒有被 commit 3(a) 波及——理由是 job object 落在
**每一次 git spawn** 上，669 個測試全部踩在上面。逐一列出來，而不是只說「全綠」：

| # | 測試 | 秒 |
|---|---|---|
| 320 | `RealRepoTest.DeclaredBenignExitCodeIsRecordedAsBenign` | 0.82 |
| 324 | `RealRepoTest.ClearingAnIdentityThatWasNeverSetIsRecordedAsBenign` | 0.60 |
| 325 | `RealRepoTest.TheUntrackedFileDiffsOwnExitOneIsRecordedAsBenign` | 1.20 |
| 326 | `RealRepoTest.MergeBaseOfUnrelatedHistoriesIsRecordedAsBenign` | 1.66 |
| 327 | `RealRepoTest.ASinkThatStopsEarlyIsRecordedAsBenign` | **1.87** |
| 328 | `RealRepoTest.ASinkThatReadsEverythingIsNotRecordedAsBenign`（反例） | 0.87 |
| 599 | `OperationLogApiTest.ReadingAnUnsetLocalIdentityIsRecordedAsBenign` | 0.52 |

### Job object 讓 Windows 的測試變慢 33%，這個數字要留下來

標準規則 5 說效能要用數字決定，所以不是「感覺沒差」。被取消的那一份日誌在卡死之前已經跑完
**326 個測試**，和這一次是同一棵樹、同一組測試、只差 `ProcessRunner.cpp` 那一個 commit——
所以 1..326 是一個現成的對照組，不需要另外造。

| 分組 | 測試數 | 修正前（run `33954549299`） | 修正後（run `33959613871`） | 比值 |
|---|---|---|---|---|
| `RealRepoTest.*`（每個都真的 spawn git） | 151 | 133.71s | 177.67s | **1.33×** |
| 其餘單元測試（`FakeProcessRunner`，不 spawn） | 175 | 5.97s | 6.78s | 1.14× |

**下面那一列是上面那一列的對照組，這是整個量測唯一站得住的理由。** 兩份 log 相隔兩小時、跑在
不同的實體 runner 上，單看 1.33× 無法排除「今天的機器比較慢」——同一天 macOS job 也從 4m19s
變成 5m08s（+19%）。但不 spawn 的那 175 個測試只慢了 1.14×，而 spawn 的那 151 個慢了 1.33×，
**差在中間那 17 個百分點**，方向和 job object 落點完全一致。被拖最慢的十個測試逐一看過，
**全部都是 `RealRepoTest`**，而且全部是 git 呼叫最密的那幾個（`BisectFindsTheFirstBadCommit…`
1.74s→4.23s、`CherryPicksARangeInOldestFirstOrder` 1.04s→3.34s、`SyncSubmodulesRewrites…`
2.83s→5.73s）；沒有一個純單元測試進到那份名單。

成本大約是 **+44 秒**攤在 151 個測試上，換算下來是每次 spawn 多一個排程來回——
`CREATE_SUSPENDED` 之後要 `ResumeThread`，加上兩個 kernel object 的建立與關閉。

**不為了這 44 秒把修正改掉，理由是兩個候選的省法都會把正確性換掉：**

1. **整個 runner 共用一個 job object**（不要每個 child 一個）——省掉 `CreateJobObjectW`，
   但 `TerminateJobObject` 就會連**同時在跑的其他 git** 一起殺掉。`sharedReadPool()` 是並行
   spawn 的，所以這等於把「砍掉這一個」變成「砍掉全部」。
2. **拿掉 `CREATE_SUSPENDED`**，`CreateProcessW` 之後直接 assign——省掉 resume 的排程來回，
   但那個 suspend 正是為了關掉「子程序在被 assign 進 job 之前就先生了孫子」的競態。而這一輪
   的病灶本來就是「孫行程握著 pipe 的寫入端」，把那個競態放回去等於把修正拆掉一半。

11m47s 距離 commit 1 的 25 分鐘上限還有一倍餘裕，所以這個代價目前沒有人在等它。
記下來是為了：**日後 Windows job 若逼近上限，第一個該回來看的就是這一段，而不是重新猜一次。**

## 追加二：stdout 那半邊的 timeout，使用者裁定順手做掉

上一段把「不輸出也不結束的子程序仍然卡得住主執行緒」記成 known-remaining，等裁定。
裁定是**順手一起做掉**，所以 pin 裡那條 Note 已就地改寫成規則
（[CPP-windows-terminate-hangs-join]），沒有留一條 `DRIFT-`。

### 先發現的是：`GitCommand::timeout` 兩個平台都沒有任何測試

整套裡每一個 `.timeout` 都是 30~120 秒、刻意選成不會觸發的值（`GitCli.cpp:55`、
`GitIntegrationTest.cpp` 十幾處）。所以逾時這條路從來沒有被執行過一次，Windows 那半邊
壞多久都不會有人知道。**這不是「測試沒涵蓋到某個分支」，是整個功能沒有測試。**

### 子程序不能用 git 演

試過的都不行，理由各自不同：沒有 stdin pipe 時 child 立刻拿到 EOF，所以
`cat-file --batch` 這類會直接結束而不是卡住；network-shaped 的又會把 port 和防火牆
拉進單元測試。所以加了一個 5 行的 `gbm_hang_forever`——什麼都不寫、也不自己結束，
路徑用 `$<TARGET_FILE:>` 在編譯期傳進去，不猜 build layout。

**刻意一個 byte 都不寫**：只要寫一個 byte，Windows 的 read 就會回來，迴圈頂端的
deadline 檢查就會觸發——那條路本來就是好的。缺陷只存在於 pipe 一直空著的時候。

### 紅是「卡住」，不是斷言失敗

```
Start 333: ProcessRunnerTimeout.AChildThatNeverWritesIsStillTimedOut
333/670 Test #333: ...  ***Timeout 300.01 sec
99% tests passed, 1 tests failed out of 670
	333 - ProcessRunnerTimeout.AChildThatNeverWritesIsStillTimedOut (Timeout) unit
```

run `33961514484` / job `101294085620`。**這是本輪 commit 2 那 300 秒第一次真的派上用場**：
沒有它，這顆紅會是一個燒到六小時上限的 job，而不是一行指名的 `***Timeout`；
`stopOnFailure: false` 讓其餘 669 個照樣跑完，整顆 job 20 分鐘結束。
護欄先進去、病灶後修，這個順序在這裡自己證明了一次。

Linux / macOS / TSan / asan-ubsan **四個 POSIX 側的 job 全綠**，因為 POSIX 用 `poll()`
加 200ms 上限輪三個 fd，從來沒有這個洞——[TEST-fixture-cannot-disagree] 的形狀，
這顆測試的主張只有 Windows CI 能反駁。

### 修法是同一個機制換一個方向

不是原本 Note 裡列的那兩個。**執行緒不能取消自己卡住的 I/O**，所以取消要從第二條
執行緒送過來：

```
        pump thread                        deadline watchdog（只在 timeout > 0 時起）
        ───────────                        ────────────────────────────────────────
        ReadFile(stdout)  ← 永遠不回來      WaitForSingleObject(pumpDone, timeout)
              ▲                                        │ WAIT_TIMEOUT
              │                            timedOut_.store(true)
              │                            terminate()            ← 砍整棵樹
              └──────── CancelSynchronousIo(pumpThread) ←┘  重試到 event 亮
        ReadFile 回 ERROR_OPERATION_ABORTED
        break → SetEvent(pumpDone) → join → 發布 *timedOut
```

沒有採用的兩個，以及為什麼：**overlapped I/O** 要把匿名 pipe 換成具名 pipe（`CreatePipe`
開不出 overlapped handle），改動面遠大於問題；**stdout 另開執行緒**會把 `LineSink` 搬到
別的執行緒上跑，和 POSIX 不對稱，等於為了修 A 製造一個跨平台的行為差異。

也考慮過 **`PeekNamedPipe` 輪詢**並且算過才放棄：每一段輸出空檔會多付一次 sleep 的延遲，
而整套會 spawn 一萬次以上 git，5ms 的間隔就是 ~50 秒——和剛量到的 job object 代價同一個
數量級。不是感覺慢，是乘出來的。

### 三個細節，只有 CI 編得到，所以逐字複查過

- `GetCurrentThread()` 是 pseudo-handle（意思是「問的人自己」），對別的執行緒沒有意義，
  必須先 `DuplicateHandle` 成真 handle。
- pump 的**每一條**離開路徑（EOF、sink 提早收工、自己的 deadline 檢查）都要 SetEvent
  後 join，handle 在 join **之後**才關——watchdog 寫 `terminate()` 和一個 atomic，
  活過這個 frame 就是 use-after-free，和 `cancelBlockedIoAndJoin` 那條 `detach()`
  的 Do-not 同一個形狀。
- `*timedOut` 由 pump 在 join 之後從 atomic 發布。迴圈和 watchdog **都**可能判定逾時，
  而那是一個 `bool*`；讓兩邊各寫各的就是資料競爭。

### 殘留，寫出來而不是暗示

`timeout == 0` 的路徑（網路指令照合約都是 0）**完全沒有 watchdog**，靠的仍然是取消時砍
整棵樹把 pipe 的寫入端關掉。這是刻意的：一條沒有 deadline 的指令沒有東西可以等。

### Mutation

| | 數 |
|---|---|
| 突變數 | 1（POSIX 的 `remaining <= 0` 改成 `false`） |
| 紅掉的測試數 | 1 |

同一個突變下其餘 509 個全綠（2 個 skip，本機沒裝 LFS），所以紅得很窄。兩個數字分開寫，
依 [TEST-mutation-check-every-test]。突變的紅一樣是**卡住**（25 秒硬砍，exit 137），
和 Windows 上的形狀相同——這也是為什麼這顆測試在本機能證明的事情有限，真正的證據在
Windows CI。
