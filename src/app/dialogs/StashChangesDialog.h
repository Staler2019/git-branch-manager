#pragma once

#include "core/git/ops/StashOps.h"

#include <QDialog>

class QLineEdit;
class QCheckBox;

namespace gbm {

/// Message + "include untracked" picker shown before saving a new stash.
class StashChangesDialog : public QDialog {
    Q_OBJECT

public:
    explicit StashChangesDialog(QWidget* parent = nullptr);

    /// Valid only after `exec()` returned `QDialog::Accepted`.
    StashSaveRequest request() const;

private:
    QLineEdit* messageEdit_ = nullptr;
    QCheckBox* includeUntracked_ = nullptr;
};

}  // namespace gbm
