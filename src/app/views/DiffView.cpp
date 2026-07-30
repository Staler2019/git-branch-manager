#include "app/views/DiffView.h"

#include <QFont>
#include <QFontDatabase>
#include <QTextBlockFormat>
#include <QTextCharFormat>
#include <QTextCursor>

namespace gbm {

namespace {

QColor addedBackground(const QPalette& palette) {
    // Derived from the palette rather than hard-coded, so the diff stays readable
    // under a dark theme without a second set of constants.
    const bool dark = palette.base().color().lightness() < 128;
    return dark ? QColor(46, 92, 54, 90) : QColor(214, 245, 214);
}

QColor removedBackground(const QPalette& palette) {
    const bool dark = palette.base().color().lightness() < 128;
    return dark ? QColor(120, 45, 45, 90) : QColor(255, 220, 220);
}

}  // namespace

DiffView::DiffView(QWidget* parent) : QPlainTextEdit(parent) {
    setReadOnly(true);
    setLineWrapMode(QPlainTextEdit::NoWrap);
    setFont(QFontDatabase::systemFont(QFontDatabase::FixedFont));
    setTextInteractionFlags(Qt::TextSelectableByMouse | Qt::TextSelectableByKeyboard);
    setPlaceholderText(QStringLiteral("Select a commit to see its changes"));
    // Bounded undo/redo history is pointless in a read-only view and only costs
    // memory on large diffs.
    setUndoRedoEnabled(false);
}

void DiffView::clearDiff() {
    diff_.reset();
    clear();
}

void DiffView::showMessage(const QString& message) {
    diff_.reset();
    clear();
    appendPlainText(message);
}

void DiffView::showDiff(std::shared_ptr<const ParsedDiff> diff) {
    diff_ = std::move(diff);
    clear();
    if (diff_) {
        render(*diff_, QString());
    }
}

void DiffView::showFile(std::shared_ptr<const ParsedDiff> diff, const QString& path) {
    diff_ = std::move(diff);
    clear();
    if (diff_) {
        render(*diff_, path);
    }
}

void DiffView::render(const ParsedDiff& diff, const QString& onlyPath) {
    QTextCursor cursor(document());
    cursor.beginEditBlock();

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

    bool renderedAnything = false;

    for (const DiffFile& file : diff.files) {
        const QString displayPath = QString::fromStdString(file.displayPath());
        if (!onlyPath.isEmpty() && displayPath != onlyPath) {
            continue;
        }
        renderedAnything = true;

        QString title = displayPath;
        switch (file.kind) {
            case FileChangeKind::Added:
                title += QStringLiteral("  (new file)");
                break;
            case FileChangeKind::Deleted:
                title += QStringLiteral("  (deleted)");
                break;
            case FileChangeKind::Renamed:
                title =
                    QString::fromStdString(file.oldPath) + QStringLiteral("  →  ") + displayPath;
                break;
            case FileChangeKind::Copied:
                title += QStringLiteral("  (copied from ") + QString::fromStdString(file.oldPath) +
                         QStringLiteral(")");
                break;
            case FileChangeKind::ModeChanged:
                title += QStringLiteral("  (mode ") + QString::fromStdString(file.oldMode) +
                         QStringLiteral(" → ") + QString::fromStdString(file.newMode) +
                         QStringLiteral(")");
                break;
            default:
                break;
        }
        cursor.insertText(title + QStringLiteral("\n"), header);

        if (file.binary) {
            // No hunks exist for a binary file, and saying so beats an empty pane.
            cursor.insertText(QStringLiteral("Binary file not shown\n\n"), dim);
            continue;
        }
        if (file.hunks.empty()) {
            cursor.insertText(QStringLiteral("No textual changes\n\n"), dim);
            continue;
        }

        for (const DiffHunk& hunk : file.hunks) {
            QString hunkLine = QStringLiteral("@@ -%1,%2 +%3,%4 @@")
                                   .arg(hunk.oldStart)
                                   .arg(hunk.oldCount)
                                   .arg(hunk.newStart)
                                   .arg(hunk.newCount);
            if (!hunk.heading.empty()) {
                hunkLine += QStringLiteral(" ") + QString::fromStdString(hunk.heading);
            }
            cursor.insertText(hunkLine + QStringLiteral("\n"), hunkHeader);

            for (const DiffLine& line : hunk.lines) {
                switch (line.kind) {
                    case DiffLineKind::Added:
                        cursor.insertText(QStringLiteral("+") + QString::fromStdString(line.text) +
                                              QStringLiteral("\n"),
                                          added);
                        break;
                    case DiffLineKind::Removed:
                        cursor.insertText(QStringLiteral("-") + QString::fromStdString(line.text) +
                                              QStringLiteral("\n"),
                                          removed);
                        break;
                    case DiffLineKind::Context:
                        cursor.insertText(QStringLiteral(" ") + QString::fromStdString(line.text) +
                                              QStringLiteral("\n"),
                                          plain);
                        break;
                    case DiffLineKind::NoNewlineMarker:
                        cursor.insertText(QString::fromStdString(line.text) + QStringLiteral("\n"),
                                          dim);
                        break;
                }
            }
        }
        cursor.insertText(QStringLiteral("\n"), plain);
    }

    if (diff.truncated) {
        // A size cap that silently hid content would be worse than slow.
        cursor.insertText(QStringLiteral("… diff truncated because it exceeds the display limit\n"),
                          dim);
    }
    if (!renderedAnything) {
        cursor.insertText(QStringLiteral("No changes to show\n"), dim);
    }

    cursor.endEditBlock();
    moveCursor(QTextCursor::Start);
}

}  // namespace gbm
