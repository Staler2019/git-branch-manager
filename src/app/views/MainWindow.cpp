#include "app/views/MainWindow.h"

#include "app/bridge/ThemeManager.h"
#include "app/dialogs/AboutDialog.h"
#include "app/dialogs/BisectDialog.h"
#include "app/dialogs/BlameDialog.h"
#include "app/dialogs/CherryPickDialog.h"
#include "app/dialogs/CleanUntrackedDialog.h"
#include "app/dialogs/FileHistoryDialog.h"
#include "app/dialogs/InteractiveRebaseDialog.h"
#include "app/dialogs/KeyboardShortcutsDialog.h"
#include "app/dialogs/LineHistoryDialog.h"
#include "app/dialogs/ManageBaseFoldersDialog.h"
#include "app/dialogs/ManageLfsDialog.h"
#include "app/dialogs/ManageStashesDialog.h"
#include "app/dialogs/ManageSubmodulesDialog.h"
#include "app/dialogs/ManageWorktreesDialog.h"
#include "app/dialogs/MergeDialog.h"
#include "app/dialogs/PreferencesDialog.h"
#include "app/dialogs/ReflogDialog.h"
#include "app/dialogs/ResetBranchDialog.h"
#include "app/dialogs/StashChangesDialog.h"
#include "app/models/CommitRowDelegate.h"
#include "app/theme/IconLoader.h"
#include "app/views/CommitExpansionPanel.h"
#include "app/views/CredentialDialog.h"
#include "core/discovery/RepoClassifier.h"
#include "core/git/ops/CheckoutOp.h"

#include <QAbstractButton>
#include <QAction>
#include <QActionGroup>
#include <QApplication>
#include <QClipboard>
#include <QDialog>
#include <QFileDialog>
#include <QGuiApplication>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QIcon>
#include <QInputDialog>
#include <QLineEdit>
#include <QListView>
#include <QMenu>
#include <QMenuBar>
#include <QMessageBox>
#include <QPainter>
#include <QPixmap>
#include <QProgressBar>
#include <QPushButton>
#include <QScrollBar>
#include <QSizePolicy>
#include <QSplitter>
#include <QStackedWidget>
#include <QStandardPaths>
#include <QStatusBar>
#include <QStringListModel>
#include <QStyle>
#include <QTabWidget>
#include <QTimer>
#include <QToolBar>
#include <QVBoxLayout>

#include <algorithm>
#include <filesystem>

