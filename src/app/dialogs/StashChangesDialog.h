#pragma once

#include "core/git/WorkingCopyStatus.h"
#include "core/git/ops/StashOps.h"

#include <QDialog>

class QLineEdit;
class QCheckBox;
class QListWidget;
class QDialogButtonBox;

namespace gbm {

/// Message + file picker + "include untracked" shown before saving a new
/// stash. `status` seeds the file checklist (staged + unstaged + untracked
/// paths, all checked by default so the no-op case still stashes
/// everything, matching plain `git stash push`).
class StashChangesDialog : public QDialog {
    Q_OBJECT

public:
    StashChangesDialog(WorkingCopyStatusPtr status, QWidget* parent = nullptr);

    /// Valid only after `exec()` returned `QDialog::Accepted`.
    StashSaveRequest request() const;

private:
    void rebuildFileList();
    void onIncludeUntrackedToggled(bool checked);
    /// Disables OK while nothing is checked, so accepting can never mean
    /// "stash everything" when the user meant "stash nothing".
    void updateOkEnabled();

    WorkingCopyStatusPtr status_;

    QLineEdit* messageEdit_ = nullptr;
    QCheckBox* includeUntracked_ = nullptr;
    QListWidget* fileList_ = nullptr;
    QDialogButtonBox* buttons_ = nullptr;
};

}  // namespace gbm
