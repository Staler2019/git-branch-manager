# Records — rulings and bugs, read on demand

One record, one file. **Nothing in here is auto-loaded**: a session looks a record up when
the code in front of it raises the question, not before. The code and the user's current
judgment win over anything written here — a record says what was true when it was written.

Round narratives stay in [../ledger/](../ledger/); this directory holds the two kinds of
fact a round produces that outlive it.

| Kind | What | Example |
|---|---|---|
| `ruling` | a user decision someone might later "fix back" — a spec deviation, a rejected alternative | the sidebar does not pin the current branch |
| `bug` | a defect worth remembering: symptom, root cause, the test that now pins it | partial `git branch -d` left the sidebar stale |

## Filename

```
docs/records/<YYYY-MM-DD>-<slug>.md
```

Date first, as in the ledger, so the directory sorts chronologically.

## Shape — STAR

```markdown
# <one-line claim>

- **Kind**: ruling | bug · **Pins**: <pin or id, if any> · **Code**: <path:symbol>

## Situation
What was true, observed, or reported. Facts and numbers only.

## Task
What had to be decided or fixed, and the constraint that made it non-trivial.

## Action
What was done or ruled, and the alternatives rejected, with why.

## Result
Outcome with evidence — test names, measured numbers, commits. What remains open.
```

## Keeping a ruling from being undone

A ruling is defended by the code, not by this file: a test that pins the behaviour, and a
one-line comment at the code site pointing here (`// ruling: docs/records/<file>`). The
record explains *why*; the test is what stops a regression.

## Correcting a record

Never rewrite one silently. Strike the wrong sentence where it stands and write the
correction beside it.
