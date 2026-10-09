# feature/mergePanel — 從分支列進 Merge / Rebase 時鎖定目標；revert 不開 editor；squash 帶 SQUASH_MSG 並 commit

## Situation

使用者回報（2026-10-08）：sidebar 分支列 `⋮`（05-B）的 `Merge into current` / `Rebase current onto here`
進對話框後還要自己選分支。讀碼後的現況：

```
05-B 項目                   路由                              來源欄位
Merge into current       → /dialogs/merge  （不帶參數）      DropdownButtonFormField，空白
Rebase current onto here → /dialogs/rebase-onto?target=X    DropdownButtonFormField，有預填但可改
```

使用者隨即更正：rebase 其實有預填，但「不應該可以選」，且「下拉的樣式也不對」——兩個對話框都用 Material
`DropdownButtonFormField`，而 repo 已有 spec P06 版的 `GbmRefPicker`（Checkout / New branch / Add worktree 在用）。

同一輪又多了兩個回報：

- 「merge 的 commit 訊息不是可留空，你要先帶入預設樣式」。
- 「revert 現在會開 editor 編輯 revert 訊息，應該用預設就好」——Windows、單筆、無衝突，跳出 VS Code。

## Task

使用者裁定（設計稿 `docs/claude-design-demo/merge-rebase-dialogs-spec.html` §05 逐條記錄）：

1. 從 05-B / 05-E 進入時目標鎖成 `ro`；從選單 / 快捷鍵進入時用 `GbmRefPicker`（① commit 列進 Rebase 也鎖定）。
2. ② Merge 來源加入 remote branch。③ 不做「落後 N 個 commit」計數。⑤ ro 欄照 app（無框）。⑥ 標題與按鈕不動。
3. ⑦ 預設訊息完全照 git。使用者先問「不是 merge from {} to {} 嗎」，實測 git 的格式是
   `Merge branch 'X'`，目的地不是 main/master 時加 ` into Y`；remote 來源是 `Merge remote-tracking branch 'origin/x'`。
4. ④ 05-E `Merge into current` 維持直接 dispatch、不開對話框。~~本輪最初對 ④ 沒有給建議~~，後補建議「不改」
   （標籤沒有省略號，依 [UX-ellipsis-promises-a-dialog] 不應開對話框），使用者採納；設計稿上以更正形式保留。
5. ⑧ squash 一起做；⑨ squash 訊息用 git 的 SQUASH_MSG；「merge 沒 conflict 才可以直接 commit」。
6. editor 根因：「--no-edit、對其 /dev/null」——revert 加 `--no-edit`，Windows 子行程 stdin 改接 `NUL`。
7. 執行模式 AUTO：可 commit，不 push、不開 PR。

## Action

十個 commit，依 S1 → S4 切片，每個皆 test-first，可逐個 revert：

| Commit | 內容 | mutation（跑了幾個 → 各自紅幾個測試） |
|---|---|---|
| `75305ea` | 設計稿 | — |
| `c6ae55e` | merge 路由帶 `source`；05-B 傳被點的分支 | 2 → 1、2 |
| `7c71e01` | Merge：鎖定 / `GbmRefPicker`（local+remote）、「合入」ro、git 預設訊息 | 3 → 3、1、2 |
| `d98bf7a` | Rebase：鎖定（branch 或 `commit <8碼>`）/ picker、「重新安置」ro；抽出 `GbmRefReadOnlyField` | 4 → 2、1、1、1 |
| `bcafed1` | `RevertOps` 加 `--no-edit`（`--no-commit` 時不加） | 2 → 1、1 |
| `34cbd3c` | Windows `ProcessRunner`：不需 stdin 時 `hStdInput` 開 `NUL` | POSIX 對照 1 → 1（逾時紅） |
| `b60970c` | core `SquashMessageStore`：重現 `.git/SQUASH_MSG` | 4 → 2、2、1、1 |
| `28ff794` | capi `GBM_EVENT_SQUASH_MESSAGE_READY = 36` + Dart binding / state | capi 2 → 1、1；Dart 3 → 1、1、1 |
| `2fd61a4` | `MergeOps` squash：有 stage 內容才 `commit --file -` | 4 → 1、1、1、4 |
| `6bcbd13` | 對話框 squash：預填預覽、陳舊即重請求、預覽未到停用 Merge | 5 → 2、2、3、2、1 |
| `29cee0e` | squash 預覽加 `--no-expand-tabs`（verifier 的 REFUTED，見下） | 1 → 2 |
| `6713043` | squash 前已有 stage 內容時只 stage、不 commit（第二次 REFUTED，見下） | 1 → 2 |

