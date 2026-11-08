# feat/stuck-waits — read 背景工作丟例外時仍回覆失敗

## Situation

#207 的後續 D。A（錯誤通道）讓 native 例外進得了 Log，但等事件回覆的呼叫端仍可能一直等：PR A ledger 的已知缺口寫
「回報發生時等事件回覆的呼叫端仍可能一直等」，並約定 D 的範圍「等本輪的 log 指出哪些函式重要再決定」。

盤點（兩個 scout，C++ 與 Dart 分開；再一個 scout 逐 site 對照）：

- mutation（fetch/pull/push/merge…）走 `OperationRunner`，例外時 `OperationRunner.cpp` 的 catch 與 `failUndelivered`
  已送 `ok:false`，不會卡。
- read 走 `sharedReadPool()`，`Session.cpp` 有 34 個 post。task 丟例外時 `ThreadPool.cpp` 的 `workerLoop` 只寫 log、
  不送事件：History 的 `isRefreshing` 停在 true、刪除分支對話框的 probe `Completer` 與另存檔案的 export `Completer`
  永不完成。`GBM_EVENT_ERROR_OCCURRED` 不帶 request id，解不開 Completer。

## Task

使用者裁定（2026-11-09，AskUserQuestion）：「全部 read 請求」— C++ 每個 read 都包一層，Dart 不加逾時。
計畫經 plan-verifier 三輪（REVISE ×2 → 第二次後由 main 判 FIX，最後一輪 READY），使用者選「核准，AUTO 模式」。

## Action

```
Session::requestX()
  postRead(lane, "Session::requestX", task, onFailure, onAlways)
     └─ pool lambda: ScopeExit(onAlways)
                     try { [測試 build：armed name == where 就丟] ; task(); }
                     catch (...) { reportCurrentException(where);                 // 照舊
                                   try { onFailure(GitError(Unknown,
                                           "The read failed unexpectedly", describe…)); }
                                   catch (...) { reportCurrentException("postRead failure reply"); } }
```

onFailure 送出這個 read 原本的失敗路徑會送的東西：

| 類別 | site | 例外時送出 |
|---|---|---|
| 一般 | 26 個（refresh*、diff、compare、blame、history、reflog、stash、worktree、remote、LFS、identity…） | `ERROR_OCCURRED` |
| prune 預覽 | `requestRemotePrunePreview` | `ERROR_OCCURRED`，`argv` 補成 `git remote prune <name> --dry-run`，Dart 的 `_isSuppressedAutoPrunePreviewError` 才認得出是自動預覽 |
| 帶 key 的 reply | probe（requestId）、export（destPath）、squash（source，先 ERROR）、prepared（先 ERROR）、working tree content（path，editable:false）、original operation message（空 message） | 該 reply，payload 由一般路徑與失敗回覆共用的函式產生 |
| 約定不送錯誤 | commit meta、commit file counts | `[]` |

`dispatchRefresh` 原本在 body 第一行用 `ScopeExit` 呼叫 `finishRefresh`；測試注入的例外在 body 之前，所以收尾移到
`postRead` 的 `onAlways`，每條路徑只結束一次。

Commits：

1. `e5f1aa74` `postRead`、`gbm_test_fail_read`、26 個 ERROR site 與 prune 預覽、`dispatchRefresh` 的 onAlways。
2. `d41de295` 8 個 reply site，payload 抽成共用函式。
3. `9003c764` `scripts/check-read-pool-posts.py` 與其測試，接進 `cq.yml`。
4. `aab2d1bc` `read_failure_real_library_test.dart`（真 library、真 `RepoSessionController`、真 git repo），接進 `ci.yml` 的 capi-build。

### Mutation

