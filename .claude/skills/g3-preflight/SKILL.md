---
name: g3-preflight
description: Run this repo's pre-push checklist (quality gate G3) against the current branch — the full test tiers its diff touches, candidate device tests, orphan wiring, hover and affordance sweep, per-commit checks — and report each result with its evidence.
disable-model-invocation: true
---

# Before pushing (G3)

Every step ends as **pass**, **red** (with output) or **skipped** (with the reason). A red is not
waved through as unrelated without having been reproduced on the parent commit. Long commands run
in the background.

## 1. Read the diff

```
git diff --stat origin/main...HEAD
git diff origin/main...HEAD
git log --format='%h %s' origin/main..HEAD
```

Note which of `src/`, `app_flutter/`, `scripts/` and `.github/` it touches, every string, key,
`GbmActionId` and `GbmPanelKind` it adds, changes or removes, and every widget it touches.

## 2. Run the tiers

| The diff touches | Run |
|---|---|
| `src/` | `scripts/format-check.sh`, `cmake --workflow --preset core-only`, `cmake --workflow --preset capi-only` |
| `app_flutter/` | from `app_flutter/`: `flutter analyze`, `flutter test`, `dart format --output=none --set-exit-if-changed <each touched .dart file>` |
| `scripts/` | `python3 scripts/test_*.py` for each test beside a touched script |
| `docs/rules/`, `.claude/rules/`, `CLAUDE.md` | `python3 scripts/check-rule-pins.py`, `python3 scripts/check-instruction-budget.py` |

Check the Flutter version against the pin first ([CI-dart-sdk-floor]) and never run a formatter over
the whole tree on a version that differs from CI's ([CI-formatter-version-drift]). A diff with no
code in it skips the suites, and the report says so.

## 3. Run the affected device tests

CI does not run this tier ([TEST-device-tier-not-in-ci]), so a green PR says nothing about it.

Find candidates by grepping `app_flutter/integration_test/` for each item from step 1, **including
the `GbmActionId` that opens the surface and its `GbmPanelKind`**: label greps miss tests that enter
through an action id ([TEST-grep-misses-intent-driven-device-tests]). A touched shared row widget,
or a removed or replaced affordance, means every device file.

```
cd app_flutter && flutter test integration_test/<file> -d macos
```

One file at a time, and leave `lib/` alone during the run ([TEST-device-runs-one-file]). `Failed to
foreground app` also prints on green runs: read for the `+N:` lines, not the last line. A hang is
handled by [TEST-stale-process-blocks-tier] before it is called a test failure.

Run a candidate rather than argue it is unaffected. No candidates is a finding to state, with the
greps that produced none.

## 4. Check orphan wiring

Dispatch the read-only `wiring-auditor` agent with the diff's changed paths and symbols, per
[CULT-orphan-wiring]. Its table is evidence; wire versus delete is decided here, and a choice that
is the user's goes to the user.

## 5. Sweep hover and affordance over touched widgets

For each widget the diff touches:

- Every clickable control has the hover state, cursor and tooltip its neighbours have.
- Every label ending in `…` names the route it pushes, and a control with none is a finding
  ([UX-ellipsis-promises-a-dialog]).
- Every disabled state reads through `isActionEnabled` ([ACT-availability]).
- Every new action goes through the shared handler map ([ACT-one-handler-map]).

## 6. Check per commit, if fixtures moved

If `git log --name-only origin/main..HEAD` shows fixtures changing across commits, test each commit
in its own `git worktree`; the tip being green does not show that each commit is.

## 7. Report

| Step | Result | Evidence |
|---|---|---|

Record any device test that ran and what it covered in the ledger, then stop. Pushing needs the
user's request. After a PR is open, watch CI to green and report any red with its output.
