#pragma once

#include <QDialog>
#include <QString>

class QLineEdit;

namespace gbm {

/// The one dialog the askpass handshake ever shows: git's own prompt text,
/// verbatim, plus a single input. Whether that input is a username or a
/// password is not part of the protocol -- only the wording of the prompt says
/// so -- hence the case-insensitive sniff for "password"/"passphrase" that
/// decides the echo mode.
class CredentialDialog : public QDialog {
    Q_OBJECT

public:
    explicit CredentialDialog(const QString& prompt, QWidget* parent = nullptr);

    QString value() const;

private:
    QLineEdit* edit_ = nullptr;
};

}  // namespace gbm
