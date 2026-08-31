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
| `ACT-` | `arch-actions.md` |
| `TEST-` | `arch-testing.md`, `arch-testing-device.md` |
| `REF-` | `fn-refs-branches.md` |
| `GIT-` | `fn-git-commands.md` |
| `FLU-` | `fn-flutter-state.md`, `fn-flutter-layout.md`, `fn-flutter-input.md` |
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
3. **Split a file when it holds two groups that different rounds edit**, not
   when it passes a line count. Length is a bad proxy: what causes a conflict
   is two branches editing the same *region*, and a file of independent `##`
   rules merges cleanly however long it is. Add the new file to CLAUDE.md's
   import list; the prefix may stay the same (`TEST-` and `FLU-` each span
   more than one file already).

   The largest files today, and why each is one file:
   `arch-structure.md` (245) and `arch-state-machine.md` (205) are mostly
   route trees and field tables — reference material, edited a row at a time;
   `arch-testing.md` (210) is dominated by one table with the same property.
   `ops-spec-reading.md` (167) and `ops-repo-culture.md` (153) are prose but
   have no second group to split at. If one of these does grow a second
   group, split it then.
4. **Superseded rule** → rewrite it in place and say what was overruled, per
   CLAUDE.md's standing rule about correcting the record. Do not delete a pin
   and mint a new one; something cites it.

## Checking your work

Two scripts, both run from the repo root, both exit non-zero on a finding:

- `scripts/check-rule-pins.py` — every `[PIN]` reference resolves to a real
  `## [PIN]` heading, and no pin is defined twice. Run it after adding or
  renaming a rule. It fences out fenced blocks and code spans, because the
  example above and the `[FLU-036]` counter-example are neither definitions
  nor references.
- `scripts/check-doc-migration-loss.py` — for the *next* round that shortens
  prose (the 101 frozen ledger rounds are the obvious candidate). Given the
  old text's `<ref:path>` and section heading, it asserts every code span,
  filename, version and issue number still appears somewhere in the new files
  or `docs/ledger.md`. Zero hits on a fact means the fact was lost, not that
  it was redundant.
