# fix/windows-device-tier — 裝置層在 Windows 全跑：4 檔紅，3 個修、1 個是額度

## Situation

- 使用者實作了許多項目，只在 macOS 跑過裝置層；要求在 Windows 跑完整 E2E。
- 上次 Windows 全跑是 2026-09-19（14 檔、29 個測試全過）；現在 `integration_test/` 有 20 檔。
- `integration_test/README.md` 的 Running 清單只列 12 檔，早已不是「全部」。

## Task

- 20 檔逐檔跑 `-d windows`，紅的找根因並修（使用者：「上面先修」）。

## Action

### 全跑結果（Flutter 3.47.5、Windows 11）

- 16 檔綠，4 檔紅：

| 檔案 | 結果 | 根因 |
|---|---|---|
| `rename_branch_flow_test` | +1 −1 | 本機全域 `commit.gpgsign=true`，fixture 的 `git commit` 出現 `gpg failed to sign the data` |
| `prepared_message_flow_test` | +4 −1 | 測試寫死 `metaLeft`（Cmd）+Enter；Windows 上按的是 Win 鍵，commit 沒送出 |
| `stage_lines_flow_test` | +7 −2 | 同上（Cmd+Alt+S）；另有排程器例外 `Cannot use "ref" after the widget was disposed`（`working_copy_view.dart`） |
| `update_check_flow_test` | −2 | `GitHub returned 403`；`api.github.com/rate_limit` 顯示 `remaining: 0`，未登入每小時 60 次的額度用完 |

- 失敗測試的 teardown 另有 `PathAccessException … 正由另一個程序使用`。這是 Windows 會鎖住開啟中檔案的連帶結果，不是第五個原因。

### 修正（三個 commit）

- `74b0fc7`：`createTempGitRepo` 在本地關掉 `commit.gpgsign` 與 `tag.gpgsign`。
  - 第一次 mutation（拿掉那一行）**沒有紅**：gpg-agent 已快取密碼，簽章成功了。原本的紅取決於 pinentry 有沒有被回應，不是每次都會發生。
  - 改用 `GIT_CONFIG_COUNT/KEY_0/VALUE_0` 把 `gpg.program` 指向 `false`，讓簽章確定失敗，不動全域設定。修正版 2/2 綠；mutation 紅 2 個。
- `0b27167`：新增 `support/key_shortcuts.dart` 的 `pressActionShortcut`，讀 `gbmActionShortcuts(Platform.isMacOS)`。
  - 用 `Platform.isMacOS`，不用 arch-suggester 建議的 `defaultTargetPlatform`，因為 `WorkspaceScreen` 綁鍵時用的是前者。
  - Windows 上兩檔 5/5、9/9 綠。mutation 1 次（拿掉 control 修飾鍵），只紅按快捷鍵的那 1 個。
- `f4e4f7d`：`ScopedDiffView.dispose()` 會在下一幀回報 `null`。整個 `WorkingCopyView` 同幀離開時，callback 裡的 `ref.read` 拋錯，submitter 也沒清掉。
  - 修法：改在 build 時先取 app 範圍的 notifier，callback 只寫它。
  - 新 widget 測試：拖曳選取後換掉整棵 view。修前紅，且是同一個 StateError。
  - mutation 2 次各紅 1：還原寫法紅在 `takeException`；忽略 `null` 紅在 `isNull`。
  - 重跑 `stage_lines_flow_test` 時這個例外沒再出現（9/9）。它在 Windows 那次之所以出現，推測是前一個測試失敗、view 在選取還框著時被拆掉；沒有另外驗證。

## Result

- 裝置層在 Windows：三個修正後，受影響的檔都綠。`update_check` 待額度重置後重跑。
- `integration_test/README.md`：清單改成用迴圈跑整個目錄；補上 403 額度說明。
