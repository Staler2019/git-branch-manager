# Engineering ledger — how to add a round

One round, one file. **Nothing in here is auto-loaded**, so length is free —
this is where the narrative, the measurements, the rejected hypotheses and the
counter-examples go.

## Filename

```
docs/ledger/<YYYY-MM-DD>-<branch>.md
             ^^^^^^^^^^  ^^^^^^^^
             date first  branch name after
```

`2026-08-31-fix-origin-head-is-not-a-branch.md`.

**The date leads because branch names are too arbitrary to find a round by.**
Sorted by filename the directory is chronological, which is the order rounds
are actually read in. The branch name stays because it is what a source comment
or a rule's `Evidence` field cites.

One file per round is the whole conflict fix: two parallel rounds create two
different files and never meet. The old scheme had every round append to the
end of one 5,900-line file, which is a guaranteed conflict — and it happened,
recorded in [../ledger.md](../ledger.md) under "Sidebar continuation":

> The only conflict was `docs/ledger.md`, and it was structural rather than
> semantic: both branches append a new section at the end, so git saw one
> region replaced two ways.

## Shape

Same shape the frozen sections use — what changed, which premises did not
survive the source, what was found by *running* rather than reading, what was
deliberately reduced or left open. Use `##` for the round's own sections; the
`#` title is the round.

## Then two more things

1. **Add one line to [INDEX.md](INDEX.md)**, newest last. That file is
   `merge=union` in `.gitattributes`, so two parallel appends merge
   automatically instead of conflicting.
2. **Distil into [../rules/](../rules/)** — only what a future session must
   know *before* it starts, in the four-field shape
   [../rules/README.md](../rules/README.md) specifies, with `Evidence`
   pointing back at your file here. A round with nothing worth distilling is
   a real outcome; do not invent a rule to have one.

## The 101 rounds before this scheme

They are frozen in [../ledger.md](../ledger.md), in place and byte-identical,
and they are not being migrated. Two reasons, both from that file's own
preamble: it is a record you can checksum, and its sections cross-reference
each other with "above"/"below", which only resolve while the order is intact.
History is never appended to again, so it cannot conflict. Cite it as
`ledger: <section name>` and grep the heading text.
