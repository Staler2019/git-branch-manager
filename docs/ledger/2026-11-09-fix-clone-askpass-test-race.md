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
