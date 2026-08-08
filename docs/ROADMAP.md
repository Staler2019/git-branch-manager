# Roadmap

| Milestone | Contents |
|---|---|
| **M0 — done** | Build and CI on three platforms, discovery + cache + Refresh, streaming graph, diffs, branch switching, operation log |
| **M1 — done** | Working copy: status with fsmonitor, stage/unstage by file, hunk and line, commit and amend, branch create/rename/delete |
| **M2 — done** | Merge (ff / no-ff / squash), cherry-pick single, multi and range with preview, conflict resolution across all three index stages, side-by-side diff |
| **M3 — done** | Worktree manager, stash, tags, fetch/pull/push with askpass helpers and `--force-with-lease` by default, signed installers |
| **M4 — done** | Interactive rebase, reset/restore/clean, blame, file and line history, reflog browser and undo |
| **M5 — done** | Submodules, bisect, LFS, patch import/export, themes, accessibility |
| **M6 — planned** | Conflict UX: state banner actually shows text and instructions ([#20](https://github.com/Staler2019/git-branch-manager/issues/20)), auto-shown three-pane conflict resolver ([#21](https://github.com/Staler2019/git-branch-manager/issues/21)) |
| **M7 — planned** | Branch sync hygiene: surface and bulk-clean local branches whose upstream was deleted ([#22](https://github.com/Staler2019/git-branch-manager/issues/22)) |
| **M8 — planned** | Stability: Windows repo-switch deadlock instrumentation ([#23](https://github.com/Staler2019/git-branch-manager/issues/23)), busy-spinner leak on graph view ([#24](https://github.com/Staler2019/git-branch-manager/issues/24)) |
| **M9 — planned** | Diff workspace: commit body in the expanded row ([#25](https://github.com/Staler2019/git-branch-manager/issues/25)), simultaneous three-pane working-copy diff with line discard ([#26](https://github.com/Staler2019/git-branch-manager/issues/26)), dual-status file drag/drop ([#27](https://github.com/Staler2019/git-branch-manager/issues/27)) |

See [FEATURES.md](FEATURES.md) for what each milestone shipped in detail. M6–M9 issues each carry their own reversible commit sequence, TDD plan, and verification steps in their GitHub issue body.
