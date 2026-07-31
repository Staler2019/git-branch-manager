#include "app/views/CredentialDialog.h"

#include <QDialogButtonBox>
#include <QLabel>
#include <QLineEdit>
#include <QVBoxLayout>

namespace gbm {

CredentialDialog::CredentialDialog(const QString& prompt, QWidget* parent) : QDialog(parent) {
    setWindowTitle(tr("Git credentials"));
    auto* layout = new QVBoxLayout(this);

    auto* label = new QLabel(prompt, this);
    label->setWordWrap(true);
    layout->addWidget(label);

    edit_ = new QLineEdit(this);
    if (prompt.contains(QStringLiteral("assword"), Qt::CaseInsensitive) ||
        prompt.contains(QStringLiteral("assphrase"), Qt::CaseInsensitive)) {
        edit_->setEchoMode(QLineEdit::Password);
    }
    layout->addWidget(edit_);

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    layout->addWidget(buttons);
    connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);

    edit_->setFocus();
    resize(420, 120);
}

QString CredentialDialog::value() const {
    return edit_->text();
}

}  // namespace gbm
