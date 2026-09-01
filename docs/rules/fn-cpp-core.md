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
