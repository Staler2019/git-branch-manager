#include "app/dialogs/BlameDialog.h"

#include <QAbstractItemView>
#include <QHeaderView>
#include <QPushButton>
#include <QTableWidget>
#include <QVBoxLayout>

namespace gbm {

BlameDialog::BlameDialog(const QString& path, const BlameResult& result, QWidget* parent)
    : QDialog(parent) {
    setWindowTitle(QStringLiteral("Blame: %1").arg(path));
    auto* layout = new QVBoxLayout(this);
    auto* table = new QTableWidget(this);
    table->setColumnCount(4);
    table->setHorizontalHeaderLabels({QStringLiteral("Commit"),
                                      QStringLiteral("Author"),
                                      QStringLiteral("Line"),
                                      QStringLiteral("Content")});
    table->horizontalHeader()->setSectionResizeMode(3, QHeaderView::Stretch);
    table->setEditTriggers(QAbstractItemView::NoEditTriggers);
    table->verticalHeader()->setVisible(false);
    table->setRowCount(static_cast<int>(result.lines.size()));
    for (int row = 0; row < static_cast<int>(result.lines.size()); ++row) {
        const BlameLine& line = result.lines[static_cast<std::size_t>(row)];
        table->setItem(
            row, 0, new QTableWidgetItem(QString::fromStdString(line.commitOid.shortHex())));
        table->setItem(row, 1, new QTableWidgetItem(QString::fromStdString(line.authorName)));
        table->setItem(row, 2, new QTableWidgetItem(QString::number(line.finalLine)));
        table->setItem(row, 3, new QTableWidgetItem(QString::fromStdString(line.content)));
    }
    layout->addWidget(table);
    auto* closeButton = new QPushButton(QStringLiteral("Close"), this);
    connect(closeButton, &QPushButton::clicked, this, &QDialog::accept);
    layout->addWidget(closeButton);
    resize(720, 480);
}

}  // namespace gbm
