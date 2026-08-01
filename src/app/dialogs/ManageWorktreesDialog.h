#pragma once

#include "app/dialogs/DialogTypes.h"

#include <QDialog>

namespace gbm {

class RepositorySession;

/// Lists every worktree and offers add/remove/lock/unlock/prune. Owns its
/// own table and talks straight to `RepositorySession`.
class ManageWorktreesDialog : public QDialog {
    Q_OBJECT

public:
    ManageWorktreesDialog(RepositorySession* session,
                          RunWithFeedbackFn runWithFeedback,
                          QWidget* parent = nullptr);
};

}  // namespace gbm
