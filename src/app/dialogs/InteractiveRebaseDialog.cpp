#include "app/dialogs/InteractiveRebaseDialog.h"

#include "app/bridge/RepositorySession.h"

#include <QAbstractItemView>
#include <QComboBox>
#include <QDialogButtonBox>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QLabel>
#include <QPushButton>
#include <QTableWidget>
#include <QVBoxLayout>

#include <functional>
#include <utility>

namespace gbm {

namespace {

QString actionLabel(RebaseTodoEntry::Action action) {
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
}

RebaseTodoEntry::Action actionFromLabel(const QString& text) {
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
}

}  // namespace

InteractiveRebaseDialog::InteractiveRebaseDialog(RepositorySession* session,
                                                 const ObjectId& upstream,
                                                 QWidget* parent)
    : QDialog(parent),
      upstream_(upstream),
      todo_(std::make_shared<std::vector<RebaseTodoEntry>>()) {
    setWindowTitle(QStringLiteral("Interactive rebase"));
    auto* layout = new QVBoxLayout(this);
    layout->addWidget(new QLabel(QStringLiteral("Commits to replay onto %1, oldest first:")
                                     .arg(QString::fromStdString(upstream_.shortHex())),
                                 this));

    auto* table = new QTableWidget(this);
    table->setColumnCount(3);
    table->setHorizontalHeaderLabels(
        {QStringLiteral("Action"), QStringLiteral("Commit"), QStringLiteral("Subject")});
    table->horizontalHeader()->setSectionResizeMode(2, QHeaderView::Stretch);
    table->setSelectionBehavior(QAbstractItemView::SelectRows);
    table->setSelectionMode(QAbstractItemView::SingleSelection);
    table->setEditTriggers(QAbstractItemView::NoEditTriggers);
    table->verticalHeader()->setVisible(false);
    layout->addWidget(table, 1);

    std::shared_ptr<std::vector<RebaseTodoEntry>> todo = todo_;
    std::function<void()> refreshTable = [table, todo] {
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
            QObject::connect(
                combo, &QComboBox::currentTextChanged, table, [todo, row](const QString& text) {
                    (*todo)[static_cast<std::size_t>(row)].action = actionFromLabel(text);
                });
            table->setCellWidget(row, 0, combo);
            table->setItem(row, 1, new QTableWidgetItem(QString::fromStdString(entry.shortOid)));
            table->setItem(row, 2, new QTableWidgetItem(QString::fromStdString(entry.subject)));
        }
    };

    connect(session,
            &RepositorySession::rebasePlanReady,
            this,
            [todo, refreshTable](std::vector<RebaseTodoEntry> entries) {
                *todo = std::move(entries);
                refreshTable();
            });
    session->requestRebasePlan(upstream_.hex());

    auto* upButton = new QPushButton(QStringLiteral("Move Up"), this);
    auto* downButton = new QPushButton(QStringLiteral("Move Down"), this);
    connect(upButton, &QPushButton::clicked, this, [table, todo, refreshTable] {
        const int row = table->currentRow();
        if (row <= 0) {
            return;
        }
        std::swap((*todo)[static_cast<std::size_t>(row)],
                  (*todo)[static_cast<std::size_t>(row - 1)]);
        refreshTable();
        table->selectRow(row - 1);
    });
    connect(downButton, &QPushButton::clicked, this, [table, todo, refreshTable] {
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

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    buttons->button(QDialogButtonBox::Ok)->setText(QStringLiteral("Start Rebase"));
    layout->addWidget(buttons);
    connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);

    resize(560, 420);
}

RebaseInteractiveRequest InteractiveRebaseDialog::request() const {
    RebaseInteractiveRequest request;
    request.upstream = upstream_.hex();
    request.todo = *todo_;
    return request;
}

bool InteractiveRebaseDialog::hasTodoEntries() const {
    return !todo_->empty();
}

}  // namespace gbm
