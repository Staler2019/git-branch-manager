# chore/path-scoped-rules — 規則改為依路徑載入

## 起因與量測

使用者開 `/memory` 後說「memory seems too large」。實測每個 session 開場自動載入：

| 來源 | 大小 |
|---|---|
| 專案 `CLAUDE.md` + 17 個 `@import` 的 `docs/rules/*.md` | **315,869 bytes** |
| 使用者全域 `~/.claude/CLAUDE.md` + `rules/**` | 44,231 bytes |

`memory/`（auto memory）是空的，大的是 rules。官方文件
（code.claude.com/docs/en/memory）明講 `@import` 不省 context —— 被 import 的檔案開場就整份載入；
省得到的只有 `.claude/rules/` 帶 `paths:` frontmatter 的 path-scoped rules，它們在 Read/Write/Edit
碰到符合的檔案時才載入。

## 三個方案與裁定

提了三案：A 依路徑載入（內容一字不改）、B 只 import 一份索引、C 把敘事縮回 ledger。使用者選 A。

我上一輪估 A 之後開場「約 100K」，~~約 100K~~ 錯了，實際是 **124,933 bytes**：
`arch-structure`、`arch-state-machine`、`drift-open` 三個大檔沒有窄路徑可限，只能留在全域。

使用者裁定：

1. 不加「讀程式檔一律用 Read tool」那條，也不實測片段 Read 是否觸發 —— 「維持 grep 工具可以用」。
   所以已知一件事寫在這裡而不寫成規則：**只用 grep/Grep 看過的檔案不會帶出它的 path-scoped 規則。**
2. `fn-refs-branches` 依 symbol 實際使用檔限縮路徑（見下）。
3. `ops-toolchain-ci` 只在碰到建置/CI 檔時載入；「analyze 必須 0」之類以 GitHub CI 結果為準。

## 搬了什麼

八個檔 `git mv` 到 `.claude/rules/`，各加 `paths:`；`docs/rules/` 留七個全域檔加 README。
搬過去的檔仍在第二層目錄，所以 `../../app_flutter/...`、`../../CLAUDE.md` 不必改；只有
`../ledger/` → `../../docs/ledger/`、`README.md` → `../../docs/rules/README.md` 被改寫。

| 檔 | paths |
|---|---|
| `fn-cpp-core.md` | `src/**`, `tests/**`, `CMakeLists.txt` |
| `fn-git-commands.md` | `src/**`, `tests/**` |
| `fn-flutter-{state,layout,input}.md` | `app_flutter/**` |
| `arch-testing.md` | `app_flutter/test/**`, `tests/**`, `app_flutter/integration_test/**` |
| `arch-testing-device.md` | `app_flutter/integration_test/**` |
| `ops-toolchain-ci.md` | `.github/**`, CMake 檔、`.gitattributes`、`app_flutter/{scripts,windows,macos,linux}/**`、`pubspec.yaml`、`analysis_options.yaml`、`.pre-commit-config.yaml`、`.clang-format`、`scripts/**` |
| `fn-refs-branches.md` | 由 11 個 symbol 的 `git grep -l` 結果列出（sidebar、dialogs 五個、`repo_session_repository.dart`、`workspace_screen.dart`、`**/*prune*`、`RefStore.*`、`BranchOps.*`/`RemoteOps.*`、`JsonCodec.cpp` 等） |

`fn-refs-branches` 的 11 個 symbol：`RemoteBranchIndex isEffectivelyGone fullRemoteRefName
shortRemoteRefName remoteCounterpartOf deleteBranchRemoteTarget isSymbolic gonePendingRefs
goneRefsDeferredByClaim DeferredPruneNotifier PruneAudience`。**已知風險**：一個新寫、不在清單裡、
又處理遠端分支的檔案不會帶出這份規則；它通常會先讀 `repo_session_repository.dart` 或 sidebar，
那時才會載入。

## 驗證

沒有程式碼變動，Dart/C++ 測試**沒有跑**（只動 markdown 與 `check-rule-pins.py` 的 glob）。

三支檢查，各做一次 mutation，紅的數字分開記：

| 檢查 | 結果 | mutation | 紅 |
|---|---|---|---|
| `scripts/check-rule-pins.py`（glob 擴到 `.claude/rules/`） | 211 條規則、179 個引用、懸空 0 | 拿掉新 glob | 懸空 14、exit 1 |
| scratchpad 的相對連結檢查（兩個 rules 目錄 + CLAUDE.md） | broken 0 | 把一條 `../../docs/ledger/` 改回 `../ledger/` | broken 1 |
| scratchpad 的 symbol 覆蓋檢查（11 個 symbol 的使用檔都落在 paths 內） | uncovered 0 | 刪掉 `app_flutter/lib/features/sidebar/**` | uncovered 15 |

3 個 mutation，分別紅 14 / 1 / 15。

**沒做的**：沒有新開 session 用 `/memory` 確認實際載入清單 —— 這要使用者在新 session 看；
依使用者裁定也沒有用 `InstructionsLoaded` hook 實測觸發。

## 沒動的

`check-doc-migration-loss.py` 檔頭的範例指令仍寫 `docs/rules/fn-cpp-core.md`，因為那是
「2026-08-31 那輪實際跑的」指令，改了就是改歷史。frozen 的 `docs/ledger.md` 與舊 ledger 裡提到
`docs/rules/<搬走的檔>` 的句子同理不動。全域 `~/.claude` 的 44K 不在本輪範圍。
