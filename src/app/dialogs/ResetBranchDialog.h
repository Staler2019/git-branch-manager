#pragma once

#include "core/git/ops/ResetOps.h"

#include <QDialog>
#include <QString>

class QRadioButton;

namespace gbm {

/// Reset-mode picker (soft/mixed/hard) shown before resetting the current
/// branch to a selected commit. The hard-reset confirmation stays at the
/// call site (MainWindow), not here: it needs `mode()` first to know whether
/// to ask at all.
class ResetBranchDialog : public QDialog {
    Q_OBJECT

public:
    ResetBranchDialog(const QString& targetShortHex, QWidget* parent = nullptr);

    /// Valid only after `exec()` returned `QDialog::Accepted`.
    ResetMode mode() const;

private:
    QRadioButton* soft_ = nullptr;
    QRadioButton* mixed_ = nullptr;
    QRadioButton* hard_ = nullptr;
};

}  // namespace gbm
