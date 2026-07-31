#pragma once

#include "app/bridge/DiscoveryController.h"
#include "app/bridge/RepositorySession.h"
#include "app/models/CommitListModel.h"
#include "app/models/GraphColumnDelegate.h"
#include "app/models/RefTreeModel.h"
#include "app/models/RepoListModel.h"
#include "app/views/DiffView.h"
#include "app/views/OperationLogView.h"
#include "app/views/WorkingCopyView.h"
#include "core/git/GitExecutable.h"
#include "core/workers/ThreadPool.h"

#include <QLabel>
#include <QMainWindow>
#include <QPoint>
#include <QTableView>
#include <QTreeView>

#include <functional>
#include <memory>

class QAction;
class QLineEdit;
class QPushButton;
class QSplitter;
class QStackedWidget;
class QProgressBar;
class QTimer;

namespace gbm {

class MainWindow : public QMainWindow {
    Q_OBJECT

public:
    MainWindow(GitInstallation installation, QWidget* parent = nullptr);
    ~MainWindow() override;

    /// Loads the cached repository list. Called after the window is shown, so the
    /// first paint never waits on anything.
    void loadInitialState();

private slots:
    void onAddBaseFolder();
    void onManageBaseFolders();
    void onRefresh();
    void onForceRefresh();
    void onCancelScan();
    void onRepoActivated(const QModelIndex& index);
    void onCommitSelectionChanged();
    void onRefActivated(const QModelIndex& index);
    void onCheckoutRequested();
    void onMergeRequested();
    void onCherryPickRequested();
    void onGraphUpdated(bool complete);
    void onCommitDetailsReady(const ObjectId& commit,
                              std::shared_ptr<const std::vector<ChangedFile>> files,
                              std::shared_ptr<const ParsedDiff> diff);
    void onOperationFinished(const OperationOutcome& outcome);
    void onCoreError(const GitError& error);
    void onRepoSearchChanged(const QString& text);
    void onCommitScrolled();
    void onShowWorkingCopy();
    void onShowHistory();

    // --- M3 -------------------------------------------------------------
    void onFetch();
    void onFetchPrune();
    void onPull();
    void onPush();
    void onPushSetUpstream();
    void onPushForceWithLease();
    void onStashChanges();
    void onManageStashes();
    void onManageWorktrees();
    void onNewTag();
    void onRefContextMenuRequested(const QPoint& pos);
    void onCredentialRequested(QString prompt);

    // --- M4 ---------------------------------------------------------------
    void onResetBranchRequested();
    void onRebaseRequested();
    void onInteractiveRebaseRequested();
    void onBannerContinue();
    void onBannerSkip();
    void onBannerAbort();
    void onCleanUntracked();
    void onShowReflog();
    void onUndoLastOperation();
    void onFileContextMenuRequested(const QPoint& pos);

    // --- M5 -----------------------------------------------------------------
    void onManageSubmodules();

private:
    void buildUi();
    void buildMenus();
    void openRepository(const RepoRecord& record);
    void closeRepository();
    void probeVisibleRepos();
    void updateStateBanner();
    void showError(const QString& summary, const GitError& error);

    /// Submits a merge/cherry-pick style request and waits for exactly one
    /// `workingCopyOperationFinished`. On success or a plain error, reports it
    /// and is done. On a recoverable choice (currently always
    /// stash-and-retry-or-abort), shows it and, if the user picks retry,
    /// re-arms itself and calls `submit(true)` again -- so `submit` never runs
    /// more than once per user decision, and this needs no member state to
    /// carry the retry across the asynchronous round trip.
    void armWorkingCopyChoiceHandler(std::function<void(bool stashFirst)> submit, bool stashFirst);

    /// The M3 equivalent for operations that are not a checkout/merge/
    /// cherry-pick: shows the outcome exactly the same way (status text,
    /// error dialog, or a confirm-then-retry prompt per recoverable choice),
    /// but leaves what "retry" means to `onChoice` instead of assuming
    /// stash-and-retry. Most M3 operations never produce a choice and pass
    /// nullptr, which still upgrades them from silent to reporting their
    /// result -- the same round trip checkout/merge/cherry-pick already get.
    void runWithFeedback(std::function<void()> submit,
                         std::function<void(OperationChoice::Kind)> onChoice = nullptr);

    /// Shows or hides the Continue/Skip/Abort banner buttons appropriately for
    /// whichever sequencer operation RepoState reports, if any.
    void updateSequencerControls(const RepoState& state);

    GitInstallation installation_;

    /// Read pool for history, diffs and metadata. Sized to leave a core for the UI.
    ThreadPool readPool_{"reads"};

    std::unique_ptr<DiscoveryController> discovery_;
    std::unique_ptr<RepositorySession> session_;

    RepoListModel* repoModel_ = nullptr;
    CommitListModel* commitModel_ = nullptr;
    RefTreeModel* refModel_ = nullptr;
    GraphColumnDelegate* graphDelegate_ = nullptr;

    QStackedWidget* stack_ = nullptr;
    QTableView* repoView_ = nullptr;
    QLineEdit* repoSearch_ = nullptr;
    QTableView* commitView_ = nullptr;
    QTreeView* refView_ = nullptr;
    QTableView* fileView_ = nullptr;
    DiffView* diffView_ = nullptr;
    OperationLogView* logView_ = nullptr;
    WorkingCopyView* workingCopyView_ = nullptr;

    QLabel* statusLabel_ = nullptr;
    QLabel* bannerLabel_ = nullptr;
    QPushButton* bannerContinueButton_ = nullptr;
    QPushButton* bannerSkipButton_ = nullptr;
    QPushButton* bannerAbortButton_ = nullptr;
    QAction* undoAction_ = nullptr;
    QProgressBar* busyBar_ = nullptr;

    /// Coalesces a burst of scroll events into a single `probeVisibleRepos()`
    /// call instead of one per event.
    QTimer* probeDebounce_ = nullptr;

    std::vector<RepoRecord> allRepos_;
    std::shared_ptr<const std::vector<ChangedFile>> currentFiles_;
    std::shared_ptr<const ParsedDiff> currentDiff_;
};

}  // namespace gbm
