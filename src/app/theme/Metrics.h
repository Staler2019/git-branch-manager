#pragma once

namespace gbm {

// Spacing scale, from `docs/design/tokens-reference.md` (`spacing.css`).
constexpr int kSpace1 = 4;
constexpr int kSpace2 = 8;
constexpr int kSpace3 = 12;
constexpr int kSpace4 = 16;
constexpr int kSpace5 = 20;
constexpr int kSpace6 = 24;
constexpr int kSpace8 = 32;
constexpr int kSpace10 = 40;
constexpr int kSpace12 = 48;
constexpr int kSpace16 = 64;

// Corner radii.
constexpr int kRadiusSm = 4;
constexpr int kRadiusMd = 6;
constexpr int kRadiusLg = 10;
constexpr int kRadiusFull = 999;

// Row heights, density-selected at runtime via `ThemeManager::rowHeight()`.
constexpr int kRowHeightComfortable = 34;
constexpr int kRowHeightCompact = 26;

// Type scale (pixel sizes, matching the design's px-based `--text-*` tokens).
// Qt's `QFont::setPixelSize` takes an int, so the one fractional value
// (`--text-sm: 12.5px`) is rounded to the nearest whole pixel rather than
// mixing point- and pixel-based sizing across the scale.
constexpr int kTextXs = 11;
constexpr int kTextSm = 13;    // 12.5px, rounded.
constexpr int kTextBase = 14;  // 13.5px, rounded.
constexpr int kTextMd = 15;
constexpr int kTextLg = 18;
constexpr int kTextXl = 22;
constexpr int kText2xl = 28;

}  // namespace gbm
