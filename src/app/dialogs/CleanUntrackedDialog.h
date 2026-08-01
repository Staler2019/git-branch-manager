#pragma once

#include "app/dialogs/DialogTypes.h"

#include <QDialog>

namespace gbm {

class RepositorySession;

/// Previews untracked (optionally ignored) files and removes the checked
/// ones. Owns its own list and talks straight to `RepositorySession`.
class CleanUntrackedDialog : public QDialog {
    Q_OBJECT

public:
    CleanUntrackedDialog(RepositorySession* session,
                         RunWithFeedbackFn runWithFeedback,
                         QWidget* parent = nullptr);
};

}  // namespace gbm
