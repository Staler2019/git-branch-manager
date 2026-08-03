#include "app/views/SideBySideDiffView.h"

#include "app/bridge/ThemeManager.h"
#include "core/git/SideBySideDiff.h"

#include <QAction>
#include <QClipboard>
#include <QContextMenuEvent>
#include <QGuiApplication>
#include <QHBoxLayout>
#include <QLabel>
#include <QMenu>
#include <QMouseEvent>
#include <QPainter>
#include <QPlainTextEdit>
#include <QScrollBar>
#include <QTextBlock>
#include <QTextCharFormat>
#include <QTextCursor>
#include <QVBoxLayout>

namespace gbm {

namespace {

constexpr int kGutterWidth = 20;
constexpr int kCheckboxSize = 13;

// Filler for the side with nothing to show, distinct from (and quieter than)
// both the added/removed tints and the ordinary background.
QColor paddingBackground(const QPalette& palette) {
    const bool dark = palette.base().color().lightness() < 128;
    return dark ? QColor(255, 255, 255, 10) : QColor(0, 0, 0, 12);
}

}  // namespace

/// A QPlainTextEdit that republishes the handful of protected members
/// DiffGutterWidget needs (block geometry, viewport margins) as public
/// wrappers, rather than making DiffGutterWidget a friend of QPlainTextEdit
/// itself, which isn't possible.
class DiffPane : public QPlainTextEdit {
public:
    explicit DiffPane(QWidget* parent) : QPlainTextEdit(parent) {
        setReadOnly(true);
        setLineWrapMode(QPlainTextEdit::NoWrap);
        // ThemeManager::monoFont() (not QFontDatabase::systemFont) so this
        // pane actually shows the bundled JetBrains Mono instead of whatever
        // fixed-width font the platform happens to default to.
        setFont(ThemeManager::monoFont(12));
        setTextInteractionFlags(Qt::TextSelectableByMouse | Qt::TextSelectableByKeyboard);
        setUndoRedoEnabled(false);
    }

    using QPlainTextEdit::blockBoundingGeometry;
    using QPlainTextEdit::blockBoundingRect;
    using QPlainTextEdit::contentOffset;
    using QPlainTextEdit::firstVisibleBlock;
    using QPlainTextEdit::setViewportMargins;
};

/// Paints gutter checkboxes for one pane's changed lines and hit-tests clicks
/// against them. A single companion widget, not one QWidget per line -- the
/// same reason DiffView stays a QPlainTextEdit: long diffs must not pay for
/// up-front per-line layout. Block geometry is read straight from the pane
/// (firstVisibleBlock/blockBoundingGeometry), the same technique Qt's own
/// line-number-area example uses, so this widget only ever draws what is
/// currently on screen.
class DiffGutterWidget : public QWidget {
public:
    DiffGutterWidget(DiffPane* pane, SideBySideDiffView* owner, bool isLeftPane)
        : QWidget(pane), pane_(pane), owner_(owner), isLeftPane_(isLeftPane) {
        setFixedWidth(kGutterWidth);
        setCursor(Qt::PointingHandCursor);
    }

protected:
    void paintEvent(QPaintEvent* event) override {
        QPainter painter(this);
        painter.fillRect(event->rect(), pane_->palette().color(QPalette::Base));

        QTextBlock block = pane_->firstVisibleBlock();
        int blockNumber = block.blockNumber();
        int top =
            qRound(pane_->blockBoundingGeometry(block).translated(pane_->contentOffset()).top());
        int bottom = top + qRound(pane_->blockBoundingRect(block).height());

        while (block.isValid() && top <= event->rect().bottom()) {
            if (block.isVisible() && bottom >= event->rect().top()) {
                if (const auto* marker = owner_->markerForBlock(isLeftPane_, blockNumber)) {
                    const QRect box(kGutterWidth / 2 - kCheckboxSize / 2,
                                    top + (bottom - top) / 2 - kCheckboxSize / 2,
                                    kCheckboxSize,
                                    kCheckboxSize);
                    if (marker->staged) {
                        painter.setPen(Qt::NoPen);
                        painter.setBrush(ThemeManager::color(Token::Accent));
                    } else {
                        painter.setPen(QPen(ThemeManager::color(Token::BorderStrong), 1));
                        painter.setBrush(Qt::NoBrush);
                    }
                    painter.drawRect(box);
                }
            }
            block = block.next();
            top = bottom;
            bottom = top + qRound(pane_->blockBoundingRect(block).height());
            ++blockNumber;
        }
    }

