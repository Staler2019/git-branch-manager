#include "app/views/MainWindow.h"

#include "app/bridge/ThemeManager.h"
#include "app/views/CredentialDialog.h"
#include "core/git/ops/CheckoutOp.h"

#include <QAbstractButton>
#include <QAction>
#include <QActionGroup>
#include <QApplication>
#include <QCheckBox>
#include <QComboBox>
#include <QDateTime>
#include <QDialog>
#include <QDialogButtonBox>
#include <QDir>
#include <QFileDialog>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QInputDialog>
#include <QLineEdit>
#include <QListWidget>
#include <QMenu>
#include <QMenuBar>
#include <QMessageBox>
#include <QPlainTextEdit>
#include <QProgressBar>
#include <QPushButton>
#include <QRadioButton>
#include <QScrollBar>
#include <QSplitter>
#include <QStackedWidget>
#include <QStandardPaths>
#include <QStatusBar>
#include <QStringListModel>
#include <QTableWidget>
#include <QTimer>
#include <QToolBar>
#include <QVBoxLayout>

#include <algorithm>
#include <optional>

namespace gbm {

namespace {

/// Rows in the repository list are cheap to render but each probe costs a few
/// stats, so only what is on screen gets probed.
constexpr int kProbeMargin = 20;

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
    repoView_->verticalHeader()->setDefaultSectionSize(24);
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

    auto* bannerRow = new QWidget(repoPage);
    bannerRow->setStyleSheet(QStringLiteral("QWidget { background: #7a4d00; }"));
    auto* bannerLayout = new QHBoxLayout(bannerRow);
    bannerLayout->setContentsMargins(6, 4, 6, 4);

    bannerLabel_ = new QLabel(bannerRow);
    bannerLabel_->setVisible(false);
    bannerLabel_->setWordWrap(true);
    bannerLabel_->setAccessibleName(QStringLiteral("Repository state banner"));
    // Unmissable by design: a repository stuck mid-rebase must never look normal.
    bannerLabel_->setStyleSheet(QStringLiteral("QLabel { color: white; }"));
    bannerLayout->addWidget(bannerLabel_, 1);

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
    refView_->setAccessibleName(QStringLiteral("Branches and tags"));
    refView_->setModel(refModel_);
    refView_->setHeaderHidden(true);
    refView_->setUniformRowHeights(true);
    connect(refView_, &QTreeView::activated, this, &MainWindow::onRefActivated);
    refView_->setContextMenuPolicy(Qt::CustomContextMenu);
    connect(refView_,
            &QTreeView::customContextMenuRequested,
            this,
            &MainWindow::onRefContextMenuRequested);
    outerSplitter->addWidget(refView_);

    auto* rightSplitter = new QSplitter(Qt::Vertical, outerSplitter);

    commitModel_ = new CommitListModel(this);
    commitView_ = new QTableView(rightSplitter);
    commitView_->setAccessibleName(QStringLiteral("Commit history"));
    commitView_->setModel(commitModel_);
    commitView_->setSelectionBehavior(QAbstractItemView::SelectRows);
    commitView_->verticalHeader()->setVisible(false);
    // Uniform row heights plus per-pixel scrolling: both required for a virtualized
    // view to stay smooth across hundreds of thousands of rows.
    commitView_->verticalHeader()->setDefaultSectionSize(22);
    commitView_->verticalHeader()->setSectionResizeMode(QHeaderView::Fixed);
    commitView_->setVerticalScrollMode(QAbstractItemView::ScrollPerPixel);
    commitView_->setShowGrid(false);
    commitView_->setWordWrap(false);

    graphDelegate_ = new GraphColumnDelegate(commitModel_, this);
    commitView_->setItemDelegateForColumn(CommitListModel::ColumnGraph, graphDelegate_);
    commitView_->setColumnWidth(CommitListModel::ColumnGraph, 160);
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
    outerSplitter->addWidget(rightSplitter);
    outerSplitter->setStretchFactor(0, 1);
    outerSplitter->setStretchFactor(1, 5);

    repoLayout->addWidget(outerSplitter, 1);

    logView_ = new OperationLogView(repoPage);
    logView_->setMaximumHeight(160);
    logView_->setVisible(false);
    repoLayout->addWidget(logView_);

    stack_->addWidget(repoPage);

    // --- page 2: working copy -------------------------------------------------
    workingCopyView_ = new WorkingCopyView(this);
    connect(workingCopyView_, &WorkingCopyView::statusMessage, this, [this](const QString& text) {
        statusLabel_->setText(text);
    });
    connect(workingCopyView_,
            &WorkingCopyView::errorOccurred,
            this,
            [this](const QString& summary, const GitError& error) { showError(summary, error); });
    stack_->addWidget(workingCopyView_);

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
    auto* fileMenu = menuBar()->addMenu(QStringLiteral("&File"));
    fileMenu->addAction(QStringLiteral("Add base folder…"), this, &MainWindow::onAddBaseFolder);
    fileMenu->addAction(
        QStringLiteral("Manage base folders…"), this, &MainWindow::onManageBaseFolders);
    fileMenu->addSeparator();
    auto* closeAction =
        fileMenu->addAction(QStringLiteral("Close repository"), this, &MainWindow::closeRepository);
    closeAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+W")));
    fileMenu->addAction(QStringLiteral("Quit"), QApplication::instance(), &QApplication::quit);

    auto* viewMenu = menuBar()->addMenu(QStringLiteral("&View"));
    auto* refreshAction =
        viewMenu->addAction(QStringLiteral("Refresh"), this, &MainWindow::onRefresh);
    refreshAction->setShortcut(QKeySequence(Qt::Key_F5));
    auto* forceAction = viewMenu->addAction(
        QStringLiteral("Refresh (rescan everything)"), this, &MainWindow::onForceRefresh);
    forceAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+F5")));
    viewMenu->addAction(QStringLiteral("Cancel scan"), this, &MainWindow::onCancelScan);
    viewMenu->addSeparator();
    auto* logAction = viewMenu->addAction(QStringLiteral("Operation log"));
    logAction->setCheckable(true);
    logAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+L")));
    connect(logAction, &QAction::toggled, this, [this](bool visible) {
        logView_->setVisible(visible);
    });
    viewMenu->addSeparator();
    auto* themeMenu = viewMenu->addMenu(QStringLiteral("Theme"));
    auto* themeGroup = new QActionGroup(this);
    themeGroup->setExclusive(true);
    const Theme currentTheme = ThemeManager::loadSetting();
    for (Theme theme : {Theme::System, Theme::Light, Theme::Dark}) {
        QAction* action = themeMenu->addAction(ThemeManager::label(theme));
        action->setCheckable(true);
        action->setChecked(theme == currentTheme);
        themeGroup->addAction(action);
        connect(action, &QAction::triggered, this, [theme] {
            ThemeManager::apply(theme);
            ThemeManager::saveSetting(theme);
        });
    }

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

    auto* repoMenu = menuBar()->addMenu(QStringLiteral("Reposi&tory"));
    undoAction_ = repoMenu->addAction(
        QStringLiteral("Undo last operation"), this, &MainWindow::onUndoLastOperation);
    undoAction_->setEnabled(false);
    repoMenu->addSeparator();
    repoMenu->addAction(QStringLiteral("Reflog…"), this, &MainWindow::onShowReflog);
    repoMenu->addSeparator();
    repoMenu->addAction(
        QStringLiteral("Clean untracked files…"), this, &MainWindow::onCleanUntracked);

    auto* historyAction =
        viewMenu->addAction(QStringLiteral("History"), this, &MainWindow::onShowHistory);
    historyAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+1")));
    auto* workingCopyAction =
        viewMenu->addAction(QStringLiteral("Working Copy"), this, &MainWindow::onShowWorkingCopy);
    workingCopyAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+2")));

    auto* remoteMenu = menuBar()->addMenu(QStringLiteral("Re&mote"));
    auto* fetchAction = remoteMenu->addAction(QStringLiteral("Fetch"), this, &MainWindow::onFetch);
    fetchAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+F")));
    remoteMenu->addAction(
        QStringLiteral("Fetch (and prune stale remote branches)"), this, &MainWindow::onFetchPrune);
    auto* pullAction = remoteMenu->addAction(QStringLiteral("Pull"), this, &MainWindow::onPull);
    pullAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+L")));
    remoteMenu->addSeparator();
    auto* pushAction = remoteMenu->addAction(QStringLiteral("Push"), this, &MainWindow::onPush);
    pushAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+P")));
    remoteMenu->addAction(
        QStringLiteral("Push (set upstream)…"), this, &MainWindow::onPushSetUpstream);
    remoteMenu->addAction(
        QStringLiteral("Push (force-with-lease)…"), this, &MainWindow::onPushForceWithLease);

