# C++ core

Pin prefix `CPP-`. Format: [README.md](README.md).

## [CPP-run-not-byte-exact] `IProcessRunner::run()` is not byte-exact

- **Rule**: it reassembles stdout from the line splitter, dropping the final separator
  and stripping `\r` before every `\n`.
- **Consequence**: a text blob comes back one byte short; a binary blob is silently corrupted.
- **Do**: for verbatim bytes use `CatFileBatch`, which reads exactly the count
  `cat-file --batch`'s header declares.

## [CPP-reads-writes-unserialised] Reads and writes are not serialised against each other

- **Rule**: background status/diff runs on `sharedReadPool()` while writes run on
  `OperationRunner`'s single serial worker, and a plain `git status` rewrites the index
  and takes `.git/index.lock`.
- **Do**: `GitCommand::globalFlags()` carries `--no-optional-locks` globally for this (**#77**).

## [CPP-attribution-by-kind] Attribution goes through `Operation::kind()`

- **Rule**: `Operation::kind()` plus `PendingOperationTracker` — never "the next completion
  event is mine", and never a match on `describe()`, whose user-facing English is not a protocol.
- **Do**: keep the `PendingOperationKind` switches free of `default`, so a new kind is a
  compile error at the place the new arm belongs.

## [CPP-paired-hooks-onalways] An unconditionally paired call needs `onAlways`

- **Rule**: anything paired unconditionally (`beginAskpass`/`endAskpass`) hangs off the
  `onAlways` hook on `submitOperation` / `submitWorkingCopyOperation`, not `onSuccess`.

## [CPP-coalescer-terminal-paths] `RefreshCoalescer` needs `onFinished()` on every terminal path

- **Rule**: use a `ScopeExit`.
- **Consequence**: miss one and it stays `running_` forever, every later request folds into
  a batch nothing drives, and **refreshes stop happening at all, silently, with no error
  anywhere**.
- **Do**: put the monotonic generation gate inside the same mutex as the snapshot write,
  or a stale walk's `complete:true` answers for a newer one.

## [CPP-session-dtor-order] `~Session()` ordering is load-bearing

- **Rule**: `operations_->drain()` → `refreshTimer_.stop()` →
  `sharedReadPool().cancelQueuedAndDrain()`.

## [CPP-ascii-renderer-is-reference] `GraphAsciiRenderer.cpp` is the reference renderer

- **Rule**: when it and the Dart painter disagree, the C++ one is right.
- **Consequence**: `edge.lane == rows[parentRow].lane` is a **false** invariant —
  `patchIncoming()` never rewrites `edge.lane`, so bending an arriving edge into the
  parent's lane is the renderer's job, not the builder's.
- **See also**: [CULT-reference-impl-not-orphan] — it has no caller and must not be swept.

## [CPP-span-no-braced-list] `std::span<const ObjectId>` does not accept a braced list in C++20

## [CPP-trunktip-reread-before-walk] `query.trunkTip` is re-read immediately before the history walk, not reused from the ref snapshot

- **Rule**: `Session::dispatchRefresh()` does not reuse `refsResult.value()->head.target` (captured
  before `refStore_->load()`'s own `for-each-ref` call) for `query.trunkTip`. It calls
  `refStore_->readHead(token)` a second time, right before `history_->walk(...)`.
- **Consequence**: the walk's `rev-list` re-resolves `historySeedRefs()`'s HEAD *name* fresh at
  whatever moment it actually runs — a third, independent process. Reusing the earlier oid left a
  window: anything that moved the branch tip inside it (another tool touching the repository)
  permanently stranded `GraphBuilder`'s lane-0 reservation, breaking History's uncommitted-row
  connector ([STRUCT-history-uncommitted-row]). Windows widens this window by roughly two orders
  of magnitude in process-spawn cost (`docs/reports/windows-process-cost.md`).
- **Do**: a failure of this second read falls back to the original snapshot's `head.target` rather
  than failing the whole walk — a connector-only refinement must not cost the history walk.
- **Evidence**: [ledger: Windows 未提交列連不到 HEAD](../ledger/2026-09-01-claude-windows-uncommitted-changes-5z40sr.md)

## [CPP-readhead-propagates-failure] `RefStore::readHead()` propagates a genuine process failure, and `Session::open()` never calls it

- **Rule**: a falsy `runner_.run()` result (spawn failure, timeout, a non-zero exit) returns
  `fail(...)` directly, before the "no commits yet" fallback. It used to fold unconditionally into
  that fallback, leaving `head.target` silently null forever on every refresh that hit it.
- **Consequence**: this is safe because `Session::open()` never calls `readHead()`/
  `RefStore::load()` — only the async `dispatchRefresh()` path does, which already has a graceful
  "keep previous state, emit `GBM_EVENT_ERROR_OCCURRED`, skip this cycle" path for any `load()`
  failure.
- **Do**: a real repository cannot express "rev-parse fails, for-each-ref still succeeds" — git
  treats a broken `HEAD` as "not a git repository" uniformly, so every command fails alike
  (measured by hand). Test this failure-vs-Unborn distinction only with a `FakeProcessRunner` that
  scripts the two commands independently (`tests/unit/RefStoreHeadTest.cpp`), never with a
  real-repo capi integration test — one was written that way first and a mutation check caught it
  staying green regardless of the fix.
- **Evidence**: [ledger: Windows 未提交列連不到 HEAD](../ledger/2026-09-01-claude-windows-uncommitted-changes-5z40sr.md)

## [CPP-parse-refuses-over-cap] Over its byte cap `UnifiedDiffParser::parse` returns *no* files, and every consumer owes the user a message

- **Rule**: `truncated == true` now means「nothing was parsed」, not「the first 2 MiB was parsed and
  the tail dropped」. The old behaviour put a diff on screen that looked complete and was not, which
  is a wrong answer rather than a partial one.
- **Consequence**: an empty `files` is therefore two different conditions, and a surface that draws
  its「no changes」placeholder for both tells a file with changes that it has none. Check
  `truncated` **before** `files.isEmpty()`.
- **Rule**: the flag was `[CULT-orphan-wiring]`'s ninth instance — serialized by `JsonCodec`,
  carried across the FFI, decoded by `ParsedDiff.fromJson`, taken as a `DiffPage` constructor field,
  and read by nothing. `kDiffTooLargeLabel` (`features/diff/diff_truncation.dart`) is now the one
  wording, shared by `DiffPage` and `ScopedDiffView`, and deliberately does not name the byte cap —
  that number lives in `UnifiedDiffParser::Options::maxBytes` and a copy would be a second source
  of truth.
- **Do**: refuse *before* reading where the size is already known — `DiffService::workingTreeDiff`
  compares an untracked file's `file_size` to the same `maxBytes` and returns `truncated` without
  spawning git. **`std::filesystem::file_size` returns `uintmax_t(-1)` on failure, not 0**, so a
  failed stat that is let through reports the file as over the cap.
- **Evidence**: [ledger: 未追蹤檔案在 Working Copy 看不到 diff](../ledger/2026-09-01-claude-working-copy-untracked-files-qq2gnc.md)


## [CPP-benign-exit-is-declared] 一個「非零 exit 其實是答案」的指令，要在 `GitCommand` 上自己宣告

- **Rule**: `GitCommand::benignExitCodes` 由**呼叫端**列出這條指令可以合法回答的非零 code，
  `ProcessRunner::recordOperation()` 據此設 `OperationRecord::benignExit`，Dart 端再用它
  加上 `cancelled`/`timedOut` 合成三個嚴重度。只有呼叫端知道自己問了什麼，所以宣告只能在那裡。
- **Rule**: **是一組 code，不是一個 bool**，而 `git config --local --unset` 是唯一的實證——
  它「從沒設過」的答案是 **5**，不是 `--get` 的 1（實測）。一個「這裡非零都沒關係」的旗標會
  連 128（設定檔壞掉、不是 repo、ref 解不出來）一起吞掉。四個呼叫點的 128 全部仍是錯誤。
- **Consequence**: 沒有這個欄位時，`ConfigOps` 那句「exits 1 … not a genuine failure」只講給
  會用到它的人聽，從沒講給紀錄聽——所以一個沒設 local identity 的 repo 每次 refresh 都在
  操作紀錄寫兩列紅字。spec P10 的 `LOGRULES` 把 error 保留給**真的被拒絕**的動作。
- **Rule**: **`benignExit` 的第二個生產者是 `sinkStopped`**，而它是 runner 自己知道的：
  `LineSink` 回傳 false 會殺掉子程序，`execute()` 回傳成功，但紀錄已經帶著殺掉留下的非零 code。
  共用同一個欄位是因為**意思相同**（都是「這次呼叫做完了該做的」）；它長得像 `cancelled` 而
  意思相反——那個是被丟掉的工作，這個是刻意提早收工的工作。
- **Do**: `recordOperation()` 刻意**不**用 `cancelled`/`timedOut` 防護，也**不**限縮成非零 code。
  Dart 的 `level` 在讀這個旗標之前就先判掉那兩個、exit 0 本來就是 info，所以兩道防護都會是
  沒有任何一層弄得紅的分支。順序就是防護本身，而且只存在於 `OperationRecord.level` 那一個地方。
- **Do**: `run()`/`stream()` 的成功失敗語意**不變**——良性 code 照樣 `fail(...)`。改的只有紀錄。
- **Do**: 測試這種東西時，條件要由**真實 git 狀態**排出來，不要探一個沒人會設的假 key。假 key
  測到的是機制會動，但主張是「git 對這個情況回這個 code」，git 哪天改了它會繼續綠（使用者裁定）。
  並且在斷言 `benignExit` 之前先 `ASSERT` 抓到的 `exitCode`，否則 fixture 的 `SetUp()` 一改就
  靜靜變成空測試——`RealRepoTest` 和 `OperationLogApiTest` 的 `SetUp()` 都會把 `user.name` 寫進
  **`--local`** scope（沒有 `--global`），所以「乾淨的 repo」在它們裡面不存在。
- **Evidence**: [ledger: 「回答了否」和「被拒絕」，紀錄分不出來](../ledger/2026-09-05-fix-benign-exit-not-logged-as-error.md)

## [CPP-windows-terminate-hangs-join] Windows 的 `terminate()` 必須砍整棵樹**並且**取消卡住的同步 I/O，否則 `pump()` 的 join 永遠回不來

- **Rule**: `WindowsChild::pump()` 的 stdout 在本執行緒 blocking `ReadFile`，stderr（和 stdin）
  另開執行緒也是 blocking。pipe 的 `ReadFile` 只有在**所有**寫入端關掉才返回，而
  `TerminateProcess` 殺的是一個行程不是一棵樹——Windows 上 git 是從登錄檔解出
  `<InstallPath>\cmd\git.exe`（`GitExecutable::gitFromRegistry`），一個會 re-exec 的 git
  留下真正在跑的那個握著寫入端。
- **Consequence**: `stderrThread.join()` 就此卡死，而 `command.timeout` **蓋不到**它：pump 只在
  兩次 `ReadFile` **之間**驗 deadline，join 在 `break` 之後。實測是一整顆 CI job 卡 81 分鐘。
- **Rule**: POSIX 那半邊沒有對應的洞，而且**不要為了對稱去改它**——單一 `poll()` 迴圈沒有執行緒
  要 join，`terminate()` 也已經是 SIGTERM→SIGKILL 兩段式。改它只會製造沒有任何一層測得紅的分支。
- **Do**: spawn 用 `CREATE_SUSPENDED` → `CreateJobObjectW` → `AssignProcessToJobObject` →
  **`ResumeThread`**，`terminate()` 先 `TerminateJobObject` 再退回 `TerminateProcess`。
  `pi.hThread` 因此要留到 resume 之後才關，而且 job 的任何一步失敗都**不可以**讓 spawn 失敗——
  留下一個 suspended 的孤兒比原本的卡死更糟；沒有 job 就退回原本的單行程 kill。
- **Do**: 刻意**不加** `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`。job handle 在**成功**路徑上也會關，
  那個旗標會連 git 正當留下的東西一起殺掉，簽章 commit 起的 `gpg-agent` 就是具體的例子。
- **Do**: join 之前用 `CancelSynchronousIo` 把 helper 從 `ReadFile` 裡拉出來，**重試**而不是只發
  一次（執行緒還沒進到 I/O 時它回 `ERROR_NOT_FOUND`）。必然收斂：任何一次 read 失敗執行緒就
  return。並且用輪詢，不要先看「已經 terminate 了嗎」再決定進不進迴圈——cancel 是別的執行緒送來
  的，可以剛好落在那個檢查之後，那就是同一個卡死又回來。
- **Do not**: 把 join 改成 `detach()`。那不是簡化而是 use-after-free——helper 寫的是 `execute()`
  的區域變數 `result.err`，lambda 還**以參考捕獲** `onProgress`。
- **Note**: 這個洞比發現它的那一輪老得多。`ASinkThatStopsEarlyIsRecordedAsBenign` 是整個 repo
  第一個讓 `LineSink` 回傳 false 的測試，現有 cancellation 測試全部在開跑前就 cancel，所以
  `WindowsChild::terminate()` 在 CI 上從來沒被執行過一次。同一個洞也在 cancel 路徑上。
- **Rule**: **stdout 那一半用 deadline watchdog 補，不要動讀取路徑。** 一個「不寫任何東西、也不
  結束」的子程序會讓 pump 卡在 stdout 的同步 `ReadFile` 上，而 deadline 只在兩次 read **之間**
  驗，所以 `command.timeout` 在 Windows 上根本不會觸發。修法是同一個機制換一個方向：一條只在
  `timeout > 0` 時才起的執行緒等 event 等到逾時，然後 `terminate()` 並對 pump 執行緒重試
  `CancelSynchronousIo`——**執行緒不能取消自己卡住的 I/O**，這是唯一的差別。
- **Do**: `GetCurrentThread()` 是 pseudo-handle，對別的執行緒沒有意義，要先 `DuplicateHandle`；
  event 用 manual-reset，pump 的**每一條**離開路徑都要 `SetEvent` 後 join，handle 在 join 之後
  才關。watchdog 寫 `terminate()` 和一個 atomic，活過這個 frame 就是 use-after-free。
- **Do**: `*timedOut` 由 pump 在 join 之後從 atomic 發布，不要讓迴圈和 watchdog 各寫各的——那是
  一個 `bool*` 上的資料競爭，而兩邊都可能判定逾時。
- **Note**: **原本這條 Note 記的是「known-remaining，本輪沒有修，等使用者裁定」，已被使用者裁定
  「順手一起做掉」推翻，就地改寫。** 當時列的兩個修法（overlapped I/O、stdout 另開執行緒）都沒有
  採用：前者要把匿名 pipe 換成具名 pipe，後者會把 `LineSink` 搬到別的執行緒上跑，和 POSIX 不對稱。
- **Note**: `timeout == 0` 的路徑（網路指令照合約都是 0）**完全沒有 watchdog**，靠的仍然是取消時
  砍整棵樹把 pipe 的寫入端關掉。這是刻意的殘留，寫出來而不是暗示。
- **Note**: macOS/Linux 上那個測試**永遠是綠的**，兩邊 pump 結構不同——這條 rule 只有 Windows CI
  能反駁（[TEST-fixture-cannot-disagree]）。
- **Note**: **job object 的成本沒有量到，而且第一次宣稱量到是錯的**（就地更正）。三次 Windows 跑，
  會 spawn git 的同 151 個測試：無 job object 133.71s、有 job object 177.67s（1.33×）、
  有 job object 再加一條 watchdog 執行緒 **136.38s（1.02×）**——同一個 job object 在第三次跑回到
  1.02×，所以那 44 秒是 runner 快慢。**當時的「對照組」是不 spawn 的 175 個測試，平均 34ms 一個，
  對機器快慢根本不敏感**（它自己第三次跑是 1.58×），拿它校正 1 秒級的測試等於用沒有刻度的尺。
  每個組態 n=1，runner 跑間變異比效應大；要量得同一顆 job 內 A/B。
- **Do**: 一個對照組要先證明**它對你要排除的變因有反應**，否則它只是另一個數字——
  [TEST-fixture-cannot-disagree] 換到量測上的同一件事。
- **Note**: 就算真的有成本也不省，兩個省法都要拿正確性換：共用一個 job 會讓 `TerminateJobObject`
  殺掉並行的其他 git；拿掉 `CREATE_SUSPENDED` 會把「孫子在 assign 之前就生出來」的競態放回去。
  Windows job 11m09s 對 25 分鐘上限，沒有人在等它。
- **Evidence**: [ledger: 追加，Windows CI 卡 81 分鐘](../ledger/2026-09-05-fix-benign-exit-not-logged-as-error.md)
