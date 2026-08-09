#include "app/views/ConflictResolvePanel.h"

#include "app/bridge/RepositorySession.h"
#include "app/bridge/ThemeManager.h"
#include "app/theme/Tokens.h"
#include "core/git/WorkingCopyStatus.h"
#include "core/git/ops/ConflictOps.h"

#include <QAbstractButton>
#include <QCheckBox>
#include <QDialog>
#include <QDialogButtonBox>
#include <QGroupBox>
#include <QHBoxLayout>
#include <QLabel>
#include <QPainter>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QResizeEvent>
#include <QScrollArea>
#include <QSettings>
#include <QSplitter>
#include <QTextBlock>
#include <QTextCursor>
#include <QTextEdit>
#include <QTimer>
#include <QVBoxLayout>

#include <algorithm>
#include <utility>

namespace gbm {

namespace {

/// A read-only-friendly QPlainTextEdit with a line-number gutter in its
/// viewport margin -- the standard Qt "Code Editor" example pattern
/// (firstVisibleBlock/blockBoundingGeometry are protected on QPlainTextEdit,
/// so a companion LineNumberArea widget can only reach them through a
/// subclass). Local to this file: nothing else in the app needs line
/// numbers yet, so this isn't pulled out into its own reusable class.
class LineNumberArea;

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

/// A line string's text with its trailing "\r\n"/"\n" stripped, for display
/// as a checkbox label -- indentation is kept (only the line ending goes),
/// since it's still code the user is choosing between.
QString lineLabelText(const std::string& line) {
    QString text = QString::fromStdString(line);
    if (text.endsWith(QStringLiteral("\r\n"))) {
        text.chop(2);
    } else if (text.endsWith(QLatin1Char('\n'))) {
        text.chop(1);
    }
    return text;
}

/// "逐行挑" (pick lines): a modal dialog for one conflict region, offering a
/// checkbox per source line on each side (in original order) and a live
/// preview of the concatenation of everything checked -- left side first,
/// then right side. It stitches together a subset of each side's lines
/// rather than letting the user interleave/reorder them; reordering would
/// need a very different UI (drag-and-drop or an ordered pick list) for a
/// case the plan doesn't call for. A modal is fine here specifically because
/// the user opens it deliberately from the region strip -- unlike the
/// auto-popping dialogs removed earlier in this epic (issue #2), this one
/// never appears on its own.
///
/// Every line handed in already carries its own trailing line ending: a
/// Region segment's ours/theirs lines are always followed by at least the
/// closing ">>>>>>>" marker line within the file, so none of them can be the
/// file's true last line -- the only line ConflictMarkerParser ever leaves
/// without a line ending (see ConflictSegment's doc comment). So selected
/// lines can just be concatenated as-is; no endings need to be invented.
class ConflictLinePickDialog : public QDialog {
public:
    /// `preselected` is the region's current resolution, if any -- reopening
    /// the dialog on an already-Custom-resolved region should show what was
    /// picked last time, not force starting over from scratch.
    ConflictLinePickDialog(std::vector<std::string> oursLines,
                            std::vector<std::string> theirsLines,
                            const std::vector<std::string>& preselected,
                            QWidget* parent);

    /// Only meaningful once exec() has returned QDialog::Accepted.
    std::vector<std::string> selectedLines() const;

private:
    void updatePreview();

