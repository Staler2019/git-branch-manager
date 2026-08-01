#pragma once

#include "core/base/ObjectId.h"
#include "core/git/UnifiedDiffParser.h"

#include <QWidget>

#include <memory>

class QLabel;

namespace gbm {

class SideBySideDiffView;

/// The design's Diff tab.
///
/// Hosts the staging-capable `SideBySideDiffView` (Phase 5's promotion of that
/// view into a first-class page -- see the plan). Fed either by
/// `RepositorySession::requestCompareWithWorkingCopy` (the commit context
/// menu's "Compare with working copy", not stageable -- an arbitrary historical
/// commit isn't the index) or `RepositorySession::requestWorkingCopyDiff` (the
/// Working Copy tab's "View diff", which is stageable since it's a real
/// index/work-tree diff). Staging is gated per call accordingly.
class DiffPage : public QWidget {
    Q_OBJECT

public:
    explicit DiffPage(QWidget* parent = nullptr);

    /// Shows the diff between `commit` and the current work tree, as produced
    /// by `RepositorySession::compareWithWorkingCopyReady`. Never stageable.
    void showCompareWithWorkingCopy(const ObjectId& commit, std::shared_ptr<const ParsedDiff> diff);

    /// Shows one file's working-copy diff ("View diff" on the Working Copy
    /// tab's unstaged/staged context menus), as produced by
    /// `RepositorySession::workingCopyDiffReady`. Stageable.
    void showWorkingCopyDiff(const QString& path,
                             bool staged,
                             std::shared_ptr<const ParsedDiff> diff);

    /// Shows a transient status message ("Comparing…") in place of a diff.
    void showMessage(const QString& message);

    /// Clears the pane back to its empty state, e.g. on repository close.
    void clearDiff();

    /// Re-renders the currently shown diff so its colours pick up the theme
    /// most recently passed to `ThemeManager::apply()` -- same reason
    /// `DiffView::refreshTheme()` exists.
    void refreshTheme();

signals:
    /// Forwarded verbatim from the hosted SideBySideDiffView, so MainWindow
    /// can wire it straight to RepositorySession::applyPatch the same way
    /// WorkingCopyView wires DiffView's signal of the same name.
    void applyPatchRequested(QString patch, bool reverse);

private:
    QLabel* headerLabel_ = nullptr;
    SideBySideDiffView* diffView_ = nullptr;
};

}  // namespace gbm