namespace gbm {

namespace {

/// Rows in the repository list are cheap to render but each probe costs a few
/// stats, so only what is on screen gets probed.
constexpr int kProbeMargin = 20;

/// The minimum acceptable danger treatment for a destructive menu action,
/// mirroring `SidebarPanel.cpp`'s `markDanger`: QSS cannot select one
/// `QMenu::item` out of many, so this tints the action's icon instead.
void markDanger(QAction* action) {
    const int size = 10;
    QPixmap pixmap(size, size);
    pixmap.fill(Qt::transparent);
    QPainter painter(&pixmap);
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setBrush(ThemeManager::color(Token::Danger));
    painter.setPen(Qt::NoPen);
    painter.drawEllipse(QRectF(1.0, 1.0, size - 2.0, size - 2.0));
    painter.end();
    action->setIcon(QIcon(pixmap));
}

}  // namespace

MainWindow::MainWindow(GitInstallation installation, QWidget* parent)
    : QMainWindow(parent), installation_(std::move(installation)) {
    setWindowTitle(QStringLiteral("git-branch-manager"));
    resize(1400, 900);

    discovery_ = std::make_unique<DiscoveryController>(installation_, this);

    buildUi();
    buildMenus();

    logView_->installAsSink();

    connect(discovery_.get(), &DiscoveryController::scanStarted, this, [this] {
        statusLabel_->setText(QStringLiteral("Scanning…"));
        busyBar_->setVisible(true);
    });
    connect(
        discovery_.get(), &DiscoveryController::scanProgress, this, [this](const QString& message) {
            statusLabel_->setText(message);
        });
    connect(discovery_.get(),
            &DiscoveryController::reposDiscovered,
            this,
            [this](const std::vector<RepoRecord>& batch) {
                repoModel_->appendRepos(batch);
                for (const RepoRecord& record : batch) {
                    allRepos_.push_back(record);
                }
            });
    connect(discovery_.get(),
            &DiscoveryController::scanFinished,
            this,
            [this](bool cancelled, const QString& summary) {
                Q_UNUSED(cancelled);
                statusLabel_->setText(summary);
                busyBar_->setVisible(false);
                allRepos_ = discovery_->loadFromCache();
                repoModel_->setRepos(allRepos_);
                probeVisibleRepos();
            });
    connect(discovery_.get(),
            &DiscoveryController::probeReady,
            this,
            [this](std::int64_t repoId, const RepoProbe& probe) {
                repoModel_->setProbe(repoId, probe);
            });
    connect(discovery_.get(), &DiscoveryController::errorOccurred, this, &MainWindow::onCoreError);
}

MainWindow::~MainWindow() {
    // Detach the log sinks before the view dies: a worker thread finishing during
    // teardown must not call into a destroyed widget.
    Log::instance().setOperationSink(nullptr);
    Log::instance().setMessageSink(nullptr);
    closeRepository();
    readPool_.shutdown();
}

void MainWindow::buildUi() {
    stack_ = new QStackedWidget(this);
    setCentralWidget(stack_);

    // --- page 0: repository browser -----------------------------------------
    auto* browserPage = new QWidget(this);
    auto* browserLayout = new QVBoxLayout(browserPage);

    repoSearch_ = new QLineEdit(browserPage);
    repoSearch_->setPlaceholderText(QStringLiteral("Filter repositories by name or path…"));
    repoSearch_->setClearButtonEnabled(true);
    repoSearch_->setAccessibleName(QStringLiteral("Filter repositories"));
    connect(repoSearch_, &QLineEdit::textChanged, this, &MainWindow::onRepoSearchChanged);

    repoModel_ = new RepoListModel(this);
    repoView_ = new QTableView(browserPage);
    repoView_->setAccessibleName(QStringLiteral("Repositories"));
    repoView_->setModel(repoModel_);
    repoView_->setSelectionBehavior(QAbstractItemView::SelectRows);
    repoView_->setSelectionMode(QAbstractItemView::SingleSelection);
    repoView_->verticalHeader()->setVisible(false);
    repoView_->verticalHeader()->setDefaultSectionSize(ThemeManager::rowHeight());
    repoView_->setShowGrid(false);
    repoView_->setAlternatingRowColors(true);
    repoView_->horizontalHeader()->setSectionResizeMode(RepoListModel::ColumnName,
                                                        QHeaderView::ResizeToContents);
    repoView_->horizontalHeader()->setStretchLastSection(true);
    connect(repoView_, &QTableView::activated, this, &MainWindow::onRepoActivated);

    // Probing is driven by what is actually visible, not by the list's size. A
    // flick of the scrollbar fires many valueChanged signals in a row; without
    // debouncing that would post one round of probes per event instead of one
    // for the whole gesture.
    probeDebounce_ = new QTimer(this);
    probeDebounce_->setSingleShot(true);
    probeDebounce_->setInterval(150);
    connect(probeDebounce_, &QTimer::timeout, this, &MainWindow::probeVisibleRepos);
    connect(repoView_->verticalScrollBar(), &QScrollBar::valueChanged, this, [this] {
        probeDebounce_->start();
    });

    browserLayout->addWidget(repoSearch_);
    browserLayout->addWidget(repoView_, 1);
    stack_->addWidget(browserPage);

    // --- page 1: repository view --------------------------------------------
    auto* repoPage = new QWidget(this);
    auto* repoLayout = new QVBoxLayout(repoPage);
    repoLayout->setContentsMargins(0, 0, 0, 0);

    bannerRow_ = new QWidget(repoPage);
    auto* bannerRow = bannerRow_;
    auto* bannerLayout = new QHBoxLayout(bannerRow);
    bannerLayout->setContentsMargins(6, 4, 6, 4);

    auto* bannerIcon = new QLabel(bannerRow);
    bannerIcon->setPixmap(style()->standardIcon(QStyle::SP_MessageBoxWarning).pixmap(16, 16));
    bannerIcon->setAccessibleName(QStringLiteral("Warning"));
    bannerLayout->addWidget(bannerIcon);

    bannerLabel_ = new QLabel(bannerRow);
    bannerLabel_->setVisible(false);
    bannerLabel_->setWordWrap(true);
    bannerLabel_->setAccessibleName(QStringLiteral("Repository state banner"));
    bannerLayout->addWidget(bannerLabel_, 1);

    // Theme-token-driven rather than a fixed literal, so the banner adapts
    // across all three themes instead of always being the same brown -- and
    // re-applied by applyThemeAndRefresh() on every theme switch, since a
    // widget's own setStyleSheet() survives qApp->setStyleSheet() untouched.
    restyleBanner();

    // Continue/Skip/Abort for whichever sequencer operation (merge, cherry-pick,
    // revert or rebase) RepoState reports in progress -- see
    // updateSequencerControls. Not every operation offers all three: a plain
    // merge has no --skip, for instance.
    bannerContinueButton_ = new QPushButton(QStringLiteral("Continue"), bannerRow);
    bannerSkipButton_ = new QPushButton(QStringLiteral("Skip"), bannerRow);
    bannerAbortButton_ = new QPushButton(QStringLiteral("Abort"), bannerRow);
    bannerContinueButton_->setVisible(false);
    bannerSkipButton_->setVisible(false);
    bannerAbortButton_->setVisible(false);
    connect(bannerContinueButton_, &QPushButton::clicked, this, &MainWindow::onBannerContinue);
    connect(bannerSkipButton_, &QPushButton::clicked, this, &MainWindow::onBannerSkip);
    connect(bannerAbortButton_, &QPushButton::clicked, this, &MainWindow::onBannerAbort);
    bannerLayout->addWidget(bannerContinueButton_);
    bannerLayout->addWidget(bannerSkipButton_);
    bannerLayout->addWidget(bannerAbortButton_);

    bannerRow->setVisible(false);
    repoLayout->addWidget(bannerRow);

    auto* outerSplitter = new QSplitter(Qt::Horizontal, repoPage);

    refModel_ = new RefTreeModel(this);
    refView_ = new QTreeView(outerSplitter);
    refView_->setObjectName(QStringLiteral("gbmRefView"));
    refView_->setAccessibleName(QStringLiteral("Branches and tags"));
    refView_->setModel(refModel_);
    refView_->setHeaderHidden(true);
    refView_->setUniformRowHeights(true);
    connect(refView_, &QTreeView::activated, this, &MainWindow::onRefActivated);
    // Context-menu policy and the Repositories/Stash sections are owned by
    // SidebarPanel below, which takes this already-constructed view over --
    // MainWindow keeps refModel_/refView_ as members because several existing
    // slots (onCheckoutRequested, onMergeRequested, the checkout retry inside
    // onOperationFinished) read them directly.
    sidebar_ = new SidebarPanel(repoModel_, refModel_, refView_, feedbackFn(), outerSplitter);
    connect(sidebar_, &SidebarPanel::checkoutRequested, this, &MainWindow::onCheckoutRequested);
    connect(
        sidebar_, &SidebarPanel::mergeIntoCurrentRequested, this, &MainWindow::onMergeRequested);
    connect(sidebar_,
            &SidebarPanel::repositorySettingsRequested,
            this,
            &MainWindow::onShowRepositorySettings);
    connect(sidebar_, &SidebarPanel::diffRequested, this, &MainWindow::onShowDiffTab);
    connect(sidebar_, &SidebarPanel::statusMessage, this, [this](const QString& text) {
        statusLabel_->setText(text);
    });
    connect(sidebar_->repoListView(),
            &QAbstractItemView::activated,
            this,
            &MainWindow::onRepoActivated);
    outerSplitter->addWidget(sidebar_);

    // The right side is a Tabs-styled QTabWidget rather than a fifth
    // top-level stack_ page per tab: keeping sidebar_ outside it means the
    // sidebar stays visible across History/Working Copy/Diff/Repository
    // instead of disappearing whenever the user switches away from History.
    tabWidget_ = new QTabWidget(outerSplitter);
    tabWidget_->setDocumentMode(true);

    auto* rightSplitter = new QSplitter(Qt::Vertical, tabWidget_);

    commitModel_ = new CommitListModel(this);
    commitView_ = new QTableView(rightSplitter);
    commitView_->setObjectName(QStringLiteral("gbmCommitView"));
    commitView_->setAccessibleName(QStringLiteral("Commit history"));
    commitView_->setModel(commitModel_);
    commitView_->setSelectionBehavior(QAbstractItemView::SelectRows);
    commitView_->verticalHeader()->setVisible(false);
    // Uniform row heights plus per-pixel scrolling: both required for a virtualized
    // view to stay smooth across hundreds of thousands of rows. The initial size
    // is density-aware; onDensityToggled re-applies it if the setting changes at
    // runtime (see the class comment on that method for the Phase 0 gap this closes).
    commitView_->verticalHeader()->setDefaultSectionSize(ThemeManager::rowHeight());
    commitView_->verticalHeader()->setSectionResizeMode(QHeaderView::Fixed);
    commitView_->setVerticalScrollMode(QAbstractItemView::ScrollPerPixel);
    commitView_->setShowGrid(false);
    commitView_->setWordWrap(false);

    graphDelegate_ = new GraphColumnDelegate(commitModel_, this);
    commitView_->setItemDelegateForColumn(CommitListModel::ColumnGraph, graphDelegate_);
    commitView_->setColumnWidth(CommitListModel::ColumnGraph, 160);
    commitView_->setItemDelegateForColumn(CommitListModel::ColumnSubject,
                                         new CommitRowDelegate(this));
    commitView_->horizontalHeader()->setSectionResizeMode(CommitListModel::ColumnSubject,
                                                          QHeaderView::Stretch);

    connect(commitView_->selectionModel(),
            &QItemSelectionModel::selectionChanged,
            this,
            &MainWindow::onCommitSelectionChanged);
    connect(commitView_->verticalScrollBar(),
            &QScrollBar::valueChanged,
            this,
            &MainWindow::onCommitScrolled);
    connect(commitView_, &QTableView::clicked, this, &MainWindow::onCommitRowClicked);
    commitView_->setContextMenuPolicy(Qt::CustomContextMenu);
    connect(commitView_,
            &QTableView::customContextMenuRequested,
            this,
            &MainWindow::onCommitContextMenuRequested);
    // Collapse any inline expansion before the model reshuffles rows out from
    // under it -- modelAboutToBeReset (not modelReset) so expandedCommitRow_
    // still points at a valid row while collapseExpandedCommitRow() clears
    // its index widget.
    connect(commitModel_, &QAbstractItemModel::modelAboutToBeReset, this, [this] {
        collapseExpandedCommitRow();
    });
    // expandCommitRow's setSpan is index-based: CommitListModel::onGraphUpdated
    // only ever grows by appending past the end (beginInsertRows(parent,
    // oldRows, newRows-1)), which never renumbers an earlier row, so a
    // prefetch append never invalidates an existing span on its own. Rows are
    // never removed today either -- this is a defensive guard against that
    // ever changing, not a currently-reachable path.
    connect(commitModel_, &QAbstractItemModel::rowsAboutToBeRemoved, this, [this] {
        collapseExpandedCommitRow();
    });

    rightSplitter->addWidget(commitView_);

    auto* detailSplitter = new QSplitter(Qt::Horizontal, rightSplitter);
    fileView_ = new QTableView(detailSplitter);
    fileView_->setAccessibleName(QStringLiteral("Changed files"));
    fileView_->setSelectionBehavior(QAbstractItemView::SelectRows);
    fileView_->verticalHeader()->setVisible(false);
    fileView_->setShowGrid(false);
    fileView_->setContextMenuPolicy(Qt::CustomContextMenu);
    connect(fileView_,
            &QTableView::customContextMenuRequested,
            this,
            &MainWindow::onFileContextMenuRequested);
    detailSplitter->addWidget(fileView_);

    diffView_ = new DiffView(detailSplitter);
    detailSplitter->addWidget(diffView_);
    detailSplitter->setStretchFactor(0, 1);
    detailSplitter->setStretchFactor(1, 3);
    rightSplitter->addWidget(detailSplitter);

    rightSplitter->setStretchFactor(0, 3);
    rightSplitter->setStretchFactor(1, 2);
    tabWidget_->addTab(rightSplitter, QStringLiteral("History"));

    // --- Working Copy tab ---------------------------------------------------
    workingCopyView_ = new WorkingCopyView(this);
    connect(workingCopyView_, &WorkingCopyView::statusMessage, this, [this](const QString& text) {
        statusLabel_->setText(text);
    });
    connect(workingCopyView_,
            &WorkingCopyView::errorOccurred,
            this,
            [this](const QString& summary, const GitError& error) { showError(summary, error); });
    connect(workingCopyView_,
            &WorkingCopyView::viewFileDiffRequested,
            this,
            &MainWindow::onViewFileDiffRequested);
    tabWidget_->addTab(workingCopyView_, QStringLiteral("Working Copy"));

    // --- Diff tab ------------------------------------------------------------
    diffPage_ = new DiffPage(this);
    connect(diffPage_, &DiffPage::applyPatchRequested, this, [this](QString patch, bool reverse) {
        if (session_) {
            session_->applyPatch(patch.toStdString(), reverse);
        }
    });
    tabWidget_->addTab(diffPage_, QStringLiteral("Diff"));

    // --- Repository tab -------------------------------------------------------
    repositoryPage_ = new RepositoryPage(this);
    connect(repositoryPage_,
            &RepositoryPage::openPreferencesRequested,
            this,
            &MainWindow::onShowPreferences);
    tabWidget_->addTab(repositoryPage_, QStringLiteral("Repository"));

    outerSplitter->addWidget(tabWidget_);
    outerSplitter->setStretchFactor(0, 1);
    outerSplitter->setStretchFactor(1, 5);

    repoLayout->addWidget(outerSplitter, 1);

    logView_ = new OperationLogView(repoPage);
    logView_->setMaximumHeight(160);
    logView_->setVisible(false);
    repoLayout->addWidget(logView_);

    stack_->addWidget(repoPage);

    // --- status bar ----------------------------------------------------------
    statusLabel_ = new QLabel(QStringLiteral("Ready"), this);
    statusLabel_->setAccessibleName(QStringLiteral("Status"));
    busyBar_ = new QProgressBar(this);
    busyBar_->setRange(0, 0);  // Indeterminate.
    busyBar_->setMaximumWidth(120);
    busyBar_->setVisible(false);
    busyBar_->setAccessibleName(QStringLiteral("Busy"));
    statusBar()->addWidget(statusLabel_, 1);
    statusBar()->addPermanentWidget(busyBar_);
    statusBar()->addPermanentWidget(new QLabel(
        QStringLiteral("git %1").arg(QString::fromStdString(installation_.version.toString())),
        this));
}

void MainWindow::buildMenus() {
    // --- File --------------------------------------------------------------
    // New/Open/Clone repository omitted: this app discovers repositories by
    // scanning base folders, not by opening a single one directly -- there is
    // no such capability to surface.
    auto* fileMenu = menuBar()->addMenu(QStringLiteral("&File"));
    fileMenu->addAction(QStringLiteral("Add base folder…"), this, &MainWindow::onAddBaseFolder);
    fileMenu->addAction(
        QStringLiteral("Manage base folders…"), this, &MainWindow::onManageBaseFolders);
    fileMenu->addSeparator();
    auto* closeAction =
        fileMenu->addAction(QStringLiteral("Close repository"), this, &MainWindow::closeRepository);
    closeAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+W")));
    fileMenu->addSeparator();
    fileMenu->addAction(QStringLiteral("Preferences…"), this, &MainWindow::onShowPreferences);
    fileMenu->addSeparator();
    fileMenu->addAction(QStringLiteral("Exit"), QApplication::instance(), &QApplication::quit);

    // --- Edit ----------------------------------------------------------------
    // Cut/Copy/Paste and Find in files omitted: no generic focused-widget
    // text editing is wired up, and there is no find-in-files feature --
    // adding non-functional entries would be worse than leaving them out.
    auto* editMenu = menuBar()->addMenu(QStringLiteral("&Edit"));
    undoAction_ = editMenu->addAction(
        QStringLiteral("Undo last operation"), this, &MainWindow::onUndoLastOperation);
    undoAction_->setShortcut(QKeySequence(QStringLiteral("Ctrl+Z")));
    undoAction_->setEnabled(false);
    // No redo capability exists in the backend (core/git/ops/UndoOps.h has no
    // redo operation) -- shown disabled with an explanatory tooltip rather
    // than fabricated.
    auto* redoAction = editMenu->addAction(QStringLiteral("Redo"));
    redoAction->setEnabled(false);
    redoAction->setToolTip(QStringLiteral("There is no redo for undone operations"));

    // --- View ----------------------------------------------------------------
    auto* viewMenu = menuBar()->addMenu(QStringLiteral("&View"));
    auto* historyAction =
        viewMenu->addAction(QStringLiteral("History"), this, &MainWindow::onShowHistory);
    historyAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+1")));
    auto* workingCopyAction =
        viewMenu->addAction(QStringLiteral("Working Copy"), this, &MainWindow::onShowWorkingCopy);
    workingCopyAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+2")));
    auto* diffAction =
        viewMenu->addAction(QStringLiteral("Diff"), this, &MainWindow::onShowDiffTab);
    diffAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+3")));
    auto* repositoryTabAction = viewMenu->addAction(
        QStringLiteral("Repository Settings"), this, &MainWindow::onShowRepositorySettings);
    repositoryTabAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+4")));
    viewMenu->addSeparator();
    auto* toggleSidebarAction = viewMenu->addAction(QStringLiteral("Toggle sidebar"));
    toggleSidebarAction->setCheckable(true);
    toggleSidebarAction->setChecked(true);
    connect(toggleSidebarAction, &QAction::toggled, this, [this](bool visible) {
        sidebar_->setVisible(visible);
    });
    auto* logAction = viewMenu->addAction(QStringLiteral("Operation log"));
    logAction->setCheckable(true);
    logAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+L")));
    connect(logAction, &QAction::toggled, this, [this](bool visible) {
        logView_->setVisible(visible);
    });
    viewMenu->addAction(QStringLiteral("Reflog…"), this, &MainWindow::onShowReflog);
    viewMenu->addSeparator();
    // Refresh/rescan/cancel-scan have no home in the design's 7-menu table --
    // View is the most sensible fit, so they stay here.
    auto* refreshAction =
        viewMenu->addAction(QStringLiteral("Refresh"), this, &MainWindow::onRefresh);
    refreshAction->setShortcut(QKeySequence(Qt::Key_F5));
    // Real Lucide SVGs (refresh-cw, download-cloud, arrow-down-to-line,
    // arrow-up-from-line) are what the design names, but this sandbox has no
    // network access to fetch them -- Qt's bundled standard icons stand in
    // rather than shipping fabricated placeholder SVGs.
    refreshAction->setIcon(style()->standardIcon(QStyle::SP_BrowserReload));
    auto* forceAction = viewMenu->addAction(
        QStringLiteral("Refresh (rescan everything)"), this, &MainWindow::onForceRefresh);
    forceAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+F5")));
    viewMenu->addAction(QStringLiteral("Cancel scan"), this, &MainWindow::onCancelScan);
    viewMenu->addAction(QStringLiteral("Preferences…"), this, &MainWindow::onShowPreferences);
    viewMenu->addSeparator();
    auto* themeMenu = viewMenu->addMenu(QStringLiteral("Theme"));
    auto* themeGroup = new QActionGroup(this);
    themeGroup->setExclusive(true);
    const ThemeId currentTheme = ThemeManager::loadSetting();
    for (ThemeId theme :
         {ThemeId::DarkTechnical, ThemeId::LightIde, ThemeId::NeutralProfessional}) {
        QAction* action = themeMenu->addAction(ThemeManager::label(theme));
        action->setCheckable(true);
        action->setChecked(theme == currentTheme);
        themeGroup->addAction(action);
        connect(action, &QAction::triggered, this, [this, theme] { applyThemeAndRefresh(theme); });
    }

    // --- Repository ------------------------------------------------------------
    // "Open in terminal" and "Remove repository" omitted: neither capability
    // exists. There is no per-repository removal -- only whole-base-folder
    // removal via Manage base folders… (File) -- and adding either would be
    // new bridge/core functionality, out of scope for a decomposition phase.
    auto* repoMenu = menuBar()->addMenu(QStringLiteral("Reposi&tory"));
    auto* fetchAction = repoMenu->addAction(QStringLiteral("Fetch"), this, &MainWindow::onFetch);
    fetchAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+F")));
    fetchAction->setIcon(style()->standardIcon(QStyle::SP_BrowserReload));
    auto* pullAction = repoMenu->addAction(QStringLiteral("Pull"), this, &MainWindow::onPull);
    pullAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+L")));
    pullAction->setIcon(style()->standardIcon(QStyle::SP_ArrowDown));
    auto* pushAction = repoMenu->addAction(QStringLiteral("Push"), this, &MainWindow::onPush);
    pushAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+P")));
    pushAction->setIcon(style()->standardIcon(QStyle::SP_ArrowUp));
    repoMenu->addAction(
        QStringLiteral("Repository settings…"), this, &MainWindow::onShowRepositorySettings);
    repoMenu->addSeparator();

    auto* stashMenu = repoMenu->addMenu(QStringLiteral("Stash"));
    stashMenu->addAction(QStringLiteral("Stash changes…"), this, &MainWindow::onStashChanges);
    stashMenu->addAction(QStringLiteral("Manage stashes…"), this, &MainWindow::onManageStashes);

    // "New tag…" used to be the one entry every ref-tree right-click offered,
    // regardless of what (if anything) was under the cursor. The sidebar's
    // tag context menu absorbed the tag-specific items (checkout/push/delete);
    // creating one is not "on" an existing ref the way those are, so it moves
    // here rather than getting a home in a context menu that needs a tag
    // selected to open.
    auto* tagMenu = repoMenu->addMenu(QStringLiteral("Tags"));
    tagMenu->addAction(QStringLiteral("New tag…"), this, &MainWindow::onNewTag);

    auto* worktreeMenu = repoMenu->addMenu(QStringLiteral("Worktrees"));
    worktreeMenu->addAction(
        QStringLiteral("Manage worktrees…"), this, &MainWindow::onManageWorktrees);

    auto* submoduleMenu = repoMenu->addMenu(QStringLiteral("Submodules"));
    submoduleMenu->addAction(
        QStringLiteral("Manage submodules…"), this, &MainWindow::onManageSubmodules);

    auto* bisectMenu = repoMenu->addMenu(QStringLiteral("Bisect"));
    bisectMenu->addAction(QStringLiteral("Bisect…"), this, &MainWindow::onBisect);

    auto* lfsMenu = repoMenu->addMenu(QStringLiteral("LFS"));
    lfsMenu->addAction(QStringLiteral("Manage LFS…"), this, &MainWindow::onManageLfs);

    auto* patchMenu = repoMenu->addMenu(QStringLiteral("Patches"));
    patchMenu->addAction(
        QStringLiteral("Export selected commits as patches…"), this, &MainWindow::onExportPatches);
    patchMenu->addSeparator();
    patchMenu->addAction(QStringLiteral("Apply patch file…"), this, &MainWindow::onApplyPatchFile);
    patchMenu->addAction(
        QStringLiteral("Import patches (git am)…"), this, &MainWindow::onImportPatches);

    repoMenu->addSeparator();
    // Same QAction as Edit → Undo, not a second one: two actions bound to the
    // same QKeySequence trigger Qt's "ambiguous shortcut" at press time.
    repoMenu->addAction(undoAction_);
    repoMenu->addAction(
        QStringLiteral("Clean untracked files…"), this, &MainWindow::onCleanUntracked);

    // --- Branch ----------------------------------------------------------------
    // New branch…, Rename current branch and Delete branch… omitted:
    // BranchOps.h has the operation factories, but RepositorySession never
    // exposes them and no existing UI wires them (checked: no call site
    // anywhere) -- surfacing them here would mean adding new bridge/UI code,
    // out of scope for a decomposition phase.
    auto* branchMenu = menuBar()->addMenu(QStringLiteral("&Branch"));
    auto* checkoutAction = branchMenu->addAction(
        QStringLiteral("Switch to selected branch"), this, &MainWindow::onCheckoutRequested);
    checkoutAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+O")));
    auto* mergeAction = branchMenu->addAction(
        QStringLiteral("Merge selected branch into current…"), this, &MainWindow::onMergeRequested);
    mergeAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+M")));
    auto* cherryPickAction =
        branchMenu->addAction(QStringLiteral("Cherry-pick selected commit(s)…"),
                              this,
                              &MainWindow::onCherryPickRequested);
    cherryPickAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+C")));
    branchMenu->addSeparator();
    branchMenu->addAction(QStringLiteral("Rebase current branch onto selected commit…"),
                          this,
                          &MainWindow::onRebaseRequested);
    branchMenu->addAction(QStringLiteral("Interactive rebase onto selected commit…"),
                          this,
                          &MainWindow::onInteractiveRebaseRequested);
    branchMenu->addSeparator();
    branchMenu->addAction(QStringLiteral("Reset current branch to selected commit…"),
                          this,
                          &MainWindow::onResetBranchRequested);

    // --- Remote --------------------------------------------------------------
    // Add remote… and Manage remotes… omitted: no add/manage-remotes UI
    // exists yet.
    auto* remoteMenu = menuBar()->addMenu(QStringLiteral("Re&mote"));
    remoteMenu->addAction(fetchAction);
    remoteMenu->addAction(
        QStringLiteral("Fetch (and prune stale remote branches)"), this, &MainWindow::onFetchPrune);
    remoteMenu->addAction(pullAction);
    remoteMenu->addSeparator();
    remoteMenu->addAction(pushAction);
    remoteMenu->addAction(
        QStringLiteral("Push (set upstream)…"), this, &MainWindow::onPushSetUpstream);
    remoteMenu->addAction(
        QStringLiteral("Push (force-with-lease)…"), this, &MainWindow::onPushForceWithLease);

    // --- Help ------------------------------------------------------------------
    // Documentation omitted: no in-app link target -- the README ships in the
    // repo, not next to the installed binary.
    auto* helpMenu = menuBar()->addMenu(QStringLiteral("&Help"));
    auto* shortcutsAction = helpMenu->addAction(QStringLiteral("Keyboard shortcuts"), this, [this] {
        KeyboardShortcutsDialog dialog(this);
        dialog.exec();
    });
    shortcutsAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+/")));
    helpMenu->addAction(QStringLiteral("About git-branch-manager"), this, [this] {
        AboutDialog dialog(this);
        dialog.exec();
    });

    // --- toolbar -------------------------------------------------------------
    // Repo name + "/ branch", a spacer, Fetch/Pull/Push (the same QAction
    // objects as the menus above -- not new ones, so there is only ever one
    // shortcut owner each), a Refresh icon button, a separator, and the three
    // theme switches the View > Theme submenu already offers.
    auto* toolBar = addToolBar(QStringLiteral("Main"));
    toolBar->setMovable(false);

    toolBarRepoNameLabel_ = new QLabel(toolBar);
    toolBarBranchLabel_ = new QLabel(toolBar);
    toolBarBranchLabel_->setEnabled(false);  // Secondary-text look via the disabled palette.
    toolBar->addWidget(toolBarRepoNameLabel_);
    toolBar->addWidget(toolBarBranchLabel_);
    // The only way back to the repository browser while one is open besides
    // closing it outright -- preserved from the previous toolbar rather than
    // dropped, since the design's toolbar row has no equivalent affordance.
    toolBar->addAction(
        QStringLiteral("Repositories"), this, [this] { stack_->setCurrentIndex(0); });

    auto* spacer = new QWidget(toolBar);
    spacer->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Preferred);
    toolBar->addWidget(spacer);

