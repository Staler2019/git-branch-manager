#pragma once

#include "core/git/UnifiedDiffParser.h"

#include <QPlainTextEdit>
#include <QWidget>

#include <memory>
#include <vector>

class QContextMenuEvent;

namespace gbm {

/// Unified diff viewer.
///
/// Built on QPlainTextEdit rather than a custom widget for one decisive reason:
/// users copy code out of diffs, and text selection, find and keyboard navigation
/// come free and behave natively. QPlainTextEdit also handles very long documents
/// without laying out the whole thing up front.
class DiffView : public QPlainTextEdit {
    Q_OBJECT

public:
    explicit DiffView(QWidget* parent = nullptr);

    void showDiff(std::shared_ptr<const ParsedDiff> diff);

    /// Shows a single file from a multi-file diff.
    void showFile(std::shared_ptr<const ParsedDiff> diff, const QString& path);

    void showMessage(const QString& message);

    void clearDiff();

    /// Offers "Stage Hunk" / "Stage Selected Lines" (or their Unstage
    /// counterparts) on the context menu. Off by default: the history diff
    /// view shows a read-only past commit, which cannot be staged.
    void setStagingEnabled(bool enabled);

    /// Which side of the index the currently shown diff represents: false for
    /// work tree vs index (the "Stage" case), true for index vs HEAD (the
    /// "Unstage" case). Determines both the menu wording and the `reverse`
    /// flag on applyPatchRequested.
    void setShowingStagedDiff(bool staged);

    /// Re-renders the currently shown diff (if any) so its add/remove colours
    /// pick up the theme most recently passed to `ThemeManager::apply()`.
    /// Colours are baked into the document's `QTextCharFormat`s at render
    /// time rather than read from the palette, so a theme switch alone does
    /// not repaint them -- this must be called explicitly after `apply()`.
    void refreshTheme();

signals:
    /// A patch the user asked to apply to the index, built from the hunk or
    /// line selection under the cursor. See
    /// UnifiedDiffParser::buildHunkPatch / buildLineSelectionPatch for what
    /// `patch` contains and how `reverse` pairs with it.
    void applyPatchRequested(QString patch, bool reverse);

protected:
    void contextMenuEvent(QContextMenuEvent* event) override;

private:
    void render(const ParsedDiff& diff, const QString& onlyPath);

    /// Maps a contiguous run of QTextBlocks back to the hunk they render, so a
    /// right-click can find which hunk (and which DiffLine, for a selection)
    /// it landed on without re-parsing the document.
    struct HunkSpan {
        int firstLine = 0;  ///< Block number of the hunk's first content line.
        int lastLine = 0;   ///< Block number of the hunk's last content line.
        const DiffFile* file = nullptr;
        const DiffHunk* hunk = nullptr;
    };

    const HunkSpan* hunkSpanForBlock(int blockNumber) const;

    std::shared_ptr<const ParsedDiff> diff_;
    std::vector<HunkSpan> hunkSpans_;
    bool stagingEnabled_ = false;
    bool showingStaged_ = false;

    /// The `onlyPath` most recently passed to `showFile`/`showDiff` (empty
    /// for a whole-diff view), remembered so `refreshTheme` can re-render
    /// with the same filter.
    QString lastOnlyPath_;
};

}  // namespace gbm
