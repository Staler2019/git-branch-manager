#pragma once

#include "core/base/ObjectId.h"
#include "core/git/UnifiedDiffParser.h"

#include <QSet>
#include <QString>
#include <QWidget>

#include <memory>
#include <vector>

class QLabel;
class QScrollArea;
class QVBoxLayout;

namespace gbm {

class SideBySideDiffView;

/// The design's Diff tab.
///
/// Hosts one collapsible `#gbmPanel` section per changed file (item 12: file
/// diffs used to render as one continuous document with no way to collapse a
/// file and no visual gap between them). Each section's body is a
/// staging-capable `SideBySideDiffView` limited to that one file via
/// `showFile`, built lazily on first expand -- one full diff view per file in
/// a large commit is real memory, so only the first file (expanded by
/// default) is built eagerly.
///
/// Fed either by `RepositorySession::requestCompareWithWorkingCopy` (the
/// commit context menu's "Compare with working copy", not stageable -- an
/// arbitrary historical commit isn't the index) or
/// `RepositorySession::requestWorkingCopyDiff` (the Working Copy tab's "View
/// diff", which is stageable since it's a real index/work-tree diff). Staging
/// is gated per call accordingly, and every section built while that
/// stageable/staged pairing is in effect is built with it baked in.
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

    /// Re-renders every already-built section so its colours pick up the
    /// theme most recently passed to `ThemeManager::apply()` -- same reason
    /// `DiffView::refreshTheme()` exists. Collapsed sections whose body was
    /// never built have nothing to re-render; they pick up the new theme's
    /// colours whenever they are first expanded instead.
    void refreshTheme();

signals:
    /// Forwarded verbatim from whichever section's SideBySideDiffView it came
    /// from, so MainWindow can wire it straight to
    /// RepositorySession::applyPatch the same way WorkingCopyView wires
    /// DiffView's signal of the same name.
    void applyPatchRequested(QString patch, bool reverse);

private:
    /// One collapsible file section. `body`/`diffView` stay null until first
    /// expanded.
    struct FileSection {
        QString path;
        QWidget* frame = nullptr;
        QWidget* header = nullptr;
        QLabel* arrowLabel = nullptr;
        QWidget* body = nullptr;
        SideBySideDiffView* diffView = nullptr;
        bool expanded = false;
    };

    void rebuildSections(std::shared_ptr<const ParsedDiff> diff);
    void setSectionExpanded(FileSection& section, bool expanded);
    void ensureSectionBodyBuilt(FileSection& section);
    void clearSections();

    QLabel* headerLabel_ = nullptr;
    QScrollArea* scrollArea_ = nullptr;
    QWidget* sectionsContainer_ = nullptr;
    QVBoxLayout* sectionsLayout_ = nullptr;
    QLabel* emptyLabel_ = nullptr;

    std::shared_ptr<const ParsedDiff> diff_;
    std::vector<std::unique_ptr<FileSection>> sections_;
    bool stageable_ = false;
    bool showingStaged_ = false;

    /// Paths the user collapsed, kept across a refresh of the *same*
    /// underlying comparison (re-showing the same diff after a stage/unstage)
    /// so acting on one file's hunk does not silently re-expand every other
    /// file. Reset whenever the page is pointed at a different comparison.
    QSet<QString> collapsedPaths_;
};

}  // namespace gbm
