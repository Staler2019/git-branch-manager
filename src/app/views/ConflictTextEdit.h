#pragma once

#include "core/git/ConflictMarkerParser.h"

#include <QPlainTextEdit>
#include <QString>

#include <vector>

class QPaintEvent;
class QResizeEvent;
class QRect;
class QWidget;

namespace gbm {

/// A read-only-friendly QPlainTextEdit with a line-number gutter in its
/// viewport margin -- the standard Qt "Code Editor" example pattern
/// (firstVisibleBlock/blockBoundingGeometry are protected on QPlainTextEdit,
/// so a companion LineNumberArea widget can only reach them through a
/// subclass). Used for all four panes (ancestor/ours/result/theirs) in
/// ConflictResolvePanel. Extracted from ConflictResolvePanel.cpp into its own
/// file because it is about to grow hover/drag-and-drop/line-pick behaviour
/// for direct-manipulation conflict resolution, which would push
/// ConflictResolvePanel.cpp well past this codebase's 800-line file guidance.
class ConflictTextEdit : public QPlainTextEdit {
public:
    explicit ConflictTextEdit(QWidget* parent = nullptr);

protected:
    void resizeEvent(QResizeEvent* event) override;

private:
    friend class LineNumberArea;
    int lineNumberAreaWidth() const;
    void lineNumberAreaPaintEvent(QPaintEvent* event);
    void updateLineNumberAreaWidth(int newBlockCount);
    void updateLineNumberArea(const QRect& rect, int dy);

    QWidget* lineNumberArea_ = nullptr;
};

/// Which side of a conflict region a pane shows -- Ours/Theirs feed
/// buildSidePaneText() below; Result names the middle/resolved pane for the
/// hover/drag wiring landing in a later commit (that pane is rendered by
/// ConflictResolvePanel::buildMiddlePreviewText() instead, which already
/// handles per-region resolution state that buildSidePaneText() does not).
enum class ConflictSide { Ours, Theirs, Result };

/// One region's row span within a side pane's rendered text: `regionIndex`
/// matches ParsedConflictFile's region-only numbering (as used by
/// ConflictResolvePanel::regionResolutions_), `firstBlock` is the 0-based
/// QPlainTextEdit block (line) the region's first line lands on, and
/// `blockCount` is how many blocks it occupies.
struct RegionRowSpan {
    int regionIndex = 0;
    int firstBlock = 0;
    int blockCount = 0;
};

/// The rendered text for one side pane plus the region -> row-span map
/// needed to know which rows belong to which region (hover/drag, a later
/// commit).
struct SidePaneRender {
    QString text;
    std::vector<RegionRowSpan> spans;
};

/// Renders `side`'s (Ours or Theirs only -- see ConflictSide's comment)
/// content from `parsed`'s already-split segments: each Text segment's lines
/// pass through verbatim, each Region segment contributes its `ours` or
/// `theirs` lines depending on `side`. Mirrors
/// ConflictResolvePanel::buildMiddlePreviewText()'s pattern of recording a
/// range as it concatenates, except in block (line) units rather than
/// characters -- a row position is what hover/drag/click need to resolve to
/// a region, not a character offset.
///
/// Block counting relies on ConflictSegment's own contract: every line
/// string keeps its trailing line ending except possibly the file's very
/// last line, so counting lines emitted so far always lands on the correct
/// block index -- no character-offset-to-block conversion needed.
///
/// A regionless file (parsed.regionCount == 0, which is also what a
/// malformed/not-well-formed file parses to -- see
/// ParsedConflictFile::wellFormed) simply returns its one Text segment
/// verbatim with no spans; ConflictResolvePanel only calls this when
/// regionCount > 0; see refreshSidePanes().
SidePaneRender buildSidePaneText(const ParsedConflictFile& parsed, ConflictSide side);

}  // namespace gbm
