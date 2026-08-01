#include "app/dialogs/ResetBranchDialog.h"

#include <QDialogButtonBox>
#include <QLabel>
#include <QRadioButton>
#include <QVBoxLayout>

namespace gbm {

ResetBranchDialog::ResetBranchDialog(const QString& targetShortHex, QWidget* parent)
    : QDialog(parent) {
    setWindowTitle(QStringLiteral("Reset branch"));
    auto* layout = new QVBoxLayout(this);
    layout->addWidget(
        new QLabel(QStringLiteral("Reset the current branch to %1:").arg(targetShortHex), this));

    soft_ = new QRadioButton(QStringLiteral("Soft (keep the index and work tree)"), this);
    mixed_ =
        new QRadioButton(QStringLiteral("Mixed (keep the work tree, unstage everything)"), this);
    hard_ = new QRadioButton(QStringLiteral("Hard (discard the index and work tree — destructive)"),
                             this);
    mixed_->setChecked(true);
    layout->addWidget(soft_);
    layout->addWidget(mixed_);
    layout->addWidget(hard_);

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    layout->addWidget(buttons);
    connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
}

ResetMode ResetBranchDialog::mode() const {
    return soft_->isChecked()   ? ResetMode::Soft
           : hard_->isChecked() ? ResetMode::Hard
                                : ResetMode::Mixed;
}

}  // namespace gbm