    std::vector<std::string> oursLines_;
    std::vector<std::string> theirsLines_;
    std::vector<QCheckBox*> oursChecks_;
    std::vector<QCheckBox*> theirsChecks_;
    QPlainTextEdit* preview_ = nullptr;
    QAbstractButton* okButton_ = nullptr;
};

ConflictLinePickDialog::ConflictLinePickDialog(std::vector<std::string> oursLines,
                                                std::vector<std::string> theirsLines,
                                                const std::vector<std::string>& preselected,
                                                QWidget* parent)
    : QDialog(parent), oursLines_(std::move(oursLines)), theirsLines_(std::move(theirsLines)) {
    // No Q_OBJECT (this class lives in an anonymous namespace, so it isn't
    // MOC-visible) -- tr() would silently resolve to QDialog::tr() with the
    // wrong translation context, so every string here goes through
    // QObject::tr() explicitly instead for a consistent context.
    setWindowTitle(QObject::tr("Pick Lines"));

    auto* layout = new QVBoxLayout(this);

    // `preselected` may contain duplicate identical lines (e.g. repeated
    // blank lines or "}"), so each entry is matched against the next
    // not-yet-matched occurrence on either side, in order, rather than
    // matching every equal line at once.
    std::vector<bool> oursMatched(oursLines_.size(), false);
    std::vector<bool> theirsMatched(theirsLines_.size(), false);
    auto consumeMatch = [](const std::string& line, const std::vector<std::string>& source,
                            std::vector<bool>& matched) {
        for (std::size_t i = 0; i < source.size(); ++i) {
            if (!matched[i] && source[i] == line) {
                matched[i] = true;
                return true;
            }
        }
        return false;
    };
    for (const std::string& line : preselected) {
        if (!consumeMatch(line, oursLines_, oursMatched)) {
            consumeMatch(line, theirsLines_, theirsMatched);
        }
    }

    auto makeColumn = [this](const QString& title,
                              const std::vector<std::string>& lines,
                              const std::vector<bool>& matched,
                              std::vector<QCheckBox*>& checks) {
        auto* group = new QGroupBox(title);
        auto* groupLayout = new QVBoxLayout(group);
        for (std::size_t i = 0; i < lines.size(); ++i) {
            auto* check = new QCheckBox(lineLabelText(lines[i]), group);
            check->setChecked(matched[i]);
            connect(check, &QCheckBox::toggled, this, &ConflictLinePickDialog::updatePreview);
            groupLayout->addWidget(check);
            checks.push_back(check);
        }
        groupLayout->addStretch(1);
        auto* scroll = new QScrollArea(this);
        scroll->setWidget(group);
        scroll->setWidgetResizable(true);
        return scroll;
    };
    auto* columns = new QHBoxLayout();
    columns->addWidget(makeColumn(QObject::tr("Current branch (mine)"), oursLines_, oursMatched, oursChecks_));
    columns->addWidget(
        makeColumn(QObject::tr("Merged branch (theirs)"), theirsLines_, theirsMatched, theirsChecks_));
    layout->addLayout(columns, 1);

    layout->addWidget(new QLabel(QObject::tr("Preview"), this));
    preview_ = new QPlainTextEdit(this);
    preview_->setReadOnly(true);
    preview_->setLineWrapMode(QPlainTextEdit::NoWrap);
    layout->addWidget(preview_);

    auto* buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel, this);
    okButton_ = buttons->button(QDialogButtonBox::Ok);
    connect(buttons, &QDialogButtonBox::accepted, this, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
    layout->addWidget(buttons);

    resize(640, 480);
    updatePreview();
}

std::vector<std::string> ConflictLinePickDialog::selectedLines() const {
    std::vector<std::string> result;
    for (std::size_t i = 0; i < oursChecks_.size(); ++i) {
        if (oursChecks_[i]->isChecked()) {
            result.push_back(oursLines_[i]);
        }
    }
    for (std::size_t i = 0; i < theirsChecks_.size(); ++i) {
        if (theirsChecks_[i]->isChecked()) {
            result.push_back(theirsLines_[i]);
        }
    }
    return result;
}

void ConflictLinePickDialog::updatePreview() {
    const std::vector<std::string> selected = selectedLines();
    QString text;
    for (const std::string& line : selected) {
        text += QString::fromStdString(line);
    }
    preview_->setPlainText(text);
    // An empty pick would resolve the region to nothing with no visible
    // trace it ever had content -- force at least one line checked before
    // Ok is reachable. Deliberately dropping a region isn't a use case this
    // dialog serves.
    okButton_->setEnabled(!selected.empty());
}

/// Mirrors WorkingCopyView::setupPersistentSplitter exactly -- both read the
/// same `window/splitters/<key>` QSettings keys. Duplicated rather than
/// shared: the two classes have no common base to hang a helper off, same
/// reasoning as WorkingCopyView's own copy.
void setupPersistentSplitter(QSplitter* splitter, const QString& key) {
    const QString settingsKey = QStringLiteral("window/splitters/%1").arg(key);

    QSettings settings;
    const QVariant saved = settings.value(settingsKey);
    if (saved.isValid()) {
        const QVariantList list = saved.toList();
        QList<int> sizes;
        sizes.reserve(list.size());
        for (const QVariant& value : list) {
            sizes.append(value.toInt());
        }
        if (!sizes.isEmpty()) {
            QTimer::singleShot(0, splitter, [splitter, sizes] { splitter->setSizes(sizes); });
        }
    }

    QObject::connect(splitter, &QSplitter::splitterMoved, splitter, [splitter, settingsKey] {
        QSettings settingsToSave;
        QVariantList list;
        for (int size : splitter->sizes()) {
            list.append(size);
        }
        settingsToSave.setValue(settingsKey, list);
    });
}

}  // namespace

ConflictResolvePanel::ConflictResolvePanel(QWidget* parent) : QWidget(parent) {
    auto* layout = new QVBoxLayout(this);

    auto* headerRow = new QHBoxLayout();
    kindLabel_ = new QLabel(this);
    kindLabel_->setVisible(false);
    headerRow->addWidget(kindLabel_, 1);
    ancestorToggle_ = new QCheckBox(tr("Show common ancestor"), this);
    headerRow->addWidget(ancestorToggle_);
    layout->addLayout(headerRow);

    // Per-region controls now live in their own full-width row above
    // panesSplitter_, not inside the middle pane's own layout. They used to
    // be inserted directly into the middle pane's container (see git
    // history) which inflated that pane's minimumSizeHint far past its
    // siblings' and made the splitter refuse to shrink it -- the actual
    // cause of the "drag bar feels wired wrong" report. A strip above the
    // splitter still sits between the title row and the panes visually, it
    // just no longer counts toward any one pane's minimum width.
    regionStrip_ = new QWidget(this);
    // Named so ConflictUiTest can locate it structurally (ancestor-of-a-pane
    // check) regardless of its current visibility -- setVisible(false) below
    // hides it but does not remove it from the layout, so a size-hint-based
    // test would silently pass for the wrong reason (hidden items are
    // excluded from minimumSizeHint()) while an objectName lookup still
    // finds it.
    regionStrip_->setObjectName(QStringLiteral("conflictRegionStrip"));
    auto* stripLayout = new QHBoxLayout(regionStrip_);
    stripLayout->setContentsMargins(0, 0, 0, 0);
    regionPrevButton_ = new QPushButton(QStringLiteral("◀"), regionStrip_);
    regionPositionLabel_ = new QLabel(regionStrip_);
    regionNextButton_ = new QPushButton(QStringLiteral("▶"), regionStrip_);
    regionTakeLeftButton_ = new QPushButton(tr("Take Left"), regionStrip_);
    regionTakeRightButton_ = new QPushButton(tr("Take Right"), regionStrip_);
    regionPickLinesButton_ = new QPushButton(tr("Pick Lines…"), regionStrip_);
    regionTakeLeftAllButton_ = new QPushButton(tr("Take Left (All)"), regionStrip_);
    regionTakeRightAllButton_ = new QPushButton(tr("Take Right (All)"), regionStrip_);
    stripLayout->addWidget(regionPrevButton_);
    stripLayout->addWidget(regionPositionLabel_);
    stripLayout->addWidget(regionNextButton_);
    stripLayout->addWidget(regionTakeLeftButton_);
    stripLayout->addWidget(regionTakeRightButton_);
    stripLayout->addWidget(regionPickLinesButton_);
    stripLayout->addStretch(1);
    stripLayout->addWidget(regionTakeLeftAllButton_);
    stripLayout->addWidget(regionTakeRightAllButton_);
    regionStrip_->setVisible(false);
    layout->addWidget(regionStrip_);

    panesSplitter_ = new QSplitter(Qt::Horizontal, this);
    // House configuration every other splitter in this app already carries
    // (see WorkingCopyView.cpp, SidebarPanel.cpp) -- panesSplitter_ was the
    // one exception, which let panes get dragged to zero width and never
    // recover.
    panesSplitter_->setHandleWidth(6);
    panesSplitter_->setChildrenCollapsible(false);
    auto makePane = [&](const QString& title) {
        auto* container = new QWidget(panesSplitter_);
        container->setMinimumWidth(160);
        auto* paneLayout = new QVBoxLayout(container);
        paneLayout->setContentsMargins(0, 0, 0, 0);
        paneLayout->addWidget(new QLabel(title, container));
        auto* edit = new ConflictTextEdit(container);
        edit->setReadOnly(true);
        edit->setLineWrapMode(QPlainTextEdit::NoWrap);
        edit->setPlainText(tr("Loading…"));
        paneLayout->addWidget(edit, 1);
        const int index = panesSplitter_->count();
        panesSplitter_->addWidget(container);
        panesSplitter_->setStretchFactor(index, 1);
        return std::pair{container, edit};
    };
    std::tie(ancestorContainer_, ancestorEdit_) = makePane(tr("Common ancestor"));
    ancestorContainer_->setVisible(false);
    std::tie(std::ignore, oursEdit_) = makePane(tr("Current branch (mine)"));
    std::tie(std::ignore, middleEdit_) = makePane(tr("Resolved content (editable)"));
    std::tie(std::ignore, theirsEdit_) = makePane(tr("Merged branch (theirs)"));
    // Equal default split -- overridden a moment later by
    // setupPersistentSplitter()'s deferred restore if sizes were saved from
    // a previous session.
    const int equalShare = qMax(panesSplitter_->width(), 800) / panesSplitter_->count();
    panesSplitter_->setSizes(
        QList<int>(panesSplitter_->count(), equalShare));
    layout->addWidget(panesSplitter_, 1);
    setupPersistentSplitter(panesSplitter_, QStringLiteral("conflictPanes"));

    connect(ancestorToggle_, &QCheckBox::toggled, ancestorContainer_, &QWidget::setVisible);

    connect(regionPrevButton_, &QPushButton::clicked, this, [this] { navigateRegion(-1); });
    connect(regionNextButton_, &QPushButton::clicked, this, [this] { navigateRegion(1); });
    connect(regionTakeLeftButton_, &QPushButton::clicked, this, [this] {
        resolveRegion(currentRegionIndex_, ConflictRegionResolution{ConflictRegionChoice::Ours, {}});
    });
    connect(regionTakeRightButton_, &QPushButton::clicked, this, [this] {
        resolveRegion(currentRegionIndex_,
                       ConflictRegionResolution{ConflictRegionChoice::Theirs, {}});
    });
    connect(regionPickLinesButton_, &QPushButton::clicked, this, [this] {
        pickLinesForCurrentRegion();
    });
    connect(regionTakeLeftAllButton_, &QPushButton::clicked, this, [this] {
        resolveAllRegions(ConflictRegionChoice::Ours);
    });
    connect(regionTakeRightAllButton_, &QPushButton::clicked, this, [this] {
        resolveAllRegions(ConflictRegionChoice::Theirs);
    });

    auto* buttonRow = new QHBoxLayout();
    auto* takeLeftButton = new QPushButton(tr("Take Left (Mine)"), this);
    auto* takeRightButton = new QPushButton(tr("Take Right (Theirs)"), this);
    saveButton_ = new QPushButton(tr("Save and Mark Resolved"), this);
    saveButton_->setEnabled(false);
    auto* cancelButton = new QPushButton(tr("Cancel"), this);
    buttonRow->addWidget(takeLeftButton);
    buttonRow->addWidget(takeRightButton);
    buttonRow->addWidget(saveButton_);
    buttonRow->addStretch(1);
    buttonRow->addWidget(cancelButton);
    layout->addLayout(buttonRow);

    connect(takeLeftButton, &QPushButton::clicked, this, [this] { submitResolution(1); });
    connect(takeRightButton, &QPushButton::clicked, this, [this] { submitResolution(2); });
    connect(saveButton_, &QPushButton::clicked, this, [this] { submitResolution(3); });
    connect(cancelButton, &QPushButton::clicked, this, [this] { submitResolution(0); });
}

void ConflictResolvePanel::showEntry(RepositorySession* session, const WorkingCopyEntry& entry) {
    session_ = session;
    path_ = entry.path;
    ancestorBlobMissing_ = entry.ancestorBlob.empty();
    oursBlobMissing_ = entry.oursBlob.empty();
    theirsBlobMissing_ = entry.theirsBlob.empty();
    middleContentHasCrlf_ = false;
    middleEditable_ = false;
    saveButton_->setEnabled(false);
    // The panel is reused across every conflict in a batch (see the
    // UniqueConnection comment below), so the previous entry's per-region
    // state must not leak into this one -- otherwise a text conflict's
    // regionStrip_ stays visible (with stale N/M text) over a subsequent
    // binary/delete-modify conflict that has no regions of its own.
    parsedMarkers_ = ParsedConflictFile{};
    regionResolutions_.clear();
    regionTextRanges_.clear();
    currentRegionIndex_ = 0;
    regionStrip_->setVisible(false);

    QString kindText;
    switch (entry.conflict) {
        case ConflictKind::BothAdded:
            kindText = tr("Both sides added this file.");
            break;
        case ConflictKind::BothModified:
            kindText = tr("Both sides modified this file.");
            break;
        case ConflictKind::BothDeleted:
            kindText = tr("Both sides deleted this file.");
            break;
        case ConflictKind::AddedByUs:
            kindText = tr("You added this file; the other side did not touch it.");
            break;
        case ConflictKind::DeletedByUs:
            kindText = tr("You deleted this file; the other side modified it.");
            break;
        case ConflictKind::AddedByThem:
            kindText = tr("The other side added this file; you did not touch it.");
            break;
        case ConflictKind::DeletedByThem:
            kindText = tr("The other side deleted this file; you modified it.");
            break;
        case ConflictKind::None:
            break;
    }
    kindLabel_->setText(kindText);
    kindLabel_->setVisible(!kindText.isEmpty());

    ancestorEdit_->setPlainText(tr("Loading…"));
    oursEdit_->setPlainText(tr("Loading…"));
    middleEdit_->setReadOnly(true);
    middleEdit_->setPlainText(tr("Loading…"));
    theirsEdit_->setPlainText(tr("Loading…"));
    if (entry.ancestorBlob.empty()) {
        ancestorEdit_->setPlainText(tr("(no common ancestor)"));
    }
    if (entry.oursBlob.empty()) {
        oursEdit_->setPlainText(tr("(deleted on this side)"));
    }
    if (entry.theirsBlob.empty()) {
        theirsEdit_->setPlainText(tr("(deleted on the other side)"));
    }

    // Scoped to this widget's lifetime: if a reply arrives after the panel
    // has already been destroyed, Qt drops the connection rather than
    // calling back into a dangling this. UniqueConnection matters here --
    // showEntry() is called again for every conflict in a batch on a panel
    // that is embedded (not recreated), so a plain connect() would stack a
    // new duplicate on top of every previous one and fire the handler N
    // times on the Nth call.
    connect(session_,
            &RepositorySession::conflictSidesReady,
            this,
            &ConflictResolvePanel::onConflictSidesReady,
            Qt::UniqueConnection);
    session_->requestConflictSides(entry.path, entry.ancestorBlob, entry.oursBlob, entry.theirsBlob);

    connect(session_,
            &RepositorySession::workingTreeContentReady,
            this,
            &ConflictResolvePanel::onWorkingTreeContentReady,
            Qt::UniqueConnection);
    session_->requestWorkingTreeContent(entry.path);
}

void ConflictResolvePanel::onConflictSidesReady(const QString& path,
                                                 const QString& ancestor,
                                                 const QString& ours,
                                                 const QString& theirs) {
    if (path.toStdString() != path_) {
        return;
    }
    if (!ancestorBlobMissing_) {
        ancestorEdit_->setPlainText(ancestor);
    }
    if (!oursBlobMissing_) {
        oursEdit_->setPlainText(ours);
    }
    if (!theirsBlobMissing_) {
        theirsEdit_->setPlainText(theirs);
    }
}

void ConflictResolvePanel::onWorkingTreeContentReady(const QString& path,
                                                      const QString& content,
                                                      bool editable) {
    if (path.toStdString() != path_) {
        return;
    }
    middleEditable_ = editable;
    saveButton_->setEnabled(editable);
    if (!editable) {
        middleEdit_->setReadOnly(true);
        middleEdit_->setPlainText(
            tr("(binary or non-UTF-8 content — use Take Left or Take Right)"));
        parsedMarkers_ = ParsedConflictFile{};
        regionResolutions_.clear();
        regionStrip_->setVisible(false);
        return;
    }

    middleContentHasCrlf_ = content.contains(QStringLiteral("\r\n"));
    parsedMarkers_ = ConflictMarkerParser{}.parse(content.toStdString());
    regionResolutions_.assign(parsedMarkers_.regionCount, ConflictRegionResolution{});
    currentRegionIndex_ = 0;
    middleEdit_->setReadOnly(false);
    regionStrip_->setVisible(parsedMarkers_.regionCount > 0);
    // regionCount == 0 covers both "no markers at all" and "the parser gave
    // up on a malformed file" (parsedMarkers_.wellFormed == false) -- either
    // way there is nothing to render per-region, so the raw on-disk content
    // is shown exactly as before per-region resolution existed.
    if (parsedMarkers_.regionCount == 0) {
        middleEdit_->setPlainText(content);
    } else {
        refreshMiddleFromResolutions();
    }
    saveButton_->setEnabled(canSave());
}

QString ConflictResolvePanel::buildMiddlePreviewText(
    std::vector<std::pair<int, int>>* regionRanges) const {
    QString text;
    int regionIndex = 0;
    for (const ConflictSegment& segment : parsedMarkers_.segments) {
        if (segment.kind == ConflictSegmentKind::Text) {
            for (const std::string& line : segment.lines) {
                text += QString::fromStdString(line);
            }
            continue;
        }

        const int rangeStart = text.size();
        const ConflictRegionResolution& resolution =
            regionResolutions_[static_cast<std::size_t>(regionIndex)];
        const std::vector<std::string>* chosen = nullptr;
        switch (resolution.choice) {
            case ConflictRegionChoice::Ours:
                chosen = &segment.ours;
                break;
            case ConflictRegionChoice::Theirs:
                chosen = &segment.theirs;
                break;
            case ConflictRegionChoice::Custom:
                chosen = &resolution.customLines;
                break;
            case ConflictRegionChoice::Unresolved:
                break;
        }
        if (chosen != nullptr) {
            for (const std::string& line : *chosen) {
                text += QString::fromStdString(line);
            }
        } else {
            text += tr("Conflict %1 of %2 — not resolved yet.\n")
                        .arg(regionIndex + 1)
                        .arg(parsedMarkers_.regionCount);
        }
        if (regionRanges != nullptr) {
            regionRanges->emplace_back(rangeStart, text.size() - rangeStart);
        }
        ++regionIndex;
    }
    return text;
}

bool ConflictResolvePanel::allRegionsResolved() const {
    return std::all_of(
        regionResolutions_.begin(), regionResolutions_.end(), [](const ConflictRegionResolution& r) {
            return r.choice != ConflictRegionChoice::Unresolved;
        });
}

bool ConflictResolvePanel::canSave() const {
    if (!middleEditable_) {
        return false;
    }
    if (parsedMarkers_.regionCount == 0) {
        return true;
    }
    return allRegionsResolved();
}

void ConflictResolvePanel::refreshMiddleFromResolutions() {
    const bool resolved = allRegionsResolved();
    if (resolved) {
        regionTextRanges_.clear();
        const std::optional<std::string> assembled =
            ConflictMarkerParser::assemble(parsedMarkers_, regionResolutions_);
        middleEdit_->setPlainText(QString::fromStdString(*assembled));
    } else {
        regionTextRanges_.clear();
        middleEdit_->setPlainText(buildMiddlePreviewText(&regionTextRanges_));
    }
    // Stays read-only until every region is resolved -- otherwise the user
    // could type into the placeholder-filled preview, only to have the next
    // Take Left/Right click silently discard it via setPlainText above.
    middleEdit_->setReadOnly(!resolved);
    saveButton_->setEnabled(canSave());
    updateRegionStrip();
    highlightCurrentRegion();
}

void ConflictResolvePanel::resolveRegion(int index, ConflictRegionResolution resolution) {
    if (index < 0 || static_cast<std::size_t>(index) >= regionResolutions_.size()) {
        return;
    }
    regionResolutions_[static_cast<std::size_t>(index)] = std::move(resolution);

    // Look forward from just past `index` first, wrapping around to the
    // start -- but never back onto `index` itself -- so resolving region 2
    // out of {0: unresolved, 1: unresolved, 2: unresolved} lands on 0, not
    // back on 2, while working straight through in order still advances one
    // step at a time as the doc comment promises.
    const int count = static_cast<int>(regionResolutions_.size());
    bool jumped = false;
    for (int offset = 1; offset < count; ++offset) {
        const int candidate = (index + offset) % count;
        if (regionResolutions_[static_cast<std::size_t>(candidate)].choice ==
            ConflictRegionChoice::Unresolved) {
            currentRegionIndex_ = candidate;
            jumped = true;
            break;
        }
    }
    if (!jumped) {
        currentRegionIndex_ = std::min(index, count - 1);
    }
    refreshMiddleFromResolutions();
}

void ConflictResolvePanel::resolveAllRegions(ConflictRegionChoice choice) {
    for (ConflictRegionResolution& resolution : regionResolutions_) {
        resolution = ConflictRegionResolution{choice, {}};
    }
    refreshMiddleFromResolutions();
}

const ConflictSegment* ConflictResolvePanel::regionSegment(int regionIndex) const {
    if (regionIndex < 0) {
        return nullptr;
    }
    int seen = 0;
    for (const ConflictSegment& segment : parsedMarkers_.segments) {
        if (segment.kind != ConflictSegmentKind::Region) {
            continue;
        }
        if (seen == regionIndex) {
            return &segment;
        }
        ++seen;
    }
    return nullptr;
}

void ConflictResolvePanel::pickLinesForCurrentRegion() {
    const ConflictSegment* segment = regionSegment(currentRegionIndex_);
    if (segment == nullptr) {
        return;
    }
    // Reopening on a region already resolved as Custom should show what was
    // picked last time rather than forcing a re-pick from scratch.
    static const std::vector<std::string> kNoPreselection;
    const std::vector<std::string>* preselected = &kNoPreselection;
    const auto index = static_cast<std::size_t>(currentRegionIndex_);
    if (index < regionResolutions_.size() &&
        regionResolutions_[index].choice == ConflictRegionChoice::Custom) {
        preselected = &regionResolutions_[index].customLines;
    }
    ConflictLinePickDialog dialog(segment->ours, segment->theirs, *preselected, this);
    if (dialog.exec() != QDialog::Accepted) {
        return;
    }
    resolveRegion(currentRegionIndex_,
                   ConflictRegionResolution{ConflictRegionChoice::Custom, dialog.selectedLines()});
}

void ConflictResolvePanel::navigateRegion(int delta) {
    if (regionResolutions_.empty()) {
        return;
    }
    const int count = static_cast<int>(regionResolutions_.size());
    currentRegionIndex_ = std::clamp(currentRegionIndex_ + delta, 0, count - 1);
    updateRegionStrip();
    highlightCurrentRegion();
}

void ConflictResolvePanel::updateRegionStrip() {
    if (parsedMarkers_.regionCount == 0) {
        return;
    }
    const int count = static_cast<int>(regionResolutions_.size());
    regionPositionLabel_->setText(tr("Conflict %1/%2").arg(currentRegionIndex_ + 1).arg(count));
    regionPrevButton_->setEnabled(currentRegionIndex_ > 0);
    regionNextButton_->setEnabled(currentRegionIndex_ < count - 1);
}

void ConflictResolvePanel::highlightCurrentRegion() {
    if (static_cast<std::size_t>(currentRegionIndex_) >= regionTextRanges_.size()) {
        middleEdit_->setExtraSelections({});
        return;
    }
    const auto [start, length] = regionTextRanges_[static_cast<std::size_t>(currentRegionIndex_)];
    QTextCursor highlightCursor(middleEdit_->document());
    highlightCursor.setPosition(start);
    highlightCursor.setPosition(start + length, QTextCursor::KeepAnchor);

    QTextEdit::ExtraSelection selection;
    selection.cursor = highlightCursor;
    selection.format.setBackground(ThemeManager::color(Token::SurfaceSunken));
    middleEdit_->setExtraSelections({selection});

    // A collapsed cursor at the region's start, not `highlightCursor` itself
    // -- setTextCursor() with an active KeepAnchor range would make the
    // whole region the live selection, so the next keystroke replaces it.
    // The ExtraSelection above already paints the highlight; this only needs
    // to scroll the view there.
    QTextCursor scrollCursor(middleEdit_->document());
    scrollCursor.setPosition(start);
    middleEdit_->setTextCursor(scrollCursor);
    middleEdit_->ensureCursorVisible();
}

void ConflictResolvePanel::submitResolution(int choice) {
    if (choice == 0 || session_ == nullptr) {
        emit cancelled();
        return;
    }

    ResolveConflictRequest request;
    request.path = path_;
    request.oursBlobMissing = oursBlobMissing_;
    request.theirsBlobMissing = theirsBlobMissing_;
    switch (choice) {
        case 1:
            request.resolution = ConflictResolution::TakeOurs;
            break;
        case 2:
            request.resolution = ConflictResolution::TakeTheirs;
            break;
        default: {
            if (!canSave()) {
                return;
            }
            request.resolution = ConflictResolution::WriteResolved;
            // Once every region has a choice, the middle buffer holds the
            // assembled result (now editable for final touch-ups) rather
            // than the per-region preview -- see refreshMiddleFromResolutions
            // -- so re-running assemble() here would just reconstruct
            // whatever the user may have hand-edited on top of it. Read the
            // buffer either way; assemble() only ever fed it, never bypassed
            // it.
            QString edited = middleEdit_->toPlainText();
            if (middleContentHasCrlf_) {
                edited.replace(QStringLiteral("\n"), QStringLiteral("\r\n"));
            }
            request.resolvedContent = edited.toUtf8().toStdString();
            break;
        }
    }
    session_->resolveConflict(request);
    emit resolutionSubmitted();
}

}  // namespace gbm
