#pragma once

#include "app/dialogs/DialogTypes.h"

#include <QWidget>

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

    RepoListModel* repoModel_ = nullptr;
    RefTreeModel* refModel_ = nullptr;
    QTreeView* refView_ = nullptr;
    RepositorySession* session_ = nullptr;
    RunWithFeedbackFn runWithFeedback_;

    QLineEdit* filterEdit_ = nullptr;
    QListView* repoListView_ = nullptr;
    QListWidget* stashList_ = nullptr;
};

}  // namespace gbm
