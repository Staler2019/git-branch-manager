#include "app/views/FileContentView.h"

#include "app/bridge/ThemeManager.h"

#include <QHBoxLayout>
#include <QPaintEvent>
#include <QPainter>
#include <QTextBlock>

namespace gbm {

namespace {

constexpr int kGutterPadding = 8;

}  // namespace

/// Republishes the protected block-geometry accessors FileContentGutter
/// needs -- the same trick SideBySideDiffView's DiffPane uses (DiffPane.cpp),
/// since QPlainTextEdit cannot grant friendship to an unrelated class.
class FileContentTextEdit : public QPlainTextEdit {
public:
    explicit FileContentTextEdit(QWidget* parent) : QPlainTextEdit(parent) {}

    using QPlainTextEdit::blockBoundingGeometry;
    using QPlainTextEdit::blockBoundingRect;
    using QPlainTextEdit::contentOffset;
    using QPlainTextEdit::firstVisibleBlock;
};

/// Paints 1-based line numbers for `editor`'s visible blocks, following Qt's
/// standard code-editor-example technique: read block geometry directly off
/// the editor rather than keeping a per-line QWidget, so this stays cheap on
/// a large file.
class FileContentGutter : public QWidget {
public:
    explicit FileContentGutter(FileContentTextEdit* editor) : QWidget(editor), editor_(editor) {}

    int widthForLineCount() const {
        int digits = 1;
        int lines = qMax(1, editor_->document()->blockCount());
        while (lines >= 10) {
            lines /= 10;
            ++digits;
        }
        return kGutterPadding * 2 +
               editor_->fontMetrics().horizontalAdvance(QLatin1Char('9')) * digits;
    }

protected:
    void paintEvent(QPaintEvent* event) override {
        QPainter painter(this);
        painter.fillRect(event->rect(), ThemeManager::color(Token::SurfaceSunken));
        painter.setPen(ThemeManager::color(Token::TextTertiary));

        QTextBlock block = editor_->firstVisibleBlock();
        int blockNumber = block.blockNumber();
        int top = qRound(
            editor_->blockBoundingGeometry(block).translated(editor_->contentOffset()).top());
        int bottom = top + qRound(editor_->blockBoundingRect(block).height());

        while (block.isValid() && top <= event->rect().bottom()) {
            if (block.isVisible() && bottom >= event->rect().top()) {
                painter.drawText(0,
                                 top,
                                 width() - kGutterPadding,
                                 editor_->fontMetrics().height(),
                                 Qt::AlignRight,
                                 QString::number(blockNumber + 1));
            }
            block = block.next();
            top = bottom;
            bottom = top + qRound(editor_->blockBoundingRect(block).height());
            ++blockNumber;
        }
    }

private:
    FileContentTextEdit* editor_;
};

FileContentView::FileContentView(QWidget* parent) : QWidget(parent) {
    auto* layout = new QHBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(0);

    auto* editor = new FileContentTextEdit(this);
    editor->setReadOnly(true);
    editor->setFrameStyle(QFrame::NoFrame);
    editor->setLineWrapMode(QPlainTextEdit::NoWrap);
    editor->setFont(ThemeManager::monoFont(12));
    editor->setTextInteractionFlags(Qt::TextSelectableByMouse | Qt::TextSelectableByKeyboard);
    editor->setUndoRedoEnabled(false);
    editor->setPlaceholderText(QStringLiteral("Select a file to see its last committed content"));
    editor->setAccessibleName(QStringLiteral("Original file content"));

    auto* gutter = new FileContentGutter(editor);
    connect(editor, &QPlainTextEdit::blockCountChanged, this, [gutter](int) {
        gutter->setFixedWidth(gutter->widthForLineCount());
    });
    connect(editor, &QPlainTextEdit::updateRequest, this, [gutter](const QRect&, int) {
        gutter->update();
    });
    gutter->setFixedWidth(gutter->widthForLineCount());

    layout->addWidget(gutter);
    layout->addWidget(editor, 1);

    text_ = editor;
    gutter_ = gutter;
}

void FileContentView::showContent(const QString& content) {
    text_->setPlainText(content);
}

void FileContentView::showMessage(const QString& message) {
    text_->clear();
    text_->setPlaceholderText(message);
}

void FileContentView::clear() {
    text_->clear();
}

void FileContentView::refreshTheme() {
    text_->setFont(ThemeManager::monoFont(12));
    gutter_->update();
}

}  // namespace gbm
