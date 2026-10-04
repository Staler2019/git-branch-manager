---
paths:
  - "app_flutter/lib/data/repositories/repo_session_repository.dart"
  - "app_flutter/**/*prune*"
---

# Refs, branches and remote counterparts

Pin prefix `REF-`. Format: [README.md](../../docs/rules/README.md). The rest of this
category is pinned by tests and site comments; the sidebar HEAD ruling is in
[record: sidebar HEAD has no privilege](../../docs/records/2026-10-04-sidebar-head-has-no-privilege.md).

## [REF-fetch-auto-prunes] A successful `fetch` prunes the unclaimed gone refs in the background, and no branch context menu says 「prune」

- **Rule**: user-ratified, do not "fix" it back. P02-12's mark → badge → explicit-Prune stages are superseded: after a fetch, exactly the refs `git remote prune --dry-run` calls gone **and** that no local branch claims are pruned; a claimed one keeps its cloud-off marking (the user can repush) and is pruned once the claim goes (`DeferredPruneNotifier`). `Remote → Prune remote branches` stays as the manual fallback; worktrees follow the same ruling (a lock plays the claim); `AppPreferences` has no `autoFetchPrune` switch.
- **Do**: only a *fetch-triggered* preview may auto-prune (`_autoPrunePreviewsInFlight`), and never for a remote the Prune dialog is listing (`PruneAudience.holdsRemote`); an automatic prune's failure stays out of `lastError` but is still recorded in the operation log.
- **Evidence**: `repo_session_auto_prune_test.dart`; `DeferredPruneNotifier`'s doc (`deferred_prune_repository.dart`); [ledger: 刪掉本機分支後殘留的 remote-tracking ref](../../docs/ledger/2026-09-26-fix-stale-remote-ref-after-local-delete.md); ledger: prune 壞掉的表象下有六個缺陷
