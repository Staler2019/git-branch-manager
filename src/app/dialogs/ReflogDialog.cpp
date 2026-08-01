#include "app/dialogs/ReflogDialog.h"

#include "app/bridge/RepositorySession.h"

#include <QAbstractItemView>
#include <QDateTime>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QMessageBox>
#include <QPushButton>
#include <QTableWidget>
#include <QVBoxLayout>

namespace gbm {

ReflogDialog::ReflogDialog(RepositorySession* session,
                           RunWithFeedbackFn runWithFeedback,
                           QWidget* parent)
    : QDialog(parent) {
    setWindowTitle(QStringLiteral("Reflog"));
    auto* layout = new QVBoxLayout(this);

    auto* table = new QTableWidget(this);
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
        session, &RepositorySession::reflogReady, this, [table](std::vector<ReflogEntry> entries) {
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
    session->requestReflog("");

    auto* buttonRow = new QHBoxLayout();
    auto* resetButton = new QPushButton(QStringLiteral("Reset to here (hard)…"), this);
    auto* closeButton = new QPushButton(QStringLiteral("Close"), this);
    buttonRow->addStretch(1);
    buttonRow->addWidget(resetButton);
    buttonRow->addWidget(closeButton);
    layout->addLayout(buttonRow);

    connect(resetButton, &QPushButton::clicked, this, [this, session, runWithFeedback, table] {
        const auto selectedRows = table->selectionModel()->selectedRows();
        if (selectedRows.isEmpty()) {
            return;
        }
        const QString oid =
            table->item(selectedRows.first().row(), 0)->data(Qt::UserRole).toString();
        const auto confirmed =
            QMessageBox::warning(this,
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
        runWithFeedback([session, request] { session->resetTo(request); }, nullptr);
        accept();
    });
    connect(closeButton, &QPushButton::clicked, this, &QDialog::accept);

    resize(560, 420);
}

}  // namespace gbm
