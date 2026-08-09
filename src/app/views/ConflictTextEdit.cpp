#include "app/views/ConflictTextEdit.h"

#include "app/bridge/ThemeManager.h"
#include "app/theme/Tokens.h"

#include <QApplication>
#include <QByteArray>
#include <QDataStream>
#include <QDrag>
#include <QDragEnterEvent>
#include <QDragLeaveEvent>
#include <QDragMoveEvent>
#include <QDropEvent>
#include <QMimeData>
#include <QMouseEvent>
#include <QPainter>
#include <QPaintEvent>
#include <QResizeEvent>
#include <QTextBlock>
#include <QTextCursor>
#include <QWidget>

namespace gbm {

const char kConflictRegionMimeType[] = "application/x-gbm-conflict-region";

QMimeData* encodeConflictRegionMimeData(int regionIndex, ConflictSide fromSide, const QString& sideText) {
    QByteArray payload;
    QDataStream stream(&payload, QIODevice::WriteOnly);
    stream << static_cast<qint32>(fromSide) << static_cast<qint32>(regionIndex);

    auto* mime = new QMimeData();
    mime->setData(QLatin1String(kConflictRegionMimeType), payload);
    mime->setText(sideText);
    return mime;
}

std::optional<DecodedConflictRegionDrag> decodeConflictRegionMimeData(const QMimeData* mime) {
    if (mime == nullptr || !mime->hasFormat(QLatin1String(kConflictRegionMimeType))) {
        return std::nullopt;
    }
    QByteArray payload = mime->data(QLatin1String(kConflictRegionMimeType));
    QDataStream stream(&payload, QIODevice::ReadOnly);
    qint32 side = 0;
    qint32 regionIndex = 0;
    stream >> side >> regionIndex;
    if (stream.status() != QDataStream::Ok) {
        return std::nullopt;
    }
    DecodedConflictRegionDrag decoded;
    decoded.fromSide = static_cast<ConflictSide>(side);
    decoded.regionIndex = regionIndex;
    return decoded;
}

// Not in an anonymous namespace: ConflictTextEdit's `friend class
// LineNumberArea;` (see ConflictTextEdit.h) is an unqualified friend
// declaration, which names gbm::LineNumberArea specifically -- an anonymous-
// namespace LineNumberArea here would be a distinct, unrelated class that
// the friendship does not extend to, and every private member access below
// would fail to compile.
class LineNumberArea : public QWidget {
public:
    explicit LineNumberArea(ConflictTextEdit* editor) : QWidget(editor), editor_(editor) {}

