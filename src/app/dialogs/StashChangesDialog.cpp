#include "app/dialogs/StashChangesDialog.h"

#include <QCheckBox>
#include <QDialogButtonBox>
#include <QLineEdit>
#include <QVBoxLayout>

namespace gbm {

StashChangesDialog::StashChangesDialog(QWidget* parent) : QDialog(parent) {
    setWindowTitle(QStringLiteral("Stash changes"));
    auto* layout = new QVBoxLayout(this);

    messageEdit_ = new QLineEdit(this);
    messageEdit_->setPlaceholderText(QStringLiteral("Stash message (optional)"));
    layout->addWidget(messageEdit_);
    includeUntracked_ = new QCheckBox(QStringLiteral("Include untracked files"), this);
    layout->addWidget(includeUntracked_);

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    layout->addWidget(buttons);
    connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
}

StashSaveRequest StashChangesDialog::request() const {
    StashSaveRequest request;
    request.message = messageEdit_->text().toStdString();
    request.includeUntracked = includeUntracked_->isChecked();
    return request;
}

}  // namespace gbm
