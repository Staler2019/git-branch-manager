#include "app/dialogs/ManageSubmodulesDialog.h"

#include "app/bridge/RepositorySession.h"
#include "app/dialogs/MessageDialogs.h"

#include <QAbstractItemView>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QInputDialog>
#include <QLineEdit>
#include <QMessageBox>
#include <QPushButton>
#include <QTableWidget>
#include <QVBoxLayout>

#include <optional>

namespace gbm {

namespace {

QString stateLabel(SubmoduleInfo::State state) {
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
}

}  // namespace

ManageSubmodulesDialog::ManageSubmodulesDialog(RepositorySession* session,
                                               RunWithFeedbackFn runWithFeedback,
                                               QWidget* parent)
    : QDialog(parent) {
    setWindowTitle(QStringLiteral("Manage submodules"));
    auto* layout = new QVBoxLayout(this);

    auto* table = new QTableWidget(this);
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

    auto reload = [session, table] {
        auto submodules = session->submodules();
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
    connect(session, &RepositorySession::submodulesUpdated, this, reload);
    session->refreshSubmodules();
    reload();

    auto selectedInfo = [session, table]() -> std::optional<SubmoduleInfo> {
        const int row = table->currentRow();
        auto submodules = session->submodules();
        if (row < 0 || !submodules || row >= static_cast<int>(submodules->size())) {
            return std::nullopt;
        }
        return (*submodules)[static_cast<std::size_t>(row)];
    };

    auto* buttonRow = new QHBoxLayout();
    auto* addButton = new QPushButton(QStringLiteral("Add…"), this);
    auto* initButton = new QPushButton(QStringLiteral("Init"), this);
    auto* updateButton = new QPushButton(QStringLiteral("Update"), this);
    auto* syncButton = new QPushButton(QStringLiteral("Sync"), this);
    auto* deinitButton = new QPushButton(QStringLiteral("Deinit…"), this);
    auto* closeButton = new QPushButton(QStringLiteral("Close"), this);
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

    connect(addButton, &QPushButton::clicked, this, [this, session, runWithFeedback] {
        const auto urlResult =
            dialogs::promptText(this, QStringLiteral("Add submodule"), QStringLiteral("URL:"));
        if (!urlResult || urlResult->isEmpty()) {
            return;
        }
        const QString url = *urlResult;
        const auto pathResult =
            dialogs::promptText(this,
                                QStringLiteral("Add submodule"),
                                QStringLiteral("Path (leave blank to derive from the URL):"));
        if (!pathResult) {
            return;
        }
        const QString path = *pathResult;
        AddSubmoduleRequest request;
        request.url = url.toStdString();
        request.path = path.toStdString();
        runWithFeedback([session, request] { session->addSubmodule(request); }, nullptr);
    });

    connect(initButton, &QPushButton::clicked, this, [session, runWithFeedback, selectedInfo] {
        auto info = selectedInfo();
        if (!info) {
            return;
        }
        SubmodulePathsRequest request;
        request.paths = {info->path};
        runWithFeedback([session, request] { session->initSubmodules(request); }, nullptr);
    });

    connect(updateButton, &QPushButton::clicked, this, [session, runWithFeedback, selectedInfo] {
        auto info = selectedInfo();
        if (!info) {
            return;
        }
        UpdateSubmodulesRequest request;
        request.paths = {info->path};
        request.init = true;
        runWithFeedback([session, request] { session->updateSubmodules(request); }, nullptr);
    });

    connect(syncButton, &QPushButton::clicked, this, [session, runWithFeedback, selectedInfo] {
        auto info = selectedInfo();
        if (!info) {
            return;
        }
        SubmodulePathsRequest request;
        request.paths = {info->path};
        runWithFeedback([session, request] { session->syncSubmodules(request); }, nullptr);
    });

    connect(
        deinitButton, &QPushButton::clicked, this, [this, session, runWithFeedback, selectedInfo] {
            auto info = selectedInfo();
            if (!info) {
                return;
            }
            const bool confirmed =
                dialogs::confirm(this,
                                 QStringLiteral("Deinitialize submodule?"),
                                 QStringLiteral("This removes the checked-out files for \"%1\" "
                                                "(any local changes inside it are discarded). "
                                                "\"%1\" stays listed in .gitmodules and can be "
                                                "initialised again later.")
                                     .arg(QString::fromStdString(info->path)),
                                 QStringLiteral("Yes"),
                                 /*destructive=*/true);
            if (!confirmed) {
                return;
            }
            DeinitSubmodulesRequest request;
            request.paths = {info->path};
            request.force = true;
            runWithFeedback([session, request] { session->deinitSubmodules(request); }, nullptr);
        });

    connect(closeButton, &QPushButton::clicked, this, &QDialog::accept);

    resize(720, 360);
}

}  // namespace gbm
