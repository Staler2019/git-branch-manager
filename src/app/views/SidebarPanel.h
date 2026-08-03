#pragma once

#include "app/dialogs/DialogTypes.h"

#include <QWidget>

class QAction;
class QLineEdit;
class QListView;
class QListWidget;
class QListWidgetItem;
class QModelIndex;
class QPoint;
class QTreeView;

namespace gbm {

class RefTreeModel;
class RepoListModel;
class RepositorySession;

/// The 250px-wide left panel: a filter box, then five sections --
/// Repositories, Branches, Remotes, Tags, Stash -- replacing the bare
/// `refView_` tree that used to be the entire sidebar.
///
/// Ownership split: MainWindow keeps owning `refModel_`/`refView_`. Several of
/// its existing slots (`onCheckoutRequested`, `onMergeRequested`, the retry
/// path inside `onOperationFinished`) read them directly by member pointer, so
/// this panel *takes* the already-constructed tree view and lays it out
/// alongside the new sections rather than owning a second copy of it. The
/// repository list reuses MainWindow's existing `RepoListModel` for the same
/// reason -- switching repositories from the sidebar should be visible on the
/// repo browser page too, for free, rather than needing to stay in sync with
/// a second model.
class SidebarPanel : public QWidget {
    Q_OBJECT

public:
    SidebarPanel(RepoListModel* repoModel,
                 RefTreeModel* refModel,
                 QTreeView* refView,
                 RunWithFeedbackFn runWithFeedback,
                 QWidget* parent = nullptr);

    /// Attaches to (or detaches from, when `session` is null) the open
    /// repository. Drives the stash section and every context-menu action
    /// that mutates state.
    void setSession(RepositorySession* session);

    /// Re-tints the filter box's hand-drawn search icon for the theme most
    /// recently passed to `ThemeManager::apply()`. Unlike the pill delegate
    /// and the context menus' danger dots (which read `ThemeManager::color`
    /// at paint/popup time), the search icon is baked into a `QIcon` once at
    /// construction, so it needs an explicit refresh on theme switch -- same
    /// reason `WorkingCopyView::refreshTheme()` exists.
    void refreshTheme();

    /// So MainWindow can connect this list's `activated` signal to the same
    /// `onRepoActivated(const QModelIndex&)` slot the repo browser page uses
    /// -- both views share `repoModel`, so a row index means the same thing
    /// in either.
    QListView* repoListView() const { return repoListView_; }

signals:
    /// Re-emits what the existing MainWindow slots already do by reading
    /// `refView`'s current selection -- checkout and merge both need the
    /// stash-retry/force-retry choice handling those slots already have
    /// (`armWorkingCopyChoiceHandler`, the checkout recovery in
    /// `onOperationFinished`), so this panel does not duplicate it.
    void checkoutRequested();
    void mergeIntoCurrentRequested();

    /// Repository Settings and Diff have no content of their own yet (Phase 6
    /// and Phase 5's job respectively) -- this just asks MainWindow to
    /// navigate to whichever page currently stands in for them.
    void repositorySettingsRequested();
    void diffRequested();

    void statusMessage(QString message);

    /// "Open repository" in the repo-list context menu -- the only in-menu
    /// way to open a repository that is not already the current one, since
    /// Fetch/Pull/Push there are disabled until it is.
    void openRepositoryRequested(int row);

private slots:
    void onFilterChanged(const QString& text);
    void onRefContextMenuRequested(const QPoint& pos);
    void onRepoContextMenuRequested(const QPoint& pos);
    void onStashContextMenuRequested(const QPoint& pos);
    void reloadStashes();

private:
    void buildUi();

    /// Recursively hides tree rows that neither match `filter` themselves nor
    /// have a descendant that does, so filtering a branch name still shows
    /// the section root and any intermediate slash-separated groups above it.
    bool applyRefFilter(const QModelIndex& parent, const QString& filter);

    void showBranchContextMenu(const QModelIndex& index, const QPoint& globalPos);
    void showRemoteBranchContextMenu(const QModelIndex& index, const QPoint& globalPos);
    void showTagContextMenu(const QModelIndex& index, const QPoint& globalPos);

    /// Builds the persistence key for a grouping/section node ("Branches",
    /// "Branches/feature", "Remotes/origin", ...) by walking the index's
    /// ancestors and joining their DisplayRole text -- ref leaves never get
    /// expanded/collapsed (no children), so this only ever runs on section
    /// roots and slash-separated grouping nodes.
    QString refNodeKey(const QModelIndex& index) const;

    /// Re-applies each grouping node's last expanded/collapsed state after
    /// refModel_ resets, and installs the defaults (Branches expanded,
    /// Remotes/Tags collapsed) for nodes never seen before. Guarded by
    /// restoringRefExpansion_ so the expanded()/collapsed() signals this
    /// provokes are not mistaken for new user action and re-saved.
    void restoreRefExpansion();
    void saveRefExpansion(const QModelIndex& index, bool expanded);

    RepoListModel* repoModel_ = nullptr;
    RefTreeModel* refModel_ = nullptr;
    QTreeView* refView_ = nullptr;
    RepositorySession* session_ = nullptr;
    RunWithFeedbackFn runWithFeedback_;

    QLineEdit* filterEdit_ = nullptr;
    QAction* searchIconAction_ = nullptr;
    QListView* repoListView_ = nullptr;
    QListWidget* stashList_ = nullptr;

    bool restoringRefExpansion_ = false;
};

}  // namespace gbm
