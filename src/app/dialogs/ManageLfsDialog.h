#pragma once

#include "app/dialogs/DialogTypes.h"

#include <QDialog>

namespace gbm {

class RepositorySession;

/// Shows Git LFS availability, tracked patterns and file transfer state, and
/// offers install/track/untrack/pull/fetch/prune. Owns its own widgets and
/// talks straight to `RepositorySession`.
class ManageLfsDialog : public QDialog {
    Q_OBJECT

public:
    ManageLfsDialog(RepositorySession* session,
                    RunWithFeedbackFn runWithFeedback,
                    QWidget* parent = nullptr);
};

}  // namespace gbm
