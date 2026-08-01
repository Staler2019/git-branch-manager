#pragma once

#include "app/bridge/DiscoveryController.h"
#include "app/bridge/RepositorySession.h"
#include "app/dialogs/DialogTypes.h"
#include "app/models/CommitListModel.h"
#include "app/models/GraphColumnDelegate.h"
#include "app/models/RefTreeModel.h"
#include "app/models/RepoListModel.h"
#include "app/theme/Tokens.h"
#include "app/views/DiffView.h"
#include "app/views/OperationLogView.h"
#include "app/views/SidebarPanel.h"
#include "app/views/pages/DiffPage.h"
#include "app/views/pages/RepositoryPage.h"
#include "app/views/pages/WorkingCopyView.h"
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
class QTabWidget;
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
    void onShowDiffTab();
    void onShowRepositorySettings();
    void onCommitContextMenuRequested(const QPoint& pos);
    void onCommitRowClicked(const QModelIndex& index);
    void onCompareWithWorkingCopyReady(const ObjectId& commit,
                                       std::shared_ptr<const ParsedDiff> diff);

    /// "View diff" from either of WorkingCopyView's context menus: switches
    /// to the Diff tab and requests this path's working-copy diff.
    void onViewFileDiffRequested(QString path, bool staged);
    /// RepositorySession::workingCopyDiffReady, filtered down to whatever
    /// onViewFileDiffRequested most recently asked for -- WorkingCopyView's
    /// own embedded pane reacts to the same broadcast independently, filtered
    /// by its own current selection instead.
    void onWorkingCopyDiffReadyForDiffTab(QString path,
                                          bool staged,
                                          std::shared_ptr<const ParsedDiff> diff);

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
    void onBisect();
    void onManageLfs();
    void onExportPatches();
    void onApplyPatchFile();
    void onImportPatches();

    // --- Phase 6 --------------------------------------------------------------
    /// Opens PreferencesDialog, wiring its theme/density signals to the exact
    /// same slots the View > Theme menu and toolbar theme buttons already use
    /// -- there is only ever one theme-switching path.
    void onShowPreferences();

