#pragma once

#include "app/theme/Tokens.h"

#include <QIcon>
#include <QString>

namespace gbm {

/// Loads the bundled Lucide SVGs (`resources/icons/`, registered under
/// `:/icons/`) and recolors them to a theme token at load time.
///
/// Qt's SVG renderer does not resolve the CSS `currentColor` keyword the
/// source files originally used, so each SVG on disk has that replaced with a
/// literal opaque colour instead (see `THIRD_PARTY_NOTICES.md`'s Lucide
/// entry). `icon()` discards that baked colour by recompositing the rendered
/// shape with `QPainter::CompositionMode_SourceIn`, so a single SVG serves
/// every token and every theme.
///
/// Baked pixmaps are cached per (name, token, pixel size, device pixel
/// ratio) because this is called from paint-adjacent code (delegates,
/// toolbar construction) where re-rendering an SVG every time would be
/// wasteful. `clearCache()` must be called on every theme switch -- see
/// `MainWindow::applyThemeAndRefresh`, which already collects every
/// theme-dependent baked-colour refresh in one place -- otherwise a widget
/// repainted after a switch would still show the previous theme's colour.
class IconLoader {
public:
    /// `name` is the SVG's file stem under `resources/icons/` (e.g.
    /// `"git-branch"` for `resources/icons/git-branch.svg`). `token` is
    /// resolved against the theme most recently passed to
    /// `ThemeManager::apply()`, consistent with `ThemeManager::color(Token)`.
    static QIcon icon(const QString& name, Token token, int pixelSize = 16);

    /// Drops every cached pixmap.
    static void clearCache();
};

}  // namespace gbm