    toolBar->addAction(fetchAction);
    toolBar->addAction(pullAction);
    toolBar->addAction(pushAction);
    toolBar->addAction(refreshAction);

    toolBar->addSeparator();

    for (ThemeId theme :
         {ThemeId::DarkTechnical, ThemeId::LightIde, ThemeId::NeutralProfessional}) {
        toolBar->addAction(
            ThemeManager::label(theme), this, [this, theme] { applyThemeAndRefresh(theme); });
    }
}

void MainWindow::loadInitialState() {
    const QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    const QString dbPath = dataDir + QStringLiteral("/repo-index.db");

    if (auto opened = discovery_->open(dbPath); !opened) {
        showError(QStringLiteral("Could not open the repository cache"), opened.error());
        return;
    }

    // Painted entirely from the cache: no filesystem access, so this stays fast
    // even with hundreds of repositories.
    allRepos_ = discovery_->loadFromCache();
    repoModel_->setRepos(allRepos_);

    if (allRepos_.empty() && discovery_->baseFolders().empty()) {
        statusLabel_->setText(
            QStringLiteral("No base folders yet — use File ▸ Add base folder to get started"));
    } else {
        statusLabel_->setText(
            QStringLiteral("%1 repositories (cached) — press F5 to refresh").arg(allRepos_.size()));
    }

    // Probe only after the window is up, and only for visible rows.
    QTimer::singleShot(0, this, [this] { probeVisibleRepos(); });

    for (const std::string& warning : installation_.warnings()) {
        logMessage(LogLevel::Warn, warning);
    }
}

void MainWindow::probeVisibleRepos() {
    if (repoView_ == nullptr || repoModel_->rowCount() == 0) {
        return;
    }
    const QModelIndex topLeft = repoView_->indexAt(repoView_->rect().topLeft());
    const QModelIndex bottomRight =
        repoView_->indexAt(repoView_->rect().bottomLeft() - QPoint(0, 1));

    const int first = std::max(0, (topLeft.isValid() ? topLeft.row() : 0) - kProbeMargin);
    const int last = std::min(
        repoModel_->rowCount() - 1,
        (bottomRight.isValid() ? bottomRight.row() : repoModel_->rowCount() - 1) + kProbeMargin);

    for (int row = first; row <= last; ++row) {
        if (const RepoRecord* record = repoModel_->repoAt(row)) {
            discovery_->probeRepo(*record);
        }
    }
}

void MainWindow::onRepoSearchChanged(const QString& text) {
    if (text.isEmpty()) {
        repoModel_->setRepos(allRepos_);
        probeVisibleRepos();
        return;
    }
    // Filtered in memory over the cached list: the whole point of the cache is that
    // this needs no filesystem access and stays instant.
    const QString needle = text.toLower();
    std::vector<RepoRecord> filtered;
    for (const RepoRecord& record : allRepos_) {
        const QString name = QString::fromStdString(record.name).toLower();
        const QString path =
            QString::fromStdString(record.workDir.empty() ? record.gitDir : record.workDir)
                .toLower();
        if (name.contains(needle) || path.contains(needle)) {
            filtered.push_back(record);
        }
    }
    repoModel_->setRepos(std::move(filtered));
    probeVisibleRepos();
}

void MainWindow::onAddBaseFolder() {
    const QString path = QFileDialog::getExistingDirectory(
        this, QStringLiteral("Choose a folder to scan for Git repositories"));
    if (path.isEmpty()) {
        return;
    }

    bool depthAccepted = false;
    const int depth = QInputDialog::getInt(
        this,
        QStringLiteral("Scan depth"),
        QStringLiteral("How many levels below this folder should be scanned?\n"
                       "1 scans only this folder and its direct children; "
                       "raise it to also find repositories nested further down."),
        1,
        0,
        10,
        1,
        &depthAccepted);
    if (!depthAccepted) {
        return;
    }

    if (auto added = discovery_->addBaseFolder(path, depth); !added) {
        showError(QStringLiteral("Could not add that folder"), added.error());
        return;
    }
    // A newly added folder has no signatures yet, so this first pass is effectively
    // a full scan of just that folder.
    discovery_->startScan(ScanMode::Incremental);
}

