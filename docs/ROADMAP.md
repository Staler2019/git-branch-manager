# Roadmap

| Milestone | Contents |
|---|---|
| **M0 — done** | Build and CI on three platforms, discovery + cache + Refresh, streaming graph, diffs, branch switching, operation log |
| **M1 — done** | Working copy: status with fsmonitor, stage/unstage by file, hunk and line, commit and amend, branch create/rename/delete |
| **M2 — done** | Merge (ff / no-ff / squash), cherry-pick single, multi and range with preview, conflict resolution across all three index stages, side-by-side diff |
| **M3 — done** | Worktree manager, stash, tags, fetch/pull/push with askpass helpers and `--force-with-lease` by default, signed installers |
| **M4 — done** | Interactive rebase, reset/restore/clean, blame, file and line history, reflog browser and undo |
| **M5 — done** | Submodules, bisect, LFS, patch import/export, themes, accessibility |
| **M6 — done** | Conflict UX: state banner shows text, instructions and a Resolve Conflicts entry point; a standalone, modal, resizable conflict window with a file list (resolved-file memory that survives a restart), drag/click direct-manipulation resolution across three or four panes, a working pane splitter that actually resizes, line-ending/encoding mismatch warnings, and the conflict's prepared commit message pre-filled once everything's resolved |
| **M7 — done** | Branch sync hygiene: local branches whose upstream was deleted carry a `gone` badge and a tooltip naming it, and the sidebar can select all of them in one go ([#22](https://github.com/Staler2019/git-branch-manager/issues/22)) — deliberately selects rather than bulk-deletes; the user still deletes through the existing multi-select Delete |
| **M8 — planned** | Stability: Windows repo-switch deadlock instrumentation ([#23](https://github.com/Staler2019/git-branch-manager/issues/23)), busy-spinner leak on graph view ([#24](https://github.com/Staler2019/git-branch-manager/issues/24)) |
| **M9 — planned** | Diff workspace: commit body in the expanded row ([#25](https://github.com/Staler2019/git-branch-manager/issues/25)), simultaneous three-pane working-copy diff with line discard ([#26](https://github.com/Staler2019/git-branch-manager/issues/26)), dual-status file drag/drop ([#27](https://github.com/Staler2019/git-branch-manager/issues/27)) |

See [FEATURES.md](FEATURES.md) for what each milestone shipped in detail. M6–M9 issues each carry their own reversible commit sequence, TDD plan, and verification steps in their GitHub issue body.
