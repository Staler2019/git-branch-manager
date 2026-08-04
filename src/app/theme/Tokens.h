#pragma once

#include <cstdint>

namespace gbm {

/// One entry per selectable visual direction. `DarkTechnical` is the app
/// default (see `ThemeManager::loadSetting`).
enum class ThemeId { DarkTechnical, LightIde, NeutralProfessional };

/// Row-height / spacing density, independent of the colour theme.
enum class Density { Comfortable, Compact };

/// Semantic colour tokens, transcribed 1:1 from `docs/design/tokens-reference.md`
/// (`colors.css`). Every consumer -- QSS placeholders, `QPalette` construction and
/// hand-painting code such as `GraphColumnDelegate` -- reads through this single
/// enum so the three themes cannot drift against each other.
enum class Token {
    SurfaceApp,
    SurfacePanel,
    SurfacePanelRaised,
    SurfaceSunken,
    SurfaceHover,
    SurfaceSelected,
    SurfaceOverlay,
    BorderSubtle,
    BorderDefault,
    BorderStrong,
    BorderFocus,
    TextPrimary,
    TextSecondary,
    TextTertiary,
    TextOnAccent,
    TextLink,
    Accent,
    AccentHover,
    AccentActive,
    AccentSubtle,
    /// Non-HEAD local-branch ref chip (PillPainter::colorsForRef). Deliberately
    /// its own tokens rather than reusing Accent/AccentSubtle: AccentSubtle is
    /// byte-identical to SurfaceSelected in the dark and neutral themes, so a
    /// chip painted with it disappears entirely on a selected commit row.
    /// RefChipFill doubles as the chip's border, matching how the HEAD chip
    /// already uses one token (Accent) for both.
    RefChipFill,
    RefChipText,
    Success,
    Danger,
    DangerHover,
    Warning,
    DiffAddBg,
    DiffAddText,
    DiffDelBg,
    DiffDelText,
    DiffAddStrong,
    DiffDelStrong,
    ScrollbarThumb,

    // The six commit-graph lane colours (`--graph-lane-1`..`--graph-lane-6`).
    // Kept as part of `Token` rather than a separate enum so `tokenColor()` has
    // one signature for every colour in the table; `ThemeManager::graphLane()`
    // maps a 0-based lane index onto these cyclically.
    GraphLane1,
    GraphLane2,
    GraphLane3,
    GraphLane4,
    GraphLane5,
    GraphLane6,
};

/// Number of `GraphLaneN` tokens, used to cycle a lane index into the table.
constexpr int kGraphLaneCount = 6;

}  // namespace gbm
