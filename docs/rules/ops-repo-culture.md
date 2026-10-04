# Repo culture

Pin prefix `CULT-`. Format: [README.md](README.md).

## [CULT-standing-rules] Standing rules, set by the user — they outrank convenience

- **Rule**: hitting a related issue means reading the spec and the decision record and fixing it; an issue number is not permission to stop.
- **Rule**: never produce a 「本輪不做」 or open a new issue without the user's decision. Stage by file; never `git add -A` at the repo root.

## [CULT-orphan-wiring] Orphan wiring is the recurring defect shape here

- **Rule**: a route, provider, preference, capi field or parameter with no caller or reader under `lib/` — or a producer whose output nothing reads. It has shipped twelve times (**#102**).
- **Do**: grep both directions before adding one and before deleting the last caller; 「who reads this」 finds the orphan, 「could the reader do what this promises」 decides wire versus delete.
- **Evidence**: [record: the twelve instances](../records/2026-10-04-orphan-wiring-instances.md)

## [CULT-single-source-of-truth] A second source of truth for a computed fact is how a bug hides

- **Rule**: it cannot disagree with itself. Folder identity, column order, selection sets, `conflictActive`, `submitCommit()` and `scopeButtonLabel()` are each deliberately single-sourced.

## [CULT-scrutinise-the-comment] A note explaining why code or a test is shaped as it is deserves the same scrutiny as the code

- **Rule**: one correct observation with a wrong cause became a permanent workaround and hid a real defect for months. A comment claiming a measured bound or a performance property is re-measured whenever anything upstream moves.
- **Do**: when a comment says two paths share something, pump both and look; a mutation that fails to land where the comment predicted means the comment is wrong.

## [CULT-cache-documents-three-things] Every cache documents three things, and needs a counting test

- **Rule**: document the key and why it distinguishes every case; which named events invalidate it (「none」 is legitimate — say so); the symptom if invalidation is missed.
- **Do**: test by counting (`hits()`/`misses()`), never by the result alone; prefer removing the recomputation to caching it.
- **Evidence**: `UntrackedLineCountCache`'s counting tests in `tests/unit/GitIntegrationTest.cpp`
