#pragma once

#include "app/dialogs/DialogTypes.h"

#include <QDialog>

namespace gbm {

class RepositorySession;

/// Lists every submodule and offers add/init/update/sync/deinit. Owns its
/// own table and talks straight to `RepositorySession`.
class ManageSubmodulesDialog : public QDialog {
    Q_OBJECT

public:
    ManageSubmodulesDialog(RepositorySession* session,
                           RunWithFeedbackFn runWithFeedback,
                           QWidget* parent = nullptr);
};

}  // namespace gbm
