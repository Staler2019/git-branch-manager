---
name: round-close
description: Close a round of work in this repo (quality gate G4) — write its ledger file and INDEX line, distil rules and records, correct whatever the round proved wrong, and run the doc checks.
disable-model-invocation: true
---

# Closing a round (G4)

Filing rules: [CLAUDE.md](../../../CLAUDE.md)'s "Where a round's write-up goes",
[docs/ledger/README.md](../../../docs/ledger/README.md),
[docs/rules/README.md](../../../docs/rules/README.md) and
[docs/records/README.md](../../../docs/records/README.md). This file is the order of work; those
files win on format.

## 1. Collect what the round actually did

`git log --format='%h %s' origin/main..HEAD` and the conversation. Note the mutation numbers from
the commit messages, every measurement, every ruling (quote it verbatim), everything that went red
and how it was resolved, and anything not run.

## 2. Write the ledger file

`docs/ledger/<YYYY-MM-DD>-<branch>.md`, with `/` in the branch written as `-`, in STAR:
`## Situation`, `## Task`, `## Action`, `## Result`. The `#` title is the round.

- A rejected hypothesis or a mistake stays in, with what disproved it.
- A check that was not run is said to be not run, with the reason.
- A scope reduction names who decided it. Without the user's decision it is not a reduction, it is
  unfinished work: finish it or say what blocks it.
- Never paste from `~/.claude` transcripts. Secret values never appear; a password becomes `••••`.

## 3. Add the INDEX line

Append one line to `docs/ledger/INDEX.md`, newest last:

```
- <YYYY-MM-DD> — [<branch>](<file>.md) — <what changed and what it was caused by>
```

## 4. Distil, only if a future session needs it before it starts

| The fact is | It goes to |
|---|---|
| enforceable by a test, type or CI check | that test, type or check, not prose |
| a subtree's current constraint the code cannot show | `.claude/rules/` |
| needed before any file is opened | `docs/rules/` |
| a ruling someone might "fix back", a bug worth remembering, how a structure came to be | `docs/records/` |
| only meaningful as "what happened in this round" | the ledger, already done |

A round with nothing to distil is a real outcome; do not invent a rule. An existing rule that
covers it gets its lines edited, not a second rule. New or migrated entries go through
`memory-steward`, and its table is applied after the user's ruling.

`Evidence` links down to the new ledger file: `../ledger/<file>.md` from `docs/rules/`,
`../../docs/ledger/<file>.md` from `.claude/rules/`.

## 5. Correct what the round proved wrong

Grep rules, records and source comments for every claim the round contradicted. Correct it where it
stands: `~~old text~~` followed by the new text. Never silently rewrite, and never delete a pin.

## 6. Run the checks

From the repo root; each exits non-zero on a finding.

```
python3 scripts/check-rule-pins.py
python3 scripts/check-instruction-budget.py
```

If L0 moved, change `L0 ceiling` in `CLAUDE.md` in the same commit: more than 2,000 characters under
it is as red as over it.

## 7. Commit and report

Stage each file by name, then commit with the `git-commit-message` skill. Do not push unless the
user has asked for it.

List issues to open or close and ask; both need the user's consent. Report what was filed, what was
corrected, what was deliberately not distilled, and what is still unrun.
