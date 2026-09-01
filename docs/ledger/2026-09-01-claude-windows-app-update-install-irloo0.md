# 2026-09-01 · claude/windows-app-update-install-irloo0 — 按下 Install and restart 之後卡在 Installing…，而且什麼都沒留下

使用者的原話：

> windows 上更新app時，點擊install and restart，沒有關閉app，也沒有看到log。但有看到app被下載在tmp，還有一個ps1 script

這一輪和上一輪（`docs/ledger.md` 的〈更新流程的三個缺陷〉，PR #107 之後）症狀正好
相反。那一輪是「app 關掉了、然後沒有回來」；這一輪是**app 根本沒關**。同一個功能，
不同的一條路。

## 光是那三個現象就把範圍縮到兩條路，不需要猜

`.ps1` 存在，代表 `launchUpdater()` 已經跑過寫檔那一步；app 還活著，代表
`_exitProcess(0)` 從來沒被呼叫到。這兩件事中間只有兩個動作：

```
script.writeAsStringSync(...)   ← 使用者看到的檔案在這裡產生
await beforeExit()              ← 候選一
_start('powershell', ...)       ← 候選二
```

候選二失敗會 `return` 一段理由，`install()` 把它變成 `UpdateState.failed`，畫面會出現
警告列。所以問使用者「對話框變成什麼樣子」就能二選一 —— 答案是**卡在 Installing…、
一顆按鈕都沒有**，候選二出局。

`installing` 不畫任何按鈕是刻意的，理由寫在 `update_state.dart` 的
doc comment 裡：「the detached updater script is already running and this process is
on its way out, so there is nothing left to cancel」。**這一輪打掉的就是那個括號裡的
前提**：行程沒有在離開，於是那一格從「正在收尾」變成一個活的黑洞。

## 根因：一個沒有任何逾時的同步阻塞 FFI 呼叫

```
_closeSessions()                      update_dialog.dart:61
  → OpenRepoSessions.closeAll()       open_repo_sessions.dart:37
  → closeNativeSession()              repo_session_repository.dart:3691
  → gbm_session_close                 ← 同步阻塞，跑在 UI isolate 上
  → Session::~Session()               src/capi/Session.cpp:183
  → operations_->drain()              src/capi/Session.cpp:207
```

`drain()` 的註解自己說得很清楚：它只在 worker thread idle 之後才回來，而且那個
thread 會把 completion callback 整個跑完。等 askpass 的 fetch 永遠不會 idle。

## 一個看起來很像修法、但實測沒有作用的修法

第一個想到的當然是 `await beforeExit().timeout(...)`。**它在這裡是空的**，而且會
騙過測試。

`_closeSessions` 雖然是 `async`，但 `closeAll()` 在第一個 suspension point 之前就
同步跑完了。`.timeout()` 掛的是一個 `Timer`，而 `Timer` 要的正是被那個呼叫塞住的
event loop。動手改任何一行 code 之前先量：

```dart
Future<void> beforeExit() async {
  sleep(const Duration(seconds: 3));   // 站在同步阻塞 FFI 的位置
}
await beforeExit().timeout(const Duration(milliseconds: 100));
```

輸出是 **`completed after 3009ms (timeout never fired)`**。

在 fake-async 的 widget test 裡它會是綠的，因為那裡沒有東西真的塞住 event loop。
這正是 `[TEST-fixture-cannot-disagree]` 那張表的第 11 個形狀：**fixture 表達不出
「同步阻塞」這件事**，所以一個什麼都沒修好的修法會全綠。

## 真正能逃出被塞死的 isolate 的只有另一個 isolate

第二個量測，同樣在動手之前：

```dart
void watchdog(int millis) { sleep(Duration(milliseconds: millis)); exit(7); }
await Isolate.spawn(watchdog, 300);
sleep(const Duration(seconds: 30));   // 主 isolate 整個塞住
```

行程在 **4.3 秒**結束、離開碼 **7**。spawn 出來的 isolate 有自己的 event loop、
自己的 OS thread，而 `exit()` 是行程層級的。

## 重排順序，是 watchdog 有意義的前提

原本是「先關 session、再啟動腳本」。維持這個順序的話，`beforeExit` 卡住時根本沒有
腳本在跑，watchdog 強制結束只會讓 app 憑空消失、什麼都不會回來 —— **比原本的 bug
更糟**。所以順序改成：

```
寫腳本 → 啟動腳本 → 武裝 watchdog → 有界地等 beforeExit → exit(0)
```

原本的 doc comment 用兩個理由辯護舊順序，**兩個都不成立**，依
`[CULT-correct-the-record]` 就地劃掉重寫而不是默默改掉：

1. 「a detached swap racing a live process」—— 不存在。腳本 `cd` 完的第一件事就是
   每 200ms 輪詢父行程、60 秒期限，逾時那條臂什麼都不動。早一點啟動是結構上安全的。
