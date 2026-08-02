#include "app/bridge/ThemeManager.h"

#include "app/theme/Metrics.h"
#include "app/theme/ThemeTokens.h"

#include <QApplication>
#include <QFile>
#include <QFontDatabase>
#include <QSettings>
#include <QStyleFactory>
#include <QTextStream>

#include <array>
#include <utility>

namespace gbm {

namespace {

constexpr auto kThemeSettingsKey = "appearance/theme";
constexpr auto kDensitySettingsKey = "appearance/density";

/// The theme most recently passed to `ThemeManager::apply()`, so the
/// zero-argument `color(Token)` overload and `graphLane()`/`rowHeight()` have
/// something to read without every caller threading a `ThemeId` through.
ThemeId& currentTheme() {
    static ThemeId theme = ThemeId::DarkTechnical;
    return theme;
}

Density& currentDensity() {
    static Density density = Density::Comfortable;
    return density;
}

/// `@token-name` placeholder <-> `Token` mapping used by `app.qss`. The name
/// matches the design's CSS custom-property name with the leading `--`
/// dropped and replaced by `@` (e.g. `--surface-panel` -> `@surface-panel`),
/// so anyone porting a new selector out of `components.css` can guess the
/// placeholder name without checking this table first. Longer names that
/// share a prefix with a shorter one (`@accent-hover` vs `@accent`) are
/// listed before the shorter name, since substitution is a plain sequential
/// string replace.
const std::array<std::pair<const char*, Token>, 37>& placeholderTable() {
    static const std::array<std::pair<const char*, Token>, 37> table{{
        {"@surface-app", Token::SurfaceApp},
        {"@surface-panel-raised", Token::SurfacePanelRaised},
        {"@surface-panel", Token::SurfacePanel},
        {"@surface-sunken", Token::SurfaceSunken},
        {"@surface-hover", Token::SurfaceHover},
        {"@surface-selected", Token::SurfaceSelected},
        {"@surface-overlay", Token::SurfaceOverlay},
        {"@border-subtle", Token::BorderSubtle},
        {"@border-default", Token::BorderDefault},
        {"@border-strong", Token::BorderStrong},
        {"@border-focus", Token::BorderFocus},
        {"@text-primary", Token::TextPrimary},
        {"@text-secondary", Token::TextSecondary},
        {"@text-tertiary", Token::TextTertiary},
        {"@text-on-accent", Token::TextOnAccent},
        {"@text-link", Token::TextLink},
        {"@accent-hover", Token::AccentHover},
        {"@accent-active", Token::AccentActive},
        {"@accent-subtle", Token::AccentSubtle},
        {"@accent", Token::Accent},
        {"@success", Token::Success},
        {"@danger-hover", Token::DangerHover},
        {"@danger", Token::Danger},
        {"@warning", Token::Warning},
        {"@diff-add-bg", Token::DiffAddBg},
        {"@diff-add-text", Token::DiffAddText},
        {"@diff-add-strong", Token::DiffAddStrong},
        {"@diff-del-bg", Token::DiffDelBg},
        {"@diff-del-text", Token::DiffDelText},
        {"@diff-del-strong", Token::DiffDelStrong},
        {"@scrollbar-thumb", Token::ScrollbarThumb},
        {"@graph-lane-1", Token::GraphLane1},
        {"@graph-lane-2", Token::GraphLane2},
        {"@graph-lane-3", Token::GraphLane3},
        {"@graph-lane-4", Token::GraphLane4},
        {"@graph-lane-5", Token::GraphLane5},
        {"@graph-lane-6", Token::GraphLane6},
    }};
    return table;
}

}  // namespace

namespace {

// New values are stored offset by this much, so they cannot collide with a
// legacy `Theme::System/Light/Dark` (0/1/2) value already on disk from before
// this migration -- `ThemeId::NeutralProfessional` is 2 as a raw ordinal,
// the same integer the legacy enum used for `Theme::Dark`, so storing raw
// ordinals directly would make a freshly saved `NeutralProfessional`
// indistinguishable from an old `Dark` on the next load.
constexpr int kNewValueOffset = 10;

}  // namespace

ThemeId ThemeManager::loadSetting() {
    QSettings settings;
    const int stored = settings.value(QLatin1String(kThemeSettingsKey), -1).toInt();
    if (stored >= kNewValueOffset) {
        switch (stored - kNewValueOffset) {
            case static_cast<int>(ThemeId::LightIde):
                return ThemeId::LightIde;
            case static_cast<int>(ThemeId::NeutralProfessional):
                return ThemeId::NeutralProfessional;
            default:
                return ThemeId::DarkTechnical;
        }
    }
    switch (stored) {
        case 1:  // legacy Theme::Light
            return ThemeId::LightIde;
        case 0:   // legacy Theme::System
        case 2:   // legacy Theme::Dark
        default:  // unset
            return ThemeId::DarkTechnical;
    }
}

void ThemeManager::saveSetting(ThemeId theme) {
    QSettings settings;
    settings.setValue(QLatin1String(kThemeSettingsKey), kNewValueOffset + static_cast<int>(theme));
}

Density ThemeManager::loadDensitySetting() {
    QSettings settings;
    const int stored = settings.value(QLatin1String(kDensitySettingsKey), 0).toInt();
    return stored == 1 ? Density::Compact : Density::Comfortable;
}

void ThemeManager::saveDensitySetting(Density density) {
    QSettings settings;
    settings.setValue(QLatin1String(kDensitySettingsKey), density == Density::Compact ? 1 : 0);
    currentDensity() = density;
}

QPalette ThemeManager::paletteFor(ThemeId theme) {
    QPalette palette;
    palette.setColor(QPalette::Window, color(theme, Token::SurfaceApp));
    palette.setColor(QPalette::WindowText, color(theme, Token::TextPrimary));
    palette.setColor(QPalette::Base, color(theme, Token::SurfacePanel));
    palette.setColor(QPalette::AlternateBase, color(theme, Token::SurfaceSunken));
    palette.setColor(QPalette::Text, color(theme, Token::TextPrimary));
    palette.setColor(QPalette::Button, color(theme, Token::SurfacePanelRaised));
    palette.setColor(QPalette::ButtonText, color(theme, Token::TextPrimary));
    palette.setColor(QPalette::Highlight, color(theme, Token::Accent));
    palette.setColor(QPalette::HighlightedText, color(theme, Token::TextOnAccent));
    palette.setColor(QPalette::Link, color(theme, Token::TextLink));
    palette.setColor(QPalette::ToolTipBase, color(theme, Token::SurfaceOverlay));
    palette.setColor(QPalette::ToolTipText, color(theme, Token::TextPrimary));

    QColor disabledText = color(theme, Token::TextTertiary);
    disabledText.setAlphaF(0.45F);
    palette.setColor(QPalette::Disabled, QPalette::Text, disabledText);
    palette.setColor(QPalette::Disabled, QPalette::WindowText, disabledText);
    palette.setColor(QPalette::Disabled, QPalette::ButtonText, disabledText);
    return palette;
}

void ThemeManager::ensureFontsRegistered() {
    // `QFontDatabase::addApplicationFont` re-parses and re-registers the font
    // on every call, so this must run at most once regardless of how many
    // times `apply()` is called across a session's theme switches.
    static const bool registered = [] {
        for (const char* resource : {":/fonts/Inter-Regular.ttf",
                                     ":/fonts/Inter-Medium.ttf",
                                     ":/fonts/Inter-SemiBold.ttf",
                                     ":/fonts/Inter-Bold.ttf",
                                     ":/fonts/JetBrainsMono-Regular.ttf",
                                     ":/fonts/JetBrainsMono-Medium.ttf"}) {
            QFontDatabase::addApplicationFont(QLatin1String(resource));
        }
        return true;
    }();
    Q_UNUSED(registered);
}

QString ThemeManager::applyTokensToQss(const QString& qssTemplate, ThemeId theme) {
    QString result = qssTemplate;
    for (const auto& [placeholder, token] : placeholderTable()) {
        result.replace(QLatin1String(placeholder), color(theme, token).name());
    }
    return result;
}

void ThemeManager::apply(ThemeId theme) {
    currentTheme() = theme;
    currentDensity() = loadDensitySetting();

    ensureFontsRegistered();

    // Native styles are free to ignore large parts of a custom QPalette (and
    // all of a stylesheet); Fusion is the one style guaranteed to respect
    // both, which is the only way three fully custom themes can look right.
    QApplication::setStyle(QStyleFactory::create(QStringLiteral("Fusion")));
    QApplication::setPalette(paletteFor(theme));

    QFile qssFile(QStringLiteral(":/qss/app.qss"));
    if (qssFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream stream(&qssFile);
        const QString qssTemplate = stream.readAll();
        qApp->setStyleSheet(applyTokensToQss(qssTemplate, theme));
    } else {
        // Not silent: this exact failure (":/qss/app.qss" missing from the
        // resource system) previously went unnoticed for the whole app's
        // life because the QPalette and every hand-painted delegate still
        // produced a plausible-looking window with no stylesheet at all --
        // see the AUTORCC comment in src/app/CMakeLists.txt for the root
        // cause and how it was found.
        qWarning("ThemeManager: could not open :/qss/app.qss (%s) -- the "
                 "resource is missing from this build, so no stylesheet was applied",
                 qUtf8Printable(qssFile.errorString()));
    }

    saveSetting(theme);
}

QString ThemeManager::label(ThemeId theme) {
    switch (theme) {
        case ThemeId::DarkTechnical:
            return QStringLiteral("Dark technical");
        case ThemeId::LightIde:
            return QStringLiteral("Light IDE");
        case ThemeId::NeutralProfessional:
            return QStringLiteral("Neutral professional");
    }
    return QStringLiteral("Dark technical");
}

QColor ThemeManager::color(ThemeId theme, Token token) {
    return tokenColor(theme, token);
}

QColor ThemeManager::color(Token token) {
    return tokenColor(currentTheme(), token);
}

QColor ThemeManager::graphLane(std::uint8_t index) {
    static constexpr std::array<Token, kGraphLaneCount> kLanes{
        Token::GraphLane1,
        Token::GraphLane2,
        Token::GraphLane3,
        Token::GraphLane4,
        Token::GraphLane5,
        Token::GraphLane6,
    };
    return tokenColor(currentTheme(), kLanes[index % kGraphLaneCount]);
}

int ThemeManager::rowHeight() {
    return currentDensity() == Density::Compact ? kRowHeightCompact : kRowHeightComfortable;
}

QFont ThemeManager::uiFont(int pixelSize) {
    QFont font;
    // `--font-ui:"Inter",-apple-system,"Segoe UI",sans-serif`. Qt has no
    // native `-apple-system` name, so the fallback chain drops straight to
    // platform-appropriate system fonts if Inter failed to register.
    font.setFamilies({QStringLiteral("Inter"),
                      QStringLiteral("Segoe UI"),
                      QStringLiteral("Helvetica Neue"),
                      QStringLiteral("sans-serif")});
    font.setPixelSize(pixelSize);
    return font;
}

QFont ThemeManager::monoFont(int pixelSize) {
    QFont font;
    // `--font-mono:"JetBrains Mono","SF Mono",Consolas,monospace`.
    font.setFamilies({QStringLiteral("JetBrains Mono"),
                      QStringLiteral("SF Mono"),
                      QStringLiteral("Consolas"),
                      QStringLiteral("monospace")});
    font.setPixelSize(pixelSize);
    font.setStyleHint(QFont::Monospace);
    return font;
}

}  // namespace gbm
