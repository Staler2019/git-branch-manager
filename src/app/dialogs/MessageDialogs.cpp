#include "app/dialogs/MessageDialogs.h"

#include <QComboBox>
#include <QDialog>
#include <QDialogButtonBox>
#include <QLabel>
#include <QLineEdit>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QSpinBox>
#include <QVBoxLayout>

namespace gbm::dialogs {

namespace {

/// Shared shell every helper below builds on: title, a wrapped message
/// label, a caller-supplied body widget (nullptr for the plain
/// info/warn/error/confirm cases), and a button box wired to accept/reject.
/// Mirrors CredentialDialog's layout (views/CredentialDialog.cpp), the
/// existing reference for a hand-built styled dialog in this app.
class MessageDialog : public QDialog {
public:
    MessageDialog(QWidget* parent,
                  const QString& title,
                  const QString& text,
                  QWidget* body,
                  QDialogButtonBox::StandardButtons buttons,
                  const QString& acceptText,
                  bool destructive)
        : QDialog(parent) {
        setWindowTitle(title);
        auto* layout = new QVBoxLayout(this);

        if (!text.isEmpty()) {
            auto* label = new QLabel(text, this);
            label->setWordWrap(true);
            layout->addWidget(label);
        }

        if (body != nullptr) {
            body->setParent(this);
            layout->addWidget(body);
        }

        auto* box = new QDialogButtonBox(buttons, this);
        if (QPushButton* accept = box->button(QDialogButtonBox::Ok)) {
            if (!acceptText.isEmpty()) {
                accept->setText(acceptText);
            }
            accept->setObjectName(destructive ? QStringLiteral("dangerButton")
                                              : QStringLiteral("primaryButton"));
            accept->setDefault(true);
        }
        if (QPushButton* cancel = box->button(QDialogButtonBox::Cancel)) {
            cancel->setObjectName(QStringLiteral("secondaryButton"));
        }
        if (QPushButton* okOnly = box->button(QDialogButtonBox::Close)) {
            okOnly->setObjectName(QStringLiteral("primaryButton"));
        }
        layout->addWidget(box);

        connect(box, &QDialogButtonBox::accepted, this, &QDialog::accept);
        connect(box, &QDialogButtonBox::rejected, this, &QDialog::reject);

        setMinimumWidth(380);
    }
};

void showAcknowledgement(QWidget* parent, const QString& title, const QString& text) {
    MessageDialog dialog(parent, title, text, nullptr, QDialogButtonBox::Close, QString(), false);
    dialog.exec();
}

}  // namespace

bool confirm(QWidget* parent,
             const QString& title,
             const QString& text,
             const QString& acceptText,
             bool destructive) {
    MessageDialog dialog(parent,
                         title,
                         text,
                         nullptr,
                         QDialogButtonBox::Ok | QDialogButtonBox::Cancel,
                         acceptText,
                         destructive);
    return dialog.exec() == QDialog::Accepted;
}

void info(QWidget* parent, const QString& title, const QString& text) {
    showAcknowledgement(parent, title, text);
}

void warn(QWidget* parent, const QString& title, const QString& text) {
    showAcknowledgement(parent, title, text);
}

void error(QWidget* parent, const QString& title, const QString& text) {
    showAcknowledgement(parent, title, text);
}

std::optional<QString> promptText(QWidget* parent,
                                  const QString& title,
                                  const QString& label,
                                  const QString& initialValue,
                                  bool passwordMode) {
    auto* edit = new QLineEdit(initialValue);
    if (passwordMode) {
        edit->setEchoMode(QLineEdit::Password);
    }
    edit->selectAll();

    MessageDialog dialog(parent,
                         title,
                         label,
                         edit,
                         QDialogButtonBox::Ok | QDialogButtonBox::Cancel,
                         QString(),
                         false);
    edit->setFocus();
    if (dialog.exec() != QDialog::Accepted) {
        return std::nullopt;
    }
    return edit->text();
}

std::optional<QString> promptMultiLineText(QWidget* parent,
                                           const QString& title,
                                           const QString& label,
                                           const QString& initialValue) {
    auto* edit = new QPlainTextEdit(initialValue);
    edit->setMinimumHeight(120);

    MessageDialog dialog(parent,
                         title,
                         label,
                         edit,
                         QDialogButtonBox::Ok | QDialogButtonBox::Cancel,
                         QString(),
                         false);
    edit->setFocus();
    if (dialog.exec() != QDialog::Accepted) {
        return std::nullopt;
    }
    return edit->toPlainText();
}

std::optional<int> promptInt(QWidget* parent,
                             const QString& title,
                             const QString& label,
                             int initialValue,
                             int minValue,
                             int maxValue) {
    auto* spin = new QSpinBox();
    spin->setRange(minValue, maxValue);
    spin->setValue(initialValue);

    MessageDialog dialog(parent,
                         title,
                         label,
                         spin,
                         QDialogButtonBox::Ok | QDialogButtonBox::Cancel,
                         QString(),
                         false);
    spin->setFocus();
    spin->selectAll();
    if (dialog.exec() != QDialog::Accepted) {
        return std::nullopt;
    }
    return spin->value();
}

std::optional<QString> promptChoice(QWidget* parent,
                                    const QString& title,
                                    const QString& label,
                                    const QStringList& choices,
                                    int currentIndex) {
    auto* combo = new QComboBox();
    combo->addItems(choices);
    if (currentIndex >= 0 && currentIndex < choices.size()) {
        combo->setCurrentIndex(currentIndex);
    }

    MessageDialog dialog(parent,
                         title,
                         label,
                         combo,
                         QDialogButtonBox::Ok | QDialogButtonBox::Cancel,
                         QString(),
                         false);
    combo->setFocus();
    if (dialog.exec() != QDialog::Accepted) {
        return std::nullopt;
    }
    return combo->currentText();
}

}  // namespace gbm::dialogs
