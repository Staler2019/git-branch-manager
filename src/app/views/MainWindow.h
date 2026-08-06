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

#include <QElapsedTimer>
#include <QLabel>
#include <QList>
#include <QMainWindow>
#include <QPoint>
#include <QTableView>
#include <QTreeView>

#include <functional>
#include <memory>
#include <optional>
#include <string>

class QAction;
class QLineEdit;
class QPushButton;
class QSplitter;
class QStackedWidget;
class QTabWidget;
class QProgressBar;
class QTimer;
class QToolButton;

namespace gbm {

class MainWindow : public QMainWindow {
    Q_OBJECT

public:
    MainWindow(GitInstallation installation, QWidget* parent = nullptr);
    ~MainWindow() override;

    /// Loads the cached repository list. Called after the window is shown, so the
    /// first paint never waits on anything.
    void loadInitialState();

    /// Test/debug seam for `GBM_SCREENSHOT_REPO`: classifies `path` directly
    /// (bypassing the discovery scan/cache) and opens it exactly as
    /// `onRepoActivated` would, so a screenshot can be taken of the repository
    /// shell instead of the browser page `stack_` otherwise starts on.
    void openRepositoryAtPathForScreenshot(const QString& path);

    /// Test/debug seam for `GBM_SCREENSHOT_EXPAND_ROW`: selects and expands
    /// `row` directly, so a screenshot can verify the inline commit
    /// expansion panel without simulating the click sequence
    /// onCommitRowClicked otherwise requires.
    void expandCommitRowForScreenshot(int row);

    /// Test/debug seam for `GBM_SCREENSHOT_SELECT_ROW`: selects `row` without
    /// expanding it, so a screenshot can verify the selected (but not
    /// expanded) row's background is uniform across all five columns --
    /// expandCommitRowForScreenshot's panel would otherwise cover exactly the
    /// area in question.
    void selectCommitRowForScreenshot(int row);

    /// Test/debug seam for `GBM_SCREENSHOT_SWITCH_THEME_AFTER`: calls the
    /// private `applyThemeAndRefresh(theme)` a screenshot can otherwise only
    /// reach by simulating a toolbar click -- exists specifically to verify
    /// that a *runtime* theme switch re-bakes every IconLoader-tinted icon
    /// (title bar, Fetch/Pull/Push, Refresh, the palette icons), not just
    /// that starting the process already on that theme looks right.
    void switchThemeForScreenshot(ThemeId theme);

private slots:
    void onAddBaseFolder();
    void onManageBaseFolders();
    void onRefresh();
    void onForceRefresh();
    void onCancelScan();
    void onWindowActivated();
    void onRepoActivated(const QModelIndex& index);
    void onRepoRowClicked(const QModelIndex& index);
    void openPendingRepo();
    void onCommitSelectionChanged();
    void onRefActivated(const QModelIndex& index);
    void onCheckoutRequested();
    void onMergeRequested();
    void onCherryPickRequested();
    void onGraphUpdated(bool complete, GraphUpdateOrigin origin);
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
    void onStashDiffRequested(int index);
    void onStashDiffReady(int index, std::shared_ptr<const ParsedDiff> diff);
    void onFilterGraphBranches();

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
    /// Shared by onRebaseRequested() (Branch menu -- reads commitView_'s
    /// selection, the only OID available there) and the commit context menu's
    /// "Rebase current onto here" (which already knows the clicked row's OID
    /// and used to re-derive it from the selection instead, only correct
    /// because the context-menu handler force-selects the clicked row first).
    /// Passing it explicitly removes that indirection.
    void performRebase(const ObjectId& upstream);
    void onBannerContinue();
    void onBannerSkip();
    void onBannerAbort();
    void onPerfHintOptimizeClicked();
    void onPerfHintNotNowClicked();
    void onPerfHintDismissClicked();
    void onCommitGraphWriteFinished(bool succeeded);
    void onCleanUntracked();
    void onOpenTerminal();
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

    /// Rescans the base folders for repositories (what the "Refresh
    /// Repository List" action/F5 does). Only touches the repo-list page --
    /// an already-open session is untouched, see resyncOpenSession().
    void rescanRepositories(ScanMode mode);

    /// Re-syncs the currently open session's working-copy status, stashes,
    /// refs and history from disk -- everything an external `git` command run
    /// in another terminal could have changed. Called on window re-activation
    /// (throttled, see windowActivateThrottle_); no longer reachable from the
    /// Refresh button, which is repo-list-only now (see rescanRepositories()).
    /// A no-op if no session is open.
    void resyncOpenSession();
    void probeVisibleRepos();
    void updateStateBanner();
    /// Restores `splitter`'s sizes from QSettings key `window/splitters/<key>`
    /// if present, then connects splitterMoved to persist future changes
    /// under the same key. Called once per splitter from buildUi() after its
    /// panes and stretch factors are set up, so an absent saved value falls
    /// back to whatever the stretch factors already produce.
    void setupPersistentSplitter(QSplitter* splitter, const QString& key);

    /// "origin" if a remote by that name exists, else the sole remote if
    /// there is exactly one, else std::nullopt -- shared by onPush() (silent
    /// auto-detection of a missing upstream) and onPushSetUpstream() (the
    /// interactive remote picker), so the two agree on what "the" remote
    /// means when there is no ambiguity.
    std::optional<std::string> resolveDefaultRemoteName() const;
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