void MainWindow::onManageBaseFolders() {
    ManageBaseFoldersDialog dialog(discovery_.get(), this);
    dialog.exec();

    if (dialog.changed()) {
        // A depth change cleared that folder's signatures, and a removal cascades
        // to its repositories outright; either way the list the window is
        // currently showing is stale until the next scan reloads it. If every
        // base folder was removed, startScan's own empty-folders check still
        // fires scanFinished and the connected handler clears allRepos_.
        discovery_->startScan(ScanMode::Incremental);
    }
}

void MainWindow::onRefresh() {
    discovery_->startScan(ScanMode::Incremental);
}

void MainWindow::onForceRefresh() {
    discovery_->startScan(ScanMode::Full);
}

void MainWindow::onCancelScan() {
    discovery_->cancelScan();
    statusLabel_->setText(QStringLiteral("Cancelling scan…"));
}

void MainWindow::onShowHistory() {
    if (session_) {
        stack_->setCurrentIndex(1);
        tabWidget_->setCurrentIndex(kHistoryTab);
    }
}

void MainWindow::onShowRepositorySettings() {
    if (session_) {
        stack_->setCurrentIndex(1);
        tabWidget_->setCurrentIndex(kRepositoryTab);
    }
}

void MainWindow::onShowWorkingCopy() {
    if (!session_) {
        return;
    }
    stack_->setCurrentIndex(1);
    tabWidget_->setCurrentIndex(kWorkingCopyTab);
    // The working-copy panel can go stale while the user is elsewhere -- a
    // checkout, for instance, does not refresh it -- so ask for a fresh read
    // on every visit rather than trying to track every place that could.
    session_->refreshWorkingCopyStatus();
}

void MainWindow::onShowDiffTab() {
    if (session_) {
        stack_->setCurrentIndex(1);
        tabWidget_->setCurrentIndex(kDiffTab);
    }
}

void MainWindow::onRepoActivated(const QModelIndex& index) {
    if (const RepoRecord* record = repoModel_->repoAt(index.row())) {
        openRepository(*record);
    }
}

void MainWindow::openRepository(const RepoRecord& record) {
    closeRepository();

    session_ = std::make_unique<RepositorySession>(installation_, record.toPaths(), readPool_);

    connect(session_.get(), &RepositorySession::graphUpdated, this, &MainWindow::onGraphUpdated);
    connect(session_.get(), &RepositorySession::refsUpdated, this, [this] {
        refModel_->setRefs(session_->refs());
        commitModel_->onRefsUpdated();
        // Depth 1 rather than 0: with pills now doing the work of showing what
        // a ref is, the section roots (Branches/Remotes/Tags) read better
        // expanded by default instead of collapsed.
        refView_->expandToDepth(1);
        if (const RefSnapshotPtr refs = session_->refs()) {
            toolBarBranchLabel_->setText(
                QStringLiteral("/ %1").arg(QString::fromStdString(refs->head.branchName)));
        }
    });
    connect(session_.get(),
            &RepositorySession::commitMetadataReady,
            commitModel_,
            &CommitListModel::onCommitMetadataReady);
    connect(session_.get(),
            &RepositorySession::commitDetailsReady,
            this,
            &MainWindow::onCommitDetailsReady);
    connect(session_.get(),
            &RepositorySession::operationFinished,
            this,
            &MainWindow::onOperationFinished);
    connect(session_.get(), &RepositorySession::errorOccurred, this, &MainWindow::onCoreError);
    connect(session_.get(), &RepositorySession::busyChanged, this, [this](bool busy) {
        busyBar_->setVisible(busy);
    });
    // Merge, cherry-pick and conflict resolution all move through
    // workingCopyOperationFinished (WorkingCopyView already reacts to it for the
    // staging/commit case); the banner reflects RepoState, which all of them can
    // change, so it needs to refresh here too regardless of what else reacts.
    connect(session_.get(),
            &RepositorySession::workingCopyOperationFinished,
            this,
            [this](const OperationOutcome&) { updateStateBanner(); });
    connect(session_.get(),
            &RepositorySession::credentialRequested,
            this,
            &MainWindow::onCredentialRequested);
    connect(session_.get(),
            &RepositorySession::compareWithWorkingCopyReady,
            this,
            &MainWindow::onCompareWithWorkingCopyReady);
    connect(session_.get(),
            &RepositorySession::workingCopyDiffReady,
            this,
            &MainWindow::onWorkingCopyDiffReadyForDiffTab);
    // A stage/unstage line/hunk action from the Diff tab (see the
    // diffPage_->applyPatchRequested connection below) applies through
    // session_->applyPatch like any other working-copy operation, but nothing
    // else re-requests that file's diff afterwards -- without this, the tab
    // would keep showing hunks that no longer match the index.
    connect(session_.get(),
            &RepositorySession::workingCopyOperationFinished,
            this,
            [this](const OperationOutcome&) {
                if (diffTabShownIsStageable_ && session_) {
                    diffTabRequestedPath_ = diffTabShownPath_;
                    diffTabRequestedStaged_ = diffTabShownStaged_;
                    diffTabRequestPending_ = true;
                    session_->requestWorkingCopyDiff(diffTabShownPath_.toStdString(),
                                                     diffTabShownStaged_);
                }
            });

    commitModel_->setSession(session_.get());
    diffView_->clearDiff();
    diffPage_->clearDiff();
    diffTabShownPath_.clear();
    diffTabShownStaged_ = false;
    diffTabShownIsStageable_ = false;
    workingCopyView_->setSession(session_.get());
    sidebar_->setSession(session_.get());
    repositoryPage_->setSession(session_.get());

    setWindowTitle(QStringLiteral("%1 — git-branch-manager").arg(session_->displayName()));
    toolBarRepoNameLabel_->setText(session_->displayName());
    toolBarBranchLabel_->setText(QString());
    stack_->setCurrentIndex(1);
    tabWidget_->setCurrentIndex(kHistoryTab);
    updateStateBanner();

    // Refs first, so the history walk can be seeded with HEAD and the trunk; that
    // seeding order is what puts the trunk in lane 0.
    session_->refreshRefs();
    session_->refreshHistory();
    // So the remote picker in the Push/Push tag dialogs has something to show
    // the first time they are opened, without waiting on a Fetch.
    session_->refreshRemotes();
}

void MainWindow::openRepositoryAtPathForScreenshot(const QString& path) {
    const auto classified = RepoClassifier::classify(std::filesystem::path(path.toStdString()));
    if (!classified.isRepo()) {
        statusLabel_->setText(
            QStringLiteral("GBM_SCREENSHOT_REPO does not look like a git repository: %1").arg(path));
        return;
    }
    RepoRecord record;
    record.workDir = classified.paths.workDir().string();
    record.gitDir = classified.paths.gitDir().string();
    record.commonDir = classified.paths.commonDir().string();
    record.kind = classified.kind;
    record.name = classified.paths.displayName();
    openRepository(record);
}

void MainWindow::expandCommitRowForScreenshot(int row) {
    if (commitModel_ == nullptr || row < 0 || row >= commitModel_->rowCount()) {
        return;
    }
    commitView_->selectRow(row);
    expandCommitRow(row);
}

void MainWindow::selectCommitRowForScreenshot(int row) {
    if (commitModel_ == nullptr || row < 0 || row >= commitModel_->rowCount()) {
        return;
    }
    commitView_->selectRow(row);
}

void MainWindow::closeRepository() {
    if (!session_) {
        return;
    }
    session_->cancelPendingReads();
    // commitModel_->setSession(nullptr) resets the model, which fires
    // modelAboutToBeReset and collapses any inline expansion -- see the
    // connection in buildUi() -- but the closing-repository case is worth
    // being explicit about rather than relying on that alone.
    collapseExpandedCommitRow();
    commitModel_->setSession(nullptr);
    refModel_->setRefs(nullptr);
    diffView_->clearDiff();
    diffPage_->clearDiff();
    diffTabShownPath_.clear();
    diffTabShownStaged_ = false;
    diffTabShownIsStageable_ = false;
    workingCopyView_->setSession(nullptr);
    sidebar_->setSession(nullptr);
    repositoryPage_->setSession(nullptr);
    session_.reset();
    pendingCheckoutTarget_.clear();
    setWindowTitle(QStringLiteral("git-branch-manager"));
    toolBarRepoNameLabel_->setText(QString());
    toolBarBranchLabel_->setText(QString());
    stack_->setCurrentIndex(0);
    bannerLabel_->parentWidget()->setVisible(false);
}

void MainWindow::restyleBanner() {
    bannerRow_->setStyleSheet(QStringLiteral("QWidget { background: %1; }")
                                  .arg(ThemeManager::color(Token::DiffDelBg).name()));
    // Unmissable by design: a repository stuck mid-rebase must never look normal.
    bannerLabel_->setStyleSheet(QStringLiteral("QLabel { color: %1; }")
                                    .arg(ThemeManager::color(Token::DiffDelText).name()));
}

void MainWindow::applyThemeAndRefresh(ThemeId theme) {
    ThemeManager::apply(theme);

    // `qApp->setStyleSheet()` re-polishes every widget styled purely through
    // app.qss, and the graph delegate reads ThemeManager::color() at paint
    // time so a repaint is all it needs. What is left is the colour baked
    // into a widget's own stylesheet, into an IconLoader-tinted pixmap, or
    // into already-rendered diff text -- none of which the app-wide restyle
    // touches.
    IconLoader::clearCache();
    restyleBanner();
    diffView_->refreshTheme();
    workingCopyView_->refreshTheme();
    sidebar_->refreshTheme();
    commitView_->viewport()->update();
}

void MainWindow::onDensityToggled(bool compact) {
    ThemeManager::saveDensitySetting(compact ? Density::Compact : Density::Comfortable);

    // The row expanded via setRowHeight() was sized for the old density; the
    // simplest safe option is to collapse it rather than leave a stale height
    // around until the user happens to collapse it themselves.
    collapseExpandedCommitRow();

    const int rowHeight = ThemeManager::rowHeight();
    commitView_->verticalHeader()->setDefaultSectionSize(rowHeight);
    repoView_->verticalHeader()->setDefaultSectionSize(rowHeight);

    // setDefaultSectionSize alone does not resize rows already laid out;
    // resizeSections forces every row (not just future ones) to pick up the
    // new height immediately, and viewport()->update() repaints it.
    commitView_->verticalHeader()->resizeSections(QHeaderView::Fixed);
    repoView_->verticalHeader()->resizeSections(QHeaderView::Fixed);
    commitView_->viewport()->update();
    repoView_->viewport()->update();
}

void MainWindow::updateStateBanner() {
    if (!session_) {
        bannerLabel_->parentWidget()->setVisible(false);
        if (undoAction_) {
            undoAction_->setEnabled(false);
        }
        return;
    }
    if (undoAction_) {
        undoAction_->setEnabled(!session_->undoJournal().empty());
    }

    const RepoState state = session_->state();
    const std::string description = state.describe();
    updateSequencerControls(state);
    if (description.empty()) {
        bannerLabel_->parentWidget()->setVisible(false);
        return;
    }
    bannerLabel_->setText(QString::fromStdString(description));
    bannerLabel_->parentWidget()->setVisible(true);
}

