#pragma once

#include "app/dialogs/DialogTypes.h"

#include <QDialog>

namespace gbm {

class RepositorySession;

/// Starts and drives a bisect session: bad/good commit entry while idle,
/// then good/bad/skip/reset controls and a running log while active. Owns
/// its own widgets and talks straight to `RepositorySession`.
class BisectDialog : public QDialog {
    Q_OBJECT

public:
    BisectDialog(RepositorySession* session,
                 RunWithFeedbackFn runWithFeedback,
                 QWidget* parent = nullptr);
};

}  // namespace gbm