    QSize sizeHint() const override { return QSize(editor_->lineNumberAreaWidth(), 0); }

protected:
    void paintEvent(QPaintEvent* event) override { editor_->lineNumberAreaPaintEvent(event); }

private:
    ConflictTextEdit* editor_;
};

ConflictTextEdit::ConflictTextEdit(QWidget* parent) : QPlainTextEdit(parent) {
    lineNumberArea_ = new LineNumberArea(this);
    connect(this,
            &QPlainTextEdit::blockCountChanged,
            this,
            &ConflictTextEdit::updateLineNumberAreaWidth);
    connect(
        this, &QPlainTextEdit::updateRequest, this, &ConflictTextEdit::updateLineNumberArea);
    updateLineNumberAreaWidth(0);
    // Needed for mouseMoveEvent() to fire on plain hover (no button held) --
    // that's how a region raises itself before the user has pressed
    // anything, see updateHoverPresentation().
    setMouseTracking(true);
}

void ConflictTextEdit::setSide(ConflictSide side) {
    side_ = side;
    // Only the result pane accepts drops; ours/theirs are drag sources
    // only. Symmetrically, QPlainTextEdit would otherwise let the result
    // pane's own selected text be dragged out once it becomes editable --
    // that's not a conflict-region drag and must not be mistaken for one,
    // so drag-out stays gated on side_ in mouseMoveEvent() regardless of
    // this flag.
    setAcceptDrops(side_ == ConflictSide::Result);
    // QAbstractScrollArea-based widgets are hit-tested via their viewport,
    // not the outer widget -- a real platform drag session targets
    // whichever widget is actually under the cursor, so the viewport needs
    // its own WA_AcceptDrops too.
    viewport()->setAcceptDrops(side_ == ConflictSide::Result);
}

void ConflictTextEdit::setRegionSpans(std::vector<RegionRowSpan> spans) {
    regionSpans_ = std::move(spans);
    hoveredSpanIndex_ = -1;
    dragCandidateSpanIndex_ = -1;
    setExtraSelections({});
}

const RegionRowSpan* ConflictTextEdit::spanForBlock(int block) const {
    for (const RegionRowSpan& span : regionSpans_) {
        if (block >= span.firstBlock && block < span.firstBlock + span.blockCount) {
            return &span;
        }
    }
    return nullptr;
}

const RegionRowSpan* ConflictTextEdit::spanForRegionIndex(int regionIndex) const {
    for (const RegionRowSpan& span : regionSpans_) {
        if (span.regionIndex == regionIndex) {
            return &span;
        }
    }
    return nullptr;
}

void ConflictTextEdit::updateHoverPresentation() {
    if (hoveredSpanIndex_ < 0) {
        setExtraSelections({});
        unsetCursor();
        return;
    }
    const RegionRowSpan& span = regionSpans_[static_cast<std::size_t>(hoveredSpanIndex_)];
    QTextBlock firstBlockObj = document()->findBlockByNumber(span.firstBlock);
    QTextBlock lastBlockObj =
        document()->findBlockByNumber(span.firstBlock + span.blockCount - 1);
    if (!firstBlockObj.isValid() || !lastBlockObj.isValid()) {
        return;
    }
    QTextCursor cursor(firstBlockObj);
    cursor.setPosition(lastBlockObj.position() + lastBlockObj.length() - 1, QTextCursor::KeepAnchor);

    QTextEdit::ExtraSelection selection;
    selection.cursor = cursor;
    selection.format.setBackground(ThemeManager::color(Token::SurfaceHover));
    selection.format.setProperty(QTextFormat::FullWidthSelection, true);
    setExtraSelections({selection});
    setCursor(Qt::OpenHandCursor);
}

void ConflictTextEdit::updateDropTargetPresentation(const RegionRowSpan* span) {
    if (span == nullptr) {
        setExtraSelections({});
        return;
    }
    QTextBlock firstBlockObj = document()->findBlockByNumber(span->firstBlock);
    QTextBlock lastBlockObj =
        document()->findBlockByNumber(span->firstBlock + span->blockCount - 1);
    if (!firstBlockObj.isValid() || !lastBlockObj.isValid()) {
        setExtraSelections({});
        return;
    }
    QTextCursor cursor(firstBlockObj);
    cursor.setPosition(lastBlockObj.position() + lastBlockObj.length() - 1, QTextCursor::KeepAnchor);

    QTextEdit::ExtraSelection selection;
    selection.cursor = cursor;
    selection.format.setBackground(ThemeManager::color(Token::SurfaceSelected));
    selection.format.setProperty(QTextFormat::FullWidthSelection, true);
    setExtraSelections({selection});
}

void ConflictTextEdit::mouseMoveEvent(QMouseEvent* event) {
    QPlainTextEdit::mouseMoveEvent(event);

    if (side_ == ConflictSide::Result) {
        return;
    }

    // A press already landed on a region and the mouse has moved far enough
    // to count as a drag rather than a click (click-to-select-lines is a
    // later commit) -- start the drag and stop tracking hover until it
    // resolves.
    if (dragCandidateSpanIndex_ >= 0 &&
        (event->pos() - dragStartPos_).manhattanLength() >= QApplication::startDragDistance()) {
        const RegionRowSpan span = regionSpans_[static_cast<std::size_t>(dragCandidateSpanIndex_)];
        dragCandidateSpanIndex_ = -1;
        hoveredSpanIndex_ = -1;
        setExtraSelections({});
        unsetCursor();

        QTextBlock firstBlockObj = document()->findBlockByNumber(span.firstBlock);
        QTextBlock lastBlockObj =
            document()->findBlockByNumber(span.firstBlock + span.blockCount - 1);
        QString sideText;
        if (firstBlockObj.isValid() && lastBlockObj.isValid()) {
            QTextCursor cursor(firstBlockObj);
            cursor.setPosition(lastBlockObj.position() + lastBlockObj.length() - 1,
                                QTextCursor::KeepAnchor);
            sideText = cursor.selectedText();
        }

        auto* drag = new QDrag(this);
        drag->setMimeData(encodeConflictRegionMimeData(span.regionIndex, side_, sideText));
        // Result: fires the connected ConflictResolvePanel handler via
        // regionDropped() on whichever pane accepted the drop; this call
        // blocks (platform drag loop) until the drag ends one way or
        // another, which offscreen QPA cannot exercise -- see
        // decodeConflictRegionMimeData()'s own test for the seam this
        // relies on instead.
        drag->exec(Qt::CopyAction);
        return;
    }

    const int block = cursorForPosition(event->pos()).blockNumber();
    const RegionRowSpan* span = spanForBlock(block);
    const int newHoveredIndex =
        (span != nullptr) ? static_cast<int>(span - regionSpans_.data()) : -1;
    if (newHoveredIndex != hoveredSpanIndex_) {
        hoveredSpanIndex_ = newHoveredIndex;
        updateHoverPresentation();
    }
}

void ConflictTextEdit::mousePressEvent(QMouseEvent* event) {
    if (side_ != ConflictSide::Result && event->button() == Qt::LeftButton &&
        hoveredSpanIndex_ >= 0) {
        dragStartPos_ = event->pos();
        dragCandidateSpanIndex_ = hoveredSpanIndex_;
        return;
    }
    QPlainTextEdit::mousePressEvent(event);
}

void ConflictTextEdit::leaveEvent(QEvent* event) {
    QPlainTextEdit::leaveEvent(event);
    dragCandidateSpanIndex_ = -1;
    if (hoveredSpanIndex_ >= 0) {
        hoveredSpanIndex_ = -1;
        updateHoverPresentation();
    }
}

void ConflictTextEdit::dragEnterEvent(QDragEnterEvent* event) {
    // Only while still read-only: once every region is resolved this pane
    // becomes the user's freely-editable buffer (see
    // ConflictResolvePanel::refreshMiddleFromResolutions()), and a drop
    // landing there would silently discard whatever they just typed -- the
    // same hazard the Take Left/Right buttons already guard against.
    if (side_ != ConflictSide::Result || !isReadOnly() ||
        !decodeConflictRegionMimeData(event->mimeData()).has_value()) {
        event->ignore();
        return;
    }
    event->acceptProposedAction();
}

void ConflictTextEdit::dragMoveEvent(QDragMoveEvent* event) {
    const auto decoded = decodeConflictRegionMimeData(event->mimeData());
    if (side_ != ConflictSide::Result || !isReadOnly() || !decoded.has_value()) {
        event->ignore();
        updateDropTargetPresentation(nullptr);
        return;
    }
    event->acceptProposedAction();
    // regionSpans_ on the result pane isn't kept up to date the way ours/
    // theirs is (its rendering is driven by refreshMiddleFromResolutions(),
    // not buildSidePaneText()) -- when it's empty (or the dragged region
    // isn't in it yet) the drop is still accepted, just without a precise
    // target highlight; see ConflictResolvePanel for how it feeds spans in.
    updateDropTargetPresentation(spanForRegionIndex(decoded->regionIndex));
}

void ConflictTextEdit::dragLeaveEvent(QDragLeaveEvent* event) {
    QPlainTextEdit::dragLeaveEvent(event);
    updateDropTargetPresentation(nullptr);
}

void ConflictTextEdit::dropEvent(QDropEvent* event) {
    const auto decoded = decodeConflictRegionMimeData(event->mimeData());
    updateDropTargetPresentation(nullptr);
    if (side_ != ConflictSide::Result || !isReadOnly() || !decoded.has_value()) {
        event->ignore();
        return;
    }
    event->acceptProposedAction();
    emit regionDropped(decoded->regionIndex, decoded->fromSide);
}

int ConflictTextEdit::lineNumberAreaWidth() const {
    int digits = 1;
    for (int maxBlock = qMax(1, blockCount()); maxBlock >= 10; maxBlock /= 10) {
        ++digits;
    }
    return 10 + fontMetrics().horizontalAdvance(QLatin1Char('9')) * digits;
}

void ConflictTextEdit::updateLineNumberAreaWidth(int /*newBlockCount*/) {
    setViewportMargins(lineNumberAreaWidth(), 0, 0, 0);
}

void ConflictTextEdit::updateLineNumberArea(const QRect& rect, int dy) {
    if (dy != 0) {
        lineNumberArea_->scroll(0, dy);
    } else {
        lineNumberArea_->update(0, rect.y(), lineNumberArea_->width(), rect.height());
    }
    if (rect.contains(viewport()->rect())) {
        updateLineNumberAreaWidth(0);
    }
}

void ConflictTextEdit::resizeEvent(QResizeEvent* event) {
    QPlainTextEdit::resizeEvent(event);
    const QRect cr = contentsRect();
    lineNumberArea_->setGeometry(QRect(cr.left(), cr.top(), lineNumberAreaWidth(), cr.height()));
}

SidePaneRender buildSidePaneText(const ParsedConflictFile& parsed, ConflictSide side) {
    Q_ASSERT(side != ConflictSide::Result);

    SidePaneRender render;
    int blockCursor = 0;
    int regionIndex = 0;
    for (const ConflictSegment& segment : parsed.segments) {
        if (segment.kind == ConflictSegmentKind::Text) {
            for (const std::string& line : segment.lines) {
                render.text += QString::fromStdString(line);
            }
            blockCursor += static_cast<int>(segment.lines.size());
            continue;
        }

        const std::vector<std::string>& sideLines =
            (side == ConflictSide::Theirs) ? segment.theirs : segment.ours;
        const int firstBlock = blockCursor;
        for (const std::string& line : sideLines) {
            render.text += QString::fromStdString(line);
        }
        const int blockCount = static_cast<int>(sideLines.size());
        render.spans.push_back(RegionRowSpan{regionIndex, firstBlock, blockCount});
        blockCursor += blockCount;
        ++regionIndex;
    }
    return render;
}

void ConflictTextEdit::lineNumberAreaPaintEvent(QPaintEvent* event) {
    QPainter painter(lineNumberArea_);
    painter.fillRect(event->rect(), ThemeManager::color(Token::SurfaceSunken));
    painter.setPen(ThemeManager::color(Token::TextTertiary));

    QTextBlock block = firstVisibleBlock();
    int blockNumber = block.blockNumber();
    int top = qRound(blockBoundingGeometry(block).translated(contentOffset()).top());
    int bottom = top + qRound(blockBoundingRect(block).height());

    while (block.isValid() && top <= event->rect().bottom()) {
        if (block.isVisible() && bottom >= event->rect().top()) {
            painter.drawText(0,
                              top,
                              lineNumberArea_->width() - 6,
                              fontMetrics().height(),
                              Qt::AlignRight,
                              QString::number(blockNumber + 1));
        }
        block = block.next();
        top = bottom;
        bottom = top + qRound(blockBoundingRect(block).height());
        ++blockNumber;
    }
}

}  // namespace gbm
