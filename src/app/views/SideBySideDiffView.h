#pragma once

#include "core/git/UnifiedDiffParser.h"

#include <QWidget>

#include <memory>

class QPlainTextEdit;

namespace gbm {

/// Side-by-side alternative to DiffView, built on the same ParsedDiff.
///
/// Two read-only panes, kept vertically in lock-step by construction rather
/// than by scroll-syncing alone: SideBySideDiff::pairHunkForSideBySide already
/// produces one row per rendered line, with a blank on whichever side has
/// nothing to show, so inserting exactly one line into both panes per row is
/// what keeps a context line lined up with its counterpart even across an
/// unequal add/remove run. Scroll position is then only a presentation detail,
/// synced so the two panes track each other during manual scrolling too.
class SideBySideDiffView : public QWidget {
    Q_OBJECT

public:
    explicit SideBySideDiffView(QWidget* parent = nullptr);

    void showDiff(std::shared_ptr<const ParsedDiff> diff);

    /// Shows a single file from a multi-file diff.
    void showFile(std::shared_ptr<const ParsedDiff> diff, const QString& path);

    void showMessage(const QString& message);

    void clearDiff();

    /// Re-renders the currently shown diff (if any) so its add/remove colours
    /// pick up the theme most recently passed to `ThemeManager::apply()`. See
    /// `DiffView::refreshTheme` for why this must be called explicitly.
    void refreshTheme();

private:
    void render(const ParsedDiff& diff, const QString& onlyPath);

    QPlainTextEdit* left_ = nullptr;
    QPlainTextEdit* right_ = nullptr;
    std::shared_ptr<const ParsedDiff> diff_;
    /// The `onlyPath` most recently passed to `showFile`/`showDiff`, so
    /// `refreshTheme` can re-render with the same filter.
    QString lastOnlyPath_;
    /// Guards against the ping-pong that connecting both scrollbars to each
    /// other directly would otherwise cause.
    bool syncingScroll_ = false;
};

}  // namespace gbm