    auto* stashMenu = menuBar()->addMenu(QStringLiteral("&Stash"));
    stashMenu->addAction(QStringLiteral("Stash changes…"), this, &MainWindow::onStashChanges);
    stashMenu->addAction(QStringLiteral("Manage stashes…"), this, &MainWindow::onManageStashes);

    auto* worktreeMenu = menuBar()->addMenu(QStringLiteral("&Worktree"));
    worktreeMenu->addAction(
        QStringLiteral("Manage worktrees…"), this, &MainWindow::onManageWorktrees);

    auto* submoduleMenu = menuBar()->addMenu(QStringLiteral("Sub&module"));
    submoduleMenu->addAction(
        QStringLiteral("Manage submodules…"), this, &MainWindow::onManageSubmodules);

    auto* bisectMenu = menuBar()->addMenu(QStringLiteral("&Bisect"));
    bisectMenu->addAction(QStringLiteral("Bisect…"), this, &MainWindow::onBisect);

    auto* lfsMenu = menuBar()->addMenu(QStringLiteral("&LFS"));
    lfsMenu->addAction(QStringLiteral("Manage LFS…"), this, &MainWindow::onManageLfs);

    auto* patchMenu = menuBar()->addMenu(QStringLiteral("&Patch"));
    patchMenu->addAction(QStringLiteral("Export selected commits as patches…"),
                         this,
                         &MainWindow::onExportPatches);
    patchMenu->addSeparator();
    patchMenu->addAction(QStringLiteral("Apply patch file…"), this, &MainWindow::onApplyPatchFile);
    patchMenu->addAction(
        QStringLiteral("Import patches (git am)…"), this, &MainWindow::onImportPatches);

    auto* toolBar = addToolBar(QStringLiteral("Main"));
    toolBar->setMovable(false);
    toolBar->addAction(refreshAction);
    toolBar->addAction(
        QStringLiteral("Repositories"), this, [this] { stack_->setCurrentIndex(0); });
    toolBar->addAction(historyAction);
    toolBar->addAction(workingCopyAction);
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
    QDialog dialog(this);
    dialog.setWindowTitle(QStringLiteral("Manage base folders"));
    auto* layout = new QVBoxLayout(&dialog);

    auto* table = new QTableWidget(&dialog);
    table->setColumnCount(3);
    table->setHorizontalHeaderLabels(
        {QStringLiteral("Path"), QStringLiteral("Depth"), QStringLiteral("Enabled")});
    table->horizontalHeader()->setSectionResizeMode(0, QHeaderView::Stretch);
    table->setSelectionBehavior(QAbstractItemView::SelectRows);
    table->setSelectionMode(QAbstractItemView::SingleSelection);
    table->setEditTriggers(QAbstractItemView::NoEditTriggers);
    table->verticalHeader()->setVisible(false);

    // A local copy: edits below go through DiscoveryController and update this
    // copy and the table in lockstep, so row indices stay valid without a
    // round-trip to the database after every click.
    std::vector<BaseFolderRecord> folders = discovery_->baseFolders();
    table->setRowCount(static_cast<int>(folders.size()));
    for (int row = 0; row < static_cast<int>(folders.size()); ++row) {
        const BaseFolderRecord& folder = folders[static_cast<std::size_t>(row)];
        table->setItem(row, 0, new QTableWidgetItem(QString::fromStdString(folder.path)));
        table->setItem(row, 1, new QTableWidgetItem(QString::number(folder.maxDepth)));
        table->setItem(
            row,
            2,
            new QTableWidgetItem(folder.enabled ? QStringLiteral("yes") : QStringLiteral("no")));
    }
    layout->addWidget(table);

    auto* buttonRow = new QHBoxLayout();
    auto* editDepthButton = new QPushButton(QStringLiteral("Change depth…"), &dialog);
    auto* removeButton = new QPushButton(QStringLiteral("Remove"), &dialog);
    auto* closeButton = new QPushButton(QStringLiteral("Close"), &dialog);
    buttonRow->addWidget(editDepthButton);
    buttonRow->addWidget(removeButton);
    buttonRow->addStretch(1);
    buttonRow->addWidget(closeButton);
    layout->addLayout(buttonRow);

    // Whether anything changed while the dialog was open, so it is only worth
    // rescanning once, on close, rather than after every click.
    bool changed = false;

    connect(editDepthButton, &QPushButton::clicked, &dialog, [&] {
        const int row = table->currentRow();
        if (row < 0) {
            return;
        }
        const BaseFolderRecord& folder = folders[static_cast<std::size_t>(row)];
        bool accepted = false;
        const int depth =
            QInputDialog::getInt(&dialog,
                                 QStringLiteral("Scan depth"),
                                 QStringLiteral("How many levels below \"%1\" should be scanned?")
                                     .arg(QString::fromStdString(folder.path)),
                                 folder.maxDepth,
                                 0,
                                 10,
                                 1,
                                 &accepted);
        if (!accepted) {
            return;
        }
        if (auto result = discovery_->setBaseFolderDepth(folder.id, depth); !result) {
            showError(QStringLiteral("Could not change the scan depth"), result.error());
            return;
        }
        table->item(row, 1)->setText(QString::number(depth));
        changed = true;
    });

    connect(removeButton, &QPushButton::clicked, &dialog, [&] {
        const int row = table->currentRow();
        if (row < 0) {
            return;
        }
        const BaseFolderRecord& folder = folders[static_cast<std::size_t>(row)];
        if (auto result = discovery_->removeBaseFolder(folder.id); !result) {
            showError(QStringLiteral("Could not remove that folder"), result.error());
            return;
        }
        table->removeRow(row);
        folders.erase(folders.begin() + row);
        changed = true;
    });

    connect(closeButton, &QPushButton::clicked, &dialog, &QDialog::accept);

    dialog.resize(560, 320);
    dialog.exec();

    if (changed) {
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
    }
}

void MainWindow::onShowWorkingCopy() {
    if (!session_) {
        return;
    }
    stack_->setCurrentIndex(2);
    // The working-copy panel can go stale while the user is elsewhere -- a
    // checkout, for instance, does not refresh it -- so ask for a fresh read
    // on every visit rather than trying to track every place that could.
    session_->refreshWorkingCopyStatus();
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
        refView_->expandToDepth(0);
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

    commitModel_->setSession(session_.get());
    diffView_->clearDiff();
    workingCopyView_->setSession(session_.get());

    setWindowTitle(QStringLiteral("%1 — git-branch-manager").arg(session_->displayName()));
    stack_->setCurrentIndex(1);
    updateStateBanner();

    // Refs first, so the history walk can be seeded with HEAD and the trunk; that
    // seeding order is what puts the trunk in lane 0.
    session_->refreshRefs();
    session_->refreshHistory();
    // So the remote picker in the Push/Push tag dialogs has something to show
    // the first time they are opened, without waiting on a Fetch.
    session_->refreshRemotes();
}

void MainWindow::closeRepository() {
    if (!session_) {
        return;
    }
    session_->cancelPendingReads();
    commitModel_->setSession(nullptr);
    refModel_->setRefs(nullptr);
    diffView_->clearDiff();
    workingCopyView_->setSession(nullptr);
    session_.reset();
    setWindowTitle(QStringLiteral("git-branch-manager"));
    stack_->setCurrentIndex(0);
    bannerLabel_->parentWidget()->setVisible(false);
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
            const QModelIndexList selected = refView_->selectionModel()->selectedRows();
            if (selected.isEmpty()) {
                break;
            }
            CheckoutRequest retry;
            retry.target = refModel_->refNameAt(selected.first()).toStdString();

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

    QDialog dialog(this);
    dialog.setWindowTitle(QStringLiteral("Merge"));
    auto* layout = new QVBoxLayout(&dialog);
    layout->addWidget(
        new QLabel(QStringLiteral("Merge \"%1\" into the current branch:").arg(name), &dialog));

    auto* ffOnly = new QRadioButton(QStringLiteral("Fast-forward only"), &dialog);
    auto* noFf =
        new QRadioButton(QStringLiteral("Create a merge commit (no fast-forward)"), &dialog);
    auto* squash =
        new QRadioButton(QStringLiteral("Squash (stage the changes, no commit)"), &dialog);
    noFf->setChecked(true);
    layout->addWidget(ffOnly);
    layout->addWidget(noFf);
    layout->addWidget(squash);

    auto* messageEdit = new QLineEdit(&dialog);
    messageEdit->setPlaceholderText(
        QStringLiteral("Merge commit message (used only when creating a merge commit)"));
    layout->addWidget(messageEdit);

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dialog);
    layout->addWidget(buttons);
    connect(buttons, &QDialogButtonBox::accepted, &dialog, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);

    if (dialog.exec() != QDialog::Accepted) {
        return;
    }

