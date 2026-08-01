#pragma once

#include "core/git/ops/MergeOps.h"

#include <QDialog>
#include <QString>

class QRadioButton;
class QLineEdit;

namespace gbm {

/// Merge-mode picker shown before merging a ref into the current branch.
/// Mirrors `CredentialDialog`: construct, `exec()`, then read the result back
/// via `request()` -- the dialog itself never talks to `RepositorySession`.
class MergeDialog : public QDialog {
    Q_OBJECT

public:
    MergeDialog(const QString& targetName, QWidget* parent = nullptr);

    /// Valid only after `exec()` returned `QDialog::Accepted`.
    MergeRequest request() const;

private:
    QString targetName_;
    QRadioButton* ffOnly_ = nullptr;
    QRadioButton* noFf_ = nullptr;
    QRadioButton* squash_ = nullptr;
    QLineEdit* messageEdit_ = nullptr;
};

}  // namespace gbm
