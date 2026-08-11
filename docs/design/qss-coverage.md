# QSS coverage audit

> **Historical.** This audit covers the Qt Widgets UI (`src/app/`), removed
> once the Flutter UI (`app_flutter/`) reached feature parity — see
> [ARCHITECTURE.md](../ARCHITECTURE.md). Qt style sheets (QSS) have no Flutter
> equivalent; styling now goes through `app_flutter/lib/theme/`. Kept for
> historical record of the theming decisions made along the way.

Requested by item 3 ("make sure all styles are self-designed, not default"):
an inventory of every Qt widget class the app instantiates, checked against
`resources/qss/app.qss` coverage, so the app is not silently falling back to
Fusion/platform defaults anywhere. Audit-and-report first, per the user's
answer when this was scoped — fixed here only the visually obvious, low-risk
gaps; the rest are listed below as decisions for the user.

Fusion is forced app-wide (`ThemeManager::apply`,
`QApplication::setStyle(QStyleFactory::create("Fusion"))`), so nothing here
falls through to a *native* OS control by accident except where noted — the
gap is un-tokenized Fusion defaults, not native chrome, unless called out.

## Fixed in this pass

| Gap | Where it showed | Fix |
|---|---|---|
| `QScrollArea` / its viewport | `DiffPage`, `CommitExpansionPanel` — both already set `NoFrame` in code, but the viewport still filled with `QPalette::Base`, a plain gray with no theme token, seaming against the panel surfaces around it | `QScrollArea { background: transparent; border: none; }` plus a structural `QScrollArea > QWidget` rule (the viewport has no stable object name) |
| `QAbstractScrollArea::corner` | The square between two scrollbars once `gbmCommitView`/`gbmRefView`/`gbmRepoView` grow wide enough to scroll both ways | Styled to `@surface-panel-raised`, matching `QHeaderView::section` |
| `QScrollBar::add-page`/`::sub-page` | The trough above/below the handle — only the groove and handle were styled, not the page regions specifically | Set to `transparent`, matching the groove |
| `QToolBar::separator` | The divider between the refresh button and the theme swatches (`MainWindow.cpp` toolbar) | Styled to `@border-subtle`, 1px |

All four verified via `ThemeTest::qssSubstitutionLeavesNoUnresolvedPlaceholder`
(no new `@` placeholders leaked unresolved) and `gbm_model_tests`/
`gbm_theme_tests` still green.

## Investigated, not fixed — reasoned out

| Gap | Why it's real | Why not fixed here |
|---|---|---|
| `QTreeView::branch` (expand/collapse arrows on `gbmRefView`) | Default Fusion branch indicators, not token-driven | QSS's `::branch` subcontrol needs an `image:`/`border-image:` the moment *any* rule targets it, or Qt's built-in arrow disappears entirely with nothing to replace it. A correct fix needs a real per-theme icon (via `IconLoader`, which already tints SVGs per token) wired through `QTreeView::indexWidget` or a custom style, not a QSS-only patch — attempting a shallow QSS rule risks *removing* the expand/collapse affordance rather than restyling it. Left as a real follow-up, not a QSS one-liner. |
| `QHeaderView::up-arrow`/`::down-arrow` (sort indicators) | Un-styled, would show default arrows | **Dead gap in practice**: `grep -rn "setSortingEnabled" src/app` returns nothing — no view in the app enables column sorting, so these subcontrols never render today. Not worth styling until sorting is a feature. |

## Deliberately left as a choice, not a fix

| Gap | Why it's real | The tradeoff |
|---|---|---|
| `QFileDialog` (`MainWindow.cpp` folder/file pickers, `ManageWorktreesDialog`) | Fully native OS dialog — `DontUseNativeDialog` is set nowhere in the repo, so these bypass QSS and the theme entirely | Forcing `DontUseNativeDialog` makes them themed, but loses the OS's recent-places sidebar, native search, and platform-specific affordances (Quick Look on macOS, etc.) — a real regression for most users, not a strict improvement. Left as the user's call. |
| `QInputDialog` (`MainWindow.cpp`, `SidebarPanel.cpp`, `ManageWorktreesDialog.cpp`) | Gets only the generic `QDialog`/`QLabel` rules already in `app.qss` (background + label color), no dedicated line-edit-in-a-prompt styling | Low-traffic surface (rename/create-with-a-name prompts); a bespoke QSS pass here is easy to add later if it turns out to matter, so it wasn't force-fit into this slice. |

## Confirmed *not* gaps (checked, already covered)

So these aren't mistakenly "fixed" again later: `QTableWidget` and
`QListWidget` are matched by the `QTableView`/`QListView` type selectors in
`app.qss` (Qt type selectors match subclasses); `QMessageBox` has its own
rule; `QDialog`, `QComboBox` (including its popup `QAbstractItemView`),
`QSpinBox`/`QDoubleSpinBox`, `QGroupBox`, `QRadioButton`, `QCheckBox`,
`QToolTip`, `QProgressBar`, `QSplitter`, `QTabBar`, `QStatusBar`,
`QDialogButtonBox`, `QScrollBar` (handle + groove), `QMenuBar`/`QMenu`
(including separators) all have dedicated rules already.

## Added since this audit, with coverage from the start

`QWidget#gbmPerfHint` / `QLabel#gbmPerfHintLabel` (MainWindow's dismissible
commit-graph advice row): styled alongside `gbmBanner`/`gbmBannerLabel` in the
same commit that added the widget, using `@accent-subtle` rather than
`gbmBanner`'s warning-red `@diff-del-bg` -- this is a suggestion, not a
warning. Verified via `ThemeTest::qssSubstitutionLeavesNoUnresolvedPlaceholder`
and `everyTokenResolvesInEveryTheme`.

## Inline `setStyleSheet` call sites (bypass the token system on purpose or not)

`DiffPage.cpp`, `WorkingCopyView.cpp` (x2), `CommitExpansionPanel.cpp` each
call `setStyleSheet()` directly on a widget rather than going through
`app.qss`. Each of these already has its own `refreshTheme()` re-applied on
a theme switch (`DiffPage::refreshTheme`, `WorkingCopyView::refreshTheme`,
etc.), so they are not stale — just outside this file's inventory. Not
flagged as a gap; noted here so a future audit doesn't re-discover them as
one.
