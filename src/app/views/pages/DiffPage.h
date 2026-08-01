#pragma once

#include "core/base/ObjectId.h"
#include "core/git/UnifiedDiffParser.h"

#include <QWidget>

#include <memory>

class QLabel;

namespace gbm {

class DiffView;

/// The design's Diff tab.
///
/// Phase 3 gives this its own tab slot without rebuilding it into the staged
/// side-by-side editor the design eventually wants (that promotion of
/// `SideBySideDiffView` to a first-class page is Phase 5's job -- see the
/// plan). For now this hosts a plain `DiffView` fed by
/// `RepositorySession::requestCompareWithWorkingCopy`, which is the one flow
/// in this phase that needs an ad hoc diff destination: the commit context
/// menu's "Compare with working copy" action.
class DiffPage : public QWidget {
    Q_OBJECT

public:
    explicit DiffPage(QWidget* parent = nullptr);

    /// Shows the diff between `commit` and the current work tree, as produced
    /// by `RepositorySession::compareWithWorkingCopyReady`.
    void showCompareWithWorkingCopy(const ObjectId& commit, std::shared_ptr<const ParsedDiff> diff);

    /// Shows a transient status message ("Comparing…") in place of a diff.
    void showMessage(const QString& message);

    /// Clears the pane back to its empty state, e.g. on repository close.
    void clearDiff();

    /// Re-renders the currently shown diff so its colours pick up the theme
    /// most recently passed to `ThemeManager::apply()` -- same reason
    /// `DiffView::refreshTheme()` exists.
    void refreshTheme();

private:
    QLabel* headerLabel_ = nullptr;
    DiffView* diffView_ = nullptr;
};

}  // namespace gbm