量測與實跑得到、讀碼得不到的事：

- **revert 為何開 editor**：git 只在 stdin 是 terminal 時開 editor。POSIX 分支本來就把子行程 stdin 接 `/dev/null`；
  Windows 分支用 `GetStdHandle` 繼承了 app 的 stdin。兩處都修：`--no-edit` 是語意上的修正，`NUL` 是讓
  其他指令也不會再遇到同一個陷阱。
- **SQUASH_MSG 可以 byte-identical 重現**：`"Squashed commit of the following:\n\n"` +
  ~~`git log --pretty=medium --no-decorate --no-abbrev-commit --no-mailmap --no-notes --no-show-signature --no-color --date=default <headOid>..<sourceOid>` + `"\n"`。~~
  更正：上面那組旗標**不夠**——內文有 tab 時 medium 格式會展開成空白，SQUASH_MSG 保留 tab。S3 的 verifier 以
  `printf 'Subject\n\n\tindented with a tab\n' | git commit -F -` 重現（`cmp` 第 9 行不同），判 REFUTED（P2，本輪引入）。
  `29cee0e` 加 `--no-expand-tabs` 後，該最小重現與 verifier 的 hostile-config 情境（含 tab、`功能/ü`、CRLF、空訊息）皆 byte 相同。
  正確的指令是 `git log --pretty=medium --no-decorate --no-abbrev-commit --no-mailmap --no-expand-tabs --no-notes --no-show-signature --no-color --date=default <headOid>..<sourceOid>`。
  `RealRepoTest.SquashPreviewMatchesTheSquashMsgGitWrites` 在設了 `log.abbrevCommit=true`、`.mailmap`、
  一筆 note、範圍含 merge commit 的 repo 上比對真的 `.git/SQUASH_MSG`。
  ~~計畫寫「逐一拿掉三個新旗標各自變紅」~~ 更正：拿掉 `--no-abbrev-commit`、`--no-mailmap` 各自讓整合測試變紅；
  拿掉 `--no-notes` **不會**——明確給 `--pretty` 時 git 本來就不印 notes。它只被參數斷言測試釘住，程式註解如實寫明是無法驗紅的保險。
- **陳舊預覽**：state 不做以 source 為 key 的快取，只存最近一次回覆；`isCurrentFor` 同時比對 source、
  HEAD oid、來源 ref 的 tip oid（`RefSnapshot.refs[*].target`），任一不符就重新請求，每個 key 只重試一次以免迴圈。
  拿掉 headOid 或 sourceOid 比對各自讓專屬測試變紅。
- **squash commit 的分支**：`merge --squash` 成功後 `diff --cached --quiet`——exit 0（沒有 stage 內容）就不 commit、
  回 up to date；exit 1 才 `commit --file -`（訊息走 stdin，不走 `-m`，避免 argv 長度與 `-` 開頭問題）。
  commit 失敗（hook、簽章）回 `succeeded=false`，summary 寫明變更已 stage。衝突時只有一條指令。
  ~~上述流程足以保證 commit 只含來源的變更~~ 更正：S3 的第二次 verifier 判 REFUTED（P2，`2fd61a4` 引入）——
  **fast-forward 的 `merge --squash` 會保留使用者原本 stage 的變更**（non-ff 時 git 會以 "Local changes would be
  overwritten" 拒絕，所以只有 ff 會中），之後的 `commit` 把它們一起寫進只列來源 commit 的訊息。`6713043` 改成
  merge **之前**先跑一次 `diff --cached --quiet`：index 與 HEAD 不同就照樣 squash，但只 stage、不 commit，summary 說明原因
  ——也就是本輪之前的行為，只用在這一種情況。勾 stash 時 stash 先跑、index 乾淨，照常 commit。
  `RealRepoTest.ASquashNeverCommitsWorkTheUserHadAlreadyStaged` 以 verifier 的情境端到端釘住。

過程中的錯誤，如實記錄：

- C4 的第一次 mutation 計數**無效**：zsh 不對 `$files` 做 word split，四個 mutation 全是載入失敗而非斷言紅。
  改用字面路徑重跑，表中數字是重跑的結果。
- C3 的 M2 第一次沒紅：對話框捲動後點擊落空。改 `ensureVisible`、開 `hitTestWarningShouldBeFatal`、加斷言 picker 選取後重跑。
- C8 的 `failed` mutation 第一次沒紅：補「失敗的回覆永遠不算 current」測試。
- clang-format：本機 v23、CI v18。`GitIntegrationTest.cpp` 原本就有 24 處不符（較早一次比對漏了 `--Werror`），
  只格式化本輪新增的行範圍，並還原一個無關的 include 重排。
