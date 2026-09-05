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