void MainWindow::updateSequencerControls(const RepoState& state) {
    // A plain merge has no --skip (there is only one thing to resolve), and
    // "continuing" it is just committing, which the working-copy panel already
    // does -- so Continue is not offered for it either. Revert is detected (for
    // the banner text) but has no continue/skip/abort operation behind it yet,
    // so it gets no buttons rather than ones that would run the wrong command.
    const bool isRebase = (state.flags & (RepoState::RebaseMerge | RepoState::RebaseApply)) != 0;
    const bool isCherryPick = (state.flags & RepoState::CherryPick) != 0;
    const bool isMerge = (state.flags & RepoState::Merge) != 0;

    bannerContinueButton_->setVisible(isRebase || isCherryPick);
    bannerSkipButton_->setVisible(isRebase || isCherryPick);
    bannerAbortButton_->setVisible(isRebase || isCherryPick || isMerge);
}

void MainWindow::onGraphUpdated(bool complete) {
    commitModel_->onGraphUpdated(complete);

    if (auto snapshot = commitModel_->snapshot()) {
        QString text = QStringLiteral("%1 commits").arg(snapshot->rowCount());
        if (!complete) {
            text += QStringLiteral(" (loading…)");
        }
        if (snapshot->truncated) {
            text += QStringLiteral(" — history truncated at the display limit");
        }
        if (snapshot->overflowedEdges > 0) {
            // Never silent: the lane cap is visible rather than quietly dropping
            // branches off the right-hand side.
            text += QStringLiteral(" — %1 branch lines beyond the %2-lane limit")
                        .arg(snapshot->overflowedEdges)
                        .arg(kMaxLanes);
        }
        if (auto refs = commitModel_->refs(); refs && refs->refCountGuardTripped) {
            text += QStringLiteral(" — %1 refs").arg(refs->totalRefCount);
        }
        statusLabel_->setText(text);

        const int width = graphDelegate_->widthForRows(
            0, static_cast<int>(std::min<std::size_t>(snapshot->rowCount(), 200)));
        commitView_->setColumnWidth(CommitListModel::ColumnGraph, width);
    }

    onCommitScrolled();
}

void MainWindow::onCommitScrolled() {
    if (commitModel_->rowCount() == 0) {
        return;
    }
    const QModelIndex topLeft = commitView_->indexAt(commitView_->rect().topLeft());
    const QModelIndex bottomLeft =
        commitView_->indexAt(commitView_->rect().bottomLeft() - QPoint(0, 1));

    const int first = topLeft.isValid() ? topLeft.row() : 0;
    const int last = bottomLeft.isValid() ? bottomLeft.row() : commitModel_->rowCount() - 1;
    commitModel_->setVisibleRange(first, last);
}

void MainWindow::onCommitSelectionChanged() {
    if (!session_) {
        return;
    }
    const QModelIndexList selected = commitView_->selectionModel()->selectedRows();

    // The expanded row is always the selected one -- expansion only ever
    // toggles on a row that is already selected -- so any selection change
    // away from it means the expansion no longer applies.
    if (expandedCommitRow_ >= 0 &&
        (selected.isEmpty() || selected.first().row() != expandedCommitRow_)) {
        collapseExpandedCommitRow();
    }

    if (selected.isEmpty()) {
        diffView_->clearDiff();
        return;
    }
    const ObjectId oid = commitModel_->oidAt(selected.first().row());
    if (oid.isNull()) {
        return;
    }
    diffView_->showMessage(QStringLiteral("Loading changes…"));
    session_->requestCommitDetails(oid);
}

void MainWindow::onCommitDetailsReady(const ObjectId& commit,
                                      std::shared_ptr<const std::vector<ChangedFile>> files,
                                      std::shared_ptr<const ParsedDiff> diff) {
    // The user may have moved on while this was loading; only render if it still
    // matches the selection.
    const QModelIndexList selected = commitView_->selectionModel()->selectedRows();
    if (!selected.isEmpty() && commitModel_->oidAt(selected.first().row()) != commit) {
        return;
    }

    currentFiles_ = std::move(files);
    currentDiff_ = std::move(diff);

    QStringList paths;
    if (currentFiles_) {
        for (const ChangedFile& file : *currentFiles_) {
            paths << QString::fromStdString(file.path);
        }
    }
    auto* listModel = new QStringListModel(paths, fileView_);
    QAbstractItemModel* previous = fileView_->model();
    fileView_->setModel(listModel);
    delete previous;
    fileView_->horizontalHeader()->setStretchLastSection(true);
    fileView_->horizontalHeader()->setVisible(false);

    connect(fileView_->selectionModel(),
            &QItemSelectionModel::selectionChanged,
            this,
            [this, listModel] {
                const QModelIndexList chosen = fileView_->selectionModel()->selectedRows();
                if (chosen.isEmpty() || !currentDiff_) {
                    return;
                }
                diffView_->showFile(currentDiff_,
                                    listModel->data(chosen.first(), Qt::DisplayRole).toString());
            });

    diffView_->showDiff(currentDiff_);

    // The commit these details belong to may be the one currently expanded --
    // expansion can be toggled on before the async detail read finishes, in
    // which case the panel was built showing "Loading changes…" and now has
    // real content to show.
    refreshExpandedCommitPanel();
}

void MainWindow::onCommitRowClicked(const QModelIndex& index) {
    if (!session_ || !index.isValid()) {
        return;
    }
    const int row = index.row();
    if (row == expandedCommitRow_) {
        // Third click (and beyond) on the same row: collapse it. clicked()
        // fires on every click regardless of whether the selection changed,
        // so a plain equality check here is enough to toggle it back off.
        collapseExpandedCommitRow();
    } else if (row == lastClickedCommitRow_) {
        // Second click on a row that was already selected (the first click
        // selected it -- see onCommitSelectionChanged -- without changing
        // lastClickedCommitRow_ until this line runs).
        expandCommitRow(row);
    }
    lastClickedCommitRow_ = row;
}

void MainWindow::expandCommitRow(int row) {
    if (row == expandedCommitRow_) {
        return;
    }
    // At most one index widget at a time: destroy whatever was expanded
    // before installing the new one.
    collapseExpandedCommitRow();

    expandedCommitRow_ = row;

    // Span the whole row into a single cell, so the panel owns the entire
    // visual unit instead of covering only the Subject column while
    // Graph/Author/Date/ShortSha keep painting into a row that grew out from
    // under them -- that mismatch (not this panel's content) was the actual
    // "conflict[s] on ui when expand" bug: the index widget only ever
    // covered one cell, but setRowHeight grows every column's cell.
    commitView_->setSpan(row, 0, 1, CommitListModel::ColumnCount);

    const QPersistentModelIndex subjectIndex(
        commitModel_->index(row, CommitListModel::ColumnSubject));
    auto* panel = new CommitExpansionPanel(subjectIndex, commitView_->viewport());
    expandedCommitPanel_ = panel;

    const ObjectId oid = commitModel_->oidAt(row);
    const bool detailsMatchThisRow =
        currentFiles_ != nullptr && !commitView_->selectionModel()->selectedRows().isEmpty() &&
        commitModel_->oidAt(commitView_->selectionModel()->selectedRows().first().row()) == oid;
    if (detailsMatchThisRow) {
        panel->setDetails(currentFiles_, currentDiff_);
    }

    commitView_->setIndexWidget(commitModel_->index(row, 0), panel);
    commitView_->setRowHeight(row, panel->sizeHint().height());
}

void MainWindow::collapseExpandedCommitRow() {
    if (expandedCommitRow_ < 0) {
        return;
    }
    // Passing nullptr deletes the previously installed widget and clears the
    // association -- no separate `delete expandedCommitPanel_` needed, and
    // none should be done: the view already owns it.
    commitView_->setIndexWidget(commitModel_->index(expandedCommitRow_, 0), nullptr);
    // Undo the span from expandCommitRow before restoring the default row
    // height -- a leftover span on a now-collapsed row would corrupt
    // whichever row ends up there next.
    commitView_->setSpan(expandedCommitRow_, 0, 1, 1);
    commitView_->setRowHeight(expandedCommitRow_,
                              commitView_->verticalHeader()->defaultSectionSize());
    expandedCommitRow_ = -1;
    expandedCommitPanel_ = nullptr;
}

void MainWindow::refreshExpandedCommitPanel() {
    if (expandedCommitRow_ < 0) {
        return;
    }
    const int row = expandedCommitRow_;
    const ObjectId oid = commitModel_->oidAt(row);
    const bool detailsMatchThisRow =
        currentFiles_ != nullptr && !commitView_->selectionModel()->selectedRows().isEmpty() &&
        commitModel_->oidAt(commitView_->selectionModel()->selectedRows().first().row()) == oid;
    if (!detailsMatchThisRow) {
        return;
    }
    static_cast<CommitExpansionPanel*>(expandedCommitPanel_)->setDetails(currentFiles_, currentDiff_);
    commitView_->setRowHeight(row, expandedCommitPanel_->sizeHint().height());
}

void MainWindow::onCommitContextMenuRequested(const QPoint& pos) {
    if (!session_) {
        return;
    }
    const QModelIndex index = commitView_->indexAt(pos);
    if (!index.isValid()) {
        return;
    }
    // Right-clicking a row that is not already selected selects it (replacing
    // any existing selection), so the reused selection-based slots below
    // (cherry-pick, rebase, reset, export) act on the row under the cursor. A
    // row that is already selected -- including one currently expanded -- is
    // left alone, so right-clicking an expanded row's own panel to reach
    // "More actions" does not collapse it first.
    if (!commitView_->selectionModel()->isRowSelected(index.row(), QModelIndex())) {
        commitView_->selectionModel()->select(
            index, QItemSelectionModel::ClearAndSelect | QItemSelectionModel::Rows);
    }
    showCommitContextMenu(index.row(), commitView_->viewport()->mapToGlobal(pos));
}

