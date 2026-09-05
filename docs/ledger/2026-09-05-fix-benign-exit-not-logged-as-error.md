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
