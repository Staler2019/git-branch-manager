#pragma once

#include "app/theme/Tokens.h"

#include <QColor>
#include <QFont>
#include <QPalette>
#include <QString>

#include <cstdint>

namespace gbm {

/// Applies and persists the app's colour theme and row density, and is the
/// single accessor every consumer -- QSS, `QPalette`, and hand-painting code
/// such as `GraphColumnDelegate` and the diff views -- reads colours through.
///
/// `apply()` always switches to the Fusion style: native styles are free to
/// ignore large parts of a custom `QPalette` (and all of a stylesheet), so
/// there is no way to make three fully custom themes look right on a native
/// style. Fusion is guaranteed to respect both.
class ThemeManager {
public:
    /// Reads the persisted choice (QSettings, defaults to `DarkTechnical`).
    /// Migrates the legacy `Theme` values this key used to store: old
    /// `System` (0) and `Dark` (2) both become `DarkTechnical`, old `Light`
    /// (1) becomes `LightIde` -- so an existing user's saved preference never
    /// silently turns into an unrelated theme.
    static ThemeId loadSetting();

    static void saveSetting(ThemeId theme);

    static Density loadDensitySetting();

    static void saveDensitySetting(Density density);

    /// Applies `theme` to the running QApplication: registers the bundled
    /// fonts (once), forces the Fusion style, builds a `QPalette` from the
    /// token table, and pushes `:/qss/app.qss` with every `@token` placeholder
    /// substituted. Safe to call before or after any windows exist; existing
    /// widgets re-polish immediately. Persists the choice via `saveSetting`.
    static void apply(ThemeId theme);

    static QString label(ThemeId theme);

    /// Colour for `token` under `theme`, regardless of what is currently applied.
    static QColor color(ThemeId theme, Token token);

    /// Colour for `token` under the theme most recently passed to `apply()`.
    static QColor color(Token token);

    /// Cycles through the six `GraphLaneN` tokens of the current theme.
    static QColor graphLane(std::uint8_t index);

    /// Row height in pixels for the current density setting.
    static int rowHeight();

    static QFont uiFont(int pixelSize);

    static QFont monoFont(int pixelSize);

    /// Uppercase, semibold, letter-spaced label font for sidebar section
    /// headers ("REPOSITORIES", "STASH", ...). QSS cannot express
    /// letter-spacing, so both the painted headers (`RefRowDelegate`) and the
    /// plain `QLabel` ones (`SidebarPanel`'s Repositories/Stash sections)
    /// call this instead of each hand-rolling their own QFont, which is what
    /// let them drift apart in the first place.
    static QFont sectionHeaderFont();

    /// Substitutes every `@token-name` placeholder in `qssTemplate` (see
    /// `resources/qss/app.qss` for the naming convention) with the hex colour
    /// for `theme`. Exposed as a pure, testable function -- separate from
    /// `apply()` -- so `ThemeTest` can assert no placeholder survives
    /// substitution for any theme without needing a live `QApplication` style
    /// change.
    static QString applyTokensToQss(const QString& qssTemplate, ThemeId theme);

private:
    static QPalette paletteFor(ThemeId theme);
    static void ensureFontsRegistered();
};

}  // namespace gbm
