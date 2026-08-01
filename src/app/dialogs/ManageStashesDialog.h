#pragma once

#include "app/dialogs/DialogTypes.h"

#include <QDialog>

namespace gbm {

class RepositorySession;

/// Lists every stash and offers apply/pop/drop/branch-from-stash. Owns its
/// own list widget and talks straight to `RepositorySession`; operation
/// results are reported through the same `runWithFeedback` MainWindow itself
/// uses.
class ManageStashesDialog : public QDialog {
    Q_OBJECT

public:
    ManageStashesDialog(RepositorySession* session,
                        RunWithFeedbackFn runWithFeedback,
                        QWidget* parent = nullptr);
};

}  // namespace gbm