    MergeRequest request;
    request.target = name.toStdString();
    request.mode = squash->isChecked()   ? MergeMode::Squash
                   : ffOnly->isChecked() ? MergeMode::FastForwardOnly
                                         : MergeMode::NoFastForward;
    request.message = messageEdit->text().toStdString();

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

    QDialog dialog(this);
    dialog.setWindowTitle(QStringLiteral("Cherry-pick"));
    auto* layout = new QVBoxLayout(&dialog);
    layout->addWidget(new QLabel(
        commits.size() == 1
            ? QStringLiteral("Cherry-pick this commit onto the current branch:")
            : QStringLiteral("Cherry-pick these %1 commits onto the current branch, oldest first:")
                  .arg(commits.size()),
        &dialog));

    auto* list = new QListWidget(&dialog);
    list->setSelectionMode(QAbstractItemView::NoSelection);
    for (int i = 0; i < subjects.size(); ++i) {
        new QListWidgetItem(
            QString::fromStdString(commits[static_cast<std::size_t>(i)].shortHex()) +
                QStringLiteral("  ") + subjects[i],
            list);
    }
    layout->addWidget(list);

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dialog);
    layout->addWidget(buttons);
    connect(buttons, &QDialogButtonBox::accepted, &dialog, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    dialog.resize(480, 320);

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

    QDialog dialog(this);
    dialog.setWindowTitle(QStringLiteral("Stash changes"));
    auto* layout = new QVBoxLayout(&dialog);

    auto* messageEdit = new QLineEdit(&dialog);
    messageEdit->setPlaceholderText(QStringLiteral("Stash message (optional)"));
    layout->addWidget(messageEdit);
    auto* includeUntracked = new QCheckBox(QStringLiteral("Include untracked files"), &dialog);
    layout->addWidget(includeUntracked);

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dialog);
    layout->addWidget(buttons);
    connect(buttons, &QDialogButtonBox::accepted, &dialog, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);

    if (dialog.exec() != QDialog::Accepted) {
        return;
    }

    StashSaveRequest request;
    request.message = messageEdit->text().toStdString();
    request.includeUntracked = includeUntracked->isChecked();

    statusLabel_->setText(QStringLiteral("Stashing changes…"));
    runWithFeedback([this, request] { session_->saveStash(request); });
}

void MainWindow::onManageStashes() {
    if (!session_) {
        return;
    }

    QDialog dialog(this);
    dialog.setWindowTitle(QStringLiteral("Manage stashes"));
    auto* layout = new QVBoxLayout(&dialog);

    auto* list = new QListWidget(&dialog);
    layout->addWidget(list, 1);

    auto reload = [this, list] {
        list->clear();
        if (auto stashes = session_->stashes()) {
            for (const StashEntry& entry : *stashes) {
                auto* item = new QListWidgetItem(QStringLiteral("stash@{%1}  %2")
                                                     .arg(entry.index)
                                                     .arg(QString::fromStdString(entry.message)),
                                                 list);
                item->setData(Qt::UserRole, entry.index);
            }
        }
    };
    // Scoped to the dialog: a stash operation finishing after it closes must
    // not touch a destroyed list widget.
    connect(session_.get(), &RepositorySession::stashesUpdated, &dialog, reload);
    session_->refreshStashes();
    reload();

    auto selectedIndex = [list]() -> std::optional<int> {
        const auto items = list->selectedItems();
        if (items.isEmpty()) {
            return std::nullopt;
        }
        return items.first()->data(Qt::UserRole).toInt();
    };

    auto* buttonRow = new QHBoxLayout();
    auto* applyButton = new QPushButton(QStringLiteral("Apply"), &dialog);
    auto* popButton = new QPushButton(QStringLiteral("Pop"), &dialog);
    auto* dropButton = new QPushButton(QStringLiteral("Drop"), &dialog);
    auto* branchButton = new QPushButton(QStringLiteral("Create branch…"), &dialog);
    auto* closeButton = new QPushButton(QStringLiteral("Close"), &dialog);
    buttonRow->addWidget(applyButton);
    buttonRow->addWidget(popButton);
    buttonRow->addWidget(dropButton);
    buttonRow->addWidget(branchButton);
    buttonRow->addStretch(1);
    buttonRow->addWidget(closeButton);
    layout->addLayout(buttonRow);

    connect(applyButton, &QPushButton::clicked, &dialog, [this, selectedIndex] {
        if (auto index = selectedIndex()) {
            StashApplyRequest request;
            request.index = *index;
            runWithFeedback([this, request] { session_->applyStash(request); });
        }
    });
    connect(popButton, &QPushButton::clicked, &dialog, [this, selectedIndex] {
        if (auto index = selectedIndex()) {
            StashApplyRequest request;
            request.index = *index;
            request.pop = true;
            runWithFeedback([this, request] { session_->applyStash(request); });
        }
    });
    connect(dropButton, &QPushButton::clicked, &dialog, [this, selectedIndex, &dialog] {
        auto index = selectedIndex();
        if (!index) {
            return;
        }
        const auto confirmed = QMessageBox::warning(&dialog,
                                                    QStringLiteral("Drop stash?"),
                                                    QStringLiteral("This permanently deletes "
                                                                   "stash@{%1}.")
                                                        .arg(*index),
                                                    QMessageBox::Discard | QMessageBox::Cancel,
                                                    QMessageBox::Cancel);
        if (confirmed != QMessageBox::Discard) {
            return;
        }
        StashDropRequest request;
        request.index = *index;
        runWithFeedback([this, request] { session_->dropStash(request); });
    });
    connect(branchButton, &QPushButton::clicked, &dialog, [this, selectedIndex, &dialog] {
        auto index = selectedIndex();
        if (!index) {
            return;
        }
        bool ok = false;
        const QString name = QInputDialog::getText(&dialog,
                                                   QStringLiteral("Create branch from stash"),
                                                   QStringLiteral("Branch name:"),
                                                   QLineEdit::Normal,
                                                   QString(),
                                                   &ok);
        if (!ok || name.isEmpty()) {
            return;
        }
        StashBranchRequest request;
        request.index = *index;
        request.branchName = name.toStdString();
        runWithFeedback([this, request] { session_->branchFromStash(request); });
    });
    connect(closeButton, &QPushButton::clicked, &dialog, &QDialog::accept);

    dialog.resize(480, 360);
    dialog.exec();
}

// --- M3: worktrees ---------------------------------------------------------

