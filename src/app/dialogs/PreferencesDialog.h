#pragma once

#include "app/theme/Tokens.h"

#include <QDialog>

class QCheckBox;
class QLineEdit;

namespace gbm {

/// App-wide preferences: General (clone directory, force-push confirmation),
/// Git (global-default identity, external editor) and Appearance (theme,
/// density). Everything here persists to `QSettings` under the same
/// `<category>/<key>` shape `ThemeManager.cpp` already established.
///
/// Two different depths, stated plainly rather than left to look uniform:
/// - Appearance's theme rows and density checkbox are fully wired -- theme
///   selection calls the exact same `ThemeManager::apply`/`saveSetting` path
///   the existing View > Theme menu and toolbar buttons use (see
///   `themeSelected`), and density calls `ThemeManager::saveDensitySetting`
///   through `densityToggled`, which `MainWindow::onDensityToggled` applies
///   live to every Fixed-mode view.
/// - General's clone directory / force-push confirmation and Git's global
///   identity / editor command persist to `QSettings` but nothing in the app
///   reads them back yet: there is no "open" or "clone" flow to default a
///   directory into (this app discovers repositories by scanning base
///   folders), no force-push confirmation prompt to gate, no reader for the
///   real global `git config`, and `CommitOps` passes no `--author` -- it
///   relies on `git`'s own ambient identity resolution. Recording the intent
///   now is forward-compatible; claiming it already works would not be.
class PreferencesDialog : public QDialog {
    Q_OBJECT

public:
    explicit PreferencesDialog(QWidget* parent = nullptr);

signals:
    /// Emitted the moment a theme row is picked -- MainWindow connects this
    /// straight to `applyThemeAndRefresh`, the same slot the toolbar and View
    /// menu already use, so there is exactly one theme-switching path.
    void themeSelected(ThemeId theme);

    /// Emitted the moment the density checkbox is toggled -- MainWindow
    /// connects this to `onDensityToggled`.
    void densityToggled(bool compact);

private:
    void buildUi();
    void loadSettings();
    void saveGeneralAndGitSettings();

    QLineEdit* cloneDirectoryEdit_ = nullptr;
    QCheckBox* confirmForcePushCheck_ = nullptr;

    QLineEdit* gitNameEdit_ = nullptr;
    QLineEdit* gitEmailEdit_ = nullptr;
    QLineEdit* editorCommandEdit_ = nullptr;

    QCheckBox* densityCheck_ = nullptr;
};

}  // namespace gbm
