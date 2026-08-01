#include "app/theme/ThemeTokens.h"

#include <array>
#include <cstddef>

namespace gbm {

namespace {

// One row per `Token`, in declaration order. Keeping the three theme tables as
// parallel arrays (rather than, say, a QHash per theme) makes it obvious at a
// glance that every theme defines every token, and a mismatched row count is a
// compile-time array-size error rather than a silent runtime gap.
constexpr int kTokenCount = 37;

using TokenTable = std::array<const char*, kTokenCount>;

// clang-format off

// [data-theme="dark-technical"] in colors.css.
constexpr TokenTable kDarkTechnical{{
    "#0d1117",  // SurfaceApp
    "#0d1117",  // SurfacePanel
    "#161b22",  // SurfacePanelRaised
    "#010409",  // SurfaceSunken
    "#161b22",  // SurfaceHover
    "#0d2a4d",  // SurfaceSelected
    "#1c2128",  // SurfaceOverlay
    "#21262d",  // BorderSubtle
    "#30363d",  // BorderDefault
    "#3d444d",  // BorderStrong
    "#2f81f7",  // BorderFocus
    "#e6edf3",  // TextPrimary
    "#9198a1",  // TextSecondary
    "#6e7681",  // TextTertiary
    "#ffffff",  // TextOnAccent
    "#4c9bff",  // TextLink
    "#2f81f7",  // Accent
    "#4c9bff",  // AccentHover
    "#1f6ce0",  // AccentActive
    "#0d2a4d",  // AccentSubtle
    "#3fb950",  // Success
    "#f85149",  // Danger
    "#ff6a63",  // DangerHover
    "#d29922",  // Warning
    "#0f2e1a",  // DiffAddBg
    "#7ee2a8",  // DiffAddText
    "#3a1414",  // DiffDelBg
    "#ff9b93",  // DiffDelText
    "#173e24",  // DiffAddStrong
    "#4d1c1c",  // DiffDelStrong
    "#30363d",  // ScrollbarThumb
    "#4c9bff",  // GraphLane1
    "#a371f7",  // GraphLane2
    "#3fb950",  // GraphLane3
    "#d29922",  // GraphLane4
    "#f85149",  // GraphLane5
    "#39c5cf",  // GraphLane6
}};

// [data-theme="light-ide"] in colors.css.
constexpr TokenTable kLightIde{{
    "#ffffff",  // SurfaceApp
    "#ffffff",  // SurfacePanel
    "#ffffff",  // SurfacePanelRaised
    "#f5f6f8",  // SurfaceSunken
    "#f0f2f5",  // SurfaceHover
    "#e4edfd",  // SurfaceSelected
    "#ffffff",  // SurfaceOverlay
    "#eaecef",  // BorderSubtle
    "#dcdfe4",  // BorderDefault
    "#c6cad1",  // BorderStrong
    "#2f81f7",  // BorderFocus
    "#1c2128",  // TextPrimary
    "#57606a",  // TextSecondary
    "#8b949e",  // TextTertiary
    "#ffffff",  // TextOnAccent
    "#1f6ce0",  // TextLink
    "#2f81f7",  // Accent
    "#1f6ce0",  // AccentHover
    "#1857b8",  // AccentActive
    "#eaf1fe",  // AccentSubtle
    "#1a7f37",  // Success
    "#cf222e",  // Danger
    "#a40e26",  // DangerHover
    "#9a6700",  // Warning
    "#e9fbee",  // DiffAddBg
    "#116329",  // DiffAddText
    "#ffebe9",  // DiffDelBg
    "#82241f",  // DiffDelText
    "#c9f0d4",  // DiffAddStrong
    "#ffc9c2",  // DiffDelStrong
    "#dcdfe4",  // ScrollbarThumb
    "#2f81f7",  // GraphLane1
    "#8250df",  // GraphLane2
    "#1a7f37",  // GraphLane3
    "#9a6700",  // GraphLane4
    "#cf222e",  // GraphLane5
    "#1b7c83",  // GraphLane6
}};

// `:root,[data-theme="neutral-professional"]` in colors.css -- the sheet's own
// default block, with `--gray-*`/`--accent-*`/etc. `var()` references resolved
// to their literal hex values by hand (QSS has no `var()`, so this resolution
// has to happen once, here, rather than at every call site).
constexpr TokenTable kNeutralProfessional{{
    "#f7f8f9",  // SurfaceApp        (gray-50)
    "#ffffff",  // SurfacePanel      (base-white)
    "#ffffff",  // SurfacePanelRaised(base-white)
    "#eef0f2",  // SurfaceSunken     (gray-100)
    "#eef0f2",  // SurfaceHover      (gray-100)
    "#eaf1fe",  // SurfaceSelected   (accent-50)
    "#ffffff",  // SurfaceOverlay    (base-white)
    "#dfe3e7",  // BorderSubtle      (gray-200)
    "#c3cad1",  // BorderDefault     (gray-300)
    "#98a3ad",  // BorderStrong      (gray-400)
    "#2f81f7",  // BorderFocus       (accent-500)
    "#171b1f",  // TextPrimary       (gray-900)
    "#4f5966",  // TextSecondary     (gray-600)
    "#6b7684",  // TextTertiary      (gray-500)
    "#ffffff",  // TextOnAccent      (base-white)
    "#1f6ce0",  // TextLink          (accent-600)
    "#2f81f7",  // Accent            (accent-500)
    "#1f6ce0",  // AccentHover       (accent-600)
    "#1857b8",  // AccentActive      (accent-700)
    "#eaf1fe",  // AccentSubtle      (accent-50)
    "#1a8a4a",  // Success           (green-500)
    "#d33d3d",  // Danger            (red-500)
    "#b32c2c",  // DangerHover       (red-600)
    "#c97a17",  // Warning           (amber-500)
    "#e6f6ec",  // DiffAddBg
    "#136c37",  // DiffAddText
    "#fbeaea",  // DiffDelBg
    "#a32e2e",  // DiffDelText
    "#bfe9cd",  // DiffAddStrong
    "#f3c8c8",  // DiffDelStrong
    "#c3cad1",  // ScrollbarThumb    (gray-300)
    "#2f81f7",  // GraphLane1        (accent-500)
    "#7358d1",  // GraphLane2        (purple-500)
    "#1a8a4a",  // GraphLane3        (green-500)
    "#c97a17",  // GraphLane4        (amber-500)
    "#d33d3d",  // GraphLane5        (red-500)
    "#0e9aa7",  // GraphLane6
}};

// clang-format on

static_assert(kDarkTechnical.size() == kTokenCount);
static_assert(kLightIde.size() == kTokenCount);
static_assert(kNeutralProfessional.size() == kTokenCount);

const TokenTable& tableFor(ThemeId theme) {
    switch (theme) {
        case ThemeId::DarkTechnical:
            return kDarkTechnical;
        case ThemeId::LightIde:
            return kLightIde;
        case ThemeId::NeutralProfessional:
            return kNeutralProfessional;
    }
    return kDarkTechnical;
}

}  // namespace

const QColor& tokenColor(ThemeId theme, Token token) {
    // One `QColor` per (theme, token) pair, built lazily on first use and kept
    // for the life of the process -- cheap enough that eagerly building all
    // 3*37 up front would be pointless, but callers such as `laneColor` run
    // per-paint and should not reparse a hex string every frame.
    static std::array<std::array<QColor, kTokenCount>, 3> cache{};
    static std::array<std::array<bool, kTokenCount>, 3> initialized{};

    const int themeIndex = static_cast<int>(theme);
    const int tokenIndex = static_cast<int>(token);

    if (!initialized[themeIndex][tokenIndex]) {
        cache[themeIndex][tokenIndex] = QColor(QLatin1String(tableFor(theme)[tokenIndex]));
        initialized[themeIndex][tokenIndex] = true;
    }
    return cache[themeIndex][tokenIndex];
}

QColor shadowColor(ThemeId theme, ShadowRole role) {
    // `effects.css`: light/neutral themes use rgba(0,0,0,.08/.12/.18);
    // dark-technical strengthens to .4/.5/.6. Real box-shadow application
    // (blur radius, offset) is deferred to the phase that draws menu/dialog
    // chrome with `QGraphicsDropShadowEffect`; this stub only carries the
    // per-theme alpha so that phase does not have to re-derive it.
    const bool strong = theme == ThemeId::DarkTechnical;
    switch (role) {
        case ShadowRole::Small:
            return QColor(0, 0, 0, strong ? 102 : 20);  // .4 / .08
        case ShadowRole::Medium:
            return QColor(0, 0, 0, strong ? 128 : 31);  // .5 / .12
        case ShadowRole::Large:
            return QColor(0, 0, 0, strong ? 153 : 46);  // .6 / .18
    }
    return QColor(0, 0, 0, 31);
}

}  // namespace gbm
