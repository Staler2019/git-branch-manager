#pragma once

#include <QPalette>
#include <QString>

namespace gbm {

enum class Theme { System, Light, Dark };

/// Applies and persists the app's colour theme.
///
/// Qt's own system-colour-scheme detection (`QStyleHints::colorScheme`) needs
/// Qt 6.5; this app's floor is 6.4, so `System` is implemented as "leave the
/// platform's own palette and style alone" rather than actively detecting
/// dark mode -- on most desktops the platform theme plugin already does the
/// right thing for the default palette, and this never fights it. `Light` and
/// `Dark` switch to the Fusion style with an explicit palette, because native
/// styles are free to ignore large parts of a custom QPalette.
class ThemeManager {
public:
    /// Reads the persisted choice (QSettings, defaults to System).
    static Theme loadSetting();

    static void saveSetting(Theme theme);

    /// Applies `theme` to the running QApplication. Safe to call before or
    /// after any windows exist; existing widgets re-polish immediately.
    static void apply(Theme theme);

    static QString label(Theme theme);

private:
    static QPalette lightPalette();
    static QPalette darkPalette();
};

}  // namespace gbm
