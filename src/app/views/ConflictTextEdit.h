#pragma once

#include "core/git/ConflictMarkerParser.h"

#include <QPlainTextEdit>
#include <QPoint>
#include <QString>

#include <optional>
#include <vector>

class QDragEnterEvent;
class QDragLeaveEvent;
class QDragMoveEvent;
class QDropEvent;
class QEvent;
class QMimeData;
class QMouseEvent;
class QPaintEvent;
class QResizeEvent;
class QRect;
class QWidget;

namespace gbm {

/// Which side of a conflict region a pane shows -- Ours/Theirs feed
/// buildSidePaneText() below and become hover/drag *sources* (see
/// ConflictTextEdit::setSide()); Result names the middle/resolved pane,
/// which becomes a drop *target* instead (that pane is rendered by
/// ConflictResolvePanel::buildMiddlePreviewText(), which already handles
/// per-region resolution state that buildSidePaneText() does not).
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
/// needed to know which rows belong to which region (hover/drag).
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

/// MIME type carrying a dragged conflict region from an ours/theirs pane to
/// the result pane. Payload is just 2 packed qint32s (side, regionIndex) --
/// see encodeConflictRegionMimeData()/decodeConflictRegionMimeData(). Drop
/// handling is entirely regionIndex-based (drop anywhere in the result pane
/// resolves that region -- there is no per-pixel drop-position semantics to
/// get wrong), so the payload never needs to carry the dragged text itself;
/// a text/plain fallback is added separately for drops outside the app.
extern const char kConflictRegionMimeType[];

/// Packs `regionIndex` and the side it's being dragged from into a
/// QMimeData payload under kConflictRegionMimeType, plus a text/plain
/// fallback (`sideText`, e.g. that region's rendered lines) for drops
/// outside the app. Caller owns the returned object.
QMimeData* encodeConflictRegionMimeData(int regionIndex, ConflictSide fromSide, const QString& sideText);

struct DecodedConflictRegionDrag {
    int regionIndex = 0;
    ConflictSide fromSide = ConflictSide::Ours;
};

/// nullopt if `mime` doesn't carry kConflictRegionMimeType or its payload
/// doesn't parse.
std::optional<DecodedConflictRegionDrag> decodeConflictRegionMimeData(const QMimeData* mime);

/// A read-only-friendly QPlainTextEdit with a line-number gutter in its
/// viewport margin -- the standard Qt "Code Editor" example pattern
/// (firstVisibleBlock/blockBoundingGeometry are protected on QPlainTextEdit,
/// so a companion LineNumberArea widget can only reach them through a
/// subclass). Used for all four panes (ancestor/ours/result/theirs) in
/// ConflictResolvePanel.
///
/// Direct-manipulation conflict resolution (Design A1): an Ours/Theirs pane
/// raises the region under the mouse (setExtraSelections background +
/// OpenHandCursor) and, on a press-drag past QApplication::startDragDistance,
/// starts a QDrag carrying that region's index and side. The Result pane
/// (setSide(ConflictSide::Result)) is the only drop target -- see setSide()
/// -- and only while it is still read-only (i.e. some region remains
/// unresolved); once every region is resolved the pane becomes the user's
/// freely-editable buffer and a drop landing there would silently discard
/// whatever they just typed, so dragEnterEvent() refuses it entirely at
/// that point (same hazard the Take Left/Right buttons already guard
/// against -- see ConflictResolvePanel.cpp's refreshMiddleFromResolutions).
class ConflictTextEdit : public QPlainTextEdit {
    Q_OBJECT

public:
    explicit ConflictTextEdit(QWidget* parent = nullptr);

    /// Which side this pane shows. Ours/Theirs become hover+drag sources;
    /// Result becomes a drop target (toggles setAcceptDrops()) and is never
    /// itself draggable, even though QPlainTextEdit would otherwise let its
    /// own selected text be dragged out.
    void setSide(ConflictSide side);
    /// The regionIndex -> row-span map for this pane's current content --
    /// see buildSidePaneText(). Empty clears hover/drag entirely (e.g. a
    /// regionless file, or before the working-tree reply has parsed one).
    void setRegionSpans(std::vector<RegionRowSpan> spans);

signals:
    /// Emitted by a Result-side pane's dropEvent() once a valid conflict-
    /// region payload lands and the pane was accepting drops (see
    /// dragEnterEvent()).
    void regionDropped(int regionIndex, ConflictSide fromSide);

protected:
    void resizeEvent(QResizeEvent* event) override;
    void mouseMoveEvent(QMouseEvent* event) override;
    void mousePressEvent(QMouseEvent* event) override;
    void leaveEvent(QEvent* event) override;
    void dragEnterEvent(QDragEnterEvent* event) override;
    void dragMoveEvent(QDragMoveEvent* event) override;
    void dragLeaveEvent(QDragLeaveEvent* event) override;
    void dropEvent(QDropEvent* event) override;

private:
    friend class LineNumberArea;
    int lineNumberAreaWidth() const;
    void lineNumberAreaPaintEvent(QPaintEvent* event);
    void updateLineNumberAreaWidth(int newBlockCount);
    void updateLineNumberArea(const QRect& rect, int dy);

    /// The span covering `block`, or nullptr if `block` belongs to no
    /// region (plain Text segment rows).
    const RegionRowSpan* spanForBlock(int block) const;
    /// The span whose regionIndex == `regionIndex`, or nullptr if
    /// regionSpans_ doesn't have (or doesn't yet have) an entry for it --
    /// see dragMoveEvent()'s comment on why that's expected on the result
    /// pane.
    const RegionRowSpan* spanForRegionIndex(int regionIndex) const;
    /// Re-applies (or clears, if hoveredSpanIndex_ < 0) the hover highlight
    /// and grab cursor for regionSpans_[hoveredSpanIndex_].
    void updateHoverPresentation();
    /// Highlights `span`'s row range as a would-accept drop target, or
    /// clears the highlight when `span` is nullptr.
    void updateDropTargetPresentation(const RegionRowSpan* span);

    QWidget* lineNumberArea_ = nullptr;
    ConflictSide side_ = ConflictSide::Ours;
    std::vector<RegionRowSpan> regionSpans_;
    /// Index into regionSpans_ the mouse is currently hovering, or -1.
    int hoveredSpanIndex_ = -1;
    /// Where mousePressEvent last recorded a press over a region, to
    /// measure drag distance in mouseMoveEvent -- only meaningful while
    /// dragCandidateSpanIndex_ >= 0.
    QPoint dragStartPos_;
    /// Which regionSpans_ index the most recent press landed in, or -1 if
    /// the press wasn't over a region (nothing to drag from there).
    int dragCandidateSpanIndex_ = -1;
};

}  // namespace gbm
