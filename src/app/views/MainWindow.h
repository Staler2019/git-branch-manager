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
#include <QTableView>
#include <QTreeView>

#include <memory>

class QLineEdit;
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

private:
    void buildUi();
    void buildMenus();
    void openRepository(const RepoRecord& record);
    void closeRepository();
    void probeVisibleRepos();
    void updateStateBanner();
    void showError(const QString& summary, const GitError& error);

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
    QProgressBar* busyBar_ = nullptr;

    /// Coalesces a burst of scroll events into a single `probeVisibleRepos()`
    /// call instead of one per event.
    QTimer* probeDebounce_ = nullptr;

    std::vector<RepoRecord> allRepos_;
    std::shared_ptr<const std::vector<ChangedFile>> currentFiles_;
    std::shared_ptr<const ParsedDiff> currentDiff_;
};

}  // namespace gbm
