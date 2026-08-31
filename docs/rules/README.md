# How to write a rule

Every file next to this one is `@import`ed by [CLAUDE.md](../../CLAUDE.md), so
everything here is auto-loaded into every session. This file is the format;
[CLAUDE.md](../../CLAUDE.md)'s own header is the filing rule that decides what
lands here at all.

The whole point of the split is that **two parallel branches should be able to
add or edit a rule without ever touching the same line**. Everything below
serves that.

## Shape

```markdown
## [FLU-postframe-no-frame] `addPostFrameCallback` does not ask for a frame

- **Rule**: it registers for the end of the *next* frame; if nothing else
  schedules one, it never runs.
- **Consequence**: a drag hides it (the drag itself keeps frames coming); the
  first plain click does not.
- **Do**: pair every deferred notification with
  `SchedulerBinding.instance.ensureVisualUpdate()`.
- **Evidence**: `selection_touch.dart`'s `_scheduleNotify`; ledger: soft-warp
```

- **One rule, one `##` heading.** git's hunk headers follow headings, so a
  conflict message names the rule it is about.
- **One fact, one line.** Never re-wrap a neighbouring bullet to make a line
  fit — that turns a one-fact change into a five-line diff, which is the
  thing that made the old monolith unmergeable.
- **Four fields, in this order.** `Rule` / `Consequence` / `Do` / `Evidence`.
  Drop a field only when it would repeat another one; never add a fifth.
- **`Evidence` is required and points *down*, never sideways.** A rule states
  what to do; the decision record says how it was found out. See "Linking
  down" below for the two link forms.

## Language

**Follow the source, do not translate.** These rules are English prose because
that is what they were written in; Chinese rulings quoted inside them
(「永遠置頂於所屬資料夾內」and the like) stay in Chinese, verbatim, because the
quote is the evidence.

## Pins

A pin is a **semantic slug**, never a running number: `[FLU-postframe-no-frame]`,
not `[FLU-036]`.

Numbers are what a counter hands out, and two parallel branches both take `036`
— that just moves the conflict from the prose into the identifier. A slug comes
from the content, so two branches independently naming the same rule is not a
collision, it is agreement.

| Prefix | File |
|---|---|
| `STRUCT-` | `arch-structure.md` |
| `STATE-` | `arch-state-machine.md` |
| `TEST-` | `arch-testing.md` |
| `GIT-` | `fn-refs-git.md` |
| `FLU-` | `fn-flutter-*.md` |
| `CPP-` | `fn-cpp-core.md` |
| `CI-` | `ops-toolchain-ci.md` |
| `SPEC-` | `ops-spec-reading.md` |
| `UX-` | `ops-ux-rubric.md` |
| `CULT-` | `ops-repo-culture.md` |
| `DRIFT-` | `drift-open.md` |

Rules: lower-case, hyphenated, 2–4 words, names the *claim* and not the
symptom. A pin never changes once written — cross-references are by pin, so
renaming one breaks them silently. Reordering a file is free, precisely
because nothing addresses a rule by position.

## Linking down

Two forms, and which one you use depends on which side of the freeze the
evidence is on:

- **Frozen history** (the 101 rounds in [../ledger.md](../ledger.md)) — plain
  text, `ledger: <section name>`. That file's own preamble says "Grep the
  heading text there"; an anchor slug generated from a Chinese heading is
  fragile and unverifiable, and the plain form is what every existing citation
  in this repo already uses.
- **A new round** — a real relative link,
  `[ledger: <name>](../ledger/<date>-<branch>.md)`. Those filenames are ours,
  so the link can be checked.

## Adding or changing a rule

1. **New rule** → append a `##` block at the end of the matching file. Two
   branches appending to *different* files never conflict; appending to the
   same file conflicts only at the tail, which is one hunk and trivially
   resolved by keeping both.
2. **Editing an existing rule** → change the affected line(s) only. Two
   branches editing different lines of the same rule auto-merge.
3. **A file past ~150 lines** → split it at a natural group boundary and add
   the new file to CLAUDE.md's import list. Prefix stays the same.
4. **Superseded rule** → rewrite it in place and say what was overruled, per
   CLAUDE.md's standing rule about correcting the record. Do not delete a pin
   and mint a new one; something cites it.