void MainWindow::showCommitContextMenu(int row, const QPoint& globalPos) {
    const ObjectId oid = commitModel_->oidAt(row);
    if (oid.isNull()) {
        return;
    }
    const QString sha7 = QString::fromStdString(oid.shortHex(7));

    // A branch tip only if a *local* branch (not a remote-tracking branch or
    // tag) points here -- matches SidebarPanel's own branch/tag menu split.
    QString tipBranchName;
    bool tipBranchIsHead = false;
    if (const RefSnapshotPtr refs = session_->refs()) {
        if (const auto* atCommit = refs->refsAt(oid)) {
            for (const RefInfo* ref : *atCommit) {
                if (ref->kind == RefKind::LocalBranch) {
                    tipBranchName = QString::fromStdString(ref->shortName);
                    tipBranchIsHead = ref->isHead;
                    break;
                }
            }
        }
    }

    QMenu menu(this);
    QAction* checkoutAction = menu.addAction(QStringLiteral("Checkout %1").arg(sha7));
    QAction* mergeAction = menu.addAction(QStringLiteral("Merge into current branch"));
    QAction* cherryPickAction = menu.addAction(QStringLiteral("Cherry-pick"));
    menu.addSeparator();
    QAction* copyShaAction = menu.addAction(QStringLiteral("Copy SHA"));
    QMenu* moreMenu = menu.addMenu(QStringLiteral("More actions"));
    QAction* rebaseAction = moreMenu->addAction(QStringLiteral("Rebase current onto here"));
    QAction* resetAction = moreMenu->addAction(QStringLiteral("Reset branch to here"));
    QAction* revertAction = moreMenu->addAction(QStringLiteral("Revert commit"));
    QAction* exportAction = moreMenu->addAction(QStringLiteral("Export as patch"));
    QAction* compareAction = moreMenu->addAction(QStringLiteral("Compare with working copy"));

    QAction* deleteBranchAction = nullptr;
    if (!tipBranchName.isEmpty()) {
        menu.addSeparator();
        deleteBranchAction = menu.addAction(QStringLiteral("Delete branch %1").arg(tipBranchName));
        deleteBranchAction->setEnabled(!tipBranchIsHead);
        markDanger(deleteBranchAction);
    }

    QAction* chosen = menu.exec(globalPos);
    if (chosen == nullptr) {
        return;
    }

    if (chosen == checkoutAction) {
        CheckoutRequest request;
        request.target = oid.hex();
        pendingCheckoutTarget_ = request.target;
        session_->checkout(request);
        statusLabel_->setText(QStringLiteral("Switching to %1…").arg(sha7));
    } else if (chosen == mergeAction) {
        MergeDialog dialog(sha7, this);
        if (dialog.exec() != QDialog::Accepted) {
            return;
        }
        MergeRequest request = dialog.request();
        statusLabel_->setText(QStringLiteral("Merging %1…").arg(sha7));
        armWorkingCopyChoiceHandler(
            [this, request](bool stashFirst) mutable {
                request.stashFirst = stashFirst;
                session_->mergeBranch(request);
            },
            false);
    } else if (chosen == cherryPickAction) {
        onCherryPickRequested();
    } else if (chosen == copyShaAction) {
        QGuiApplication::clipboard()->setText(QString::fromStdString(oid.hex()));
    } else if (chosen == rebaseAction) {
        onRebaseRequested();
    } else if (chosen == resetAction) {
        onResetBranchRequested();
    } else if (chosen == revertAction) {
        RevertRequest request;
        request.commits = {oid};
        statusLabel_->setText(QStringLiteral("Reverting %1…").arg(sha7));
        armWorkingCopyChoiceHandler(
            [this, request](bool stashFirst) mutable {
                request.stashFirst = stashFirst;
                session_->revertCommit(request);
            },
            false);
    } else if (chosen == exportAction) {
        onExportPatches();
    } else if (chosen == compareAction) {
        diffPage_->showMessage(QStringLiteral("Comparing %1 with the working copy…").arg(sha7));
        tabWidget_->setCurrentIndex(kDiffTab);
        session_->requestCompareWithWorkingCopy(oid);
    } else if (chosen == deleteBranchAction) {
        const auto confirmed =
            QMessageBox::warning(this,
                                 QStringLiteral("Delete branch?"),
                                 QStringLiteral("Delete branch \"%1\"?").arg(tipBranchName),
                                 QMessageBox::Yes | QMessageBox::Cancel,
                                 QMessageBox::Cancel);
        if (confirmed != QMessageBox::Yes) {
            return;
        }
        DeleteBranchRequest request;
        request.name = tipBranchName.toStdString();
        statusLabel_->setText(QStringLiteral("Deleting %1…").arg(tipBranchName));
        runWithFeedback([this, request] { session_->deleteBranch(request); },
                        [this, request](OperationChoice::Kind kind) mutable {
                            // The only choice DeleteBranchOperation ever offers: the
                            // branch has unmerged commits, and the user just confirmed
                            // deleting it anyway (the warning box above already did that).
                            if (kind == OperationChoice::Kind::ForceDiscard) {
                                DeleteBranchRequest forced = request;
                                forced.force = true;
                                runWithFeedback([this, forced] { session_->deleteBranch(forced); },
                                                nullptr);
                            }
                        });
    }
}

void MainWindow::onCompareWithWorkingCopyReady(const ObjectId& commit,
                                               std::shared_ptr<const ParsedDiff> diff) {
    // Not a stageable working-copy diff: stop re-requesting whatever file the
    // Diff tab previously showed via "View diff".
    diffTabShownPath_.clear();
    diffTabShownStaged_ = false;
    diffTabShownIsStageable_ = false;
    diffPage_->showCompareWithWorkingCopy(commit, std::move(diff));
}

void MainWindow::onViewFileDiffRequested(QString path, bool staged) {
    if (!session_) {
        return;
    }
    diffTabRequestedPath_ = path;
    diffTabRequestedStaged_ = staged;
    diffTabRequestPending_ = true;
    diffPage_->showMessage(QStringLiteral("Loading changes for %1…").arg(path));
    tabWidget_->setCurrentIndex(kDiffTab);
    session_->requestWorkingCopyDiff(path.toStdString(), staged);
}

void MainWindow::onWorkingCopyDiffReadyForDiffTab(QString path,
                                                  bool staged,
                                                  std::shared_ptr<const ParsedDiff> diff) {
    if (!diffTabRequestPending_ || path != diffTabRequestedPath_ ||
        staged != diffTabRequestedStaged_) {
        // Either no "View diff" request is outstanding, or this reply belongs
        // to WorkingCopyView's own embedded-pane request instead.
        return;
    }
    diffTabRequestPending_ = false;
    diffTabShownPath_ = path;
    diffTabShownStaged_ = staged;
    diffTabShownIsStageable_ = true;
    diffPage_->showWorkingCopyDiff(path, staged, std::move(diff));
}

void MainWindow::onRefActivated(const QModelIndex& index) {
    const QString name = refModel_->refNameAt(index);
    if (!name.isEmpty()) {
        onCheckoutRequested();
    }
}

void MainWindow::onCheckoutRequested() {
    if (!session_) {
        return;
    }
    const QModelIndexList selected = refView_->selectionModel()->selectedRows();
    if (selected.isEmpty()) {
        return;
    }
    const QString name = refModel_->refNameAt(selected.first());
    if (name.isEmpty()) {
        return;
    }

    CheckoutRequest request;
    request.target = name.toStdString();
    pendingCheckoutTarget_ = request.target;
    session_->checkout(request);
    statusLabel_->setText(QStringLiteral("Switching to %1…").arg(name));
}

void MainWindow::onOperationFinished(const OperationOutcome& outcome) {
    updateStateBanner();

    if (outcome.succeeded) {
        statusLabel_->setText(QString::fromStdString(outcome.summary));
        return;
    }

    // The operation offered the user a way forward, so present those choices
    // rather than a dead-end error box.
    if (!outcome.choices.empty()) {
        QMessageBox box(this);
        box.setIcon(QMessageBox::Warning);
        box.setText(QString::fromStdString(outcome.summary));
        if (outcome.error) {
            box.setDetailedText(QString::fromStdString(outcome.error->detail));
        }

        std::vector<QPushButton*> buttons;
        buttons.reserve(outcome.choices.size());
        for (const OperationChoice& choice : outcome.choices) {
            auto* button = box.addButton(QString::fromStdString(choice.label),
                                         choice.kind == OperationChoice::Kind::Abort
                                             ? QMessageBox::RejectRole
                                             : QMessageBox::ActionRole);
            button->setToolTip(QString::fromStdString(choice.explanation));
            buttons.push_back(button);
        }
        box.exec();

        for (std::size_t i = 0; i < buttons.size(); ++i) {
            if (box.clickedButton() != buttons[i]) {
                continue;
            }
            const OperationChoice& choice = outcome.choices[i];
            if (pendingCheckoutTarget_.empty()) {
                break;
            }
            CheckoutRequest retry;
            // Re-issues whatever checkout was actually in flight -- a ref
            // name from refView_'s selection, or a raw commit hex from the
            // commit context menu's "Checkout <sha7>" -- rather than
            // re-reading refView_'s selection, which is wrong for the latter.
            retry.target = pendingCheckoutTarget_;

            switch (choice.kind) {
                case OperationChoice::Kind::StashAndRetry:
                    retry.stashFirst = true;
                    session_->checkout(retry);
                    break;
                case OperationChoice::Kind::ForceDiscard: {
                    // A destructive action gets an explicit second confirmation.
                    const auto confirmed =
                        QMessageBox::warning(this,
                                             QStringLiteral("Discard changes?"),
                                             QString::fromStdString(choice.explanation),
                                             QMessageBox::Discard | QMessageBox::Cancel,
                                             QMessageBox::Cancel);
                    if (confirmed == QMessageBox::Discard) {
                        retry.force = true;
                        session_->checkout(retry);
                    }
                    break;
                }
                default:
                    break;
            }
            break;
        }
        return;
    }

    if (outcome.error) {
        showError(QString::fromStdString(outcome.summary), *outcome.error);
    }
}

void MainWindow::onMergeRequested() {
    if (!session_) {
        return;
    }
    const QModelIndexList selected = refView_->selectionModel()->selectedRows();
    if (selected.isEmpty()) {
        return;
    }
    const QString name = refModel_->refNameAt(selected.first());
    if (name.isEmpty()) {
        return;
    }

    MergeDialog dialog(name, this);
    if (dialog.exec() != QDialog::Accepted) {
        return;
    }
    MergeRequest request = dialog.request();

    statusLabel_->setText(QStringLiteral("Merging %1…").arg(name));
    armWorkingCopyChoiceHandler(
        [this, request](bool stashFirst) mutable {
            request.stashFirst = stashFirst;
            session_->mergeBranch(request);
        },
        false);
}

void MainWindow::onCherryPickRequested() {
    if (!session_) {
        return;
    }
    const QModelIndexList selected = commitView_->selectionModel()->selectedRows();
    if (selected.isEmpty()) {
        return;
    }

    // The list is newest-first; a cherry-pick must apply oldest first, so sort
    // descending by row (a higher row number is further back in history).
    std::vector<int> rows;
    rows.reserve(static_cast<std::size_t>(selected.size()));
    for (const QModelIndex& index : selected) {
        rows.push_back(index.row());
    }
    std::sort(rows.begin(), rows.end(), std::greater<>());

    std::vector<ObjectId> commits;
    commits.reserve(rows.size());
    QStringList subjects;
    for (int row : rows) {
        commits.push_back(commitModel_->oidAt(row));
        const QModelIndex subjectIndex = commitModel_->index(row, CommitListModel::ColumnSubject);
        subjects << commitModel_->data(subjectIndex, Qt::DisplayRole).toString();
    }

    CherryPickDialog dialog(commits, subjects, this);
    if (dialog.exec() != QDialog::Accepted) {
        return;
    }

    CherryPickRequest request;
    request.commits = std::move(commits);

    statusLabel_->setText(QStringLiteral("Cherry-picking…"));
    armWorkingCopyChoiceHandler(
        [this, request](bool stashFirst) mutable {
            request.stashFirst = stashFirst;
            session_->cherryPick(request);
        },
        false);
}

void MainWindow::armWorkingCopyChoiceHandler(std::function<void(bool)> submit, bool stashFirst) {
    // A one-shot connection: the handler disconnects itself the moment it runs,
    // so it never reacts to an unrelated working-copy operation finishing later.
    auto connection = std::make_shared<QMetaObject::Connection>();
    *connection =
        connect(session_.get(),
                &RepositorySession::workingCopyOperationFinished,
                this,
                [this, submit, connection](const OperationOutcome& outcome) {
                    QObject::disconnect(*connection);

                    if (outcome.succeeded) {
                        statusLabel_->setText(QString::fromStdString(outcome.summary));
                        return;
                    }
                    if (outcome.choices.empty()) {
                        if (outcome.error) {
                            showError(QString::fromStdString(outcome.summary), *outcome.error);
                        }
                        return;
                    }

                    QMessageBox box(this);
                    box.setIcon(QMessageBox::Warning);
                    box.setText(QString::fromStdString(outcome.summary));
                    if (outcome.error) {
                        box.setDetailedText(QString::fromStdString(outcome.error->detail));
                    }
                    std::vector<QPushButton*> buttons;
                    buttons.reserve(outcome.choices.size());
                    for (const OperationChoice& choice : outcome.choices) {
                        auto* button = box.addButton(QString::fromStdString(choice.label),
                                                     choice.kind == OperationChoice::Kind::Abort
                                                         ? QMessageBox::RejectRole
                                                         : QMessageBox::ActionRole);
                        button->setToolTip(QString::fromStdString(choice.explanation));
                        buttons.push_back(button);
                    }
                    box.exec();
                    for (std::size_t i = 0; i < buttons.size(); ++i) {
                        if (box.clickedButton() != buttons[i]) {
                            continue;
                        }
                        if (outcome.choices[i].kind == OperationChoice::Kind::StashAndRetry) {
                            armWorkingCopyChoiceHandler(submit, true);
                        }
                        break;
                    }
                });
    submit(stashFirst);
}

void MainWindow::onCoreError(const GitError& error) {
    // Errors go to the status bar and the operation log rather than interrupting
    // with a modal box: most are transient and the log keeps the full detail.
    statusLabel_->setText(QString::fromStdString(error.message));
    logMessage(LogLevel::Error, error.message + (error.detail.empty() ? "" : ": " + error.detail));
}

