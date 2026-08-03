# Features

Everything below works end to end on Linux, macOS and Windows.

- **Fork-style commit graph.** A branch's first-parent chain renders as one
  unbroken vertical column, the trunk owns the leftmost lane for all of history,
  and merges branch right and rejoin with a single bend.
- **Multiple base folders** scanned for repositories, with a SQLite cache and an
  explicit Refresh, so startup never waits on the filesystem.
- **Branch switching**, including the dirty-work-tree case with Stash / Discard /
  Cancel rather than a raw Git error.
- **Diff viewing** per commit and per file, with real text selection.
- **The working copy**: status, stage/unstage by file, hunk or line, commit and
  amend.
- **Merge** (fast-forward-only / no-fast-forward / squash), **cherry-pick**
  (single, multi and range), and **conflict resolution** across all three index
  stages, with a side-by-side diff.
- **Worktrees, stash and tags**: add/remove/lock/prune worktrees; save/apply/
  pop/drop/branch stashes; create/delete/push annotated or lightweight tags.
- **Fetch, pull and push**, with credential prompts routed through an askpass
  helper rather than failing outright, and force-pushing offering only
  `--force-with-lease`, never a bare `--force`.
- **An operation log** recording every Git command, its exit code, duration and
  full stderr, with a copy button.
- **Interactive rebase**: reorder, drop, squash and fixup commits from an
  editable plan (no external editor process — see
  [Architecture](ARCHITECTURE.md#design-decisions-worth-knowing)), plus `edit`
  stops that hand off to the existing amend flow; conflicts, `--skip` and
  `--abort` are Continue/Skip/Abort banner controls shared with cherry-pick.
- **Reset, restore and clean**: soft/mixed/hard reset to any commit, unstage
  or discard changes per path, and a preview-before-you-delete untracked-file
  clean.
- **Blame, and file/line history**: per-line attribution (`git blame
  --line-porcelain`), a file's commit history across renames (`--follow`), and
  a specific line range's history (`log -L`).
- **Reflog browser and undo**: every `HEAD` movement, and a one-click "Undo
  last operation" backed by the operation runner's own undo journal rather
  than a reflog guess.
- **Submodules**: status (not-initialized / up-to-date / modified /
  conflicted) read from `.gitmodules` plus `git submodule status`; add, init,
  update, sync and deinit.
- **Bisect**: start with a bad/good range (or neither, marking as you go),
  good/bad/skip stepping with the next candidate and concluding message
  surfaced directly, and reset.
- **Git LFS**: detected rather than assumed; track/untrack patterns, see
  which files are pointers vs. downloaded, and pull/fetch/prune.
- **Patch import/export**: `format-patch` an arbitrary commit selection to a
  folder, `apply` a plain diff to the work tree, and `am` a patch series into
  commits with its own Continue/Skip/Abort recovery — deliberately not the
  shared rebase banner, since `git rebase --continue` refuses outright during
  an `am` session even though the two share an on-disk state directory.
- **Light/dark/system themes**, persisted and switchable from View > Theme.
- **Accessible names** on the repository list, commit history, ref tree,
  changed-files list, diff panes, working-copy lists and the credential
  prompt, so a screen reader has more than a generic control type to
  announce.

See [ROADMAP.md](ROADMAP.md) for what's still ahead.
