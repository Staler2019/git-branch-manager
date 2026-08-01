#include "app/dialogs/CherryPickDialog.h"

#include <QAbstractItemView>
#include <QDialogButtonBox>
#include <QLabel>
#include <QListWidget>
#include <QVBoxLayout>

namespace gbm {

CherryPickDialog::CherryPickDialog(const std::vector<ObjectId>& commits,
                                   const QStringList& subjects,
                                   QWidget* parent)
    : QDialog(parent) {
    setWindowTitle(QStringLiteral("Cherry-pick"));
    auto* layout = new QVBoxLayout(this);
    layout->addWidget(new QLabel(
        commits.size() == 1
            ? QStringLiteral("Cherry-pick this commit onto the current branch:")
            : QStringLiteral("Cherry-pick these %1 commits onto the current branch, oldest first:")
                  .arg(commits.size()),
        this));

    auto* list = new QListWidget(this);
    list->setSelectionMode(QAbstractItemView::NoSelection);
    for (int i = 0; i < subjects.size(); ++i) {
        new QListWidgetItem(
            QString::fromStdString(commits[static_cast<std::size_t>(i)].shortHex()) +
                QStringLiteral("  ") + subjects[i],
            list);
    }
    layout->addWidget(list);

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    layout->addWidget(buttons);
    connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
    resize(480, 320);
}

}  // namespace gbm