    /// Submits a merge/cherry-pick style request and waits for exactly one
    /// `workingCopyOperationFinished`. On success or a plain error, reports it
    /// and is done. On a recoverable choice (currently always
    /// stash-and-retry-or-abort), shows it and, if the user picks retry,
    /// re-arms itself and calls `submit(true)` again -- so `submit` never runs
    /// more than once per user decision, and this needs no member state to
    /// carry the retry across the asynchronous round trip.
    /// `announceSuccess`: most callers are satisfied by the statusLabel_ text
    /// this already sets on success; rebase-onto-a-commit is not, since a
    /// "current branch is up to date" no-op success looks identical to
    /// nothing having happened if the only feedback is a status-bar corner.
    /// When true, a successful outcome also gets a QMessageBox so it cannot
    /// be missed. Defaults to false rather than changing behaviour for
    /// checkout/merge/revert/reset/cherry-pick, which already share this path.
    void armWorkingCopyChoiceHandler(std::function<void(bool stashFirst)> submit,
                                     bool stashFirst,
                                     bool announceSuccess = false);

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
    QPushButton* branchFilterButton_ = nullptr;
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

    /// Members (rather than buildUi() locals) only so their sizes can be
    /// persisted to QSettings on splitterMoved and restored on startup --
    /// see restoreSplitterSizes()/persistSplitterSizes() in MainWindow.cpp.
    QSplitter* outerSplitter_ = nullptr;
    QSplitter* rightSplitter_ = nullptr;
    QSplitter* detailSplitter_ = nullptr;

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

    /// A sibling of bannerRow_, not a reuse of it: bannerRow_ reflects
    /// RepoState (merge/rebase/cherry-pick in progress) via updateStateBanner()
    /// and is driven by workingCopyOperationFinished; this one is an
    /// unrelated, dismissible performance hint driven by onGraphUpdated(). The
    /// two concerns would fight over one slot's worth of space if merged.
    QWidget* perfHintRow_ = nullptr;
    QLabel* perfHintLabel_ = nullptr;
    QPushButton* perfHintOptimizeButton_ = nullptr;
    QPushButton* perfHintNotNowButton_ = nullptr;
    QPushButton* perfHintDismissButton_ = nullptr;
    /// Set the first time the hint is shown for the current session, and
    /// never cleared until the next openRepository(). Without this,
    /// MainWindow::openRepository()'s unconditional maybeAutoFetch() call
    /// produces a second graphUpdated(complete=true) 750ms-1s later on a
    /// successful silent fetch (see RepositorySession::fetchRemoteSilently),
    /// which would otherwise reopen a hint the user just dismissed -- observed
    /// in 2 of 4 headless runs against a real large clone; see
    /// docs/reports/vscode-graph-performance.md's bottleneck #3.
    bool commitGraphHintShown_ = false;
    QAction* undoAction_ = nullptr;
    QProgressBar* busyBar_ = nullptr;

    /// Icons baked once via IconLoader::icon() at buildMenus() time, unlike
    /// the delegate-painted ones (sidebar rows, ref pills) that call it fresh
    /// on every paint. IconLoader::clearCache() alone does not repaint an
    /// already-set QIcon/QPixmap, so applyThemeAndRefresh() re-bakes each of
    /// these explicitly after clearing the cache -- otherwise they keep the
    /// previous theme's tint indefinitely after a theme switch.
    QLabel* titleBarIconLabel_ = nullptr;
    QAction* fetchAction_ = nullptr;
    QAction* pullAction_ = nullptr;
    QAction* pushAction_ = nullptr;
    QAction* refreshAction_ = nullptr;
    QList<QAction*>
        toolbarThemeActions_;  // Same order as {DarkTechnical, LightIde, NeutralProfessional}.
    /// The toolbar's styled Fetch/Pull/Push buttons construct their icon from
    /// fetchAction_->icon() etc. as a one-time snapshot, not a live binding
    /// to the action -- setting the action's icon later does not move these.
    QPushButton* fetchButton_ = nullptr;
    QPushButton* pullButton_ = nullptr;
    QPushButton* pushButton_ = nullptr;

    /// Coalesces a burst of scroll events into a single `probeVisibleRepos()`
    /// call instead of one per event.
    QTimer* probeDebounce_ = nullptr;

    /// Coalesces a burst of selection changes (e.g. arrow-key or click
    /// scrubbing down the repository list) into opening only the row the
    /// user actually lands on, rather than opening -- and immediately
    /// tearing down -- a RepositorySession per row passed through.
    QTimer* repoOpenDebounce_ = nullptr;
    int pendingRepoOpenRow_ = -1;

    /// Throttles resyncOpenSession() on repeated app-activation events (e.g.
    /// alt-tab drumming) to roughly once per second. Local git reads only --
    /// the auto-fetch triggered alongside it (RepositorySession::
    /// maybeAutoFetch) is gated by its own, much longer interval, not this
    /// one; see the call site in onWindowActivated().
    QElapsedTimer windowActivateThrottle_;
    static constexpr qint64 kWindowActivateThrottleMs = 1000;

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
