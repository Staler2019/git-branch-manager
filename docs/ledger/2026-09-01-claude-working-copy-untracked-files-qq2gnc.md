# 未追蹤檔案在 Working Copy 看不到 diff

使用者回報：「working copy cannot view untracked file in 2 file era or unified
era as unstaged」。在 Working Copy 的 unstaged 欄選一個未追蹤的檔案，兩種 diff
模式都畫出 `Nothing unstaged`，而同一列的 badge 明明寫著 `+12`。同一個畫面上的
兩個東西互相矛盾。

## 一句話的成因

`Session::requestWorkingCopyDiff` 呼叫 `DiffService::workingTreeDiff(staged:
false, {path})`，那裡跑的是 `git diff -- <path>`。**未追蹤的路徑同時不在 index
也不在 HEAD，所以 git 什麼都不印。** 回覆照常送出，只是 `files` 是空的；Dart 的
`_fileOf()` 看到空的就回 `null`，`ScopedDiffView` 於是畫它的 `emptyLabel`。

這個不對稱早就被記過一次，但只記了「行數」那一半 —— `WorkingCopyStatus.h:69-71`
與 `[GIT-zero-means-unmeasured]` 都寫著未追蹤檔案的行數是「讀檔案讀出來的，因為
`git diff` 看不到它」。diff 這一半從來沒有補上。整個 repo（`src/`、
`app_flutter/lib/`、`tests/`）grep `--no-index` 是零筆。

## 同一道牆後面其實有三個缺陷

修好第一個之後，另外兩個會立刻浮出來，因為 scope 的 Stage / Discard 按鈕就畫在
那個 diff 裡面：

1. **看不到 diff** —— 上面那一段。
2. **`PartialStageOperation` 與 `DiscardLinesOperation` 會失敗**。兩者
   （`StageOps.cpp:189`、`:270`）都重新去拿同一份 `workingTreeDiff`，拿到空的就
   回 `No pending changes found for "<path>"`。所以修在 `DiffService` 裡面而不是
   修在 `Session::requestWorkingCopyDiff`，一個地方修好三個呼叫點。
3. **重建出來的 patch 貼不上去**。`appendPatchHeader` 永遠寫
   `--- a/<oldPath>`，從來不寫 `new file mode` + `--- /dev/null`。實測：
   `git apply --cached` 對一個不在 index 的路徑會回
   `error: <path>: does not exist in index`，exit 1；換成 new-file 標頭就成功，
   而且正確地落成 `AM`（index 裡是選到的那幾行，工作區還是全部）。

## 實測出來的 git 行為

全部是真的跑出來的，不是推論來的：

| 指令 | 結果 |
|---|---|
| `git diff --no-index -- /dev/null notes.txt` | 標準的 `new file mode 100644` / `--- /dev/null` / `@@ -0,0 +1,3 @@`，**exit 1** |
| 同上，二進位檔 | `Binary files /dev/null and b/b.bin differ` |
| 同上，結尾沒換行 | 有 `\ No newline at end of file` |
| 同上，子目錄路徑、`-C <dir>`、`globalFlags()` + `diffFlags()` 全帶 | 都可以 |
| `git diff --no-index -- /dev/null nested/` | `Could not access 'nested/null'`，git 拿 /dev/null 的 basename 去配目錄裡面 |
| `git status --porcelain=v2 -z -uall` 對一個未追蹤的巢狀 repo | 回報成目錄 `nested/`（帶斜線） |
| `git ls-files -z -- <path>` | 追蹤的印回路徑，未追蹤的什麼都不印 |
| new-file 標頭的 patch 對 `git add -N` 的路徑 `git apply --cached` | exit 0，落成 `AM` —— 所以 intent-to-add 不會被這個改動弄壞 |

`--no-index` **exit 1 是「有差異」而不是「失敗」**，而
`ProcessRunner::execute` 把任何非零 exit 都轉成 `fail(...)`，`run()` 又只在成功
時才填 `result->out` —— 也就是說 stdout 在失敗路徑上被丟掉了。這裡用
`runner_.stream()` 配一個本地 accumulator：sink 在 `wait()` 回報 exit code 之前
就已經收完每一行了。`stream` 和 `run` 差的只是錯誤分類用的那個 stdout 指標，分隔
符、line splitter、尾端分隔符的處理都一樣，所以組出來的 bytes 和其他 diff 路徑
逐位元組相同（含 `[CPP-run-not-byte-exact]` 的 `\r` 處理）。把 exit 1 當資料讀，
`CompareOps::readMergeBase` 已經是先例。

## 沒有活下來的兩個前提

**其一，`working_copy_view.dart` 自己的註解。** 它寫著「an empty `files` means
git reported no change on that side rather than an error」。這句話就是這個 bug
的成分：對未追蹤的路徑，空的 `files` 的意思是「git 看不到它」。已就地改寫。

