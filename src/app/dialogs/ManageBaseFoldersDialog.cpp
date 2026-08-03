#include "app/dialogs/ManageBaseFoldersDialog.h"

#include "app/bridge/DiscoveryController.h"
#include "app/dialogs/MessageDialogs.h"

#include <QAbstractItemView>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QInputDialog>
#include <QMessageBox>
#include <QPushButton>
#include <QTableWidget>
#include <QVBoxLayout>

namespace gbm {

namespace {

void showDiscoveryError(QWidget* parent, const QString& summary, const GitError& error) {
    QMessageBox box(parent);
    box.setIcon(QMessageBox::Critical);
    box.setText(summary.isEmpty() ? QString::fromStdString(error.message) : summary);
    box.setInformativeText(QString::fromStdString(error.message));
    if (!error.detail.empty()) {
        box.setDetailedText(QString::fromStdString(error.detail));
    }
    box.exec();
}

}  // namespace

ManageBaseFoldersDialog::ManageBaseFoldersDialog(DiscoveryController* discovery, QWidget* parent)
    : QDialog(parent) {
    setWindowTitle(QStringLiteral("Manage base folders"));
    auto* layout = new QVBoxLayout(this);

    auto* table = new QTableWidget(this);
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
    folders_ = discovery->baseFolders();
    table->setRowCount(static_cast<int>(folders_.size()));
    for (int row = 0; row < static_cast<int>(folders_.size()); ++row) {
        const BaseFolderRecord& folder = folders_[static_cast<std::size_t>(row)];
        table->setItem(row, 0, new QTableWidgetItem(QString::fromStdString(folder.path)));
        table->setItem(row, 1, new QTableWidgetItem(QString::number(folder.maxDepth)));
        table->setItem(
            row,
            2,
            new QTableWidgetItem(folder.enabled ? QStringLiteral("yes") : QStringLiteral("no")));
    }
    layout->addWidget(table);

    auto* buttonRow = new QHBoxLayout();
    auto* editDepthButton = new QPushButton(QStringLiteral("Change depth…"), this);
    auto* removeButton = new QPushButton(QStringLiteral("Remove"), this);
    auto* closeButton = new QPushButton(QStringLiteral("Close"), this);
    buttonRow->addWidget(editDepthButton);
    buttonRow->addWidget(removeButton);
    buttonRow->addStretch(1);
    buttonRow->addWidget(closeButton);
    layout->addLayout(buttonRow);

    connect(editDepthButton, &QPushButton::clicked, this, [this, discovery, table] {
        const int row = table->currentRow();
        if (row < 0) {
            return;
        }
        const BaseFolderRecord& folder = folders_[static_cast<std::size_t>(row)];
        const auto depthResult =
            dialogs::promptInt(this,
                               QStringLiteral("Scan depth"),
                               QStringLiteral("How many levels below \"%1\" should be scanned?")
                                   .arg(QString::fromStdString(folder.path)),
                               folder.maxDepth,
                               0,
                               10);
        if (!depthResult) {
            return;
        }
        const int depth = *depthResult;
        if (auto result = discovery->setBaseFolderDepth(folder.id, depth); !result) {
            showDiscoveryError(
                this, QStringLiteral("Could not change the scan depth"), result.error());
            return;
        }
        table->item(row, 1)->setText(QString::number(depth));
        changed_ = true;
    });

    connect(removeButton, &QPushButton::clicked, this, [this, discovery, table] {
        const int row = table->currentRow();
        if (row < 0) {
            return;
        }
        const BaseFolderRecord& folder = folders_[static_cast<std::size_t>(row)];
        if (auto result = discovery->removeBaseFolder(folder.id); !result) {
            showDiscoveryError(
                this, QStringLiteral("Could not remove that folder"), result.error());
            return;
        }
        table->removeRow(row);
        folders_.erase(folders_.begin() + row);
        changed_ = true;
    });

    connect(closeButton, &QPushButton::clicked, this, &QDialog::accept);

    resize(560, 320);
}

}  // namespace gbm