void MainWindow::onManageWorktrees() {
    if (!session_) {
        return;
    }

    QDialog dialog(this);
    dialog.setWindowTitle(QStringLiteral("Manage worktrees"));
    auto* layout = new QVBoxLayout(&dialog);

    auto* table = new QTableWidget(&dialog);
    table->setColumnCount(3);
    table->setHorizontalHeaderLabels(
        {QStringLiteral("Path"), QStringLiteral("Branch"), QStringLiteral("Status")});
    table->horizontalHeader()->setSectionResizeMode(0, QHeaderView::Stretch);
    table->setSelectionBehavior(QAbstractItemView::SelectRows);
    table->setSelectionMode(QAbstractItemView::SingleSelection);
    table->setEditTriggers(QAbstractItemView::NoEditTriggers);
    table->verticalHeader()->setVisible(false);
    layout->addWidget(table, 1);

    auto reload = [this, table] {
        auto worktrees = session_->worktrees();
        table->setRowCount(0);
        if (!worktrees) {
            return;
        }
        table->setRowCount(static_cast<int>(worktrees->size()));
        for (int row = 0; row < static_cast<int>(worktrees->size()); ++row) {
            const WorktreeInfo& info = (*worktrees)[static_cast<std::size_t>(row)];
            table->setItem(
                row, 0, new QTableWidgetItem(QString::fromStdString(info.path.string())));
            const QString branch = info.isBare       ? QStringLiteral("(bare)")
                                   : info.isDetached ? QStringLiteral("(detached)")
                                                     : QString::fromStdString(info.branch);
            table->setItem(row, 1, new QTableWidgetItem(branch));
            QStringList status;
            if (info.isMain) {
                status << QStringLiteral("main");
            }
            if (info.isLocked) {
                status << QStringLiteral("locked");
            }
            if (info.isPrunable) {
                status << QStringLiteral("prunable");
            }
            table->setItem(row, 2, new QTableWidgetItem(status.join(QStringLiteral(", "))));
        }
    };
    connect(session_.get(), &RepositorySession::worktreesUpdated, &dialog, reload);
    session_->refreshWorktrees();
    reload();

    auto selectedInfo = [this, table]() -> std::optional<WorktreeInfo> {
        const int row = table->currentRow();
        auto worktrees = session_->worktrees();
        if (row < 0 || !worktrees || row >= static_cast<int>(worktrees->size())) {
            return std::nullopt;
        }
        return (*worktrees)[static_cast<std::size_t>(row)];
    };

    auto* buttonRow = new QHBoxLayout();
    auto* addButton = new QPushButton(QStringLiteral("Add…"), &dialog);
    auto* removeButton = new QPushButton(QStringLiteral("Remove"), &dialog);
    auto* lockButton = new QPushButton(QStringLiteral("Lock…"), &dialog);
    auto* unlockButton = new QPushButton(QStringLiteral("Unlock"), &dialog);
    auto* pruneButton = new QPushButton(QStringLiteral("Prune stale"), &dialog);
    auto* closeButton = new QPushButton(QStringLiteral("Close"), &dialog);
    buttonRow->addWidget(addButton);
    buttonRow->addWidget(removeButton);
    buttonRow->addWidget(lockButton);
    buttonRow->addWidget(unlockButton);
    buttonRow->addWidget(pruneButton);
    buttonRow->addStretch(1);
    buttonRow->addWidget(closeButton);
    layout->addLayout(buttonRow);

    connect(addButton, &QPushButton::clicked, &dialog, [this, &dialog] {
        const QString parentDir = QFileDialog::getExistingDirectory(
            &dialog, QStringLiteral("Choose a parent folder for the new worktree"));
        if (parentDir.isEmpty()) {
            return;
        }
        bool ok = false;
        const QString folderName = QInputDialog::getText(&dialog,
                                                         QStringLiteral("New worktree"),
                                                         QStringLiteral("Folder name:"),
                                                         QLineEdit::Normal,
                                                         QString(),
                                                         &ok);
        if (!ok || folderName.isEmpty()) {
            return;
        }

        QStringList branchNames;
        if (const RefSnapshotPtr refs = session_->refs()) {
            for (const RefInfo* ref : refs->ofKind(RefKind::LocalBranch)) {
                branchNames << QString::fromStdString(ref->shortName);
            }
        }
        QString branch;
        if (!branchNames.isEmpty()) {
            bool branchOk = false;
            branch = QInputDialog::getItem(&dialog,
                                           QStringLiteral("New worktree"),
                                           QStringLiteral("Branch:"),
                                           branchNames,
                                           0,
                                           false,
                                           &branchOk);
            if (!branchOk) {
                return;
            }
        }

        AddWorktreeRequest request;
        request.path = std::filesystem::path(QDir(parentDir).filePath(folderName).toStdString());
        request.branch = branch.toStdString();
        runWithFeedback([this, request] { session_->addWorktree(request); });
    });

    connect(removeButton, &QPushButton::clicked, &dialog, [this, selectedInfo, &dialog] {
        auto info = selectedInfo();
        if (!info) {
            return;
        }
        if (info->isMain) {
            QMessageBox::information(&dialog,
                                     QStringLiteral("Cannot remove"),
                                     QStringLiteral("The main worktree cannot be removed."));
            return;
        }
        const auto confirmed =
            QMessageBox::warning(&dialog,
                                 QStringLiteral("Remove worktree?"),
                                 QStringLiteral("Remove the worktree at \"%1\"?")
                                     .arg(QString::fromStdString(info->path.string())),
                                 QMessageBox::Yes | QMessageBox::Cancel,
                                 QMessageBox::Cancel);
        if (confirmed != QMessageBox::Yes) {
            return;
        }
        const std::filesystem::path path = info->path;
        runWithFeedback(
            [this, path] {
                RemoveWorktreeRequest request;
                request.path = path;
                session_->removeWorktree(request);
            },
            [this, path](OperationChoice::Kind kind) {
                if (kind == OperationChoice::Kind::ForceDiscard) {
                    RemoveWorktreeRequest request;
                    request.path = path;
                    request.force = true;
                    session_->removeWorktree(request);
                }
            });
    });

    connect(lockButton, &QPushButton::clicked, &dialog, [this, selectedInfo, &dialog] {
        auto info = selectedInfo();
        if (!info) {
            return;
        }
        bool ok = false;
        const QString reason = QInputDialog::getText(&dialog,
                                                     QStringLiteral("Lock worktree"),
                                                     QStringLiteral("Reason (optional):"),
                                                     QLineEdit::Normal,
                                                     QString(),
                                                     &ok);
        if (!ok) {
            return;
        }
        LockWorktreeRequest request;
        request.path = info->path;
        request.reason = reason.toStdString();
        runWithFeedback([this, request] { session_->lockWorktree(request); });
    });

    connect(unlockButton, &QPushButton::clicked, &dialog, [this, selectedInfo] {
        auto info = selectedInfo();
        if (!info) {
            return;
        }
        UnlockWorktreeRequest request;
        request.path = info->path;
        runWithFeedback([this, request] { session_->unlockWorktree(request); });
    });

    connect(pruneButton, &QPushButton::clicked, &dialog, [this] {
        runWithFeedback([this] { session_->pruneWorktrees(); });
    });

    connect(closeButton, &QPushButton::clicked, &dialog, &QDialog::accept);

    dialog.resize(640, 360);
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

void MainWindow::onRefContextMenuRequested(const QPoint& pos) {
    if (!session_) {
        return;
    }
    const QModelIndex index = refView_->indexAt(pos);
    const bool onTag =
        index.isValid() && refModel_->data(index, RefTreeModel::IsRefRole).toBool() &&
        refModel_->data(index, RefTreeModel::RefKindRole).toInt() == static_cast<int>(RefKind::Tag);
    const QString tagName = onTag ? refModel_->refNameAt(index) : QString();

    QMenu menu(this);
    QAction* newTagAction = menu.addAction(QStringLiteral("New tag…"));
    QAction* deleteTagAction = nullptr;
    QAction* pushTagAction = nullptr;
    if (onTag) {
        menu.addSeparator();
        deleteTagAction = menu.addAction(QStringLiteral("Delete tag \"%1\"").arg(tagName));
        pushTagAction = menu.addAction(QStringLiteral("Push tag \"%1\"…").arg(tagName));
    }

    QAction* chosen = menu.exec(refView_->viewport()->mapToGlobal(pos));
    if (chosen == nullptr) {
        return;
    }

    if (chosen == newTagAction) {
        onNewTag();
        return;
    }
    if (chosen == deleteTagAction) {
        const auto confirmed =
            QMessageBox::warning(this,
                                 QStringLiteral("Delete tag?"),
                                 QStringLiteral("Delete tag \"%1\"?").arg(tagName),
                                 QMessageBox::Yes | QMessageBox::Cancel,
                                 QMessageBox::Cancel);
        if (confirmed != QMessageBox::Yes) {
            return;
        }
        DeleteTagRequest request;
        request.name = tagName.toStdString();
        runWithFeedback([this, request] { session_->deleteTag(request); });
        return;
    }
    if (chosen == pushTagAction) {
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
            this, QStringLiteral("Push tag"), QStringLiteral("Remote:"), names, 0, false, &ok);
        if (!ok || remote.isEmpty()) {
            return;
        }
        PushTagRequest request;
        request.remoteName = remote.toStdString();
        request.name = tagName.toStdString();
        statusLabel_->setText(QStringLiteral("Pushing tag %1…").arg(tagName));
        runWithFeedback([this, request] { session_->pushTag(request); });
    }
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

    QDialog dialog(this);
    dialog.setWindowTitle(QStringLiteral("Reset branch"));
    auto* layout = new QVBoxLayout(&dialog);
    layout->addWidget(new QLabel(QStringLiteral("Reset the current branch to %1:")
                                     .arg(QString::fromStdString(target.shortHex())),
                                 &dialog));

    auto* soft = new QRadioButton(QStringLiteral("Soft (keep the index and work tree)"), &dialog);
    auto* mixed =
        new QRadioButton(QStringLiteral("Mixed (keep the work tree, unstage everything)"), &dialog);
    auto* hard = new QRadioButton(
        QStringLiteral("Hard (discard the index and work tree — destructive)"), &dialog);
    mixed->setChecked(true);
    layout->addWidget(soft);
    layout->addWidget(mixed);
    layout->addWidget(hard);

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dialog);
    layout->addWidget(buttons);
    connect(buttons, &QDialogButtonBox::accepted, &dialog, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);

    if (dialog.exec() != QDialog::Accepted) {
        return;
    }

    const ResetMode mode = soft->isChecked()   ? ResetMode::Soft
                           : hard->isChecked() ? ResetMode::Hard
                                               : ResetMode::Mixed;
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

    QDialog dialog(this);
    dialog.setWindowTitle(QStringLiteral("Interactive rebase"));
    auto* layout = new QVBoxLayout(&dialog);
    layout->addWidget(new QLabel(QStringLiteral("Commits to replay onto %1, oldest first:")
                                     .arg(QString::fromStdString(upstream.shortHex())),
                                 &dialog));

    auto* table = new QTableWidget(&dialog);
    table->setColumnCount(3);
    table->setHorizontalHeaderLabels(
        {QStringLiteral("Action"), QStringLiteral("Commit"), QStringLiteral("Subject")});
    table->horizontalHeader()->setSectionResizeMode(2, QHeaderView::Stretch);
    table->setSelectionBehavior(QAbstractItemView::SelectRows);
    table->setSelectionMode(QAbstractItemView::SingleSelection);
    table->setEditTriggers(QAbstractItemView::NoEditTriggers);
    table->verticalHeader()->setVisible(false);
    layout->addWidget(table, 1);

    // Shared with every lambda below rather than read back from the table
    // widget: the combo boxes are the only place the action lives once edited,
    // but reordering rebuilds the whole table, so the todo list itself is the
    // one source of truth.
    auto todo = std::make_shared<std::vector<RebaseTodoEntry>>();

    auto actionLabel = [](RebaseTodoEntry::Action action) {
        switch (action) {
            case RebaseTodoEntry::Action::Pick:
                return QStringLiteral("pick");
            case RebaseTodoEntry::Action::Edit:
                return QStringLiteral("edit");
            case RebaseTodoEntry::Action::Squash:
                return QStringLiteral("squash");
            case RebaseTodoEntry::Action::Fixup:
                return QStringLiteral("fixup");
            case RebaseTodoEntry::Action::Drop:
                return QStringLiteral("drop");
        }
        return QStringLiteral("pick");
    };
    auto actionFromLabel = [](const QString& text) {
        if (text == QStringLiteral("edit")) {
            return RebaseTodoEntry::Action::Edit;
        }
        if (text == QStringLiteral("squash")) {
            return RebaseTodoEntry::Action::Squash;
        }
        if (text == QStringLiteral("fixup")) {
            return RebaseTodoEntry::Action::Fixup;
        }
        if (text == QStringLiteral("drop")) {
            return RebaseTodoEntry::Action::Drop;
        }
        return RebaseTodoEntry::Action::Pick;
    };

    std::function<void()> refreshTable = [table, todo, actionLabel, actionFromLabel] {
        table->setRowCount(static_cast<int>(todo->size()));
        for (int row = 0; row < static_cast<int>(todo->size()); ++row) {
            const RebaseTodoEntry& entry = (*todo)[static_cast<std::size_t>(row)];
            auto* combo = new QComboBox(table);
            combo->addItems({QStringLiteral("pick"),
                             QStringLiteral("edit"),
                             QStringLiteral("squash"),
                             QStringLiteral("fixup"),
                             QStringLiteral("drop")});
            combo->setCurrentText(actionLabel(entry.action));
            QObject::connect(combo,
                             &QComboBox::currentTextChanged,
                             table,
                             [todo, row, actionFromLabel](const QString& text) {
                                 (*todo)[static_cast<std::size_t>(row)].action =
                                     actionFromLabel(text);
                             });
            table->setCellWidget(row, 0, combo);
            table->setItem(row, 1, new QTableWidgetItem(QString::fromStdString(entry.shortOid)));
            table->setItem(row, 2, new QTableWidgetItem(QString::fromStdString(entry.subject)));
        }
    };

    connect(session_.get(),
            &RepositorySession::rebasePlanReady,
            &dialog,
            [todo, refreshTable](std::vector<RebaseTodoEntry> entries) {
                *todo = std::move(entries);
                refreshTable();
            });
    session_->requestRebasePlan(upstream.hex());

    auto* upButton = new QPushButton(QStringLiteral("Move Up"), &dialog);
    auto* downButton = new QPushButton(QStringLiteral("Move Down"), &dialog);
    connect(upButton, &QPushButton::clicked, &dialog, [table, todo, refreshTable] {
        const int row = table->currentRow();
        if (row <= 0) {
            return;
        }
        std::swap((*todo)[static_cast<std::size_t>(row)],
                  (*todo)[static_cast<std::size_t>(row - 1)]);
        refreshTable();
        table->selectRow(row - 1);
    });
    connect(downButton, &QPushButton::clicked, &dialog, [table, todo, refreshTable] {
        const int row = table->currentRow();
        if (row < 0 || row + 1 >= static_cast<int>(todo->size())) {
            return;
        }
        std::swap((*todo)[static_cast<std::size_t>(row)],
                  (*todo)[static_cast<std::size_t>(row + 1)]);
        refreshTable();
        table->selectRow(row + 1);
    });
    auto* moveRow = new QHBoxLayout();
    moveRow->addWidget(upButton);
    moveRow->addWidget(downButton);
    moveRow->addStretch(1);
    layout->addLayout(moveRow);

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &dialog);
    buttons->button(QDialogButtonBox::Ok)->setText(QStringLiteral("Start Rebase"));
    layout->addWidget(buttons);
    connect(buttons, &QDialogButtonBox::accepted, &dialog, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);

    dialog.resize(560, 420);
    if (dialog.exec() != QDialog::Accepted || todo->empty()) {
        return;
    }

    RebaseInteractiveRequest request;
    request.upstream = upstream.hex();
    request.todo = *todo;
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

    QDialog dialog(this);
    dialog.setWindowTitle(QStringLiteral("Clean untracked files"));
    auto* layout = new QVBoxLayout(&dialog);

    auto* includeIgnored = new QCheckBox(QStringLiteral("Also remove ignored files"), &dialog);
    layout->addWidget(includeIgnored);

    auto* list = new QListWidget(&dialog);
    layout->addWidget(list, 1);

    connect(session_.get(),
            &RepositorySession::cleanPreviewReady,
            &dialog,
            [list](std::vector<CleanEntry> entries) {
                list->clear();
                for (const CleanEntry& entry : entries) {
                    auto* item = new QListWidgetItem(
                        QString::fromStdString(entry.path) +
                            (entry.isDirectory ? QStringLiteral("/") : QString()),
                        list);
                    item->setFlags(item->flags() | Qt::ItemIsUserCheckable);
                    item->setCheckState(Qt::Checked);
                    item->setData(Qt::UserRole, QString::fromStdString(entry.path));
                }
            });
    auto reload = [this, includeIgnored] {
        session_->requestCleanPreview(includeIgnored->isChecked());
    };
    connect(includeIgnored, &QCheckBox::toggled, &dialog, [reload](bool) { reload(); });
    reload();

    auto* buttonRow = new QHBoxLayout();
    auto* removeButton = new QPushButton(QStringLiteral("Remove"), &dialog);
    auto* closeButton = new QPushButton(QStringLiteral("Close"), &dialog);
    buttonRow->addStretch(1);
    buttonRow->addWidget(removeButton);
    buttonRow->addWidget(closeButton);
    layout->addLayout(buttonRow);

    connect(removeButton, &QPushButton::clicked, &dialog, [this, list, includeIgnored, &dialog] {
        std::vector<std::string> paths;
        for (int i = 0; i < list->count(); ++i) {
            auto* item = list->item(i);
            if (item->checkState() == Qt::Checked) {
                paths.push_back(item->data(Qt::UserRole).toString().toStdString());
            }
        }
        if (paths.empty()) {
            return;
        }
        const auto confirmed =
            QMessageBox::warning(&dialog,
                                 QStringLiteral("Remove untracked files?"),
                                 QStringLiteral("This permanently deletes %1 item(s). This "
                                                "cannot be undone.")
                                     .arg(paths.size()),
                                 QMessageBox::Discard | QMessageBox::Cancel,
                                 QMessageBox::Cancel);
        if (confirmed != QMessageBox::Discard) {
            return;
        }
        CleanRequest request;
        request.paths = paths;
        request.includeIgnored = includeIgnored->isChecked();
        runWithFeedback([this, request] { session_->cleanUntracked(request); });
        dialog.accept();
    });
    connect(closeButton, &QPushButton::clicked, &dialog, &QDialog::accept);

    dialog.resize(480, 400);
    dialog.exec();
}

