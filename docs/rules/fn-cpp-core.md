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
- **Note**: **就地更正上一條 Note 的「沒有量到」**——量的工具現在有了，
  `tests/tools/spawn_cost_win.cpp`（`gbm_spawn_cost`），`perf-nightly.yml` 的
  `windows-spawn-cost` 每晚跑。**～～數字仍然沒有，要等一次 nightly～～ 數字有了**（就地更正）：
  `windows-2022`／MSVC 14.44／51 輪，job object **每次 spawn 71µs，佔一次 `git --version`
  的 0.27%**，解析度 18µs、注入 300µs 回收 291µs（誤差 3%）。**「慢 33%」因此差了兩個
  數量級**。上面那三個秒數仍然不可引用。比值 gate 仍然關著——一個樣本不足以挑門檻。
  全文與方法：`docs/reports/windows-process-cost.md`。
- **Note**: **同一次跑的 watchdog 數字不可引用**，而且錯的是工具不是 runner：它印
  `watchdog delta = -72us (resolved)`，而 watchdog 不可能讓 spawn 變快。那 18µs 是在 ~16ms 的
  trivial child 上量的，卻拿去判 ~26ms 的 git 行程——**拿 A 的尺量 B**，和 33% 被更正的
  理由是同一個，只是低一層。已改成給 `prod_*` 那一對自己的 A/A null 手臂；在那之後才有的
  `prod_resolution_us` 才是判準。
- **Do**: 那支工具的形狀就是上一條 Do 的實作，照抄即可：**A/A null 手臂**量出這一次執行的
  解析度（差值小於它就只印上界、絕不印點估計），**注入一個已知延遲**當作儀器自我檢查
  （回收不到 50% 以內就印 `verdict=instrument-unreliable`，那一次的數字不准引用），
  手臂**交錯**而非分區塊，每一個樣本都驗 exit code、stdout 位元組和 `IsProcessInJob`。
  分母是同一個交錯裡的 `git --version`，不是那個 trivial child。
- **Do**: 比值 gate 預設**關著**（`GBM_MAX_JOB_OVERHEAD_FRACTION` 0.0）。要 gate 的數字還沒
  收集到，而在量測之前先挑門檻正是這支工具存在要更正的那個順序。
- **Note**: 就算真的有成本也不省，兩個省法都要拿正確性換：共用一個 job 會讓 `TerminateJobObject`
  殺掉並行的其他 git；拿掉 `CREATE_SUSPENDED` 會把「孫子在 assign 之前就生出來」的競態放回去。
  Windows job 11m09s 對 25 分鐘上限，沒有人在等它。
- **Evidence**: [ledger: 追加，Windows CI 卡 81 分鐘](../ledger/2026-09-05-fix-benign-exit-not-logged-as-error.md)

## [CPP-idle-not-total] 一個動作的逾時要問「還活著嗎」，不是「跑多久了」——而這兩題對 `timeout = 0` 的指令答案不同

- **Rule**: `GitCommand` 有兩個獨立的欄位。`timeout` 是**總時長**上限；`idleTimeout` 是距離
  上一次「有任何 I/O 進展」多久算卡死。~100 個有限 `timeout` 的呼叫點**不設** `idleTimeout`：
  它們本來就不可能永遠卡住，加上去只會多一個誤殺「合法但安靜」指令的風險而換不到安全性。
- **Rule**: 進展的定義是三個都算——stdout 讀到 `n > 0`、stderr 讀到 `n > 0`、**stdin 寫出
  `n > 0`**。最後一個容易漏：一個正在吃我們 stdin 的子程序是活的，即使它還沒回答任何東西。
- **Consequence**: 28 個 `timeout = 0` 的呼叫點（fetch / pull / push / clone / merge / rebase /
  cherry-pick / revert / checkout / `reset --hard` / repack / LFS / submodule）原本**既沒有
  deadline，也沒有搆得到的取消**——它們註解裡寫的那個控制到這一輪才存在
  （[CULT-orphan-wiring]，見 `gbm_cancel_operation`）。
- **Rule**: **`kHangCeiling` 是 10 分鐘，而它被當成總時長上限來挑，不是當成兩次進度訊息之間的
  間隔。** 理由是量出來的：**git 只有在 stderr 是 tty 時才畫進度條**，所以走 pipe 的時候這 28 個
  指令對 stderr 一個位元組都不吐——閒置逾時對它們就退化成總時長上限。實測最慢的一次完全安靜的
  執行是 `repack -adf` 的 3540ms，10 分鐘是它的約 170 倍。
- **Note**: 全套測試約 10k 次呼叫的普查裡，**最大的閒置間隔是 148ms**。那個數字看起來允許一個
  緊得多的天花板，而它**不能**——它是有輸出的指令量出來的，正好不是設 `idleTimeout` 的那一群。
  把它當成上限的依據，會是拿量到 A 的尺去裁 B。