void MainWindow::showError(const QString& summary, const GitError& error) {
    QMessageBox box(this);
    box.setIcon(QMessageBox::Critical);
    box.setText(summary.isEmpty() ? QString::fromStdString(error.message) : summary);
    box.setInformativeText(QString::fromStdString(error.message));
    if (!error.detail.empty()) {
        box.setDetailedText(QString::fromStdString(error.detail));
    }
    box.exec();
}

void MainWindow::runWithFeedback(std::function<void()> submit,
                                 std::function<void(OperationChoice::Kind)> onChoice) {
    auto connection = std::make_shared<QMetaObject::Connection>();
    *connection =
        connect(session_.get(),
                &RepositorySession::workingCopyOperationFinished,
                this,
                [this, onChoice, connection](const OperationOutcome& outcome) {
                    QObject::disconnect(*connection);

                    if (outcome.succeeded) {
                        statusLabel_->setText(QString::fromStdString(outcome.summary));
                        return;
                    }
                    if (outcome.choices.empty()) {
                        if (outcome.error) {
                            showError(QString::fromStdString(outcome.summary), *outcome.error);
                        }
                        return;
                    }

                    QMessageBox box(this);
                    box.setIcon(QMessageBox::Warning);
                    box.setText(QString::fromStdString(outcome.summary));
                    if (outcome.error) {
                        box.setDetailedText(QString::fromStdString(outcome.error->detail));
                    }
                    std::vector<QPushButton*> buttons;
                    buttons.reserve(outcome.choices.size());
                    for (const OperationChoice& choice : outcome.choices) {
                        auto* button = box.addButton(QString::fromStdString(choice.label),
                                                     choice.kind == OperationChoice::Kind::Abort
                                                         ? QMessageBox::RejectRole
                                                         : QMessageBox::ActionRole);
                        button->setToolTip(QString::fromStdString(choice.explanation));
                        buttons.push_back(button);
                    }
                    box.exec();
                    for (std::size_t i = 0; i < buttons.size(); ++i) {
                        if (box.clickedButton() != buttons[i]) {
                            continue;
                        }
                        const OperationChoice& choice = outcome.choices[i];
                        if (choice.kind == OperationChoice::Kind::Abort || !onChoice) {
                            break;
                        }
                        if (choice.destructive) {
                            const auto confirmed =
                                QMessageBox::warning(this,
                                                     QStringLiteral("Are you sure?"),
                                                     QString::fromStdString(choice.explanation),
                                                     QMessageBox::Yes | QMessageBox::Cancel,
                                                     QMessageBox::Cancel);
                            if (confirmed != QMessageBox::Yes) {
                                break;
                            }
                        }
                        onChoice(choice.kind);
                        break;
                    }
                });
    submit();
}

RunWithFeedbackFn MainWindow::feedbackFn() {
    return
        [this](std::function<void()> submit, std::function<void(OperationChoice::Kind)> onChoice) {
            runWithFeedback(std::move(submit), std::move(onChoice));
        };
}

// --- M3: remotes -------------------------------------------------------

void MainWindow::onFetch() {
    if (!session_) {
        return;
    }
    statusLabel_->setText(QStringLiteral("Fetching…"));
    runWithFeedback([this] { session_->fetchRemote(FetchRequest{}); });
}

void MainWindow::onFetchPrune() {
    if (!session_) {
        return;
    }
    statusLabel_->setText(QStringLiteral("Fetching…"));
    FetchRequest request;
    request.prune = true;
    runWithFeedback([this, request] { session_->fetchRemote(request); });
}

void MainWindow::onPull() {
    if (!session_) {
        return;
    }
    statusLabel_->setText(QStringLiteral("Pulling…"));
    armWorkingCopyChoiceHandler(
        [this](bool stashFirst) {
            PullRequest request;
            request.stashFirst = stashFirst;
            session_->pullChanges(request);
        },
        false);
}

void MainWindow::onPush() {
    if (!session_) {
        return;
    }
    statusLabel_->setText(QStringLiteral("Pushing…"));
    runWithFeedback([this] { session_->pushChanges(PushRequest{}); });
}

void MainWindow::onPushSetUpstream() {
    if (!session_) {
        return;
    }
    QStringList names;
    if (auto remotes = session_->remotes()) {
        for (const RemoteInfo& remote : *remotes) {
            names << QString::fromStdString(remote.name);
        }
    }
    if (names.isEmpty()) {
        names << QStringLiteral("origin");
    }
    bool ok = false;
    const QString remote = QInputDialog::getItem(
        this, QStringLiteral("Push"), QStringLiteral("Remote:"), names, 0, false, &ok);
    if (!ok || remote.isEmpty()) {
        return;
    }

    const RefSnapshotPtr refs = session_->refs();
    PushRequest request;
    request.remoteName = remote.toStdString();
    request.branch = refs ? refs->head.branchName : std::string();
    request.setUpstream = true;

    statusLabel_->setText(QStringLiteral("Pushing to %1…").arg(remote));
    runWithFeedback([this, request] { session_->pushChanges(request); });
}

void MainWindow::onPushForceWithLease() {
    if (!session_) {
        return;
    }
    const auto confirmed = QMessageBox::warning(
        this,
        QStringLiteral("Force-with-lease push?"),
        QStringLiteral(
            "This overwrites the remote branch with your history, unless someone else has "
            "pushed to it since your last fetch — in which case Git refuses rather than "
            "silently discarding their work."),
        QMessageBox::Yes | QMessageBox::Cancel,
        QMessageBox::Cancel);
    if (confirmed != QMessageBox::Yes) {
        return;
    }

    PushRequest request;
    request.force = PushForceMode::ForceWithLease;
    statusLabel_->setText(QStringLiteral("Pushing (force-with-lease)…"));
    runWithFeedback([this, request] { session_->pushChanges(request); });
}

// --- M3: stashes ---------------------------------------------------------

void MainWindow::onStashChanges() {
    if (!session_) {
        return;
    }

    StashChangesDialog dialog(this);
    if (dialog.exec() != QDialog::Accepted) {
        return;
    }
    const StashSaveRequest request = dialog.request();

    statusLabel_->setText(QStringLiteral("Stashing changes…"));
    runWithFeedback([this, request] { session_->saveStash(request); });
}

void MainWindow::onManageStashes() {
    if (!session_) {
        return;
    }

    ManageStashesDialog dialog(session_.get(), feedbackFn(), this);
    dialog.exec();
}

// --- M3: worktrees ---------------------------------------------------------

void MainWindow::onManageWorktrees() {
    if (!session_) {
        return;
    }

    ManageWorktreesDialog dialog(session_.get(), feedbackFn(), this);
    dialog.exec();
}

// --- M3: tags --------------------------------------------------------------

void MainWindow::onNewTag() {
    if (!session_) {
        return;
    }

    bool ok = false;
    const QString name = QInputDialog::getText(this,
                                               QStringLiteral("New tag"),
                                               QStringLiteral("Tag name:"),
                                               QLineEdit::Normal,
                                               QString(),
                                               &ok);
    if (!ok || name.isEmpty()) {
        return;
    }
    const QString message = QInputDialog::getMultiLineText(
        this,
        QStringLiteral("New tag"),
        QStringLiteral("Message (leave empty for a lightweight tag):"));

    CreateTagRequest request;
    request.name = name.toStdString();
    request.message = message.toStdString();

    // Tags whatever commit is selected in the history list, or HEAD if none is.
    if (commitView_->selectionModel() != nullptr) {
        const QModelIndexList selected = commitView_->selectionModel()->selectedRows();
        if (!selected.isEmpty()) {
            const ObjectId oid = commitModel_->oidAt(selected.first().row());
            if (!oid.isNull()) {
                request.target = oid.hex();
            }
        }
    }

    statusLabel_->setText(QStringLiteral("Creating tag %1…").arg(name));
    runWithFeedback([this, request] { session_->createTag(request); });
}

void MainWindow::onCredentialRequested(QString prompt) {
    if (!session_) {
        return;
    }
    CredentialDialog dialog(prompt, this);
    if (dialog.exec() == QDialog::Accepted) {
        session_->provideCredential(dialog.value());
    } else {
        session_->cancelCredential();
    }
}

// --- M4: sequencer controls (Continue/Skip/Abort on the banner) ------------

void MainWindow::onBannerContinue() {
    if (!session_) {
        return;
    }
    const RepoState state = session_->state();
    statusLabel_->setText(QStringLiteral("Continuing…"));
    if ((state.flags & (RepoState::RebaseMerge | RepoState::RebaseApply)) != 0) {
        runWithFeedback([this] { session_->continueRebase(); });
    } else if ((state.flags & RepoState::CherryPick) != 0) {
        runWithFeedback([this] { session_->continueCherryPick(); });
    }
}

void MainWindow::onBannerSkip() {
    if (!session_) {
        return;
    }
    const RepoState state = session_->state();
    statusLabel_->setText(QStringLiteral("Skipping…"));
    if ((state.flags & (RepoState::RebaseMerge | RepoState::RebaseApply)) != 0) {
        runWithFeedback([this] { session_->skipRebase(); });
    } else if ((state.flags & RepoState::CherryPick) != 0) {
        runWithFeedback([this] { session_->skipCherryPick(); });
    }
}

void MainWindow::onBannerAbort() {
    if (!session_) {
        return;
    }
    const auto confirmed =
        QMessageBox::warning(this,
                             QStringLiteral("Abort?"),
                             QStringLiteral("This unwinds the operation in progress back to "
                                            "where it started."),
                             QMessageBox::Yes | QMessageBox::Cancel,
                             QMessageBox::Cancel);
    if (confirmed != QMessageBox::Yes) {
        return;
    }

    const RepoState state = session_->state();
    statusLabel_->setText(QStringLiteral("Aborting…"));
    if ((state.flags & (RepoState::RebaseMerge | RepoState::RebaseApply)) != 0) {
        runWithFeedback([this] { session_->abortRebase(); });
    } else if ((state.flags & RepoState::CherryPick) != 0) {
        runWithFeedback([this] { session_->abortCherryPick(); });
    } else if ((state.flags & RepoState::Merge) != 0) {
        runWithFeedback([this] { session_->abortMerge(); });
    }
}

// --- M4: reset / rebase -----------------------------------------------------

void MainWindow::onResetBranchRequested() {
    if (!session_) {
        return;
    }
    const QModelIndexList selected = commitView_->selectionModel()->selectedRows();
    if (selected.isEmpty()) {
        return;
    }
    const ObjectId target = commitModel_->oidAt(selected.first().row());
    if (target.isNull()) {
        return;
    }

    ResetBranchDialog dialog(QString::fromStdString(target.shortHex()), this);
    if (dialog.exec() != QDialog::Accepted) {
        return;
    }

    const ResetMode mode = dialog.mode();
    if (mode == ResetMode::Hard) {
        const auto confirmed = QMessageBox::warning(
            this,
            QStringLiteral("Hard reset?"),
            QStringLiteral("This permanently discards uncommitted changes, and any commits not "
                           "reachable from %1.")
                .arg(QString::fromStdString(target.shortHex())),
            QMessageBox::Discard | QMessageBox::Cancel,
            QMessageBox::Cancel);
        if (confirmed != QMessageBox::Discard) {
            return;
        }
    }

    ResetRequest request;
    request.target = target.hex();
    request.mode = mode;
    statusLabel_->setText(QStringLiteral("Resetting…"));
    runWithFeedback([this, request] { session_->resetTo(request); });
}

void MainWindow::onRebaseRequested() {
    if (!session_) {
        return;
    }
    const QModelIndexList selected = commitView_->selectionModel()->selectedRows();
    if (selected.isEmpty()) {
        return;
    }
    const ObjectId upstream = commitModel_->oidAt(selected.first().row());
    if (upstream.isNull()) {
        return;
    }

    const auto confirmed =
        QMessageBox::question(this,
                              QStringLiteral("Rebase"),
                              QStringLiteral("Rebase the current branch onto %1?")
                                  .arg(QString::fromStdString(upstream.shortHex())),
                              QMessageBox::Yes | QMessageBox::Cancel,
                              QMessageBox::Cancel);
    if (confirmed != QMessageBox::Yes) {
        return;
    }

    RebaseRequest request;
    request.upstream = upstream.hex();
    statusLabel_->setText(QStringLiteral("Rebasing…"));
    armWorkingCopyChoiceHandler(
        [this, request](bool stashFirst) mutable {
            request.stashFirst = stashFirst;
            session_->startRebase(request);
        },
        false);
}

