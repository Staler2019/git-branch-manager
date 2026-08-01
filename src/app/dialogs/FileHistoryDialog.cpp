#include "app/dialogs/FileHistoryDialog.h"

#include <QAbstractItemView>
#include <QHeaderView>
#include <QPushButton>
#include <QTableWidget>
#include <QVBoxLayout>

namespace gbm {

FileHistoryDialog::FileHistoryDialog(const QString& path,
                                     const std::vector<FileHistoryEntry>& entries,
                                     QWidget* parent)
    : QDialog(parent) {
    setWindowTitle(QStringLiteral("History: %1").arg(path));
    auto* layout = new QVBoxLayout(this);
    auto* table = new QTableWidget(this);
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
        table->setItem(row, 0, new QTableWidgetItem(QString::fromStdString(entry.oid.shortHex())));
        table->setItem(row, 1, new QTableWidgetItem(QString::fromStdString(entry.author.name)));
        QString status = QString::fromStdString(entry.status);
        if (!entry.renamedFrom.empty()) {
            status += QStringLiteral(" (from %1)").arg(QString::fromStdString(entry.renamedFrom));
        }
        table->setItem(row, 2, new QTableWidgetItem(status));
        table->setItem(row, 3, new QTableWidgetItem(QString::fromStdString(entry.subject)));
    }
    layout->addWidget(table);
    auto* closeButton = new QPushButton(QStringLiteral("Close"), this);
    connect(closeButton, &QPushButton::clicked, this, &QDialog::accept);
    layout->addWidget(closeButton);
    resize(720, 480);
}

}  // namespace gbm