2. 「a hang there leaves the app alive ... recoverable」—— 這正是使用者遇到的那條，
   而它不可恢復：`installing` 沒有任何按鈕，沒有東西可以拿來 recover。

兩層防護都留，而且註解寫清楚少了任一層都不行：`.timeout` 擋非同步的慢（也是唯一
測得到的那半），watchdog 擋 isolate 被塞死（唯一在真實機器上有用的那半）。

三個期限是巢狀的，順序是硬性條件：**10s < 20s < 60s**。watchdog 若晚於腳本自己的
60 秒，腳本會先 exit 2 放棄、app 才死 —— 結果是「關掉了又沒更新」。

## 承諾了一個診斷管道，卻只有對面那一側會寫

`update_dialog.dart` 對使用者說「If it does not come back, `<temp>\gbm-update.log`
says why」。但那個 log **只有產生出來的腳本會寫**，而這次腳本從來沒被啟動。
「沒有看到 log」不是意外，是設計上就不會有。

交接的 app 這一側 —— 解壓縮、`install()` 開頭守衛條件直接 return、關 session、
啟動 powershell —— 一行都不會留。所以 `UpdateLog` 進來，**截斷的所有權從腳本移到
app**：`begin()` 在安裝開始時截斷（原本「累積的 transcript 會把正在問的那一次埋掉」
的理由完整保留），兩支腳本改成純附加。

順帶補掉三個無聲分支：

- `install()` 守衛不成立時是一個裸 `return` —— 按下去畫面完全沒變化，任何地方都沒有紀錄。
- `_startDetached` 把 `ProcessException` 的訊息整個丟成一個 bool。「The system cannot
  find the file specified」和「Access is denied」把使用者送去完全不同的地方，而那個
  bool 兩個都不送。
- PowerShell 改名迴圈的 `catch { Start-Sleep }` 吞掉全部 20 次重試的例外，所以 exit 3
  只說得出失敗的**步驟**、說不出**原因**。

## 順手修掉的 powershell 解析

`launchUpdater` 用的是裸的 `'powershell'`，而同一個 repo 的
`desktop_launcher.dart:85` 用的是 `'powershell.exe'`。裸名字由 `CreateProcess` 走
`PATH` 解析，而 `PATH` 被截斷或弄壞在 Windows 上是真的會發生的狀況 —— 而它會廢掉
這個 app 唯一的自我更新途徑，為了一個從來不會移動的檔案。改成絕對路徑優先：

```
%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe
→ powershell.exe
→ pwsh.exe
```

這**不是**這次的元凶（候選二已經出局），是同一條路上的另一個缺陷。

## 這一輪只有 root 環境才看得到的事

跑測試的容器是 uid 0。`update_installer_script_test.dart` 和
`update_installer_test.dart` 裡三個用 `chmod 555` 製造「不可寫」的 fixture，在 root
底下**完全無效** —— root 直接無視 mode bits。這三個測試在**父 commit 上就是紅的**，
先 stash 再跑父 commit 確認過，不是這一輪弄壞的。

它們在正常開發機上是對的，所以留著不動。但新加的「改名失敗要記下原因」改用一個
**任何 uid 都會失敗**的 fixture：目標目錄根本不存在。`chmod` 那個是忠於真實形狀的，
不存在那個是到處都跑得動的，兩個都留、註解說明為什麼是兩個而不是一個。

## CI 多了一個 windows-latest job

上一輪把「加不加」留給使用者決定，這一輪使用者說要加。`.ps1` 是這個 repo 裡唯一
沒有任何東西編譯、解析或執行的產物，而**語法錯誤會在腳本寫下第一個字之前就發生**,
所以連 transcript 都不會有 —— 使用者看到的又會是「app 關掉了然後沒回來」。

job 解析的是簽入的 golden 而不是自己產生腳本，這樣 Windows runner 上不需要整套
Flutter。不會無聲漂移的理由是這條鏈：改了產生器沒重跑 golden → Linux 上的
golden 測試就紅；重跑了 → 語法錯誤原封不動被帶進 golden → Windows job 抓到。
**懶惰地重新產生不是漏洞，把錯誤帶下去正是第三步抓得到的原因。**

只解析、絕不執行：這支腳本會把安裝目錄改名搬走，不是可以在 CI 機器上不小心跑起來的東西。

## 還是沒驗到的部分

真正的 install-and-restart 全程依然只有使用者在下一個正式 release 上用舊版實測才驗
得到。這一輪把 PowerShell 那半邊從「完全沒驗」提升到「語法有驗」，並且讓失敗一定
會留下 transcript、app 最多卡 20 秒。`[DRIFT-updater-windows-untested]` 就地改寫成
這個新狀態，不是刪掉。
