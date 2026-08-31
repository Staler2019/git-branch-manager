# UX acceptance bar

Pin prefix `UX-`. Format: [README.md](README.md).

## [UX-evidence-tier] What the score is, and what it is not

Evaluated with the `product-design-harness` UX3 framework (User Flow led;
Business/Evidence Flow lightly weighted — this is an internal tool's
usability pass, not a stakeholder business decision), Standard Gate mode.
**Evidence tier: T2** — static code analysis plus reachability/step-count
inspection, not moderated user testing. Treat the scores below as a
code-verifiable floor, not a substitute for real usability testing before a
1.0 release.

## [UX-rubric] Scoring rubric (100 pts)

| Dimension | Weight | What's measured |
|---|---|---|
| A. High-frequency action reachability | 30 | stage/unstage, commit, checkout, fetch/pull/push, view diff, switch pane — each should be reachable in ≤2 steps |
| B. Full-action discoverability | 25 | Every feature in docs/FEATURES.md has a UI entry point (menu / context menu / shortcut); no orphaned routes |
| C. Step efficiency | 25 | Sampled flows (merge, cherry-pick, stash, conflict resolve, bulk branch delete) measured against comparable desktop Git clients |
| D. View necessity & information architecture | 20 | No redundant views; no *hidden material state* — see `ux3.rule.human_factors_load` |

## [UX-score-is-history] The score trajectory is ledger material, not a rule

- **Rule**: the current score and how it was reached live in
  [ledger: UX3 round 1](../ledger/2026-08-13-feat-flutter-design-restore.md), not here.
- **Consequence**: a rules file states the bar a change is held to; "we scored 95 in round 1"
  only makes sense as what happened in round N, which is [CULT-filing-rule] ledger material.
