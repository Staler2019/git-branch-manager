#pragma once

#include "app/theme/Tokens.h"

#include <QColor>

namespace gbm {

/// Resolves a semantic `Token` to its concrete colour for one theme. This is
/// the single source of truth every consumer reads through -- the QSS
/// substitution in `ThemeManager::apply`, the `QPalette` it builds, and
/// hand-painting code such as `GraphColumnDelegate::laneColor` and the diff
/// views. Values are transcribed verbatim from
/// `docs/design/tokens-reference.md` (`colors.css`); do not approximate.
const QColor& tokenColor(ThemeId theme, Token token);

/// Shadow role, carried for later phases (menus/dialogs). Phase 0 only needs a
/// sensible stub: QSS has no `box-shadow`, so shadows are applied later via
/// `QGraphicsDropShadowEffect` rather than the stylesheet, and nothing in this
/// phase consumes this yet.
enum class ShadowRole { Small, Medium, Large };

/// Alpha-blended shadow colour for `role` in `theme`, approximating
/// `effects.css`'s `--shadow-sm/md/lg` (dark themes use a stronger shadow).
/// Real blur/offset application is deferred to the phase that adds menu and
/// dialog chrome.
QColor shadowColor(ThemeId theme, ShadowRole role);

}  // namespace gbm
