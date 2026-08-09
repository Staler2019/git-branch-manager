#include "app/views/ConflictTextEdit.h"

#include "app/bridge/ThemeManager.h"
#include "app/theme/Tokens.h"

#include <QPainter>
#include <QPaintEvent>
#include <QResizeEvent>
#include <QTextBlock>
#include <QWidget>

namespace gbm {

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
