# CLAUDE.md

Root-level guide for Claude Code (and other AI assistants) working in this
repo. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and
[docs/FEATURES.md](docs/FEATURES.md) first — this file adds the Flutter UI's
structure, its session state machine, the UX acceptance bar `app_flutter/`
changes are held to, and the invariants and traps that keep being rediscovered.

**This file is an umbrella.** The rules themselves live in one file per
category under [docs/rules/](docs/rules/) and are pulled in by the `@` imports
below, so everything is still auto-loaded into every session — what changed is
that two parallel branches now edit two different files instead of two regions
of one 1,742-line one.

## Three layers, and what belongs in each

```
CLAUDE.md                        this file — filing rules + imports. No rule text.
  └─ docs/rules/<category>.md    the rules. Short, pinned, four fields each.
       └─ docs/ledger/<date>-<branch>.md   the decision record. Length is free.
```

| Layer | Holds | Auto-loaded | Conflict shape |
|---|---|---|---|
| `CLAUDE.md` | filing rules, imports, redirects | yes | rarely edited |
| `docs/rules/*.md` | current-state facts + distilled invariants | yes (via `@`) | different categories → different files |
| `docs/ledger/*.md` | one round's narrative and evidence | no | one round → one new file |

## Where a round's write-up goes

When you finish a round of work:

1. **The narrative goes to its own file** —
   `docs/ledger/<YYYY-MM-DD>-<branch>.md`, plus one line appended to
   [docs/ledger/INDEX.md](docs/ledger/INDEX.md). Date first, because branch
   names are too arbitrary to find a round by. Shape and rationale:
   [docs/ledger/README.md](docs/ledger/README.md). Length is free there.
2. **Only what a future session must know *before* it starts is distilled into
   [docs/rules/](docs/rules/)** — as a `## [PIN] Title` block with
   `Rule` / `Consequence` / `Do` / `Evidence`, `Evidence` pointing back at the
   round's file. Short and precise; the long form stays in the ledger. Format:
   [docs/rules/README.md](docs/rules/README.md). If an existing rule already
   covers it, edit that rule's lines rather than adding a second one.
3. **Current-state facts are rules too** — a route, a field, a state
   transition, a CI constraint, a still-open drift, all under
   `docs/rules/`. History is not: if the sentence only makes sense as "what
   happened in round N", it is ledger material.

**Do not put rule text back into this file, and do not append a round-shaped
section anywhere.** Both are what broke the previous two schemes: this file
reached ~176KB before the ledger was split out of it, and the ledger then
reached 5,900 lines with every round appending to the same end-of-file.

## Rules

@docs/rules/README.md
@docs/rules/arch-structure.md
@docs/rules/arch-state-machine.md
@docs/rules/arch-actions.md
@docs/rules/arch-testing.md
@docs/rules/arch-testing-device.md
@docs/rules/fn-refs-branches.md
@docs/rules/fn-git-commands.md
@docs/rules/fn-flutter-state.md
@docs/rules/fn-flutter-layout.md
@docs/rules/fn-flutter-input.md
@docs/rules/ops-ux-rubric.md
@docs/rules/ops-spec-reading.md
@docs/rules/ops-repo-culture.md
@docs/rules/ops-toolchain-ci.md
@docs/rules/fn-cpp-core.md
@docs/rules/drift-open.md

## Invariants and traps

Distilled from [docs/ledger.md](docs/ledger.md) — every entry here happened,
and the round that found it is named so the original measurement, the
counter-example and the issue number stay one grep away. Organised by what
you are touching, not by when it was learned.

## Engineering ledger

[docs/ledger.md](docs/ledger.md) holds every round's narrative, moved here
verbatim (the moved block is byte-identical; nothing was reworded, dropped, or
summarised away). Filing rule for a new round: see the top of this file.

**Everything a source comment cites as "CLAUDE.md's Tier 0c note",
"Known gaps", "Tier 6c", "Spec conformance audit" or any other `Tier N` /
round heading is in `docs/ledger.md` now**, under the same heading text. The
comments were left alone rather than rewritten across ~30 files; this
paragraph is the redirect.
