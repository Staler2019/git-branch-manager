# CLAUDE.md

Root-level guide for Claude Code (and other AI assistants) working in this
repo. Read [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) and
[docs/FEATURES.md](docs/FEATURES.md) first — this file adds the Flutter UI's
structure, its session state machine, the UX acceptance bar `app_flutter/`
changes are held to, and the invariants and traps that keep being rediscovered.

**This file is an umbrella.** The rules themselves live in one file per
category, in one of two places: [docs/rules/](docs/rules/) for rules every
session needs, pulled in by the `@` imports below, and
[.claude/rules/](.claude/rules/) for rules that matter only to part of the
tree, which Claude Code loads by their `paths:` frontmatter when a matching
file is read or edited. Two parallel branches still edit two different files
instead of two regions of one 1,742-line one.

## Layering

```
src/core/   headless C++20, no Qt/Dart (docs/ARCHITECTURE.md)
  -> src/capi/                        gbm_capi.h, extern "C", JSON/event bridge
  -> app_flutter/lib/data/ffi/        gbm_bindings.dart (dart:ffi)
  -> app_flutter/lib/data/repositories/  Riverpod state (RepoSessionState, ...)
  -> app_flutter/lib/features/**      views
```

Routes are `app_flutter/lib/routing/route_paths.dart`; the feature directories are
`app_flutter/lib/features/`. Neither is restated here — the code is the list.

## Memory filing

Startup-loaded text is capped by Claude Code at 150k characters, `~/.claude` included, so
this repo gets a share of it and `scripts/check-instruction-budget.py` holds it there in CI.

- **L0 ceiling**: 61,591 characters — ratchet; lower it whenever L0 shrinks. Target 30,000.
- **L0** (loaded at start): project settings that change only when the architecture does.
- **L1** (`.claude/rules/`, `paths:`): a subtree's current constraints the code cannot show.
- **L2** (never loaded, searched on demand): rulings and bugs in [docs/records/](docs/records/),
  round narratives in [docs/ledger/](docs/ledger/), both written as STAR.
- Code and the user's current judgment win over any record. A trap that a test, type or CI
  check can enforce is encoded there instead of written down.
- New or migrated entries are classified by the `memory-steward` agent, read-only; the main
  session applies its table after the user's ruling.

## Three layers, and what belongs in each

```
CLAUDE.md                        this file — filing rules + imports. No rule text.
  ├─ docs/rules/<category>.md    the rules every session needs. Short, pinned, four fields each.
  ├─ .claude/rules/<category>.md the rules one part of the tree needs. Same shape, plus `paths:`.
  └─ docs/ledger/<date>-<branch>.md   the decision record. Length is free.
```

| Layer | Holds | Auto-loaded | Conflict shape |
|---|---|---|---|
| `CLAUDE.md` | filing rules, imports, redirects | yes | rarely edited |
| `docs/rules/*.md` | current-state facts + distilled invariants | yes (via `@`) | different categories → different files |
| `.claude/rules/*.md` | the same, scoped to a subtree | when a file matching `paths:` is read or edited | same as above |
| `docs/ledger/*.md` | one round's narrative and evidence | no | one round → one new file |

## Where a round's write-up goes

When you finish a round of work:

1. **The narrative goes to its own file** —
   `docs/ledger/<YYYY-MM-DD>-<branch>.md`, plus one line appended to
   [docs/ledger/INDEX.md](docs/ledger/INDEX.md). Date first, because branch
   names are too arbitrary to find a round by. Shape and rationale:
   [docs/ledger/README.md](docs/ledger/README.md). Length is free there.
2. **Only what a future session must know *before* it starts is distilled into
   [docs/rules/](docs/rules/) or [.claude/rules/](.claude/rules/)** — as a `## [PIN] Title` block with
   `Rule` / `Consequence` / `Do` / `Evidence`, `Evidence` pointing back at the
   round's file. Short and precise; the long form stays in the ledger. Format:
   [docs/rules/README.md](docs/rules/README.md). If an existing rule already
   covers it, edit that rule's lines rather than adding a second one.
3. **Current-state facts are rules too** — a route, a field, a state
   transition, a CI constraint, a still-open drift, all under
   `docs/rules/` or `.claude/rules/`. History is not: if the sentence only makes sense as "what
   happened in round N", it is ledger material.

**Do not put rule text back into this file, and do not append a round-shaped
section anywhere.** Both are what broke the previous two schemes: this file
reached ~176KB before the ledger was split out of it, and the ledger then
reached 5,900 lines with every round appending to the same end-of-file.

## Rules

Which file a category lives in is a context-cost decision, recorded in
[docs/rules/README.md](docs/rules/README.md)'s prefix table: the eleven
path-scoped ones under `.claude/rules/` are loaded only when their subtree is
touched, the rest are imported here.

@docs/rules/README.md
@docs/rules/arch-state-machine.md
@docs/rules/arch-actions.md
@docs/rules/ops-ux-rubric.md
@docs/rules/ops-repo-culture.md

## Where the rules went, and why a source comment still says "CLAUDE.md"

The `## Invariants and traps` section that used to fill most of this file is
gone as a *section*; every entry in it is now a pinned rule under
[docs/rules/](docs/rules/) or [.claude/rules/](.claude/rules/). **Nothing was dropped** — each
category's move was checked by re-finding every concrete fact (code span,
filename, version, issue number, measured figure) from the old text in either
the new rules file or the ledger.

**A source comment that cites "CLAUDE.md" is still correct.** Roughly 49
comments across `app_flutter/` and `src/` say things like "CLAUDE.md records
X" or "CLAUDE.md's rule for a new state-dependent gate"; none cites a line
number, and CLAUDE.md remains the auto-loaded rule set — the text simply
arrives through `@import` or a path-scoped rule now. The comments were left
alone rather than rewritten across ~30 files; this paragraph is the redirect.
Grep `docs/rules/` and `.claude/rules/` for the rule, or search its pin.

## Engineering ledger

[docs/ledger.md](docs/ledger.md) holds the first 101 rounds' narratives, moved
there verbatim (the moved block is byte-identical; nothing was reworded,
dropped, or summarised away). **It is closed to new rounds** — one round is one
file under [docs/ledger/](docs/ledger/) now, indexed by
[docs/ledger/INDEX.md](docs/ledger/INDEX.md), because a single shared
end-of-file was a guaranteed conflict for any two parallel branches. Filing
rule: see "Where a round's write-up goes" above and
[docs/ledger/README.md](docs/ledger/README.md).

**Everything a source comment cites as "CLAUDE.md's Tier 0c note",
"Known gaps", "Tier 6c", "Spec conformance audit" or any other `Tier N` /
round heading is in `docs/ledger.md`**, under the same heading text.
