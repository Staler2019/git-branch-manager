#pragma once

#include <QDialog>

namespace gbm {

/// Minimal, static reference of the shortcuts MainWindow actually binds
/// today. Not generated from the action list -- keep this in sync by hand
/// when `buildMenus()` gains or loses a shortcut.
class KeyboardShortcutsDialog : public QDialog {
    Q_OBJECT

public:
    explicit KeyboardShortcutsDialog(QWidget* parent = nullptr);
};

}  // namespace gbm