void MainWindow::onInteractiveRebaseRequested() {
    if (!session_) {
        return;
    }
    const QModelIndexList selected = commitView_->selectionModel()->selectedRows();
    if (selected.isEmpty()) {
        return;
    }
    const ObjectId upstream = commitModel_->oidAt(selected.first().row());
    if (upstream.isNull()) {
        return;
    }

    InteractiveRebaseDialog dialog(session_.get(), upstream, this);
    if (dialog.exec() != QDialog::Accepted || !dialog.hasTodoEntries()) {
        return;
    }

    RebaseInteractiveRequest request = dialog.request();
    statusLabel_->setText(QStringLiteral("Rebasing…"));
    armWorkingCopyChoiceHandler(
        [this, request](bool stashFirst) mutable {
            request.stashFirst = stashFirst;
            session_->startInteractiveRebase(request);
        },
        false);
}

// --- M4: clean ---------------------------------------------------------------

void MainWindow::onCleanUntracked() {
    if (!session_) {
        return;
    }

    CleanUntrackedDialog dialog(session_.get(), feedbackFn(), this);
    dialog.exec();
}

// --- M4: reflog and undo -----------------------------------------------------

void MainWindow::onShowReflog() {
    if (!session_) {
        return;
    }

    ReflogDialog dialog(session_.get(), feedbackFn(), this);
    dialog.exec();
}

void MainWindow::onUndoLastOperation() {
    if (!session_ || session_->undoJournal().empty()) {
        return;
    }
    const auto& entry = session_->undoJournal().back();
    const auto confirmed = QMessageBox::question(
        this,
        QStringLiteral("Undo?"),
        QStringLiteral("Undo \"%1\"? This resets the current branch back to where it stood "
                       "before.")
            .arg(QString::fromStdString(entry.description)),
        QMessageBox::Yes | QMessageBox::Cancel,
        QMessageBox::Cancel);
    if (confirmed != QMessageBox::Yes) {
        return;
    }
    statusLabel_->setText(QStringLiteral("Undoing…"));
    runWithFeedback([this] { session_->undoLastOperation(); });
}

// --- M4: blame, file and line history ---------------------------------------

void MainWindow::onFileContextMenuRequested(const QPoint& pos) {
    if (!session_ || fileView_->model() == nullptr) {
        return;
    }
    const QModelIndex index = fileView_->indexAt(pos);
    if (!index.isValid()) {
        return;
    }
    const QString path = fileView_->model()->data(index, Qt::DisplayRole).toString();
    const QModelIndexList selectedCommit = commitView_->selectionModel()->selectedRows();
    if (selectedCommit.isEmpty()) {
        return;
    }
    const ObjectId commit = commitModel_->oidAt(selectedCommit.first().row());
    if (commit.isNull()) {
        return;
    }

    QMenu menu(this);
    QAction* blameAction = menu.addAction(QStringLiteral("Blame this file"));
    QAction* historyAction = menu.addAction(QStringLiteral("File history"));
    QAction* lineHistoryAction = menu.addAction(QStringLiteral("Line history for a range…"));
    QAction* chosen = menu.exec(fileView_->viewport()->mapToGlobal(pos));
    if (chosen == nullptr) {
        return;
    }

    const std::string stdPath = path.toStdString();
    const std::string revision = commit.hex();

    if (chosen == blameAction) {
        auto connection = std::make_shared<QMetaObject::Connection>();
        *connection = connect(session_.get(),
                              &RepositorySession::blameReady,
                              this,
                              [this, connection, path](BlameResultPtr result) {
                                  QObject::disconnect(*connection);
                                  if (!result) {
                                      return;
                                  }
                                  BlameDialog dialog(path, *result, this);
                                  dialog.exec();
                              });
        session_->requestBlame(stdPath, revision, 0, 0);
        return;
    }

    if (chosen == historyAction) {
        auto connection = std::make_shared<QMetaObject::Connection>();
        *connection = connect(session_.get(),
                              &RepositorySession::fileHistoryReady,
                              this,
                              [this, connection, path](std::vector<FileHistoryEntry> entries) {
                                  QObject::disconnect(*connection);
                                  FileHistoryDialog dialog(path, entries, this);
                                  dialog.exec();
                              });
        session_->requestFileHistory(stdPath, revision);
        return;
    }

    if (chosen == lineHistoryAction) {
        bool ok = false;
        const int startLine = QInputDialog::getInt(this,
                                                   QStringLiteral("Line history"),
                                                   QStringLiteral("Start line:"),
                                                   1,
                                                   1,
                                                   1000000,
                                                   1,
                                                   &ok);
        if (!ok) {
            return;
        }
        const int endLine = QInputDialog::getInt(this,
                                                 QStringLiteral("Line history"),
                                                 QStringLiteral("End line:"),
                                                 startLine,
                                                 startLine,
                                                 1000000,
                                                 1,
                                                 &ok);
        if (!ok) {
            return;
        }

        auto connection = std::make_shared<QMetaObject::Connection>();
        *connection = connect(session_.get(),
                              &RepositorySession::lineHistoryReady,
                              this,
                              [this, connection, path](std::vector<LineHistoryChunk> chunks) {
                                  QObject::disconnect(*connection);
                                  LineHistoryDialog dialog(path, chunks, this);
                                  dialog.exec();
                              });
        session_->requestLineHistory(stdPath, startLine, endLine, revision);
    }
}

// --- M5: submodules ----------------------------------------------------------

void MainWindow::onManageSubmodules() {
    if (!session_) {
        return;
    }

    ManageSubmodulesDialog dialog(session_.get(), feedbackFn(), this);
    dialog.exec();
}

// --- M5: bisect ----------------------------------------------------------

void MainWindow::onBisect() {
    if (!session_) {
        return;
    }

    BisectDialog dialog(session_.get(), feedbackFn(), this);
    dialog.exec();
}

// --- M5: LFS ---------------------------------------------------------------

void MainWindow::onManageLfs() {
    if (!session_) {
        return;
    }

    ManageLfsDialog dialog(session_.get(), feedbackFn(), this);
    dialog.exec();
}

// --- M5: patch import/export -------------------------------------------------

void MainWindow::onExportPatches() {
    if (!session_) {
        return;
    }
    const QModelIndexList selected = commitView_->selectionModel()->selectedRows();
    if (selected.isEmpty()) {
        return;
    }

    // Newest-first selection, oldest-first output -- same convention as
    // onCherryPickRequested, and the same reason: `format-patch --start-number`
    // must see the commits in the order they were made.
    std::vector<int> rows;
    rows.reserve(static_cast<std::size_t>(selected.size()));
    for (const QModelIndex& index : selected) {
        rows.push_back(index.row());
    }
    std::sort(rows.begin(), rows.end(), std::greater<>());

    std::vector<ObjectId> commits;
    commits.reserve(rows.size());
    for (int row : rows) {
        commits.push_back(commitModel_->oidAt(row));
    }

    const QString dir =
        QFileDialog::getExistingDirectory(this, QStringLiteral("Choose a folder for the patches"));
    if (dir.isEmpty()) {
        return;
    }

    ExportPatchesRequest request;
    request.commits = commits;
    request.outputDir = std::filesystem::path(dir.toStdString());
    runWithFeedback([this, request] { session_->exportPatches(request); });
}

void MainWindow::onApplyPatchFile() {
    if (!session_) {
        return;
    }
    const QStringList files =
        QFileDialog::getOpenFileNames(this,
                                      QStringLiteral("Apply patch"),
                                      QString(),
                                      QStringLiteral("Patches (*.patch *.diff);;All files (*)"));
    if (files.isEmpty()) {
        return;
    }

    ApplyPatchFilesRequest request;
    for (const QString& file : files) {
        request.patchFiles.push_back(std::filesystem::path(file.toStdString()));
    }
    // Staged, not just written to the work tree: applying a patch from the
    // menu is a deliberate "bring this change in" action, so it is left ready
    // to review and commit rather than as an extra unstaged-diff step.
    request.updateIndex = true;
    runWithFeedback([this, request] { session_->applyPatchFiles(request); });
}

void MainWindow::onImportPatches() {
    if (!session_) {
        return;
    }
    const QStringList files = QFileDialog::getOpenFileNames(
        this,
        QStringLiteral("Import patches (git am)"),
        QString(),
        QStringLiteral("Patches (*.patch *.eml *.mbox);;All files (*)"));
    if (files.isEmpty()) {
        return;
    }

    ImportPatchesRequest request;
    for (const QString& file : files) {
        request.patchFiles.push_back(std::filesystem::path(file.toStdString()));
    }
    request.threeWay = true;

    // A conflicted patch leaves `git am` mid-sequence (see PatchOps.h on why
    // this needs its own Continue/Skip/Abort rather than the shared banner,
    // which would call `git rebase --continue` and be refused outright). This
    // recurses on itself via a shared_ptr so each subsequent patch in the
    // series -- which can conflict again -- gets the same recovery prompt.
    auto handleOutcome = std::make_shared<std::function<void(const OperationOutcome&)>>();
    *handleOutcome = [this, handleOutcome](const OperationOutcome& outcome) {
        if (outcome.succeeded) {
            statusLabel_->setText(QString::fromStdString(outcome.summary));
            return;
        }
        if (!session_ || !RepoState::read(session_->paths()).isSequencerOperation()) {
            if (outcome.error) {
                showError(QString::fromStdString(outcome.summary), *outcome.error);
            }
            return;
        }

        QMessageBox box(this);
        box.setIcon(QMessageBox::Warning);
        box.setText(
            QStringLiteral("A patch did not apply cleanly. Resolve the conflict in the "
                           "working copy (stage the result), then Continue -- or Skip "
                           "this patch, or Abort the import."));
        if (outcome.error) {
            box.setDetailedText(QString::fromStdString(outcome.error->detail));
        }
        QPushButton* continueButton =
            box.addButton(QStringLiteral("Continue"), QMessageBox::AcceptRole);
        QPushButton* skipButton = box.addButton(QStringLiteral("Skip"), QMessageBox::ActionRole);
        QPushButton* abortButton = box.addButton(QStringLiteral("Abort"), QMessageBox::RejectRole);
        box.addButton(QStringLiteral("Later"), QMessageBox::DestructiveRole);
        box.exec();

        QAbstractButton* clicked = box.clickedButton();
        if (clicked != continueButton && clicked != skipButton && clicked != abortButton) {
            return;
        }

        auto connection = std::make_shared<QMetaObject::Connection>();
        *connection = connect(session_.get(),
                              &RepositorySession::workingCopyOperationFinished,
                              this,
                              [connection, handleOutcome](const OperationOutcome& next) {
                                  QObject::disconnect(*connection);
                                  (*handleOutcome)(next);
                              });
        if (clicked == continueButton) {
            session_->continueImport();
        } else if (clicked == skipButton) {
            session_->skipImport();
        } else {
            session_->abortImport();
        }
    };

    auto connection = std::make_shared<QMetaObject::Connection>();
    *connection = connect(session_.get(),
                          &RepositorySession::workingCopyOperationFinished,
                          this,
                          [connection, handleOutcome](const OperationOutcome& outcome) {
                              QObject::disconnect(*connection);
                              (*handleOutcome)(outcome);
                          });
    session_->importPatches(request);
}

void MainWindow::onShowPreferences() {
    PreferencesDialog dialog(this);
    connect(&dialog, &PreferencesDialog::themeSelected, this, &MainWindow::applyThemeAndRefresh);
    connect(&dialog, &PreferencesDialog::densityToggled, this, &MainWindow::onDensityToggled);
    dialog.exec();
}

}  // namespace gbm
