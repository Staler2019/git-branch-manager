#pragma once

#include "app/dialogs/DialogTypes.h"

#include <QDialog>

namespace gbm {

class RepositorySession;

/// Shows the reflog for HEAD and offers a hard reset to any entry. Owns its
/// own table and talks straight to `RepositorySession`.
class ReflogDialog : public QDialog {
    Q_OBJECT

public:
    ReflogDialog(RepositorySession* session,
                 RunWithFeedbackFn runWithFeedback,
                 QWidget* parent = nullptr);
};

}  // namespace gbm