    void mousePressEvent(QMouseEvent* event) override {
        if (event->button() == Qt::LeftButton) {
            const int blockNumber =
                pane_->cursorForPosition(QPoint(0, event->pos().y())).blockNumber();
            owner_->toggleLine(isLeftPane_, blockNumber);
        }
        QWidget::mousePressEvent(event);
    }

    void contextMenuEvent(QContextMenuEvent* event) override {
        const int blockNumber = pane_->cursorForPosition(QPoint(0, event->pos().y())).blockNumber();
        owner_->showLineContextMenu(isLeftPane_, blockNumber, event->globalPos());
    }

private:
    DiffPane* pane_;
    SideBySideDiffView* owner_;
    bool isLeftPane_;
};

SideBySideDiffView::SideBySideDiffView(QWidget* parent) : QWidget(parent) {
    auto* outer = new QVBoxLayout(this);
    outer->setContentsMargins(0, 0, 0, 0);
    outer->setSpacing(4);

    summaryLabel_ = new QLabel(this);
    summaryLabel_->setVisible(false);
    outer->addWidget(summaryLabel_);

    auto* panes = new QWidget(this);
    auto* layout = new QHBoxLayout(panes);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(1);

    left_ = new DiffPane(panes);
    right_ = new DiffPane(panes);
    left_->setPlaceholderText(QStringLiteral("Select a commit to see its changes"));
    left_->setAccessibleName(QStringLiteral("Diff, before"));
    right_->setAccessibleName(QStringLiteral("Diff, after"));
    layout->addWidget(left_);
    layout->addWidget(right_);
    outer->addWidget(panes, 1);

    resultPreview_ = new QPlainTextEdit(this);
    resultPreview_->setReadOnly(true);
    resultPreview_->setLineWrapMode(QPlainTextEdit::NoWrap);
    resultPreview_->setUndoRedoEnabled(false);
    resultPreview_->setVisible(false);
    resultPreview_->setFont(ThemeManager::monoFont(12));
    resultPreview_->setMaximumHeight(160);
    resultPreview_->setAccessibleName(QStringLiteral("Result preview"));
    outer->addWidget(resultPreview_);

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

void SideBySideDiffView::setStagingEnabled(bool enabled) {
    if (stagingEnabled_ == enabled) {
        return;
    }
    stagingEnabled_ = enabled;
    setupStagingChrome();
}

void SideBySideDiffView::setShowingStagedDiff(bool staged) {
    showingStaged_ = staged;
}

void SideBySideDiffView::setupStagingChrome() {
    summaryLabel_->setVisible(stagingEnabled_);
    resultPreview_->setVisible(stagingEnabled_);

    auto* leftPane = static_cast<DiffPane*>(left_);
    auto* rightPane = static_cast<DiffPane*>(right_);

    if (stagingEnabled_ && leftGutter_ == nullptr) {
        leftGutter_ = new DiffGutterWidget(leftPane, this, true);
        rightGutter_ = new DiffGutterWidget(rightPane, this, false);
        leftPane->setViewportMargins(kGutterWidth, 0, 0, 0);
        rightPane->setViewportMargins(kGutterWidth, 0, 0, 0);
        left_->installEventFilter(this);
        right_->installEventFilter(this);
        // updateRequest already covers scroll- and edit-driven repaints (Qt
        // fires it for both), so no separate scrollbar connection is needed.
        connect(left_, &QPlainTextEdit::updateRequest, this, [this] { leftGutter_->update(); });
        connect(right_, &QPlainTextEdit::updateRequest, this, [this] { rightGutter_->update(); });
        leftGutter_->setGeometry(0, 0, kGutterWidth, left_->height());
        rightGutter_->setGeometry(0, 0, kGutterWidth, right_->height());
        leftGutter_->show();
        rightGutter_->show();
    } else if (!stagingEnabled_ && leftGutter_ != nullptr) {
        left_->removeEventFilter(this);
        right_->removeEventFilter(this);
        leftPane->setViewportMargins(0, 0, 0, 0);
        rightPane->setViewportMargins(0, 0, 0, 0);
        leftGutter_->deleteLater();
        rightGutter_->deleteLater();
        leftGutter_ = nullptr;
        rightGutter_ = nullptr;
    }
}

bool SideBySideDiffView::eventFilter(QObject* watched, QEvent* event) {
    if (event->type() == QEvent::Resize) {
        if (watched == left_ && leftGutter_ != nullptr) {
            leftGutter_->setGeometry(0, 0, kGutterWidth, left_->height());
        } else if (watched == right_ && rightGutter_ != nullptr) {
            rightGutter_->setGeometry(0, 0, kGutterWidth, right_->height());
        }
    }
    return QWidget::eventFilter(watched, event);
}

void SideBySideDiffView::clearDiff() {
    diff_.reset();
    leftMarkers_.clear();
    rightMarkers_.clear();
    left_->clear();
    right_->clear();
    updateSummary();
    updateResultPreview();
}

void SideBySideDiffView::showMessage(const QString& message) {
    diff_.reset();
    leftMarkers_.clear();
    rightMarkers_.clear();
    left_->clear();
    right_->clear();
    left_->appendPlainText(message);
    updateSummary();
    updateResultPreview();
}

void SideBySideDiffView::showDiff(std::shared_ptr<const ParsedDiff> diff) {
    diff_ = std::move(diff);
    lastOnlyPath_.clear();
    left_->clear();
    right_->clear();
    if (diff_) {
        render(*diff_, QString());
    }
}

void SideBySideDiffView::showFile(std::shared_ptr<const ParsedDiff> diff, const QString& path) {
    diff_ = std::move(diff);
    lastOnlyPath_ = path;
    left_->clear();
    right_->clear();
    if (diff_) {
        render(*diff_, path);
    }
}

void SideBySideDiffView::refreshTheme() {
    if (!diff_) {
        return;
    }
    left_->clear();
    right_->clear();
    render(*diff_, lastOnlyPath_);
}

const SideBySideDiffView::LineMarker* SideBySideDiffView::markerForBlock(bool onLeftPane,
                                                                         int blockNumber) const {
    const std::vector<LineMarker>& markers = onLeftPane ? leftMarkers_ : rightMarkers_;
    for (const LineMarker& marker : markers) {
        if (marker.blockNumber == blockNumber) {
            return &marker;
        }
    }
    return nullptr;
}

SideBySideDiffView::LineMarker* SideBySideDiffView::markerForBlock(bool onLeftPane,
                                                                   int blockNumber) {
    std::vector<LineMarker>& markers = onLeftPane ? leftMarkers_ : rightMarkers_;
    for (LineMarker& marker : markers) {
        if (marker.blockNumber == blockNumber) {
            return &marker;
        }
    }
    return nullptr;
}

void SideBySideDiffView::toggleLine(bool onLeftPane, int blockNumber) {
    LineMarker* marker = markerForBlock(onLeftPane, blockNumber);
    if (marker == nullptr || marker->pending) {
        return;
    }
    marker->pending = true;
    marker->staged = !marker->staged;

    std::vector<bool> selected(marker->hunk->lines.size(), false);
    selected[marker->lineIndex] = true;
    // showingStaged_ doubles as buildLineSelectionPatch's `unstaging` here, the
    // same as DiffView::contextMenuEvent's line-selection action -- this pane
    // is reachable staging-enabled from DiffPage::showWorkingCopyDiff(staged =
    // true), and without this the "patch does not apply" bug (item 7) still
    // hit by toggling a single line here even after DiffView's fix.
    const std::string patch = UnifiedDiffParser::buildLineSelectionPatch(
        *marker->file, *marker->hunk, selected, /*unstaging=*/showingStaged_);
    emit applyPatchRequested(QString::fromStdString(patch), showingStaged_);

    (onLeftPane ? leftGutter_ : rightGutter_)->update();
    updateSummary();
    updateResultPreview();
}

void SideBySideDiffView::showLineContextMenu(bool onLeftPane,
                                             int blockNumber,
                                             const QPoint& globalPos) {
    LineMarker* marker = markerForBlock(onLeftPane, blockNumber);
    if (marker == nullptr) {
        return;
    }

    QMenu menu;
    QAction* lineAction = menu.addAction(marker->staged ? tr("Unstage Line") : tr("Stage Line"));
    connect(lineAction, &QAction::triggered, this, [this, onLeftPane, blockNumber] {
        toggleLine(onLeftPane, blockNumber);
    });

    QAction* hunkAction = menu.addAction(showingStaged_ ? tr("Unstage Hunk") : tr("Stage Hunk"));
    const DiffFile* file = marker->file;
    const DiffHunk* hunk = marker->hunk;
    const bool reverse = showingStaged_;
    connect(hunkAction, &QAction::triggered, this, [this, file, hunk, reverse] {
        // See DiffView::contextMenuEvent's identical hunk-staging action: this
        // pane is staging-enabled from DiffPage::showWorkingCopyDiff, so the
        // same rename-unstage hazard applies here.
        const std::string patch = UnifiedDiffParser::buildHunkPatch(
            *file, *hunk, /*reverse=*/false, /*unstaging=*/reverse);
        emit applyPatchRequested(QString::fromStdString(patch), reverse);
    });

    menu.addSeparator();
    QAction* copyAction = menu.addAction(tr("Copy Line"));
    const QString lineText = QString::fromStdString(marker->hunk->lines[marker->lineIndex].text);
    connect(copyAction, &QAction::triggered, this, [lineText] {
        QGuiApplication::clipboard()->setText(lineText);
    });

    menu.exec(globalPos);
}

void SideBySideDiffView::updateSummary() {
    if (!stagingEnabled_) {
        return;
    }
    const int total = static_cast<int>(leftMarkers_.size() + rightMarkers_.size());
    int staged = 0;
    for (const LineMarker& marker : leftMarkers_) {
        staged += marker.staged ? 1 : 0;
    }
    for (const LineMarker& marker : rightMarkers_) {
        staged += marker.staged ? 1 : 0;
    }
    summaryLabel_->setText(tr("%1 of %2 changed lines staged").arg(staged).arg(total));
}

void SideBySideDiffView::updateResultPreview() {
    if (!stagingEnabled_) {
        return;
    }
    if (!diff_) {
        resultPreview_->setPlainText(QString());
        return;
    }

    QString result;
    for (const DiffFile& file : diff_->files) {
        const QString displayPath = QString::fromStdString(file.displayPath());
        if (!lastOnlyPath_.isEmpty() && displayPath != lastOnlyPath_) {
            continue;
        }
        result += displayPath + QStringLiteral("\n");
        for (const DiffHunk& hunk : file.hunks) {
            for (const DiffLine& line : hunk.lines) {
                bool checked = false;
                for (const LineMarker& marker :
                     line.kind == DiffLineKind::Removed ? leftMarkers_ : rightMarkers_) {
                    if (marker.hunk == &hunk && &hunk.lines[marker.lineIndex] == &line) {
                        checked = marker.staged;
                        break;
                    }
                }
                switch (line.kind) {
                    case DiffLineKind::Context:
                        result += QString::fromStdString(line.text) + QStringLiteral("\n");
                        break;
                    case DiffLineKind::Added:
                        // An unselected added line was never staged: it drops out.
                        if (checked) {
                            result += QString::fromStdString(line.text) + QStringLiteral("\n");
                        }
                        break;
                    case DiffLineKind::Removed:
                        // An unselected removed line is not being removed: it
                        // stays, exactly like buildLineSelectionPatch's rule.
                        if (!checked) {
                            result += QString::fromStdString(line.text) + QStringLiteral("\n");
                        }
                        break;
                    case DiffLineKind::NoNewlineMarker:
                        break;
                }
            }
        }
        result += QStringLiteral("\n");
    }
    resultPreview_->setPlainText(result);
}

void SideBySideDiffView::render(const ParsedDiff& diff, const QString& onlyPath) {
    leftMarkers_.clear();
    rightMarkers_.clear();

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
    added.setBackground(ThemeManager::color(Token::DiffAddBg));
    added.setForeground(ThemeManager::color(Token::DiffAddText));
    QTextCharFormat removed;
    removed.setBackground(ThemeManager::color(Token::DiffDelBg));
    removed.setForeground(ThemeManager::color(Token::DiffDelText));
    QTextCharFormat dim;
    dim.setForeground(ThemeManager::color(Token::TextTertiary));
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
                if (stagingEnabled_ && row.left != nullptr &&
                    row.left->kind == DiffLineKind::Removed) {
                    const auto lineIndex = static_cast<std::size_t>(row.left - hunk.lines.data());
                    leftMarkers_.push_back(LineMarker{leftCursor.blockNumber() - 1,
                                                      &file,
                                                      &hunk,
                                                      lineIndex,
                                                      showingStaged_,
                                                      false});
                }
                insertCell(rightCursor, row.right);
                if (stagingEnabled_ && row.right != nullptr &&
                    row.right->kind == DiffLineKind::Added) {
                    const auto lineIndex = static_cast<std::size_t>(row.right - hunk.lines.data());
                    rightMarkers_.push_back(LineMarker{rightCursor.blockNumber() - 1,
                                                       &file,
                                                       &hunk,
                                                       lineIndex,
                                                       showingStaged_,
                                                       false});
                }
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

    if (leftGutter_ != nullptr) {
        // Re-assert geometry (not just repaint): if this is the first render
        // after setStagingEnabled(true) and the pane hadn't been laid out yet
        // (height() still a placeholder default), no QEvent::Resize may have
        // reached the event filter yet to size the gutter correctly.
        leftGutter_->setGeometry(0, 0, kGutterWidth, left_->height());
        rightGutter_->setGeometry(0, 0, kGutterWidth, right_->height());
        leftGutter_->update();
        rightGutter_->update();
    }
    updateSummary();
    updateResultPreview();
}

}  // namespace gbm
