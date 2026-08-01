#include "app/dialogs/ManageStashesDialog.h"

#include "app/bridge/RepositorySession.h"

#include <QHBoxLayout>
#include <QInputDialog>
#include <QLineEdit>
#include <QListWidget>
#include <QMessageBox>
#include <QPushButton>
#include <QVBoxLayout>

#include <optional>

namespace gbm {

ManageStashesDialog::ManageStashesDialog(RepositorySession* session,
                                         RunWithFeedbackFn runWithFeedback,
                                         QWidget* parent)
    : QDialog(parent) {
    setWindowTitle(QStringLiteral("Manage stashes"));
    auto* layout = new QVBoxLayout(this);

    auto* list = new QListWidget(this);
    layout->addWidget(list, 1);

    auto reload = [session, list] {
        list->clear();
        if (auto stashes = session->stashes()) {
            for (const StashEntry& entry : *stashes) {
                auto* item = new QListWidgetItem(QStringLiteral("stash@{%1}  %2")
                                                     .arg(entry.index)
                                                     .arg(QString::fromStdString(entry.message)),
                                                 list);
                item->setData(Qt::UserRole, entry.index);
            }
        }
    };
    // Scoped to this dialog: a stash operation finishing after it closes must
    // not touch a destroyed list widget.
    connect(session, &RepositorySession::stashesUpdated, this, reload);
    session->refreshStashes();
    reload();

    auto selectedIndex = [list]() -> std::optional<int> {
        const auto items = list->selectedItems();
        if (items.isEmpty()) {
            return std::nullopt;
        }
        return items.first()->data(Qt::UserRole).toInt();
    };

    auto* buttonRow = new QHBoxLayout();
    auto* applyButton = new QPushButton(QStringLiteral("Apply"), this);
    auto* popButton = new QPushButton(QStringLiteral("Pop"), this);
    auto* dropButton = new QPushButton(QStringLiteral("Drop"), this);
    auto* branchButton = new QPushButton(QStringLiteral("Create branch…"), this);
    auto* closeButton = new QPushButton(QStringLiteral("Close"), this);
    buttonRow->addWidget(applyButton);
    buttonRow->addWidget(popButton);
    buttonRow->addWidget(dropButton);
    buttonRow->addWidget(branchButton);
    buttonRow->addStretch(1);
    buttonRow->addWidget(closeButton);
    layout->addLayout(buttonRow);

    connect(applyButton, &QPushButton::clicked, this, [session, runWithFeedback, selectedIndex] {
        if (auto index = selectedIndex()) {
            StashApplyRequest request;
            request.index = *index;
            runWithFeedback([session, request] { session->applyStash(request); }, nullptr);
        }
    });
    connect(popButton, &QPushButton::clicked, this, [session, runWithFeedback, selectedIndex] {
        if (auto index = selectedIndex()) {
            StashApplyRequest request;
            request.index = *index;
            request.pop = true;
            runWithFeedback([session, request] { session->applyStash(request); }, nullptr);
        }
    });
    connect(
        dropButton, &QPushButton::clicked, this, [this, session, runWithFeedback, selectedIndex] {
            auto index = selectedIndex();
            if (!index) {
                return;
            }
            const auto confirmed = QMessageBox::warning(this,
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
            runWithFeedback([session, request] { session->dropStash(request); }, nullptr);
        });
    connect(
        branchButton, &QPushButton::clicked, this, [this, session, runWithFeedback, selectedIndex] {
            auto index = selectedIndex();
            if (!index) {
                return;
            }
            bool ok = false;
            const QString name = QInputDialog::getText(this,
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
            runWithFeedback([session, request] { session->branchFromStash(request); }, nullptr);
        });
    connect(closeButton, &QPushButton::clicked, this, &QDialog::accept);

    resize(480, 360);
}

}  // namespace gbm
