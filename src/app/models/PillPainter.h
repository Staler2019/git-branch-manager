#pragma once

#include "core/git/RefStore.h"

#include <QColor>
#include <QFont>
#include <QFontMetrics>
#include <QRect>
#include <QString>

class QPainter;

namespace gbm {

/// Colours for one pill. `fill` invalid (default `QColor()`) means border
/// only, matching `.gbm-tag-tag` / `.gbm-tag-remote` in
/// `docs/design/tokens-reference.md`, which are outlined rather than filled.
struct PillColors {
    QColor text;
    QColor border;
    QColor fill;
};

/// Shared rounded "gbm-tag" pill painter (`docs/design/tokens-reference.md`,
/// `.gbm-tag`). Extracted out of `RefRowDelegate` -- the sidebar's
/// branch/remote/tag pills are the one part of the app that already matched
/// the design -- so `CommitRowDelegate`'s commit-row ref chips draw the exact
/// same pill instead of a second, independently drifting implementation.
class PillPainter {
public:
    static constexpr int kHeight = 20;
    static constexpr int kHorizontalPad = 8;

    /// Width a pill for `text` under `metrics` would need, clamped to at
    /// least `kHeight` (so a one-character pill stays circular-ish rather
    /// than squashed). Callers doing right-to-left layout of several pills
    /// call this first for every pill before painting any of them.
    static int widthFor(const QString& text, const QFontMetrics& metrics);

    /// Paints one pill filling exactly `rect` -- vertically centered text,
    /// rounded corners at `kHeight / 2`, optional fill, 1px border.
    static void paint(QPainter* painter,
                      const QRect& rect,
                      const QString& text,
                      const QFont& font,
                      const PillColors& colors);

    /// The `.gbm-tag-branch` / `.gbm-tag-branch.current` / `.gbm-tag-tag` /
    /// `.gbm-tag-remote` colour rules from
    /// `docs/design/tokens-reference.md`, shared by every pill in the app: a
    /// local branch is accent-outlined, accent-filled when it is HEAD; a
    /// remote branch is tertiary-outlined; a tag is warning-outlined.
    static PillColors colorsForRef(RefKind kind, bool isHead);
};

}  // namespace gbm
