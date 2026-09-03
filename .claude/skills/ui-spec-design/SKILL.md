---
name: ui-spec-design
description: Produce or revise a UI design spec for this repo — a viewable HTML demo under docs/claude-design-demo/ drawn from the bundled Flutter Desktop Spec. Use whenever a dialog, panel, or screen is being redesigned, when the user asks for a design/spec before implementation, or when a visual change needs a spec to be held against. Encodes the mandatory extraction and audit passes that must pass BEFORE the user is shown anything.
---

# Designing to this repo's spec

## The one failure mode this skill exists to stop

Every visual defect in the round that produced this skill had the **same cause**: a
number was *chosen* instead of *quoted*. Six consecutive corrections, all mine, none
of which needed the user's taste to catch — only their eyes, doing work I should have
done:

| # | What was drawn | What the spec said | Why it happened |
|---|---|---|---|
| 1 | a Markdown doc | the spec is a **viewable HTML demo** | assumed the format |
| 2 | fields 40px, radius 4px | `.gbm-input` **30px**, `--radius-md` **6**, `--radius-lg` **10** | never opened the component CSS |
| 3 | title as padded text | a `.mkbar` — own ground + `border-bottom` | never opened P17's markup |
| 4 | warning as a rounded amber card | `warn` field = sunken + **2px `--warning` left rail** | invented, then "fixed" to the wrong component (`.gbm-banner-warning` is a *screen* banner) |
| 5 | title 15px, frame untouched | P6 mock: **13px**, `padding:12px 15px` | split the difference between prose and mock — a third value neither states |
| 6 | `--surface-sunken` referenced | defined in **none** of the three palettes | never audited; five backgrounds silently transparent |

In **every** case the Flutter widget was already conformant. The app followed the
spec; the drawing did not. So:

> **Never draw a value you have not read. If you cannot cite it, it goes in the
> Inferred list — it does not get quietly chosen.**

This is not a preference to weigh against speed. Treat a self-chosen pixel value the
same way you treat a fabricated citation.

## Where the spec is, and how to read it

`docs/claude-design-demo/Flutter Desktop Spec (standalone).html` — 941 KB, a bundled
claude.ai artifact. It is **not** hand-written HTML: the readable parts are JS string
literals with escaped newlines. Unescape before searching, or you will miss everything:

```python
s = open("docs/claude-design-demo/Flutter Desktop Spec (standalone).html",
         encoding="utf-8", errors="replace").read()
s = s.replace('\\n','\n').replace('\\"','"').replace("\\'","'").replace('\\u002F','/')
```

Beware: the file also holds base64 blobs. A bare `grep isP6` hits one. Search for the
template form — `{{ isP6 }}`, `{{ isP17 }}` — not the bare identifier.

### The four sources, in precedence order

1. **`.gbm-*` component CSS** — the UI kit. Its own comment says *"Token-driven; safe to
   reuse directly in UI kit screens."* This is implementation-grade and the app already
   follows it. Extract with:
   `re.findall(r'\.(gbm-[a-z0-9-]+)\s*\{', s)` then print each block.
2. **P6's full-size dialog mock** — the only dialog drawn at real size. Its inline styles
   are the shell geometry.
3. **`dlgFields()` / `dlgGroup()` in `spec_logic.js`** — the field vocabulary all 26
   spec'd dialogs are drawn from: kinds `text` / `focus` / `ro` / `list` / `chk` /
   `chk-on` / `radio` / `radio-on` / `note` / `warn`, plus `mono`, `label`, `hint`.
   Find it by searching `dlgFields(f) {`. **This is the highest-value block in the file
   and the easiest to miss.**
4. **Prose** — P6's shared-shell sentence, P17's 260820 paragraph.

**When prose and mock disagree, they are a question for the user, not a gap to split.**
P6 says 18px title / 16px padding; its own mock draws 13px / 14px. Splitting the
difference produced a third value neither states. Ask, then take the chosen source
**whole** — a geometry half from each is incoherent.

`docs/rules/ops-spec-reading.md`'s `[SPEC-mockup-is-not-prose]` governs *conformance
verdicts*. It does not license inventing a value when the user has ruled for the mock.

### Facts already extracted (verify, do not re-derive blindly)

```
--radius-sm 4   --radius-md 6   --radius-lg 10   --radius-full 999
--text-xs 11   --text-sm 12.5   --text-base 13.5   --text-md 15   --text-lg 18
--row-h-compact 26   --row-h-comfortable 34
--shadow-sm/md/lg   --space-1..16 (4,8,12,16,20,24,32,40,48,64)

.gbm-btn      h30 r6 text-sm w500 pad 0/12      .gbm-btn-sm  h24 text-xs pad 0/8
.gbm-input    h30 r6 text-sm pad 0/12           .gbm-row     h26 r4 pad 0/12
.gbm-checkbox 15x15 r3 1.5px --border-strong    .gbm-panel-raised  r10 --shadow-md
.gbm-banner   align center, gap --space-3, pad --space-2/--space-4, border-bottom
              -warning = --diff-del-bg / --diff-del-text   (a SCREEN banner)
.mkbar        h28, pad 0/10, --surface-panel-raised, border-bottom --border-subtle
.mklbl        10px, uppercase, ls .06em, --text-tertiary   (a PANE header)
.kbd          mono 10.5px, --surface-sunken, 1px --border-default, r4

P6 full-size dialog, verbatim:
  shell   .gbm-panel-raised + border:1px solid --border-default + overflow:hidden
  title   padding:12px 15px; border-bottom:1px solid --border-subtle;
          font-size:13px; font-weight:600
  body    padding:14px 15px; display:flex; flex-direction:column; gap:11px
  actions padding:11px 15px; border-top:1px solid --border-subtle;
          justify-content:flex-end; gap:7px      -- BOTH buttons .gbm-btn-sm

dialog warn field (dlgFields, NOT .gbm-banner):
  --surface-sunken + 1px --border-subtle + border-left:2px --warning
  + --radius-md + padding 8px 9px
radio mark: circle; off 1.5px --border-strong; ON = thick --accent RING, not a dot
```