**其二，我自己第一輪的讀法。** 我先跟使用者說「超過上限的 tracked diff 會畫成
空白」，這是錯的：`UnifiedDiffParser::parse` 會**留下前 2 MiB 並解析它**，只丟掉
尾巴，設 `truncated = true`。也就是說它從來不是空白，而是把一份看起來完整、其實
不完整的 diff 放到使用者面前。這個更正改變了使用者的選擇，所以是先更正再問第二
次，而不是照著錯的前提做下去。

順帶找到的是 `[CULT-orphan-wiring]` 的第九個實例：`ParsedDiff.truncated` 由
`JsonCodec` 序列化、過 FFI、`ParsedDiff.fromJson` 解出來、`DiffPage` 收成建構子
欄位 —— 然後**沒有任何一個地方讀它**。`ScopedDiffView` 連收都沒收到。

## 使用者的裁定

問了三輪，第二輪是因為我上面那個錯的前提。

1. 機制：`git diff --no-index`（讓 git 做），不是自己在 C++ 合成 diff 文字。與
   `DiffService::stashDiff` 自己註解裡的理由一致 ——「matching git's own output
   exactly is safer than hand-rolling」。
2. 範圍：**view + stage + discard 一起做**，不是只讓它看得到。
3. 太大的檔案：**真的拒絕顯示**，兩個介面都要，tracked 也一起改。使用者原話是
   「if file too large, refuse to show like file diff do. there's might already
   a cap there」—— 上限確實有（2 MiB），「拒絕」則本來沒有。

所以 `UnifiedDiffParser::parse` 現在超過上限就直接回，`files` 是空的；
`DiffPage` 和 `ScopedDiffView` 各自畫 `kDiffTooLargeLabel`。這順便讓 payload 從
「幾 MB 的 hunk」變成「一個 flag」。

## 收斂條件（為什麼是這五個）

`workingTreeDiff` 裡的 fallback 只在五個條件全中時才走。先跑原本的 `git diff`，
然後：

1. `!staged && paths.size() == 1 && files.empty()`；
2. `!paths_.isBare()`；
3. `is_regular_file(workDir / path)`；
4. `git ls-files -z -- <path>` 是空的（⇒ 不在 index）；
5. `file_size <= UnifiedDiffParser::Options{}.maxBytes`，超過就**不開 process**
   直接回 `truncated`。

第 4 條是**問 git，不是猜**（`[STATE-never-guess-what-git-would-say]`）。少了它，
一個「有被追蹤、但沒有改動」的檔案也會得到空的 diff，然後被 `--no-index` 畫成整
個檔案都是新增的 —— 那是**錯的 diff**，比現在這個「少一個 diff」更糟。

## 測試上兩件本來會假綠的事

**一、`file.oldPath.empty()` 這個條件永遠不成立。** 我原本把 new-file 標頭的條件
寫成「kind 是 Added 而且 oldPath 是空的」，因為 `stripPathPrefix` 確實把
`/dev/null` 變成空字串。但 `diff --git a/new.txt b/new.txt` 那一行**在
`--- /dev/null` 之前**就已經把 `oldPath` 填好了，而 `---` 的處理是
`if (!path.empty())` —— 它不會用空字串覆蓋回去。所以一個新增檔案的 `oldPath` 是
它自己的路徑。是 `WorkingTreeDiffShowsAnUntrackedFileAsWhollyAdded` 這個測試抓到
的，而不是讀出來的；條件改成只看 `kind`，並在兩邊都留了註解。

**二、目錄那個測試一開始證明不了任何事。** `WorkingTreeDiffLeavesAnUntracked
DirectoryEmpty` 原本只斷言「回來是空的」，而把 `is_regular_file` 放寬成 `exists`
之後它**照樣綠** —— 因為結果一樣是空的，測試分不出「被擋掉」和「跑了 git 然後無
害地失敗」。改法有兩步：

- 加 `CommandSpy`，借用 `Log::instance().setOperationSink()` 數有幾個 argv 帶
  `--no-index`，並且在「正向」那個測試裡放 `EXPECT_EQ(spy.count(), 1)` 當**儀器
  的對照組**。沒有這個對照組，兩個「沒有跑 `--no-index`」的斷言可能只是因為 spy
  根本什麼都看不到。
- 再加 `EXPECT_FALSE(truncated)`。因為 `std::filesystem::file_size` 失敗時回的是
  `uintmax_t(-1)` 而不是 0，兩個 gate 都拿掉時會掉進「太大」那條路，結果也是空的
  `files` —— 只有 `truncated` 分得出來。

而**在 Linux 上，沒有任何單行 mutation 能讓 `is_regular_file` 那一行變紅**：
`file_size` 對目錄也會設 `ec`，第二道 gate 自己就擋住了。這是平台大方，不是程式
碼對 —— 標準把「對非一般檔案呼叫 `file_size`」定為 implementation-defined，所以
兩道都留著，並且在測試註解裡直接寫明「會變紅的 mutation 是兩道一起拿掉」，而不是
留給下一個人去找一個綠的。