| Commit | 跑了 | 變紅 | 說明 |
|---|---|---|---|
| 1（C++） | 5 | 5 | 不呼叫 onFailure（8 紅，每個測試都靠回覆）；不寫 log（2）；armed name 不清除（2）；prune 不補 argv（1）；拿掉 onAlways（2） |
| 1（Dart） | 2 | 2 | matcher 多要求 `-C`（1：新的「stays out of the banner」）；不消耗 in-flight 標記（2：新的與既有的「second failure surfaces」） |
| 2 | 9 | 9 | 8 個 site 各改成送 ERROR／別的事件，各只紅自己的測試；probe 回錯的 requestId（1）。另 1 個把 requestId 換成 0，未使用的 capture 在 `-Werror` 下編不過，不計 |
| 3 | 4 | 4 | 不檢查參照（1）、不去註解（1）、不排除 postRead 本身（4）、不允許跨行（1） |
| 4 | 2 | 2 | library 端 probe 失敗不回 reply（只紅 probe 那個）；拿掉 `finishRefresh`（只紅 History 那個）。以 20 秒 deadline 轉成紅，不是 hang |

c2 的 8 個測試第一次在 stub 下有 3 個是綠的：original message、commit meta、file counts 的正常回覆剛好也是空的，
fixture 分不出成功與失敗（[TEST-fixture-cannot-disagree] 1）。改成寫入 `MERGE_MSG`、用真的 HEAD oid 後 8 個都紅。

## Result

- capi（`capi-only`）1085 個 100% 通過（c2 之後）。
- `read_failure_real_library_test.dart` 在 macOS 本機連跑 10 次，10/10 綠。
- G3：`flutter analyze` 無問題、`dart format` 無變更、`flutter test` 4598 過 19 skip；wiring-auditor 對本輪符號
  沒有找到無呼叫者／無讀取者。
- verifier（fresh context）：**CONFIRMED**。自行重跑 ctest 1085/1085、真 library 3/3、檢查腳本 8/8、
  auto preview 測試；以 `git diff -w main...HEAD` 逐一比對 34 個 site（main 上 34 個 post，HEAD 上 34 個 `postRead`）。

### 和計畫不同的地方

- ~~27 個 `ERROR_OCCURRED`、7 個 reply~~ 實際是 26／8：commit meta 計畫送 `ERROR_OCCURRED`，但 `gbm_capi.h` 寫明它
  「always fires GBM_EVENT_COMMIT_META_READY, never GBM_EVENT_ERROR_OCCURRED」，所以改回空 batch，與 file counts 一致。
- `requestRemotePrunePreview` 的 task 原本 `remoteName = std::move(remoteName)`，onFailure 也要名稱，兩個引數的求值順序
  未定義，第一次跑時 argv 裡是空字串；改成兩邊各自複製。
- Dart 的 prune 預覽測試用的是字面 payload，C++ 端拿掉 argv 不會讓它變紅；它釘的是 Dart 認得這個形狀，C++ 端由
  `APrunePreviewThatThrowsCarriesItsDryRunArgv` 釘（[TEST-fixture-cannot-disagree] 9）。

- verifier 指出（P4，記錄不改）：`refreshLfs` 的一般失敗路徑不算錯誤、仍送 `LFS_UPDATED`，丟例外時卻送
  `ERROR_OCCURRED`，所以「26 個 ERROR site 的一般失敗都是 ERROR」對它不成立。Dart 沒有東西在等 `LFS_UPDATED`，
  不會卡；main 上這時什麼都不送。另外 `ctest -R ReadFailure` 只跑到 14 個，`PostRead.*` 的 2 個要
  `-R "ReadFailure|PostRead"`。

### 已知缺口

- `scripts/check-read-pool-posts.py` 只認 `sharedReadPool().post(` 與 `ThreadPool& x = sharedReadPool()`；
  `auto& pool = sharedReadPool()` 會漏（wiring-auditor）。目前 `src/` 沒有這種寫法。

- void 匯出在把 task 排進 pool 之前就丟例外（例如 `toOidVector` 配置失敗），匯出的 catch 只寫 log，不回覆。
- 不在 read pool 上的執行緒（`CloneJob`、`AskpassPoller`、`Scanner`、`DelayTimer`、`CatFileBatch` 的 watchdog）沒有處理。
- `CallbackRegistry::emit` 在沒有 callback 或 malloc 失敗時丟掉事件。
- session 關閉時 `cancelQueuedAndDrain` 丟掉的 read 不回覆；這時 controller 也正在關閉。
