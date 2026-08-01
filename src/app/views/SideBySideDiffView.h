#pragma once

#include "core/git/UnifiedDiffParser.h"

#include <QWidget>

#include <memory>
#include <vector>

class QPlainTextEdit;
class QLabel;

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
///
/// When staging is enabled (see setStagingEnabled), each changed line grows a
/// small gutter checkbox -- painted onto a thin companion widget next to the
/// pane rather than one QWidget per line, so long diffs still avoid up-front
/// per-line layout the same way DiffView does. Clicking a checkbox, or using
/// the line/hunk context menu, stages or unstages through the same
/// applyPatchRequested(QString, bool) path DiffView already uses.
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

    /// Offers per-line gutter checkboxes, a "N of M staged" summary, a result
    /// preview, and a Stage/Unstage line-or-hunk context menu. Off by default:
    /// a commit-vs-working-copy comparison (the History tab's "Compare with
    /// working copy") isn't a working-copy-vs-index diff and can't be staged
    /// the way an actual working-copy file diff can.
    void setStagingEnabled(bool enabled);

    /// Which side of the index the currently shown diff represents: false for
    /// work tree vs index (the "Stage" case), true for index vs HEAD (the
    /// "Unstage" case). See DiffView::setShowingStagedDiff -- same meaning.
    void setShowingStagedDiff(bool staged);

signals:
    /// A patch the user asked to apply to the index, built from the hunk or
    /// line under the cursor/checkbox. Same shape as DiffView's signal of the
    /// same name, so callers can wire both through one slot.
    void applyPatchRequested(QString patch, bool reverse);

protected:
    bool eventFilter(QObject* watched, QEvent* event) override;

private:
    friend class DiffGutterWidget;

    void render(const ParsedDiff& diff, const QString& onlyPath);
    void setupStagingChrome();
    void updateSummary();
    void updateResultPreview();
    void toggleLine(bool onLeftPane, int blockNumber);
    void showLineContextMenu(bool onLeftPane, int blockNumber, const QPoint& globalPos);

    /// One changed (added or removed) line rendered in a pane, mapping a
    /// QTextBlock back to the DiffLine it came from -- the side-by-side
    /// equivalent of DiffView::HunkSpan, at line rather than hunk grain since
    /// that's what the gutter checkbox needs to hit-test against.
    struct LineMarker {
        int blockNumber = 0;
        const DiffFile* file = nullptr;
        const DiffHunk* hunk = nullptr;
        std::size_t lineIndex = 0;  ///< Index into hunk->lines.
        bool staged = false;
        bool pending = false;  ///< A stage/unstage request for this line is in flight.
    };

    const LineMarker* markerForBlock(bool onLeftPane, int blockNumber) const;
    LineMarker* markerForBlock(bool onLeftPane, int blockNumber);

    QPlainTextEdit* left_ = nullptr;
    QPlainTextEdit* right_ = nullptr;
    QWidget* leftGutter_ = nullptr;
    QWidget* rightGutter_ = nullptr;
    QLabel* summaryLabel_ = nullptr;
    QPlainTextEdit* resultPreview_ = nullptr;

    std::shared_ptr<const ParsedDiff> diff_;
    /// The `onlyPath` most recently passed to `showFile`/`showDiff`, so
    /// `refreshTheme` can re-render with the same filter.
    QString lastOnlyPath_;
    /// Guards against the ping-pong that connecting both scrollbars to each
    /// other directly would otherwise cause.
    bool syncingScroll_ = false;

    bool stagingEnabled_ = false;
    bool showingStaged_ = false;
    std::vector<LineMarker> leftMarkers_;
    std::vector<LineMarker> rightMarkers_;
};

}  // namespace gbm
