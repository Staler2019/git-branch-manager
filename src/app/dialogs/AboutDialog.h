#pragma once

#include <QDialog>

namespace gbm {

/// Minimal "About" dialog: app name and the version CPack/the binary itself
/// report (`gbm/Version.h`, generated from `Version.h.in`). No dependency on
/// `RepositorySession` -- reachable even with no repository open.
class AboutDialog : public QDialog {
    Q_OBJECT

public:
    explicit AboutDialog(QWidget* parent = nullptr);
};

}  // namespace gbm
