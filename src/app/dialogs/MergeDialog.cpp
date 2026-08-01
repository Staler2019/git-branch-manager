#include "app/dialogs/MergeDialog.h"

#include <QDialogButtonBox>
#include <QLabel>
#include <QLineEdit>
#include <QRadioButton>
#include <QVBoxLayout>

namespace gbm {

MergeDialog::MergeDialog(const QString& targetName, QWidget* parent)
    : QDialog(parent), targetName_(targetName) {
    setWindowTitle(QStringLiteral("Merge"));
    auto* layout = new QVBoxLayout(this);
    layout->addWidget(
        new QLabel(QStringLiteral("Merge \"%1\" into the current branch:").arg(targetName_), this));

    ffOnly_ = new QRadioButton(QStringLiteral("Fast-forward only"), this);
    noFf_ = new QRadioButton(QStringLiteral("Create a merge commit (no fast-forward)"), this);
    squash_ = new QRadioButton(QStringLiteral("Squash (stage the changes, no commit)"), this);
    noFf_->setChecked(true);
    layout->addWidget(ffOnly_);
    layout->addWidget(noFf_);
    layout->addWidget(squash_);

    messageEdit_ = new QLineEdit(this);
    messageEdit_->setPlaceholderText(
        QStringLiteral("Merge commit message (used only when creating a merge commit)"));
    layout->addWidget(messageEdit_);

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    layout->addWidget(buttons);
    connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
}

MergeRequest MergeDialog::request() const {
    MergeRequest request;
    request.target = targetName_.toStdString();
    request.mode = squash_->isChecked()   ? MergeMode::Squash
                   : ffOnly_->isChecked() ? MergeMode::FastForwardOnly
                                          : MergeMode::NoFastForward;
    request.message = messageEdit_->text().toStdString();
    return request;
}

}  // namespace gbm