// --- M4: reflog and undo -----------------------------------------------------

void MainWindow::onShowReflog() {
    if (!session_) {
        return;
    }

    QDialog dialog(this);
    dialog.setWindowTitle(QStringLiteral("Reflog"));
    auto* layout = new QVBoxLayout(&dialog);

    auto* table = new QTableWidget(&dialog);
    table->setColumnCount(3);
    table->setHorizontalHeaderLabels(
        {QStringLiteral("Commit"), QStringLiteral("When"), QStringLiteral("Action")});
    table->horizontalHeader()->setSectionResizeMode(2, QHeaderView::Stretch);
    table->setSelectionBehavior(QAbstractItemView::SelectRows);
    table->setSelectionMode(QAbstractItemView::SingleSelection);
    table->setEditTriggers(QAbstractItemView::NoEditTriggers);
    table->verticalHeader()->setVisible(false);
    layout->addWidget(table, 1);

    connect(
        session_.get(),
        &RepositorySession::reflogReady,
        &dialog,
        [table](std::vector<ReflogEntry> entries) {
            table->setRowCount(static_cast<int>(entries.size()));
            for (int row = 0; row < static_cast<int>(entries.size()); ++row) {
                const ReflogEntry& entry = entries[static_cast<std::size_t>(row)];
                auto* oidItem = new QTableWidgetItem(QString::fromStdString(entry.oid.shortHex()));
                oidItem->setData(Qt::UserRole, QString::fromStdString(entry.oid.hex()));
                table->setItem(row, 0, oidItem);
                table->setItem(
                    row,
                    1,
                    new QTableWidgetItem(
                        QDateTime::fromSecsSinceEpoch(entry.who.when).toString(Qt::ISODate)));
                table->setItem(row, 2, new QTableWidgetItem(QString::fromStdString(entry.message)));
            }
        });
    session_->requestReflog("");

    auto* buttonRow = new QHBoxLayout();
    auto* resetButton = new QPushButton(QStringLiteral("Reset to here (hard)…"), &dialog);
    auto* closeButton = new QPushButton(QStringLiteral("Close"), &dialog);
    buttonRow->addStretch(1);
    buttonRow->addWidget(resetButton);
    buttonRow->addWidget(closeButton);
    layout->addLayout(buttonRow);

    connect(resetButton, &QPushButton::clicked, &dialog, [this, table, &dialog] {
        const auto selectedRows = table->selectionModel()->selectedRows();
        if (selectedRows.isEmpty()) {
            return;
        }
        const QString oid =
            table->item(selectedRows.first().row(), 0)->data(Qt::UserRole).toString();
        const auto confirmed =
            QMessageBox::warning(&dialog,
                                 QStringLiteral("Hard reset?"),
                                 QStringLiteral("This permanently discards uncommitted changes "
                                                "and moves the current branch to %1.")
                                     .arg(oid.left(10)),
                                 QMessageBox::Discard | QMessageBox::Cancel,
                                 QMessageBox::Cancel);
        if (confirmed != QMessageBox::Discard) {
            return;
        }
        ResetRequest request;
        request.target = oid.toStdString();
        request.mode = ResetMode::Hard;
        runWithFeedback([this, request] { session_->resetTo(request); });
        dialog.accept();
    });
    connect(closeButton, &QPushButton::clicked, &dialog, &QDialog::accept);

    dialog.resize(560, 420);
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
        *connection = connect(
            session_.get(),
            &RepositorySession::blameReady,
            this,
            [this, connection, path](BlameResultPtr result) {
                QObject::disconnect(*connection);
                if (!result) {
                    return;
                }
                QDialog dialog(this);
                dialog.setWindowTitle(QStringLiteral("Blame: %1").arg(path));
                auto* layout = new QVBoxLayout(&dialog);
                auto* table = new QTableWidget(&dialog);
                table->setColumnCount(4);
                table->setHorizontalHeaderLabels({QStringLiteral("Commit"),
                                                  QStringLiteral("Author"),
                                                  QStringLiteral("Line"),
                                                  QStringLiteral("Content")});
                table->horizontalHeader()->setSectionResizeMode(3, QHeaderView::Stretch);
                table->setEditTriggers(QAbstractItemView::NoEditTriggers);
                table->verticalHeader()->setVisible(false);
                table->setRowCount(static_cast<int>(result->lines.size()));
                for (int row = 0; row < static_cast<int>(result->lines.size()); ++row) {
                    const BlameLine& line = result->lines[static_cast<std::size_t>(row)];
                    table->setItem(
                        row,
                        0,
                        new QTableWidgetItem(QString::fromStdString(line.commitOid.shortHex())));
                    table->setItem(
                        row, 1, new QTableWidgetItem(QString::fromStdString(line.authorName)));
                    table->setItem(row, 2, new QTableWidgetItem(QString::number(line.finalLine)));
                    table->setItem(
                        row, 3, new QTableWidgetItem(QString::fromStdString(line.content)));
                }
                layout->addWidget(table);
                auto* closeButton = new QPushButton(QStringLiteral("Close"), &dialog);
                connect(closeButton, &QPushButton::clicked, &dialog, &QDialog::accept);
                layout->addWidget(closeButton);
                dialog.resize(720, 480);
                dialog.exec();
            });
        session_->requestBlame(stdPath, revision, 0, 0);
        return;
    }

    if (chosen == historyAction) {
        auto connection = std::make_shared<QMetaObject::Connection>();
        *connection = connect(
            session_.get(),
            &RepositorySession::fileHistoryReady,
            this,
            [this, connection, path](std::vector<FileHistoryEntry> entries) {
                QObject::disconnect(*connection);
                QDialog dialog(this);
                dialog.setWindowTitle(QStringLiteral("History: %1").arg(path));
                auto* layout = new QVBoxLayout(&dialog);
                auto* table = new QTableWidget(&dialog);
                table->setColumnCount(4);
                table->setHorizontalHeaderLabels({QStringLiteral("Commit"),
                                                  QStringLiteral("Author"),
                                                  QStringLiteral("Status"),
                                                  QStringLiteral("Subject")});
                table->horizontalHeader()->setSectionResizeMode(3, QHeaderView::Stretch);
                table->setEditTriggers(QAbstractItemView::NoEditTriggers);
                table->verticalHeader()->setVisible(false);
                table->setRowCount(static_cast<int>(entries.size()));
                for (int row = 0; row < static_cast<int>(entries.size()); ++row) {
                    const FileHistoryEntry& entry = entries[static_cast<std::size_t>(row)];
                    table->setItem(
                        row, 0, new QTableWidgetItem(QString::fromStdString(entry.oid.shortHex())));
                    table->setItem(
                        row, 1, new QTableWidgetItem(QString::fromStdString(entry.author.name)));
                    QString status = QString::fromStdString(entry.status);
                    if (!entry.renamedFrom.empty()) {
                        status += QStringLiteral(" (from %1)")
                                      .arg(QString::fromStdString(entry.renamedFrom));
                    }
                    table->setItem(row, 2, new QTableWidgetItem(status));
                    table->setItem(
                        row, 3, new QTableWidgetItem(QString::fromStdString(entry.subject)));
                }
                layout->addWidget(table);
                auto* closeButton = new QPushButton(QStringLiteral("Close"), &dialog);
                connect(closeButton, &QPushButton::clicked, &dialog, &QDialog::accept);
                layout->addWidget(closeButton);
                dialog.resize(720, 480);
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
        *connection =
            connect(session_.get(),
                    &RepositorySession::lineHistoryReady,
                    this,
                    [this, connection, path](std::vector<LineHistoryChunk> chunks) {
                        QObject::disconnect(*connection);
                        QDialog dialog(this);
                        dialog.setWindowTitle(QStringLiteral("Line history: %1").arg(path));
                        auto* layout = new QVBoxLayout(&dialog);
                        auto* text = new QPlainTextEdit(&dialog);
                        text->setReadOnly(true);
                        text->setLineWrapMode(QPlainTextEdit::NoWrap);
                        QString content;
                        for (const LineHistoryChunk& chunk : chunks) {
                            content += QStringLiteral("commit %1 — %2\n%3\n\n")
                                           .arg(QString::fromStdString(chunk.oid.shortHex()))
                                           .arg(QString::fromStdString(chunk.subject))
                                           .arg(QString::fromStdString(chunk.diffText));
                        }
                        text->setPlainText(content);
                        layout->addWidget(text);
                        auto* closeButton = new QPushButton(QStringLiteral("Close"), &dialog);
                        connect(closeButton, &QPushButton::clicked, &dialog, &QDialog::accept);
                        layout->addWidget(closeButton);
                        dialog.resize(720, 480);
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

    QDialog dialog(this);
    dialog.setWindowTitle(QStringLiteral("Manage submodules"));
    auto* layout = new QVBoxLayout(&dialog);

    auto* table = new QTableWidget(&dialog);
    table->setColumnCount(4);
    table->setHorizontalHeaderLabels({QStringLiteral("Path"),
                                      QStringLiteral("URL"),
                                      QStringLiteral("Commit"),
                                      QStringLiteral("Status")});
    table->horizontalHeader()->setSectionResizeMode(1, QHeaderView::Stretch);
    table->setSelectionBehavior(QAbstractItemView::SelectRows);
    table->setSelectionMode(QAbstractItemView::SingleSelection);
    table->setEditTriggers(QAbstractItemView::NoEditTriggers);
    table->verticalHeader()->setVisible(false);
    table->setAccessibleName(QStringLiteral("Submodule list"));
    layout->addWidget(table, 1);

    auto stateLabel = [](SubmoduleInfo::State state) {
        switch (state) {
            case SubmoduleInfo::State::NotInitialized:
                return QStringLiteral("not initialized");
            case SubmoduleInfo::State::Modified:
                return QStringLiteral("modified");
            case SubmoduleInfo::State::Conflicted:
                return QStringLiteral("conflicted");
            case SubmoduleInfo::State::UpToDate:
                return QStringLiteral("up to date");
        }
        return QStringLiteral("up to date");
    };

    auto reload = [this, table, stateLabel] {
        auto submodules = session_->submodules();
        table->setRowCount(0);
        if (!submodules) {
            return;
        }
        table->setRowCount(static_cast<int>(submodules->size()));
        for (int row = 0; row < static_cast<int>(submodules->size()); ++row) {
            const SubmoduleInfo& info = (*submodules)[static_cast<std::size_t>(row)];
            table->setItem(row, 0, new QTableWidgetItem(QString::fromStdString(info.path)));
            table->setItem(row, 1, new QTableWidgetItem(QString::fromStdString(info.url)));
            table->setItem(
                row, 2, new QTableWidgetItem(QString::fromStdString(info.headOid).left(10)));
            table->setItem(row, 3, new QTableWidgetItem(stateLabel(info.state)));
        }
    };
    connect(session_.get(), &RepositorySession::submodulesUpdated, &dialog, reload);
    session_->refreshSubmodules();
    reload();

    auto selectedInfo = [this, table]() -> std::optional<SubmoduleInfo> {
        const int row = table->currentRow();
        auto submodules = session_->submodules();
        if (row < 0 || !submodules || row >= static_cast<int>(submodules->size())) {
            return std::nullopt;
        }
        return (*submodules)[static_cast<std::size_t>(row)];
    };

    auto* buttonRow = new QHBoxLayout();
    auto* addButton = new QPushButton(QStringLiteral("Add…"), &dialog);
    auto* initButton = new QPushButton(QStringLiteral("Init"), &dialog);
    auto* updateButton = new QPushButton(QStringLiteral("Update"), &dialog);
    auto* syncButton = new QPushButton(QStringLiteral("Sync"), &dialog);
    auto* deinitButton = new QPushButton(QStringLiteral("Deinit…"), &dialog);
    auto* closeButton = new QPushButton(QStringLiteral("Close"), &dialog);
    for (QPushButton* button :
        {addButton, initButton, updateButton, syncButton, deinitButton, closeButton}) {
        button->setAccessibleDescription(QStringLiteral("Submodule action"));
    }
    buttonRow->addWidget(addButton);
    buttonRow->addWidget(initButton);
    buttonRow->addWidget(updateButton);
    buttonRow->addWidget(syncButton);
    buttonRow->addWidget(deinitButton);
    buttonRow->addStretch(1);
    buttonRow->addWidget(closeButton);
    layout->addLayout(buttonRow);

    connect(addButton, &QPushButton::clicked, &dialog, [this, &dialog] {
        bool ok = false;
        const QString url = QInputDialog::getText(
            &dialog, QStringLiteral("Add submodule"), QStringLiteral("URL:"),
            QLineEdit::Normal, QString(), &ok);
        if (!ok || url.isEmpty()) {
            return;
        }
        const QString path = QInputDialog::getText(
            &dialog,
            QStringLiteral("Add submodule"),
            QStringLiteral("Path (leave blank to derive from the URL):"),
            QLineEdit::Normal,
            QString(),
            &ok);
        if (!ok) {
            return;
        }
        AddSubmoduleRequest request;
        request.url = url.toStdString();
        request.path = path.toStdString();
        runWithFeedback([this, request] { session_->addSubmodule(request); });
    });

    connect(initButton, &QPushButton::clicked, &dialog, [this, selectedInfo] {
        auto info = selectedInfo();
        if (!info) {
            return;
        }
        SubmodulePathsRequest request;
        request.paths = {info->path};
        runWithFeedback([this, request] { session_->initSubmodules(request); });
    });

    connect(updateButton, &QPushButton::clicked, &dialog, [this, selectedInfo] {
        auto info = selectedInfo();
        if (!info) {
            return;
        }
        UpdateSubmodulesRequest request;
        request.paths = {info->path};
        request.init = true;
        runWithFeedback([this, request] { session_->updateSubmodules(request); });
    });

    connect(syncButton, &QPushButton::clicked, &dialog, [this, selectedInfo] {
        auto info = selectedInfo();
        if (!info) {
            return;
        }
        SubmodulePathsRequest request;
        request.paths = {info->path};
        runWithFeedback([this, request] { session_->syncSubmodules(request); });
    });

    connect(deinitButton, &QPushButton::clicked, &dialog, [this, selectedInfo, &dialog] {
        auto info = selectedInfo();
        if (!info) {
            return;
        }
        const auto confirmed =
            QMessageBox::warning(&dialog,
                                 QStringLiteral("Deinitialize submodule?"),
                                 QStringLiteral("This removes the checked-out files for \"%1\" "
                                               "(any local changes inside it are discarded). "
                                               "\"%1\" stays listed in .gitmodules and can be "
                                               "initialised again later.")
                                     .arg(QString::fromStdString(info->path)),
                                 QMessageBox::Yes | QMessageBox::Cancel,
                                 QMessageBox::Cancel);
        if (confirmed != QMessageBox::Yes) {
            return;
        }
        DeinitSubmodulesRequest request;
        request.paths = {info->path};
        request.force = true;
        runWithFeedback([this, request] { session_->deinitSubmodules(request); });
    });

    connect(closeButton, &QPushButton::clicked, &dialog, &QDialog::accept);

    dialog.resize(720, 360);
    dialog.exec();
}

// --- M5: bisect ----------------------------------------------------------

void MainWindow::onBisect() {
    if (!session_) {
        return;
    }

    QDialog dialog(this);
    dialog.setWindowTitle(QStringLiteral("Bisect"));
    auto* layout = new QVBoxLayout(&dialog);

    // --- "not bisecting yet" form ---
    auto* startForm = new QWidget(&dialog);
    auto* startLayout = new QVBoxLayout(startForm);
    startLayout->setContentsMargins(0, 0, 0, 0);
    auto* badRow = new QHBoxLayout();
    auto* badLabel = new QLabel(QStringLiteral("Bad commit:"), startForm);
    auto* badEdit = new QLineEdit(QStringLiteral("HEAD"), startForm);
    badEdit->setAccessibleName(QStringLiteral("Bad commit"));
    badRow->addWidget(badLabel);
    badRow->addWidget(badEdit, 1);
    startLayout->addLayout(badRow);
    auto* goodRow = new QHBoxLayout();
    auto* goodLabel = new QLabel(QStringLiteral("Good commit:"), startForm);
    auto* goodEdit = new QLineEdit(startForm);
    goodEdit->setPlaceholderText(QStringLiteral("e.g. a tag, branch or commit known to work"));
    goodEdit->setAccessibleName(QStringLiteral("Good commit"));
    goodRow->addWidget(goodLabel);
    goodRow->addWidget(goodEdit, 1);
    startLayout->addLayout(goodRow);
    auto* startButton = new QPushButton(QStringLiteral("Start bisect"), startForm);
    startLayout->addWidget(startButton, 0, Qt::AlignRight);
    layout->addWidget(startForm);

    // --- "bisecting" status view ---
    auto* statusWidget = new QWidget(&dialog);
    auto* statusLayout = new QVBoxLayout(statusWidget);
    statusLayout->setContentsMargins(0, 0, 0, 0);
    auto* currentLabel = new QLabel(statusWidget);
    currentLabel->setWordWrap(true);
    statusLayout->addWidget(currentLabel);
    auto* logText = new QPlainTextEdit(statusWidget);
    logText->setReadOnly(true);
    logText->setAccessibleName(QStringLiteral("Bisect log"));
    statusLayout->addWidget(logText, 1);
    auto* actionRow = new QHBoxLayout();
    auto* goodButton = new QPushButton(QStringLiteral("Mark Good"), statusWidget);
    auto* badButton = new QPushButton(QStringLiteral("Mark Bad"), statusWidget);
    auto* skipButton = new QPushButton(QStringLiteral("Skip"), statusWidget);
    auto* resetButton = new QPushButton(QStringLiteral("Reset (end bisect)"), statusWidget);
    actionRow->addWidget(goodButton);
    actionRow->addWidget(badButton);
    actionRow->addWidget(skipButton);
    actionRow->addStretch(1);
    actionRow->addWidget(resetButton);
    statusLayout->addLayout(actionRow);
    layout->addWidget(statusWidget);

    auto* closeButton = new QPushButton(QStringLiteral("Close"), &dialog);
    layout->addWidget(closeButton, 0, Qt::AlignRight);
    connect(closeButton, &QPushButton::clicked, &dialog, &QDialog::accept);

    auto reload = [this, startForm, statusWidget, currentLabel, logText] {
        auto status = session_->bisectStatus();
        const bool active = status && status->active;
        startForm->setVisible(!active);
        statusWidget->setVisible(active);
        if (!active) {
            return;
        }
        QString summary = QStringLiteral("Currently testing: %1")
                              .arg(QString::fromStdString(status->currentOid).left(12));
        if (!status->badOid.empty()) {
            summary +=
                QStringLiteral("\nBad: %1").arg(QString::fromStdString(status->badOid).left(12));
        }
        if (!status->goodOids.empty()) {
            summary += QStringLiteral("\nGood: %1 commit(s) marked").arg(status->goodOids.size());
        }
        if (!status->skippedOids.empty()) {
            summary +=
                QStringLiteral("\nSkipped: %1 commit(s)").arg(status->skippedOids.size());
        }
        currentLabel->setText(summary);
        logText->setPlainText(QString::fromStdString(status->logText));
    };
    connect(session_.get(), &RepositorySession::bisectStatusUpdated, &dialog, reload);
    session_->refreshBisectStatus();
    reload();

    connect(startButton, &QPushButton::clicked, &dialog, [this, badEdit, goodEdit] {
        BisectStartRequest request;
        request.badRef = badEdit->text().toStdString();
        if (!goodEdit->text().isEmpty()) {
            request.goodRefs = {goodEdit->text().toStdString()};
        }
        runWithFeedback([this, request] { session_->startBisect(request); });
    });
    connect(goodButton, &QPushButton::clicked, &dialog, [this] {
        BisectMarkRequest request;
        request.good = true;
        runWithFeedback([this, request] { session_->markBisect(request); });
    });
    connect(badButton, &QPushButton::clicked, &dialog, [this] {
        BisectMarkRequest request;
        request.good = false;
        runWithFeedback([this, request] { session_->markBisect(request); });
    });
    connect(skipButton, &QPushButton::clicked, &dialog, [this] {
        runWithFeedback([this] { session_->skipBisect(BisectSkipRequest{}); });
    });
    connect(resetButton, &QPushButton::clicked, &dialog, [this] {
        runWithFeedback([this] { session_->resetBisect(BisectResetRequest{}); });
    });

    dialog.resize(560, 420);
    dialog.exec();
}

// --- M5: LFS ---------------------------------------------------------------

void MainWindow::onManageLfs() {
    if (!session_) {
        return;
    }

    QDialog dialog(this);
    dialog.setWindowTitle(QStringLiteral("Manage LFS"));
    auto* layout = new QVBoxLayout(&dialog);

    auto* statusLabel = new QLabel(&dialog);
    statusLabel->setWordWrap(true);
    layout->addWidget(statusLabel);

    auto* installButton = new QPushButton(QStringLiteral("Set up LFS for this repository"), &dialog);
    layout->addWidget(installButton);

    auto* patternsGroup = new QWidget(&dialog);
    auto* patternsLayout = new QVBoxLayout(patternsGroup);
    patternsLayout->setContentsMargins(0, 0, 0, 0);
    patternsLayout->addWidget(new QLabel(QStringLiteral("Tracked patterns:"), patternsGroup));
    auto* patternsList = new QListWidget(patternsGroup);
    patternsList->setAccessibleName(QStringLiteral("LFS tracked patterns"));
    patternsList->setMaximumHeight(100);
    patternsLayout->addWidget(patternsList);
    auto* patternButtons = new QHBoxLayout();
    auto* addPatternButton = new QPushButton(QStringLiteral("Track pattern…"), patternsGroup);
    auto* removePatternButton = new QPushButton(QStringLiteral("Untrack"), patternsGroup);
    patternButtons->addWidget(addPatternButton);
    patternButtons->addWidget(removePatternButton);
    patternButtons->addStretch(1);
    patternsLayout->addLayout(patternButtons);
    layout->addWidget(patternsGroup);

    auto* filesTable = new QTableWidget(&dialog);
    filesTable->setColumnCount(3);
    filesTable->setHorizontalHeaderLabels(
        {QStringLiteral("Path"), QStringLiteral("Object"), QStringLiteral("Local")});
    filesTable->horizontalHeader()->setSectionResizeMode(0, QHeaderView::Stretch);
    filesTable->setEditTriggers(QAbstractItemView::NoEditTriggers);
    filesTable->verticalHeader()->setVisible(false);
    filesTable->setAccessibleName(QStringLiteral("LFS files"));
    layout->addWidget(filesTable, 1);

    auto* transferRow = new QHBoxLayout();
    auto* pullButton = new QPushButton(QStringLiteral("Pull"), &dialog);
    auto* fetchButton = new QPushButton(QStringLiteral("Fetch"), &dialog);
    auto* pruneButton = new QPushButton(QStringLiteral("Prune"), &dialog);
    auto* closeButton = new QPushButton(QStringLiteral("Close"), &dialog);
    transferRow->addWidget(pullButton);
    transferRow->addWidget(fetchButton);
    transferRow->addWidget(pruneButton);
    transferRow->addStretch(1);
    transferRow->addWidget(closeButton);
    layout->addLayout(transferRow);
    connect(closeButton, &QPushButton::clicked, &dialog, &QDialog::accept);

    auto reload = [this, statusLabel, installButton, patternsGroup, filesTable, pullButton,
                   fetchButton, pruneButton, patternsList] {
        auto installation = session_->lfsInstallation();
        const bool available = installation && installation->available;
        installButton->setVisible(available);
        patternsGroup->setVisible(available);
        filesTable->setVisible(available);
        pullButton->setEnabled(available);
        fetchButton->setEnabled(available);
        pruneButton->setEnabled(available);

        if (!installation) {
            statusLabel->setText(QStringLiteral("Checking for Git LFS…"));
            return;
        }
        if (!available) {
            statusLabel->setText(
                QStringLiteral("Git LFS is not installed. Install the git-lfs extension to "
                              "track large files in this repository."));
            return;
        }
        statusLabel->setText(
            QStringLiteral("Git LFS is available (%1).")
                .arg(QString::fromStdString(installation->version).split(QChar(' ')).value(0)));

        patternsList->clear();
        if (auto patterns = session_->lfsTrackedPatterns()) {
            for (const std::string& pattern : *patterns) {
                patternsList->addItem(QString::fromStdString(pattern));
            }
        }

        filesTable->setRowCount(0);
        if (auto files = session_->lfsFiles()) {
            filesTable->setRowCount(static_cast<int>(files->size()));
            for (int row = 0; row < static_cast<int>(files->size()); ++row) {
                const LfsFileInfo& info = (*files)[static_cast<std::size_t>(row)];
                filesTable->setItem(row, 0, new QTableWidgetItem(QString::fromStdString(info.path)));
                filesTable->setItem(
                    row, 1, new QTableWidgetItem(QString::fromStdString(info.oid).left(10)));
                filesTable->setItem(row,
                                    2,
                                    new QTableWidgetItem(info.downloadedLocally
                                                             ? QStringLiteral("yes")
                                                             : QStringLiteral("no")));
            }
        }
    };
    connect(session_.get(), &RepositorySession::lfsUpdated, &dialog, reload);
    session_->refreshLfs();
    reload();

    connect(installButton, &QPushButton::clicked, &dialog, [this] {
        runWithFeedback([this] { session_->installLfs(); });
    });

    connect(addPatternButton, &QPushButton::clicked, &dialog, [this, &dialog] {
        bool ok = false;
        const QString pattern = QInputDialog::getText(&dialog,
                                                      QStringLiteral("Track pattern"),
                                                      QStringLiteral("Pattern (e.g. *.psd):"),
                                                      QLineEdit::Normal,
                                                      QString(),
                                                      &ok);
        if (!ok || pattern.isEmpty()) {
            return;
        }
        LfsTrackRequest request;
        request.pattern = pattern.toStdString();
        runWithFeedback([this, request] { session_->trackLfsPattern(request); });
    });

    connect(removePatternButton, &QPushButton::clicked, &dialog, [this, patternsList] {
        const auto items = patternsList->selectedItems();
        if (items.isEmpty()) {
            return;
        }
        LfsUntrackRequest request;
        request.pattern = items.first()->text().toStdString();
        runWithFeedback([this, request] { session_->untrackLfsPattern(request); });
    });

    connect(pullButton, &QPushButton::clicked, &dialog, [this] {
        runWithFeedback([this] { session_->pullLfs(LfsTransferRequest{}); });
    });
    connect(fetchButton, &QPushButton::clicked, &dialog, [this] {
        runWithFeedback([this] { session_->fetchLfs(LfsTransferRequest{}); });
    });
    connect(pruneButton, &QPushButton::clicked, &dialog, [this] {
        runWithFeedback([this] { session_->pruneLfs(LfsPruneRequest{}); });
    });

    dialog.resize(640, 480);
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

    const QString dir = QFileDialog::getExistingDirectory(
        this, QStringLiteral("Choose a folder for the patches"));
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
    const QStringList files = QFileDialog::getOpenFileNames(
        this,
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
        box.setText(QStringLiteral("A patch did not apply cleanly. Resolve the conflict in the "
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

}  // namespace gbm
