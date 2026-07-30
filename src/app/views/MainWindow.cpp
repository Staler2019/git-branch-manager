#include "app/views/MainWindow.h"

#include "core/git/ops/CheckoutOp.h"

#include <QAction>
#include <QApplication>
#include <QFileDialog>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QLineEdit>
#include <QMenuBar>
#include <QMessageBox>
#include <QProgressBar>
#include <QPushButton>
#include <QScrollBar>
#include <QSplitter>
#include <QStackedWidget>
#include <QStandardPaths>
#include <QStatusBar>
#include <QStringListModel>
#include <QTimer>
#include <QToolBar>
#include <QVBoxLayout>

#include <algorithm>

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
    connect(repoSearch_, &QLineEdit::textChanged, this, &MainWindow::onRepoSearchChanged);

    repoModel_ = new RepoListModel(this);
    repoView_ = new QTableView(browserPage);
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
    // Probing is driven by what is actually visible, not by the list's size.
    connect(repoView_->verticalScrollBar(), &QScrollBar::valueChanged, this, [this] {
        probeVisibleRepos();
    });

    browserLayout->addWidget(repoSearch_);
    browserLayout->addWidget(repoView_, 1);
    stack_->addWidget(browserPage);

    // --- page 1: repository view --------------------------------------------
    auto* repoPage = new QWidget(this);
    auto* repoLayout = new QVBoxLayout(repoPage);
    repoLayout->setContentsMargins(0, 0, 0, 0);

    bannerLabel_ = new QLabel(repoPage);
    bannerLabel_->setVisible(false);
    bannerLabel_->setWordWrap(true);
    // Unmissable by design: a repository stuck mid-rebase must never look normal.
    bannerLabel_->setStyleSheet(
        QStringLiteral("QLabel { background: #7a4d00; color: white; padding: 6px; }"));
    repoLayout->addWidget(bannerLabel_);

    auto* outerSplitter = new QSplitter(Qt::Horizontal, repoPage);

    refModel_ = new RefTreeModel(this);
    refView_ = new QTreeView(outerSplitter);
    refView_->setModel(refModel_);
    refView_->setHeaderHidden(true);
    refView_->setUniformRowHeights(true);
    connect(refView_, &QTreeView::activated, this, &MainWindow::onRefActivated);
    outerSplitter->addWidget(refView_);

    auto* rightSplitter = new QSplitter(Qt::Vertical, outerSplitter);

    commitModel_ = new CommitListModel(this);
    commitView_ = new QTableView(rightSplitter);
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
    fileView_->setSelectionBehavior(QAbstractItemView::SelectRows);
    fileView_->verticalHeader()->setVisible(false);
    fileView_->setShowGrid(false);
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

    // --- status bar ----------------------------------------------------------
    statusLabel_ = new QLabel(QStringLiteral("Ready"), this);
    busyBar_ = new QProgressBar(this);
    busyBar_->setRange(0, 0);  // Indeterminate.
    busyBar_->setMaximumWidth(120);
    busyBar_->setVisible(false);
    statusBar()->addWidget(statusLabel_, 1);
    statusBar()->addPermanentWidget(busyBar_);
    statusBar()->addPermanentWidget(new QLabel(
        QStringLiteral("git %1").arg(QString::fromStdString(installation_.version.toString())),
        this));
}

void MainWindow::buildMenus() {
    auto* fileMenu = menuBar()->addMenu(QStringLiteral("&File"));
    fileMenu->addAction(QStringLiteral("Add base folder…"), this, &MainWindow::onAddBaseFolder);
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

    auto* branchMenu = menuBar()->addMenu(QStringLiteral("&Branch"));
    auto* checkoutAction = branchMenu->addAction(
        QStringLiteral("Switch to selected branch"), this, &MainWindow::onCheckoutRequested);
    checkoutAction->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+O")));

    auto* toolBar = addToolBar(QStringLiteral("Main"));
    toolBar->setMovable(false);
    toolBar->addAction(refreshAction);
    toolBar->addAction(
        QStringLiteral("Repositories"), this, [this] { stack_->setCurrentIndex(0); });
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
    if (auto added = discovery_->addBaseFolder(path); !added) {
        showError(QStringLiteral("Could not add that folder"), added.error());
        return;
    }
    // A newly added folder has no signatures yet, so this first pass is effectively
    // a full scan of just that folder.
    discovery_->startScan(ScanMode::Incremental);
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

    commitModel_->setSession(session_.get());
    diffView_->clearDiff();

    setWindowTitle(QStringLiteral("%1 — git-branch-manager").arg(session_->displayName()));
    stack_->setCurrentIndex(1);
    updateStateBanner();

    // Refs first, so the history walk can be seeded with HEAD and the trunk; that
    // seeding order is what puts the trunk in lane 0.
    session_->refreshRefs();
    session_->refreshHistory();
}

void MainWindow::closeRepository() {
    if (!session_) {
        return;
    }
    session_->cancelPendingReads();
    commitModel_->setSession(nullptr);
    refModel_->setRefs(nullptr);
    diffView_->clearDiff();
    session_.reset();
    setWindowTitle(QStringLiteral("git-branch-manager"));
    stack_->setCurrentIndex(0);
    bannerLabel_->setVisible(false);
}

void MainWindow::updateStateBanner() {
    if (!session_) {
        bannerLabel_->setVisible(false);
        return;
    }
    const RepoState state = session_->state();
    const std::string description = state.describe();
    if (description.empty()) {
        bannerLabel_->setVisible(false);
        return;
    }
    bannerLabel_->setText(QString::fromStdString(description));
    bannerLabel_->setVisible(true);
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

}  // namespace gbm
