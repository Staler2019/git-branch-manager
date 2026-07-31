#include "app/views/SideBySideDiffView.h"

#include "core/git/SideBySideDiff.h"

#include <QFontDatabase>
#include <QHBoxLayout>
#include <QPlainTextEdit>
#include <QScrollBar>
#include <QTextCharFormat>
#include <QTextCursor>

namespace gbm {

namespace {

// Same palette-derived scheme as DiffView, so switching between unified and
// side-by-side never looks like a different tool.
QColor addedBackground(const QPalette& palette) {
    const bool dark = palette.base().color().lightness() < 128;
    return dark ? QColor(46, 92, 54, 90) : QColor(214, 245, 214);
}

QColor removedBackground(const QPalette& palette) {
    const bool dark = palette.base().color().lightness() < 128;
    return dark ? QColor(120, 45, 45, 90) : QColor(255, 220, 220);
}

// Filler for the side with nothing to show, distinct from (and quieter than)
// both the added/removed tints and the ordinary background.
QColor paddingBackground(const QPalette& palette) {
    const bool dark = palette.base().color().lightness() < 128;
    return dark ? QColor(255, 255, 255, 10) : QColor(0, 0, 0, 12);
}

QPlainTextEdit* makePane(QWidget* parent) {
    auto* edit = new QPlainTextEdit(parent);
    edit->setReadOnly(true);
    edit->setLineWrapMode(QPlainTextEdit::NoWrap);
    edit->setFont(QFontDatabase::systemFont(QFontDatabase::FixedFont));
    edit->setTextInteractionFlags(Qt::TextSelectableByMouse | Qt::TextSelectableByKeyboard);
    edit->setUndoRedoEnabled(false);
    return edit;
}

}  // namespace

SideBySideDiffView::SideBySideDiffView(QWidget* parent) : QWidget(parent) {
    auto* layout = new QHBoxLayout(this);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(1);

    left_ = makePane(this);
    right_ = makePane(this);
    left_->setPlaceholderText(QStringLiteral("Select a commit to see its changes"));
    layout->addWidget(left_);
    layout->addWidget(right_);

    connect(left_->verticalScrollBar(), &QScrollBar::valueChanged, this, [this](int value) {
        if (syncingScroll_) {
            return;
        }
        syncingScroll_ = true;
        right_->verticalScrollBar()->setValue(value);
        syncingScroll_ = false;
    });
    connect(right_->verticalScrollBar(), &QScrollBar::valueChanged, this, [this](int value) {
        if (syncingScroll_) {
            return;
        }
        syncingScroll_ = true;
        left_->verticalScrollBar()->setValue(value);
        syncingScroll_ = false;
    });
}

void SideBySideDiffView::clearDiff() {
    diff_.reset();
    left_->clear();
    right_->clear();
}

void SideBySideDiffView::showMessage(const QString& message) {
    diff_.reset();
    left_->clear();
    right_->clear();
    left_->appendPlainText(message);
}

void SideBySideDiffView::showDiff(std::shared_ptr<const ParsedDiff> diff) {
    diff_ = std::move(diff);
    left_->clear();
    right_->clear();
    if (diff_) {
        render(*diff_, QString());
    }
}

void SideBySideDiffView::showFile(std::shared_ptr<const ParsedDiff> diff, const QString& path) {
    diff_ = std::move(diff);
    left_->clear();
    right_->clear();
    if (diff_) {
        render(*diff_, path);
    }
}

void SideBySideDiffView::render(const ParsedDiff& diff, const QString& onlyPath) {
    QTextCursor leftCursor(left_->document());
    QTextCursor rightCursor(right_->document());
    leftCursor.beginEditBlock();
    rightCursor.beginEditBlock();

    QTextCharFormat plain;
    QTextCharFormat header;
    header.setFontWeight(QFont::Bold);
    QTextCharFormat hunkHeader;
    hunkHeader.setForeground(palette().color(QPalette::Link));
    QTextCharFormat added;
    added.setBackground(addedBackground(palette()));
    QTextCharFormat removed;
    removed.setBackground(removedBackground(palette()));
    QTextCharFormat dim;
    dim.setForeground(palette().color(QPalette::Disabled, QPalette::Text));
    QTextCharFormat padding;
    padding.setBackground(paddingBackground(palette()));

    auto insertLine = [](QTextCursor& cursor, const QString& text, const QTextCharFormat& format) {
        cursor.insertText(text + QStringLiteral("\n"), format);
    };

    auto insertCell = [&](QTextCursor& cursor, const DiffLine* line) {
        if (line == nullptr) {
            insertLine(cursor, QString(), padding);
            return;
        }
        switch (line->kind) {
            case DiffLineKind::Added:
                insertLine(cursor, QString::fromStdString(line->text), added);
                break;
            case DiffLineKind::Removed:
                insertLine(cursor, QString::fromStdString(line->text), removed);
                break;
            case DiffLineKind::Context:
                insertLine(cursor, QString::fromStdString(line->text), plain);
                break;
            case DiffLineKind::NoNewlineMarker:
                insertLine(cursor, QString::fromStdString(line->text), dim);
                break;
        }
    };

    bool renderedAnything = false;

    for (const DiffFile& file : diff.files) {
        const QString displayPath = QString::fromStdString(file.displayPath());
        if (!onlyPath.isEmpty() && displayPath != onlyPath) {
            continue;
        }
        renderedAnything = true;

        insertLine(leftCursor, displayPath, header);
        insertLine(rightCursor, displayPath, header);

        if (file.binary) {
            insertLine(leftCursor, QStringLiteral("Binary file not shown"), dim);
            insertLine(rightCursor, QString(), dim);
            continue;
        }
        if (file.hunks.empty()) {
            insertLine(leftCursor, QStringLiteral("No textual changes"), dim);
            insertLine(rightCursor, QString(), dim);
            continue;
        }

        for (const DiffHunk& hunk : file.hunks) {
            const QString hunkLine = QStringLiteral("@@ -%1,%2 +%3,%4 @@")
                                         .arg(hunk.oldStart)
                                         .arg(hunk.oldCount)
                                         .arg(hunk.newStart)
                                         .arg(hunk.newCount);
            insertLine(leftCursor, hunkLine, hunkHeader);
            insertLine(rightCursor, hunkLine, hunkHeader);

            for (const SideBySideRow& row : pairHunkForSideBySide(hunk)) {
                insertCell(leftCursor, row.left);
                insertCell(rightCursor, row.right);
            }
        }
        insertLine(leftCursor, QString(), plain);
        insertLine(rightCursor, QString(), plain);
    }

    if (diff.truncated) {
        const QString message =
            QStringLiteral("… diff truncated because it exceeds the display limit");
        insertLine(leftCursor, message, dim);
        insertLine(rightCursor, QString(), dim);
    }
    if (!renderedAnything) {
        insertLine(leftCursor, QStringLiteral("No changes to show"), dim);
        insertLine(rightCursor, QString(), dim);
    }

    leftCursor.endEditBlock();
    rightCursor.endEditBlock();
    left_->moveCursor(QTextCursor::Start);
    right_->moveCursor(QTextCursor::Start);
}

}  // namespace gbm