## 各層測試與對應的 mutation

| Mutation | 變紅的 |
|---|---|
| 拿掉 `--no-index` fallback | 7 個 `RealRepoTest`（tracked-unmodified 與 directory 兩個負向測試正確地留綠） |
| 把 `ls-files` gate 反過來 | 只有 `WorkingTreeDiffLeavesATrackedUnmodifiedFileEmpty` |
| 把 size gate 調大 100 倍 | 只有 `WorkingTreeDiffRefusesAnOversizedUntrackedFile` |
| 兩道 file-kind gate 一起拿掉 | 只有 `WorkingTreeDiffLeavesAnUntrackedDirectoryEmpty` |
| 拿掉 new-file patch 標頭 | 只有 `StagesSelectedLinesOfAnUntrackedFile`（既有的 stage/unstage 測試全部留綠） |
| 拿掉 `--no-index` fallback（capi 層） | 只有 `WorkingCopyDiffReportsAnUntrackedFileAsWhollyAdded` |
| 拿掉 `ScopedDiffView` 的 truncated 分支 | `scoped_diff_view_test` 與 `working_copy_diff_pane_test` 各一個 |
| 拿掉 `DiffPage` 的 truncated 分支 | `diff_page_truncated_test` 一個 |

capi 那一層是分開寫的，理由是
`[TEST-fixture-cannot-disagree]` 第 9 列：欄位要活過 `JsonCodec` 和 event
payload，不是只要 C++ struct 裡有就好。`WorkingCopyApiTest` 的 fixture 從寫下來
那天就有一個 `untracked.txt`，而 `requestDiffJson` 從來沒被拿來問過它 —— 這正是
這個洞活這麼久的方式。

## Dart 那邊幾乎沒有改

`working_copy_view.dart:145-149` 本來就把未追蹤的項目併進 unstaged 欄，
`_selectedSides` 本來就解得出它，`_requestBothSides` 本來就會送請求。回覆不再是空
的，畫面就對了。Dart 的改動只有三件：把 `truncated` 從 reply 串到
`WorkingCopyDiffPane` 再串到 `ScopedDiffView`、`DiffPage` 多一個分支、以及就地改
寫那句錯的註解。所以**沒有為「未追蹤的 diff 會顯示」新增 Dart 測試** —— 餵一個非
空 `DiffFile` 進去只能證明 `ScopedDiffView` 會畫，而那件事
`working_copy_diff_pane_test.dart` 早就證明了。

`kDiffTooLargeLabel` 放在 `lib/features/diff/diff_truncation.dart` 而不是各寫各
的，因為兩邊講不一樣的話正是這個 repo 一直在找的那種裂縫。它**刻意不寫出上限的
數字**：那個數字在 C++ 的 `UnifiedDiffParser::Options::maxBytes`，抄一份過來就是
第二個沒人維護的真相來源。

## 順手單一化的一件事

`fsutil::pathFromUtf8()`。UTF-8 路徑轉 `std::filesystem::path` 要走
`std::u8string`，否則 Windows 會用 ANSI code page 解碼，中文檔名就變成另一個路
徑、然後 stat 回報「不存在」而不是報錯。原本只有
`WorkingCopyStatus.cpp:246` 一處手寫這段 `char8_t` 轉換；這輪需要第二處，所以抽
成一個有註解的函式，兩邊都走它。

## 沒有修，記在這裡

- **把一個未追蹤檔案「唯一的那個 scope」整個 discard，會留下一個 0 byte 的檔案而
  不是把檔案刪掉。** 實測過。要刪掉的話就是在決定「discard 整個未追蹤檔案 ＝ 刪
  檔」，而那是 `Tools → Clean untracked files` 的事，是行為決策不是修 bug。已跟
  使用者說明並保留現狀。
- **未追蹤的目錄列（`nested/`）仍然畫 `Nothing unstaged`。** 它不是一個檔案，沒有
  單一檔案的 diff 可畫。
- **這台容器以 root 執行，所以 4 個 updater 測試本來就是紅的**
  （`update_installer_test`、`update_installer_script_test` ×2、
  `update_controller_test`）：它們把目錄 chmod 成不可寫再期待被擋下來，而 root 無
  視權限位。用 `git worktree` 開乾淨的樹驗證過兩次 —— 分支的起點 `b696fee`，以及
  合併進來之後的 `origin/main`（`0b9d6f1`）—— 兩次都是同樣這 4 個紅，與本輪無關。
  第二次值得跑，是因為 #128 正好改過這一區的 fixture（把 chmod 555 換成「目標不
  存在」，理由同樣是 root 無視 mode bits）：它換掉的是另一個，這 4 個沒有被涵蓋。
- **裝置層沒有跑。** `integration_test/` 需要一個真的桌面 session；已 grep 過
  `Nothing unstaged` / `No changes` / `truncated` / `untracked`，零筆命中，所以沒
  有 finder 被這輪改動打到。
