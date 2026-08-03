#include "app/dialogs/ManageWorktreesDialog.h"

#include "app/bridge/RepositorySession.h"
#include "app/dialogs/MessageDialogs.h"

#include <QAbstractItemView>
#include <QDir>
#include <QFileDialog>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QInputDialog>
#include <QLineEdit>
#include <QMessageBox>
#include <QPushButton>
#include <QTableWidget>
#include <QVBoxLayout>

#include <filesystem>
#include <optional>

namespace gbm {

ManageWorktreesDialog::ManageWorktreesDialog(RepositorySession* session,
                                             RunWithFeedbackFn runWithFeedback,
                                             QWidget* parent)
    : QDialog(parent) {
    setWindowTitle(QStringLiteral("Manage worktrees"));
    auto* layout = new QVBoxLayout(this);

    auto* table = new QTableWidget(this);
    table->setColumnCount(3);
    table->setHorizontalHeaderLabels(
        {QStringLiteral("Path"), QStringLiteral("Branch"), QStringLiteral("Status")});
    table->horizontalHeader()->setSectionResizeMode(0, QHeaderView::Stretch);
    table->setSelectionBehavior(QAbstractItemView::SelectRows);
    table->setSelectionMode(QAbstractItemView::SingleSelection);
    table->setEditTriggers(QAbstractItemView::NoEditTriggers);
    table->verticalHeader()->setVisible(false);
    layout->addWidget(table, 1);

    auto reload = [session, table] {
        auto worktrees = session->worktrees();
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
    connect(session, &RepositorySession::worktreesUpdated, this, reload);
    session->refreshWorktrees();
    reload();

    auto selectedInfo = [session, table]() -> std::optional<WorktreeInfo> {
        const int row = table->currentRow();
        auto worktrees = session->worktrees();
        if (row < 0 || !worktrees || row >= static_cast<int>(worktrees->size())) {
            return std::nullopt;
        }
        return (*worktrees)[static_cast<std::size_t>(row)];
    };

    auto* buttonRow = new QHBoxLayout();
    auto* addButton = new QPushButton(QStringLiteral("Add…"), this);
    auto* removeButton = new QPushButton(QStringLiteral("Remove"), this);
    auto* lockButton = new QPushButton(QStringLiteral("Lock…"), this);
    auto* unlockButton = new QPushButton(QStringLiteral("Unlock"), this);
    auto* pruneButton = new QPushButton(QStringLiteral("Prune stale"), this);
    auto* closeButton = new QPushButton(QStringLiteral("Close"), this);
    buttonRow->addWidget(addButton);
    buttonRow->addWidget(removeButton);
    buttonRow->addWidget(lockButton);
    buttonRow->addWidget(unlockButton);
    buttonRow->addWidget(pruneButton);
    buttonRow->addStretch(1);
    buttonRow->addWidget(closeButton);
    layout->addLayout(buttonRow);

    connect(addButton, &QPushButton::clicked, this, [this, session, runWithFeedback] {
        const QString parentDir = QFileDialog::getExistingDirectory(
            this, QStringLiteral("Choose a parent folder for the new worktree"));
        if (parentDir.isEmpty()) {
            return;
        }
        const auto folderNameResult = dialogs::promptText(
            this, QStringLiteral("New worktree"), QStringLiteral("Folder name:"));
        if (!folderNameResult || folderNameResult->isEmpty()) {
            return;
        }
        const QString folderName = *folderNameResult;

        QStringList branchNames;
        if (const RefSnapshotPtr refs = session->refs()) {
            for (const RefInfo* ref : refs->ofKind(RefKind::LocalBranch)) {
                branchNames << QString::fromStdString(ref->shortName);
            }
        }
        QString branch;
        if (!branchNames.isEmpty()) {
            const auto branchResult = dialogs::promptChoice(
                this, QStringLiteral("New worktree"), QStringLiteral("Branch:"), branchNames, 0);
            if (!branchResult) {
                return;
            }
            branch = *branchResult;
        }

        AddWorktreeRequest request;
        request.path = std::filesystem::path(QDir(parentDir).filePath(folderName).toStdString());
        request.branch = branch.toStdString();
        runWithFeedback([session, request] { session->addWorktree(request); }, nullptr);
    });

    connect(
        removeButton, &QPushButton::clicked, this, [this, session, runWithFeedback, selectedInfo] {
            auto info = selectedInfo();
            if (!info) {
                return;
            }
            if (info->isMain) {
                dialogs::info(this,
                              QStringLiteral("Cannot remove"),
                              QStringLiteral("The main worktree cannot be removed."));
                return;
            }
            const bool confirmed =
                dialogs::confirm(this,
                                 QStringLiteral("Remove worktree?"),
                                 QStringLiteral("Remove the worktree at \"%1\"?")
                                     .arg(QString::fromStdString(info->path.string())),
                                 QStringLiteral("Yes"),
                                 /*destructive=*/true);
            if (!confirmed) {
                return;
            }
            const std::filesystem::path path = info->path;
            runWithFeedback(
                [session, path] {
                    RemoveWorktreeRequest request;
                    request.path = path;
                    session->removeWorktree(request);
                },
                [session, path](OperationChoice::Kind kind) {
                    if (kind == OperationChoice::Kind::ForceDiscard) {
                        RemoveWorktreeRequest request;
                        request.path = path;
                        request.force = true;
                        session->removeWorktree(request);
                    }
                });
        });

    connect(
        lockButton, &QPushButton::clicked, this, [this, session, runWithFeedback, selectedInfo] {
            auto info = selectedInfo();
            if (!info) {
                return;
            }
            const auto reasonResult = dialogs::promptText(
                this, QStringLiteral("Lock worktree"), QStringLiteral("Reason (optional):"));
            if (!reasonResult) {
                return;
            }
            const QString reason = *reasonResult;
            LockWorktreeRequest request;
            request.path = info->path;
            request.reason = reason.toStdString();
            runWithFeedback([session, request] { session->lockWorktree(request); }, nullptr);
        });

    connect(unlockButton, &QPushButton::clicked, this, [session, runWithFeedback, selectedInfo] {
        auto info = selectedInfo();
        if (!info) {
            return;
        }
        UnlockWorktreeRequest request;
        request.path = info->path;
        runWithFeedback([session, request] { session->unlockWorktree(request); }, nullptr);
    });

    connect(pruneButton, &QPushButton::clicked, this, [session, runWithFeedback] {
        runWithFeedback([session] { session->pruneWorktrees(); }, nullptr);
    });

    connect(closeButton, &QPushButton::clicked, this, &QDialog::accept);

    resize(640, 360);
}

}  // namespace gbm