- plan-verifier 對 S3 兩次 REVISE（argv 長度、空範圍 / commit 失敗、git config 旗標、快取 key、metadata；
  第二次是 sourceOid 沒有 reader）。全部在計畫裡 FIX，依規則停在 Stop 0 交使用者裁定，未再自動重送。

## Result

- 05-B 兩個項目進對話框時目標鎖定，選單進入時用 `GbmRefPicker`；兩檔的 `DropdownButtonFormField` 已移除。
- Merge 訊息預填 git 預設格式；squash 預填 SQUASH_MSG，無衝突時直接 commit 成一筆一般 commit。
- revert 不再開 editor。
- G3 全套（`6bcbd13` 上）：core 572 pass／2 skipped（git-lfs 未安裝的兩個 LFS 測試）；capi 183 pass；Flutter 3282 pass／1 skipped；`dart analyze` 0、`dart format` 0。
  之後的 `29cee0e`、`6713043` 只動 C++：core 576 pass（+2 新測試；git-lfs 於 2026-10-09 13:53 出現在 homebrew——
  同時段 go／llvm／qtbase 也被更新，不是本 session 做的——兩個 LFS 測試因此不再 skip）、capi 183 pass。
- S3 的 verifier（risk 單元，序列化邊界）共三次：REFUTED（tab 展開）→ `29cee0e`；REFUTED（ff squash 夾帶已 stage 變更）→ `6713043`；
  第三次 **CONFIRMED**（HEAD `6713043`；含 hostile config、ISO-8859-1、remote、detached、capi JSON 跳脫、dialog probe、真實 repo 七個 merge 情境）。
  計畫預算「fix/reverify 至多 2 輪」剛好用完。
- 延後的 P4（未修，理由：不影響正確性或已 fail-safe）：失敗回覆多一次重請求；整合測試容忍一個結尾換行；postFront 回覆順序顛倒（未重現）；
  非 UTF-8 訊息的嚴格 `utf8.decode`（未重現）；commit 時 git 把 `"    \n"` 清成 `"\n"`（與手動 commit SQUASH_MSG 相同）；
  淨變更為零的 squash 留下 `.git/SQUASH_MSG`；與 branch 同名的 tag 讓預覽一直陳舊（fail-safe）；
  non-ff squash 遇已 stage 變更時 git 直接拒絕（連 stage 都沒有，走既有錯誤路徑）；預覽失敗時使用者自行輸入的文字仍會被 commit。
- G3 orphan grep 兩方向：`requestSquashMessage` / `squashMessagePreview` / `mergeDialogFor` / `openMergeDialog` /
  `GbmRefReadOnlyField` 在 `lib/` 都有 caller 與 reader。改動的 lib 檔沒有新的 `InkWell(` / `GestureDetector(`。
- device 層：`integration_test/` 沒有任何測試走 merge / rebase / revert（唯一 grep 命中是 05-G 的 discard 行測試，與本輪無關），
  所以本輪沒有可跑的 device 測試；這是覆蓋缺口，不是「跑過且綠」。

未驗證 / 未做，明列：

- **Windows 分支未在本機編譯或執行**（本機 macOS）。`ProcessRunner.cpp` 的 `NUL` 分支只能靠 Windows CI；
  [CPP-windows-terminate-hangs-join] 的原則同樣適用。
- 使用者的 Windows 機器上 revert 不再跳 VS Code，**尚未由使用者確認**。
- 沒有 push、沒有開 PR（AUTO 模式不授權）。
- **沒有實際啟動 app 點擊驗證**：本 session 沒有能操作原生 macOS 視窗的工具，05-B 兩個項目的實點只由 widget / integration 層（`sidebar_branch_compare_rebase_test`、`dialog_target_prefill_test`）驗證。
- 發現但未處理（只報告，未開 issue）：`src/core/git/PreparedCommitMessage.h` 的 `readPreparedCommitMessage` /
  `shouldApplyPreparedCommitMessage` 在 `src/capi/` 與 `app_flutter/lib/` 都沒有 caller，只有單元測試引用——
  [CULT-orphan-wiring] 的形狀。本輪的 SQUASH_MSG 走預覽而非讀檔，所以沒有接它。

沒有新增 rule：本輪的陷阱（revert 的 tty 判斷、`--no-notes` 冗餘）都已由測試或程式註解釘住。