- **Do**: 想要一個緊得多的天花板，正確的作法是**讓 git 願意講話**（`--progress` 會在非 tty 時
  也輸出），但那會改變 stderr 的內容，而 `classifyGitStderr` 和操作紀錄都在讀它——所以那是
  另一個決定，不是這一個的延伸。
- **Do**: POSIX 那半邊是把固定的 `deadline` 換成滑動的 `lastProgress`，既有 200ms 上限的
  `poll()` 迴圈結構不動。Windows 那半邊是同一條 watchdog 執行緒換一個問法：反覆等一小段，
  每次醒來比對 atomic 的 `lastProgress_`——**讀取熱路徑不增加任何 syscall**，因為 watchdog
  自己輪詢 atomic 而不是靠 event 通知（[CPP-windows-terminate-hangs-join]）。
- **Do**: **鑑別測試是「還在滴輸出」那一顆，不是「完全不講話」那一顆。** 只有後者的話，把 idle
  實作成 total 會全綠。`hang_forever --drip N` 每 200ms 印一行、印 N 行後轉靜默，斷言總耗時
  **超過** `N × 200ms`（證明產出期間沒被砍）**且**最後仍逾時收場。每一行都要 flush——stdout 對
  pipe 是 block-buffered，沒 flush 的 drip 會在結束時一次湧出，和靜默無從分辨
  ([TEST-fixture-cannot-disagree])。
- **Evidence**: [ledger: 追加四，動作的逾時改成閒置](../ledger/2026-09-05-fix-benign-exit-not-logged-as-error.md)

## [CPP-cancel-is-registered-not-returned] `OperationRunner::submit()` 的 `Handle` 要被存起來，不是被丟掉

- **Rule**: `Session::submitOperation()` 把 `Handle{id, cancel}` 存進 `inFlight_`，
  完成 callback 自己 erase，`gbm_cancel_operation(session, id)` 據此取消（`id == 0` 是全部）。
- **Consequence**: 在這之前 ~40 個呼叫點全部丟掉那個 `Handle`，全 `src/` 只有兩處 `.cancel()`
  且都是 `historyCancel_`——所以 [CPP-idle-not-total] 那 28 個指令註解裡的「Cancellation is the
  control the user actually needs」指的是一個搆不到的控制。[CULT-orphan-wiring] 的生產者端孤兒，
  正是該 rule「grep both directions」才看得見的形狀。
- **Rule**: **註冊的鎖刻意跨過 `submit()`**。callback 第一件事就是拿同一把 `inFlightMutex_`，
  所以很快做完的操作不可能搶在 insert 前面 erase 一個還不存在的 entry——用構造定序，而不是留一個
  要用推理說服自己的窗口，而那個窗口測試逼不出來，推理就會是唯一的證據。`submit()` 只 push 進
  queue 加 notify、從不等 worker，所以跨著它拿第二把鎖不會 deadlock。
- **Do**: 三顆測試裡**只有一顆看得見 insert**——另外兩顆斷言 0，把註冊整個刪掉也是 0。那一顆
  決定性而非賽跑，靠的是兩件事一起成立：worker 是序列的且自己呼叫 `onDone`，而
  `CallbackRegistry::emit` 是同步的。所以 callback 跑的時候 worker 卡在 #1 的完成裡、#2..#10
  必然還在佇列上且已註冊，而 #1 已被 erase——**9 是精確值，不是下界**。
- **Note**: **Dart / UI 刻意沒接**（使用者裁定：「開 capi cancellation token 然後先不接線」），
  所以這是一個**新開的、被記錄的**孤兒，寫在 `gbm_capi.h` 的 doc comment 裡而不是留給下一次
  orphan sweep 當死碼刪掉。[TEST-ffi-matches-symbol-only] 指出這條縫只有 device 層測得到。
  追在 **#139**，並列在 [DRIFT-cancel-capi-unwired]。
- **Note**: 「取消一個**正在跑**的 git 會不會真的砍掉它」在 capi 層**沒有**自動化測試——這一層
  沒有跑得夠久又不必跟斷言賽跑的操作。那個主張靠的是下一層既有的覆蓋
  （`ProcessRunnerTest` 的 `source.cancel()`、`CancelsAReadOnlyWalkPromptly`、
  `CommitMetaStoreStopsIssuingRequestsOnceCancelled`），三者都在工作開始**之前**取消，
  所以是決定性的。寫在測試檔頂端，不是留白（[SPEC-absent-not-faked]）。
- **Evidence**: [ledger: 追加四，動作的逾時改成閒置](../ledger/2026-09-05-fix-benign-exit-not-logged-as-error.md)
