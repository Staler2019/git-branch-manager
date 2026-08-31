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
