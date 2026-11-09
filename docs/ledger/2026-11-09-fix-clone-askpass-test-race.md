# fix/clone-askpass-test-race — 假 askpass 腳本的 request 寫入 race

## Situation

在 Windows 本機（MSVC x64，`cmake --workflow --preset capi-only`）測 PR #213 時，ctest 1085 個中有 1 個失敗：

```
CloneJobApiTest.ACredentialPromptIsRaisedAndAnswered
CloneJobApiTest.cpp(599): Expected equality of these values:
  log.payloadsOf(GBM_EVENT_CREDENTIAL_REQUESTED).front()
    Which is: "{\"prompt\":\"\"}"
  "{\"prompt\":\"Password for x: \"}"
```

PR #213 的 diff 沒有碰 clone、credential 或 askpass；同一個 build 單獨重跑該測試 20 次，0 次失敗。

## Task

找出空 prompt 的來源，判斷是產品還是 fixture 的問題，並修到穩定不再出現。

## Action

- 讀 `AskpassHelper.cpp:160-163`：真正的 askpass client 用 `writeHandshakeFile()` 寫 `request`，註解寫明 poller 只看檔案「是否存在」，所以檔案必須一次完整出現。
- 測試裡的假 ssh 腳本用 `printf '...' > "$GBM_ASKPASS_DIR/request"`：shell 先建立空檔再寫入。poller 在這段時間掃到，就讀到 `""`。這是 fixture 的 race，產品端沒有問題。
- 同樣寫法共 4 處：`CloneJobApiTest.cpp` 2 處、`RemoteApiTest.cpp` 2 處。會比對 prompt 文字的是 `ACredentialPromptIsRaisedAndAnswered` 和 `SshRemoteApiTest.PushQueuedBehindABackgroundFetchStillRaisesItsPrompt`；另外兩處只看有沒有 prompt，不會因此變紅，一起改是為了寫法一致。
- 修法：先寫 `request.tmp` 再 `mv` 成 `request`，跟 `writeHandshakeFile()` 一樣讓檔案一次完整出現。

## Result

- 先紅：把舊寫法的時間窗拉大成 `{ sleep 0.5; printf ...; } > request` → `ACredentialPromptIsRaisedAndAnswered` 穩定變紅，訊息跟原本偶發失敗完全一樣（`"{\"prompt\":\"\"}"`）。Mutation 執行 1 次，變紅的測試 1 個。
- 後綠：新寫法套上同樣的 `sleep 0.5`（寫 `request.tmp`，再 `mv`）→ 綠。
- 拿掉放大條件後：`CloneJobApiTest.*:SshRemoteApiTest.*:RemoteApiTest.*` 40/40 通過；兩個比對 prompt 文字的測試連跑 30 次，0 次失敗。
- ~~`RemoteApiTest.cpp` 的 push 那一處沒有另外做 mutation；它跟 clone 那處是同一種寫法，這裡照實記下。~~ 已補做：push 那一處改回舊寫法並拉大時間窗（`{ sleep 0.5; printf ...; } > request`），`SshRemoteApiTest.*` 2 個中只有 `PushQueuedBehindABackgroundFetchStillRaisesItsPrompt` 變紅，訊息同樣是 `"{\"prompt\":\"\"}"`；新寫法套上同樣的 `sleep 0.5`，2/2 通過。Mutation 合計執行 2 次，各有 1 個測試變紅。
- 另外兩處（`ACancelledPromptLetsTheCloneFail`、`BackgroundFetchNeverRaisesACredentialPrompt`）不比對 prompt 文字，race 不會讓它們變紅，所以沒有可觀察的紅燈；改它們只是為了跟其他地方寫法一致。
- `tests/` 不在 `format-check.sh` 的範圍內（它只檢查 `src/`）；用 clang-format 22.1.8 比對修改前後，這兩個檔案的格式差異行數不變。
- 沒有萃取新規則：fixture 旁的註解已經指向 `writeHandshakeFile()`。

## 追加：Windows 裝置層的三個 fixture 紅燈

### Situation

同一台 Windows ARM64 機器（開發人員模式開啟後）跑 PR #213 的 `integration_test/`，29 個中 4 個紅；`main` 上重跑同樣 4 個、訊息相同，所以是既有問題，不是 #213 引入。其中 `update_check_flow_test` 是因為發布的資產裡沒有 arm64 版本，另開一輪處理。剩下三個：

- `context_menu_flows_test`、`full_file_stage_flow_test`：預期 `'alpha\n'`，實際 `'alpha\r\n'`。
- `merge_squash_flow_test`：`fatal: unable to auto-detect email address`。

### Task

使用者裁定：測試要符合實際情形（類似 .NET 的 `Environment.NewLine`），不能用改環境的方式讓它變綠。

### Action

- 實測：Git for Windows 安裝時就在系統層設了 `core.autocrlf=true`（`C:/Program Files/Git/etc/gitconfig`）。Discard 走的是 `git apply -R`（`PatchOps.cpp:80`），git 會把整個檔案改寫成 CRLF。這就是 git 在這台機器上的真實行為。
- 換行該是什麼，由 git 的 eol 設定決定，不是作業系統，所以 Dart 的 `Platform.lineTerminator` 並不準。新增 `integration_test/support/git_worktree_bytes.dart` 的 `expectedWorktreeText`（位置依 arch-suggester 建議）：先把內容以 `hash-object -w --no-filters` 存成 blob，再用 `cat-file --filters --path=<path>` 取得 checkout 時會套用的轉換結果。實測它的輸出跟 `apply -R` 寫出的檔案逐位元組相同。
- `merge_squash_flow_test` 的 `_gitsSquashMsg` 會另外 clone 一份當參照，但 clone 不會帶上 local config，所以非 fast-forward 的 squash 拿不到身分。改成沿用受測 repo 自己的 `user.name`/`user.email`。修好之後，同一個測試接著出現同樣的 CRLF 問題（`topic.txt`），也改用 helper。

### Result

- 修正前：三個測試都紅（上面的訊息）。修正後：`context_menu_flows_test` +5 全過；`merge_squash_flow_test` +2 全過；`full_file_stage_flow_test` 裡的 discard 斷言轉綠。
- Mutation：讓 helper 直接回傳 LF 原文 → `discarding one diff line reverts only that line on disk` 和 `Squash prefills git's own SQUASH_MSG…` 兩個測試變紅，其他測試沒有變紅。共執行 1 次 mutation，2 個測試變紅。`full_file_stage` 用的是同一個呼叫，沒有另外跑 mutation。
- 新的 helper 只在 Windows 實測過。macOS/Linux 上 `cat-file --filters` 預期不會做轉換、回傳原文，但沒有實際跑過；這一層也不在 CI 裡（[TEST-device-tier-not-in-ci]）。
- **還沒解決**：`full_file_stage_flow_test` 的 `an autoscrolling drag past unbuilt rows…` 在 Windows 上 6 次中有 3 次大約 82 秒時 `did not complete`，host 端出現 `stream_impl.dart:378` 的 assertion；沒有 crash 事件，也沒有 native error log；`main` 上也會發生。根因還沒查到，要不要繼續查等使用者決定。
