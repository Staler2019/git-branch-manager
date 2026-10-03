# Preferences has a seventh, Developer section, with no spec basis

- **Kind**: ruling · **Pins**: was `STRUCT-developer-preferences-tab` · **Code**: `PreferencesSection.developer`, `_DeveloperSection`

## Situation
`PREFNAV` lists six sections. fix/refresh-ui-first-tiering added three feature flags (`showRefreshTimings`, `keepDiffDuringRefresh`, `tieredRefresh`) to compare old and new refresh behaviour on real hardware without rebuilding.

## Task
Expose the flags without inventing new UI.

## Action
A seventh `PreferencesSection.developer` renders `_DeveloperSection`, reusing the section's `_SectionHeading` / `_NavItem` / toggle-row widgets — no new drawn value, which is why a `spec-auditor` pass had nothing new to audit. A user-requested addition (same category as the soft-wrap ruling); a future spec audit should not expect it quoted in the 21 pages.

## Result
`preferences_dialog_test.dart`'s 「PreferencesDialogContent - Developer」 group. Evidence: [ledger: fix/refresh-ui-first-tiering](../ledger/2026-09-17-fix-refresh-ui-first-tiering.md).