**Two pairs that look alike and are not.** `.gbm-banner-warning` is a screen-level
strip; a dialog's warning is the `warn` *field*. `.mklbl` is a pane header (uppercase);
a dialog field label is P6's 11px `--text-secondary` sentence case. Conflating either
pair has already shipped once each.

### Language is per element, not per app

Counted from `DLGS` (26 dialogs): titles **26 English / 0 Chinese**; primary buttons
**26 / 0**; field labels **3 / 47** (the 3 are `URL`, `Remote`×2); options **40 / 81**
(the 40 are data — refs, paths, hashes); hints **0 / 13**. Git vocabulary stays English
inline (「先 stash，切完不自動還原」). 使用者裁定 2026-09-04: dialogs follow this.

## Output

An HTML file in `docs/claude-design-demo/`, published with the Artifact tool so the user
can see it. **Never a Markdown doc** — the repo's spec is viewable, and
`[SPEC-demo-dom-is-the-spec]` says the DOM is its readable half.

- **Class names are the Flutter widgets** (`.gbm-dialog-shell`, `.gbm-ref-picker`,
  `.gbm-row`). A reader maps DOM → widget with no legend; this is how `.variant-B-card`
  is still cited in `scoped_diff_view.dart`.
- **Cite the source inline** on each declaration: `[KIT]`, `[P6]`, `[P17]`.
- Namespace mockup tokens (`--gbm-*`) away from page-chrome tokens (`--pg-*`), and define
  the mockup tokens on **one** ancestor only — a descendant redeclaring them overrides
  what it inherits from the themed stage and pins every specimen to one palette.
- Offer all three palettes (`neutral-professional`, `dark-technical`, `light-ide`) as a
  live toggle. The tokens are the contract; one screenshot is not.

## Mandatory audits — run ALL of these before showing the user

These are mechanical. Every one of them caught a real defect in the round that produced
this skill. Not running them is the failure this skill exists to prevent.

1. **Unsourced-value audit.** Every pixel/colour/weight in the specimen CSS has an inline
   `[KIT]`/`[P6]`/`[P17]` citation, or appears in the Inferred list. **Zero uncited
   values.** This is a gate, not a score.
2. **Token coverage.** Parse the CSS; compare `var(--gbm-*)` used against those defined
   in *each* palette block. Assert: none used-but-undefined, none defined-in-base-but-
   missing-from-a-theme, none dead. Locate the token block by *content* (`--gbm-` inside
   it), not by selector name — two rules can share a selector.
3. **Contrast.** Compute WCAG ratios for title / label / hint / field / warning / button
   in all three palettes. Anything under 4.5 gets **reported, not silently fixed** — if it
   comes from `tokens-reference.md` it is a spec issue and changing it here desyncs the
   page from its source.
4. **Well-formedness.** `html.parser` over the file; assert zero mismatched and zero
   unclosed tags.
5. **Implementation cross-check.** For every geometry claim, open the Flutter widget and
   record what it already does. In this round the app was conformant **six times out of
   six** — so a mismatch is far more likely to be the drawing than the code. Report both
   columns; never assume the app is wrong.
6. **Component confusion check.** For each component drawn, name the spec class and
   confirm no sibling class covers a *different* context (banner vs warn field, `.mklbl`
   vs field label).

## Quality bar before handing over

Score honestly. **Gate = every mandatory audit passes AND ≥ 90/100.** Below that, fix
first — the user's attention is for design judgement, not for catching arithmetic.

| Dimension | Pts | What earns it |
|---|---|---|
| Spec fidelity | 35 | every value cited; prose/mock conflicts surfaced not split |
| Audits clean | 25 | all six above pass, evidenced by output not assertion |
| Declared uncertainty | 15 | an explicit Inferred list; nothing quietly chosen |
| Decisions surfaced | 10 | every point needing a ruling is called out, with evidence both ways |
| Scope honesty | 10 | real counts (files, sites), measured not estimated |
| Craft | 5 | hierarchy, rhythm, both themes deliberate |

**Corrections to your own earlier claims count double.** Three claims in this round were
wrong and self-caught ("ten dialogs" was six, three of which were a different component;
`OutlineInputBorder` was the norm, not a deviation). Stating those plainly is worth more
than a clean-looking page.

## What the user cares about, learned the hard way

- **They will not accept "I checked" without the check.** Show the command and its output.
- **They read the numbers.** 13 vs 15 vs 18 was caught by eye, twice.
- **They want the guessed parts named** — *「跟我說一下還有哪個區塊元件你是用猜的」*. An
  honest Inferred list buys trust; a silent guess spends it.
- **They will not evaluate the visuals until the mechanics are right** —
  *「我會叫你修到好，我才開始評價畫面」*. Do not ask for aesthetic feedback while an audit
  is failing.
- **Design before code, always.** *「沒有設計給我看過才做，需要重做」*. Show the spec, get
  the ruling, commit the spec, then implement.
- Respond in Traditional Chinese; use ASCII/tables to make structure visible.

## Order of work

1. Extract from the bundle → write down every value with its source.
2. Draw. Cite inline as you go.
3. Run all six audits. Fix. Re-run.
4. Score. If < 90 or any gate fails, go back to 3.
5. Publish the Artifact, report findings **and** the Inferred list, ask for rulings.
6. Commit the spec file only after the user approves it.
7. Implement against the committed spec.