private:
    void buildUi();
    void buildMenus();
    void openRepository(const RepoRecord& record);
    void closeRepository();
    void probeVisibleRepos();
    void updateStateBanner();
    void showError(const QString& summary, const GitError& error);

    /// Applies `theme`, then repaints everything Phase 0's single-token-table
    /// design cannot fix for free: `qApp->setStyleSheet()` re-polishes any
    /// widget styled purely through `app.qss`, but the banner's own
    /// stylesheet and the diff views' baked-in `QTextCharFormat` colours are
    /// set once at construction/render time and need an explicit refresh.
    void applyThemeAndRefresh(ThemeId theme);

    /// Saves the density setting, then closes Phase 0's gap: `rowHeight()`
    /// changing at runtime previously did nothing for `commitView_` because
    /// `QHeaderView::Fixed`'s `defaultSectionSize` is only read at
    /// construction. Re-applies the new row height to every `Fixed`-mode view
    /// (`commitView_`, `repoView_`) and repaints so the change is visible
    /// without restarting. Collapses any open inline commit expansion first --
    /// its row height was set explicitly via `setRowHeight` at the old
    /// density, and would otherwise go stale until the next collapse.
    void onDensityToggled(bool compact);

    /// Re-applies the banner's background/text colours from the current
    /// theme. Called once at construction and again by
    /// `applyThemeAndRefresh` after every theme switch.
    void restyleBanner();

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

    /// `runWithFeedback` bound to `this`, in the shape extracted dialogs
    /// (`app/dialogs/`) take so they can report an operation's outcome the
    /// same way MainWindow itself does, without depending on MainWindow.
    RunWithFeedbackFn feedbackFn();

    /// Shows or hides the Continue/Skip/Abort banner buttons appropriately for
    /// whichever sequencer operation RepoState reports, if any.
    void updateSequencerControls(const RepoState& state);

    // --- Phase 3: inline commit expansion -----------------------------------
    // At most one expanded row at a time, no model change: see the class
    // comment on expandedCommitRow_ for why.

    /// Expands `row` in place: taller row height plus an index widget summarising
    /// the commit's changed files. Collapses whatever was expanded before, if
    /// anything -- exactly one index widget exists at a time.
    void expandCommitRow(int row);

    /// Destroys the current expansion (if any) and restores its row to the
    /// default height. Safe to call when nothing is expanded.
    void collapseExpandedCommitRow();

    /// Builds the panel shown by expandCommitRow(): a summary line plus each
    /// changed file with its +added/-removed counts, built from whatever
    /// currentFiles_/currentDiff_ currently hold for the (necessarily
    /// selected) expanded row.
    QWidget* buildCommitExpansionPanel(int row) const;

    /// Re-populates the currently expanded panel's content once
    /// onCommitDetailsReady delivers data for the row that is expanded --
    /// expansion can be toggled before the async detail read finishes.
    void refreshExpandedCommitPanel();

    /// Builds and shows the two-level commit context menu (Checkout/Merge/
    /// Cherry-pick/Copy SHA/More actions/Delete branch) for the commit at `row`.
    void showCommitContextMenu(int row, const QPoint& globalPos);

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
    SidebarPanel* sidebar_ = nullptr;
    QTableView* fileView_ = nullptr;
    DiffView* diffView_ = nullptr;
    OperationLogView* logView_ = nullptr;
    WorkingCopyView* workingCopyView_ = nullptr;
    DiffPage* diffPage_ = nullptr;
    RepositoryPage* repositoryPage_ = nullptr;

    /// The right-hand content area: History / Working Copy / Diff / Repository,
    /// each a tab rather than a separate top-level `stack_` page, so the
    /// sidebar stays visible across all of them. `stack_` itself now only
    /// switches between the repository browser (index 0) and this repository
    /// shell (index 1).
    QTabWidget* tabWidget_ = nullptr;
    static constexpr int kHistoryTab = 0;
    static constexpr int kWorkingCopyTab = 1;
    static constexpr int kDiffTab = 2;
    static constexpr int kRepositoryTab = 3;

    /// The row currently showing its inline expansion panel, or -1 if none.
    /// Invariant: at most one row is ever expanded, it is always the selected
    /// row (expansion only toggles on a row that is already selected), and
    /// commitView_->setIndexWidget was called at most once for it since the
    /// last collapse -- see expandCommitRow/collapseExpandedCommitRow.
    int expandedCommitRow_ = -1;
    /// The widget last passed to setIndexWidget for expandedCommitRow_. Owned
    /// by commitView_ once installed; cleared (and implicitly deleted by Qt)
    /// on collapse.
    QWidget* expandedCommitPanel_ = nullptr;
    /// The row clicked immediately before the current click, so a second
    /// click on the same (already selected) row can be told apart from a
    /// first click that merely changed the selection.
    int lastClickedCommitRow_ = -1;

    QLabel* statusLabel_ = nullptr;
    QLabel* toolBarRepoNameLabel_ = nullptr;
    QLabel* toolBarBranchLabel_ = nullptr;
    QWidget* bannerRow_ = nullptr;
    QLabel* bannerLabel_ = nullptr;
    QPushButton* bannerContinueButton_ = nullptr;
    QPushButton* bannerSkipButton_ = nullptr;
    QPushButton* bannerAbortButton_ = nullptr;
    QAction* undoAction_ = nullptr;
    QProgressBar* busyBar_ = nullptr;

    /// Coalesces a burst of scroll events into a single `probeVisibleRepos()`
    /// call instead of one per event.
    QTimer* probeDebounce_ = nullptr;

    /// The target of the checkout currently in flight (a ref name or a raw
    /// commit hex), so onOperationFinished's dirty-work-tree retry re-issues
    /// the same checkout instead of assuming it always came from refView_'s
    /// selection -- the commit context menu's "Checkout <sha7>" does not.
    std::string pendingCheckoutTarget_;

    std::vector<RepoRecord> allRepos_;
    std::shared_ptr<const std::vector<ChangedFile>> currentFiles_;
    std::shared_ptr<const ParsedDiff> currentDiff_;

    /// What onViewFileDiffRequested last asked for, so
    /// onWorkingCopyDiffReadyForDiffTab can tell its own reply apart from one
    /// meant for WorkingCopyView's embedded pane. Empty/false until the first
    /// "View diff" context-menu action.
    QString diffTabRequestedPath_;
    bool diffTabRequestedStaged_ = false;
    bool diffTabRequestPending_ = false;

    /// The path/staged pair the Diff tab is currently displaying via
    /// showWorkingCopyDiff, so a stage/unstage line/hunk action from that same
    /// view (see DiffPage::applyPatchRequested) can re-request its diff once
    /// the operation lands, instead of leaving stale hunks with checkboxes
    /// that no longer match the index. Empty/false when the Diff tab isn't
    /// showing a stageable working-copy diff (e.g. after "Compare with working
    /// copy", or before any "View diff").
    QString diffTabShownPath_;
    bool diffTabShownStaged_ = false;
    bool diffTabShownIsStageable_ = false;
};

}  // namespace gbm
