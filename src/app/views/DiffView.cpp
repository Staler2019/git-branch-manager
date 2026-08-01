#include "app/views/DiffView.h"

#include "app/bridge/ThemeManager.h"

#include <QAction>
#include <QContextMenuEvent>
#include <QFont>
#include <QFontDatabase>
#include <QMenu>
#include <QTextBlockFormat>
#include <QTextCharFormat>
#include <QTextCursor>

#include <memory>

namespace gbm {

DiffView::DiffView(QWidget* parent) : QPlainTextEdit(parent) {
    setReadOnly(true);
    setLineWrapMode(QPlainTextEdit::NoWrap);
    setFont(QFontDatabase::systemFont(QFontDatabase::FixedFont));
    setTextInteractionFlags(Qt::TextSelectableByMouse | Qt::TextSelectableByKeyboard);
    setPlaceholderText(QStringLiteral("Select a commit to see its changes"));
    setAccessibleName(QStringLiteral("Diff"));
    // Bounded undo/redo history is pointless in a read-only view and only costs
    // memory on large diffs.
    setUndoRedoEnabled(false);
}

void DiffView::setStagingEnabled(bool enabled) {
    stagingEnabled_ = enabled;
}

void DiffView::setShowingStagedDiff(bool staged) {
    showingStaged_ = staged;
}

void DiffView::clearDiff() {
    diff_.reset();
    hunkSpans_.clear();
    clear();
}

void DiffView::showMessage(const QString& message) {
    diff_.reset();
    hunkSpans_.clear();
    clear();
    appendPlainText(message);
}

void DiffView::showDiff(std::shared_ptr<const ParsedDiff> diff) {
    diff_ = std::move(diff);
    lastOnlyPath_.clear();
    clear();
    if (diff_) {
        render(*diff_, QString());
    }
}

void DiffView::showFile(std::shared_ptr<const ParsedDiff> diff, const QString& path) {
    diff_ = std::move(diff);
    lastOnlyPath_ = path;
    clear();
    if (diff_) {
        render(*diff_, path);
    }
}

void DiffView::refreshTheme() {
    if (!diff_) {
        return;
    }
    clear();
    render(*diff_, lastOnlyPath_);
}

const DiffView::HunkSpan* DiffView::hunkSpanForBlock(int blockNumber) const {
    for (const HunkSpan& span : hunkSpans_) {
        if (blockNumber >= span.firstLine && blockNumber <= span.lastLine) {
            return &span;
        }
    }
    return nullptr;
}

void DiffView::contextMenuEvent(QContextMenuEvent* event) {
    if (!stagingEnabled_ || !diff_) {
        QPlainTextEdit::contextMenuEvent(event);
        return;
    }

    const HunkSpan* span = hunkSpanForBlock(cursorForPosition(event->pos()).blockNumber());
    if (span == nullptr) {
        QPlainTextEdit::contextMenuEvent(event);
        return;
    }

    std::unique_ptr<QMenu> menu(createStandardContextMenu());
    menu->addSeparator();

    QAction* hunkAction = menu->addAction(showingStaged_ ? tr("Unstage Hunk") : tr("Stage Hunk"));
    const bool reverse = showingStaged_;
    connect(hunkAction, &QAction::triggered, this, [this, span, reverse] {
        const std::string patch = UnifiedDiffParser::buildHunkPatch(*span->file, *span->hunk);
        emit applyPatchRequested(QString::fromStdString(patch), reverse);
    });

    // Line-level staging only when the selection sits entirely inside this
    // hunk's body: a selection spanning hunks or files has no single patch.
    const QTextCursor selection = textCursor();
    if (selection.hasSelection()) {
        QTextCursor start(document());
        start.setPosition(selection.selectionStart());
        QTextCursor end(document());
        end.setPosition(selection.selectionEnd());
        const int selStart = start.blockNumber();
        const int selEnd = end.blockNumber();

        if (selStart >= span->firstLine && selEnd <= span->lastLine) {
            QAction* lineAction = menu->addAction(showingStaged_ ? tr("Unstage Selected Lines")
                                                                 : tr("Stage Selected Lines"));
            connect(lineAction, &QAction::triggered, this, [this, span, selStart, selEnd, reverse] {
                std::vector<bool> selected(span->hunk->lines.size(), false);
                for (int line = selStart; line <= selEnd; ++line) {
                    const auto index = static_cast<std::size_t>(line - span->firstLine);
                    if (index < selected.size()) {
                        selected[index] = true;
                    }
                }
                const std::string patch =
                    UnifiedDiffParser::buildLineSelectionPatch(*span->file, *span->hunk, selected);
                emit applyPatchRequested(QString::fromStdString(patch), reverse);
            });
        }
    }

    menu->exec(event->globalPos());
}

void DiffView::render(const ParsedDiff& diff, const QString& onlyPath) {
    hunkSpans_.clear();
    QTextCursor cursor(document());
    cursor.beginEditBlock();

    QTextCharFormat plain;
    QTextCharFormat header;
    header.setFontWeight(QFont::Bold);
    QTextCharFormat hunkHeader;
    hunkHeader.setForeground(palette().color(QPalette::Link));
    QTextCharFormat added;
    added.setBackground(ThemeManager::color(Token::DiffAddBg));
    added.setForeground(ThemeManager::color(Token::DiffAddText));
    QTextCharFormat removed;
    removed.setBackground(ThemeManager::color(Token::DiffDelBg));
    removed.setForeground(ThemeManager::color(Token::DiffDelText));
    QTextCharFormat dim;
    dim.setForeground(ThemeManager::color(Token::TextTertiary));

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
            const int firstLine = cursor.blockNumber();

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

            if (stagingEnabled_ && !hunk.lines.empty()) {
                hunkSpans_.push_back({firstLine, cursor.blockNumber() - 1, &file, &hunk});
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
