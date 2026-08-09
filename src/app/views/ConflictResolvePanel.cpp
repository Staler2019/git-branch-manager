#include "app/views/ConflictResolvePanel.h"

#include "app/bridge/RepositorySession.h"
#include "app/bridge/ThemeManager.h"
#include "app/theme/Tokens.h"
#include "app/views/ConflictTextEdit.h"
#include "core/git/WorkingCopyStatus.h"
#include "core/git/ops/ConflictOps.h"

#include <QCheckBox>
#include <QHBoxLayout>
#include <QKeySequence>
#include <QLabel>
#include <QMessageBox>
#include <QPlainTextEdit>
#include <QPushButton>
#include <QSettings>
#include <QShortcut>
#include <QSplitter>
#include <QStringList>
#include <QTextCursor>
#include <QTextEdit>
#include <QTimer>
#include <QVBoxLayout>

#include <algorithm>
#include <tuple>
#include <utility>

namespace gbm {

bool middleBufferHasUnsavedEdits(const QString& currentText, const QString& lastAssembledText,
                                  bool isReadOnly) {
    if (isReadOnly) {
        return false;
    }
    return currentText != lastAssembledText;
}

namespace {

// Untranslated technical tokens -- LF/CRLF/Mixed/UTF-16 LE/UTF-16 BE/
// Non-UTF-8/Binary read the same regardless of UI language, the same way
// this app never translates e.g. "M/M" conflict-kind shorthand. Empty
// return means "nothing worth badging" (Utf8/Utf8Bom, or LineEndingKind::
// None -- see ConflictTraitsSummary's own doc comment).
QString lineEndingBadgeToken(LineEndingKind kind) {
    switch (kind) {
        case LineEndingKind::Lf:
            return QStringLiteral("LF");
        case LineEndingKind::Crlf:
            return QStringLiteral("CRLF");
        case LineEndingKind::Mixed:
            return QStringLiteral("Mixed");
        case LineEndingKind::None:
            return QString();
    }
    return QString();
}

QString encodingBadgeToken(EncodingKind kind) {
    switch (kind) {
        case EncodingKind::Utf8:
        case EncodingKind::Utf8Bom:
            return QString();
        case EncodingKind::Utf16Le:
            return QStringLiteral("UTF-16 LE");
        case EncodingKind::Utf16Be:
            return QStringLiteral("UTF-16 BE");
        case EncodingKind::NonUtf8:
            return QStringLiteral("Non-UTF-8");
        case EncodingKind::Binary:
            return QStringLiteral("Binary");
    }
    return QString();
}

bool isEncodingUnsafeForLineOps(EncodingKind kind) {
    return kind == EncodingKind::NonUtf8 || kind == EncodingKind::Binary ||
           kind == EncodingKind::Utf16Le || kind == EncodingKind::Utf16Be;
}

// Appends `token` to `badge`, joined with ", " when `badge` already has
// content -- a side can carry both a line-ending token and an encoding
// token at once (e.g. CRLF *and* Non-UTF-8), and neither should clobber the
// other.
void appendBadgeToken(QString& badge, const QString& token) {
    if (token.isEmpty()) {
        return;
    }
    if (badge.isEmpty()) {
        badge = token;
    } else {
        badge += QStringLiteral(", ") + token;
    }
}

}  // namespace

ConflictTraitsSummary summarizeConflictSideTraits(const TextTraits& ours, const TextTraits& theirs) {
    ConflictTraitsSummary summary;

    // Diff-based: must_not_do explicitly forbids a badge/warning when the
    // two sides already agree, and LineEndingKind::None never disagrees
    // with anything (see the header's own comment).
    if (ours.lineEnding != LineEndingKind::None && theirs.lineEnding != LineEndingKind::None &&
        ours.lineEnding != theirs.lineEnding) {
        summary.lineEndingsDiffer = true;
        appendBadgeToken(summary.oursBadge, lineEndingBadgeToken(ours.lineEnding));
        appendBadgeToken(summary.theirsBadge, lineEndingBadgeToken(theirs.lineEnding));
    }

    // Absolute, not diff-based: each side's own encoding decides its own
    // badge and its own unsafe flag, regardless of the other side's.
    summary.oursLineOpsUnsafe = isEncodingUnsafeForLineOps(ours.encoding);
    summary.theirsLineOpsUnsafe = isEncodingUnsafeForLineOps(theirs.encoding);
    if (summary.oursLineOpsUnsafe) {
        appendBadgeToken(summary.oursBadge, encodingBadgeToken(ours.encoding));
    }
    if (summary.theirsLineOpsUnsafe) {
        appendBadgeToken(summary.theirsBadge, encodingBadgeToken(theirs.encoding));
    }

    return summary;
}

namespace {

// panesSplitter_ persistence, split by whether the ancestor column is
// currently shown: a size list saved with the ancestor hidden has its
// index-0 entry near zero, and applying that list once the ancestor is
// shown again would leave it collapsed-looking even though
// childrenCollapsible() is off. Two keys means a 3-column and a 4-column
// layout each remember their own widths instead of clobbering each other.
// Local to this file rather than shared with WorkingCopyView's own
// setupPersistentSplitter -- that one has a single, always-visible layout
// and no equivalent need for a variant key.
QString conflictPanesSettingsKey(bool ancestorVisible) {
    return QStringLiteral("window/splitters/conflictPanes%1").arg(ancestorVisible ? 4 : 3);
}

/// Restores sizes saved for the given ancestor-visibility variant, if any
/// were saved and the saved list's length still matches the splitter's
/// current pane count -- a length mismatch means stale or corrupt data, and
/// is silently ignored rather than partially applied.
void restoreConflictPanesSizes(QSplitter* splitter, bool ancestorVisible) {
    QSettings settings;
    const QVariant saved = settings.value(conflictPanesSettingsKey(ancestorVisible));
    if (!saved.isValid()) {
        return;
    }
    const QVariantList list = saved.toList();
    if (list.size() != splitter->count()) {
        return;
    }
    QList<int> sizes;
    sizes.reserve(list.size());
    for (const QVariant& value : list) {
        sizes.append(value.toInt());
    }
    QTimer::singleShot(0, splitter, [splitter, sizes] { splitter->setSizes(sizes); });
}

void saveConflictPanesSizes(QSplitter* splitter, bool ancestorVisible) {
    QSettings settings;
    QVariantList list;
    for (int size : splitter->sizes()) {
        list.append(size);
    }
    settings.setValue(conflictPanesSettingsKey(ancestorVisible), list);
}

// Pane order is fixed by makePane()'s call order in the constructor.
constexpr int kAncestorPaneIndex = 0;

/// Called right after the ancestor pane becomes visible when there is no
/// saved 4-column layout to restore yet (first time the toggle is ever
/// checked): Qt's own redistribution after showing a previously-hidden
/// splitter child tends to leave it far under its minimum width, so this
/// borrows the shortfall from whichever pane is currently widest instead of
/// leaving the ancestor column looking broken.
void borrowWidthForAncestorPane(QSplitter* splitter) {
    QList<int> sizes = splitter->sizes();
    if (sizes.size() != splitter->count() || sizes.isEmpty()) {
        return;
    }
    QWidget* ancestorPane = splitter->widget(kAncestorPaneIndex);
    const int minimumWidth = ancestorPane->minimumWidth();
    if (sizes[kAncestorPaneIndex] >= minimumWidth) {
        return;
    }
    int widestIndex = 0;
    for (int i = 1; i < sizes.size(); ++i) {
        if (sizes[i] > sizes[widestIndex]) {
            widestIndex = i;
        }
    }
    const int deficit = minimumWidth - sizes[kAncestorPaneIndex];
    if (widestIndex == kAncestorPaneIndex || sizes[widestIndex] - deficit < minimumWidth) {
        return;
    }
    sizes[kAncestorPaneIndex] = minimumWidth;
    sizes[widestIndex] -= deficit;
    splitter->setSizes(sizes);
}

}  // namespace

ConflictResolvePanel::ConflictResolvePanel(QWidget* parent) : QWidget(parent) {
    auto* layout = new QVBoxLayout(this);

    auto* headerRow = new QHBoxLayout();
    kindLabel_ = new QLabel(this);
    kindLabel_->setVisible(false);
    headerRow->addWidget(kindLabel_, 1);
    ancestorToggle_ = new QCheckBox(tr("Show common ancestor"), this);
    // Named so ConflictUiTest can drive it without depending on tr() text.
    ancestorToggle_->setObjectName(QStringLiteral("conflictAncestorToggle"));
    headerRow->addWidget(ancestorToggle_);
    layout->addLayout(headerRow);

    // Design A5's file-level warning banner -- reflects oursTraits_/
    // theirsTraits_ (blob-level, independent of region parsing), so it sits
    // above regionStrip_ rather than being gated by it; see
    // updateTraitsPresentation(). Starts hidden -- nothing has been loaded
    // yet, and summarizeConflictSideTraits() of two default TextTraits has
    // nothing to say (must_not_do: never show this when there's nothing to
    // disagree about).
    traitsWarningRow_ = new QWidget(this);
    traitsWarningRow_->setObjectName(QStringLiteral("conflictTraitsWarningRow"));
    auto* traitsWarningLayout = new QHBoxLayout(traitsWarningRow_);
    traitsWarningLayout->setContentsMargins(0, 0, 0, 0);
    traitsWarningLabel_ = new QLabel(traitsWarningRow_);
    traitsWarningLabel_->setWordWrap(true);
    traitsWarningLayout->addWidget(traitsWarningLabel_, 1);
    traitsWarningRow_->setVisible(false);
    layout->addWidget(traitsWarningRow_);

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
    // Design A3: per-region Take Left/Take Right are gone -- dragging a
    // region onto the middle pane (Commit 6) and the Left/Right keyboard
    // shortcuts wired below now cover that same action. regionResetButton_
    // is new: the direct-manipulation surface's one recovery path.
    regionResetButton_ = new QPushButton(tr("Reset"), regionStrip_);
    // Named so ConflictUiTest can find it without depending on tr() text,
    // matching ancestorToggle_/regionStrip_'s own objectName convention.
    regionResetButton_->setObjectName(QStringLiteral("conflictRegionResetButton"));
    regionTakeLeftAllButton_ = new QPushButton(tr("Take Left (All)"), regionStrip_);
    regionTakeRightAllButton_ = new QPushButton(tr("Take Right (All)"), regionStrip_);
    stripLayout->addWidget(regionPrevButton_);
    stripLayout->addWidget(regionPositionLabel_);
    stripLayout->addWidget(regionNextButton_);
    stripLayout->addWidget(regionResetButton_);
    stripLayout->addStretch(1);
    stripLayout->addWidget(regionTakeLeftAllButton_);
    stripLayout->addWidget(regionTakeRightAllButton_);
    regionStrip_->setVisible(false);
    layout->addWidget(regionStrip_);

    // Design A3's first-use hint -- mirrors MainWindow's perfHintRow_
    // dismissible-hint pattern (label + a small "✕" dismiss button, state
    // persisted so it doesn't come back once dismissed). Visibility is kept
    // in lockstep with regionStrip_'s via updateDirectManipulationHintVisibility(),
    // called everywhere regionStrip_->setVisible() is.
    directManipulationHintRow_ = new QWidget(this);
    directManipulationHintRow_->setObjectName(QStringLiteral("conflictDirectManipulationHint"));
    auto* hintLayout = new QHBoxLayout(directManipulationHintRow_);
    hintLayout->setContentsMargins(0, 0, 0, 0);
    directManipulationHintLabel_ = new QLabel(
        tr("Drag a highlighted region from the left or right pane into the middle to take it, "
           "or click individual lines to compose the result yourself."),
        directManipulationHintRow_);
    directManipulationHintLabel_->setWordWrap(true);
    hintLayout->addWidget(directManipulationHintLabel_, 1);
    directManipulationHintDismissButton_ =
        new QPushButton(QStringLiteral("✕"), directManipulationHintRow_);
    directManipulationHintDismissButton_->setObjectName(QStringLiteral("secondaryButton"));
    directManipulationHintDismissButton_->setAccessibleName(tr("Dismiss hint"));
    hintLayout->addWidget(directManipulationHintDismissButton_);
    directManipulationHintRow_->setVisible(false);
    layout->addWidget(directManipulationHintRow_);
    connect(directManipulationHintDismissButton_, &QPushButton::clicked, this, [this] {
        QSettings settings;
        settings.setValue(QStringLiteral("conflictResolve/hintDismissed"), true);
        updateDirectManipulationHintVisibility();
    });

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
        // Design A5's per-column badge lives beside the title rather than
        // below it, so the badges row doesn't add its own vertical strip --
        // hidden (empty text) until updateTraitsPresentation() has
        // something to say about this side.
        auto* titleRow = new QHBoxLayout();
        titleRow->addWidget(new QLabel(title, container), 1);
        auto* badge = new QLabel(container);
        badge->setVisible(false);
        titleRow->addWidget(badge);
        paneLayout->addLayout(titleRow);
        auto* edit = new ConflictTextEdit(container);
        edit->setReadOnly(true);
        // NoFocus by default: ancestor/ours/theirs never take keyboard input
        // (pure display + hover/drag surfaces -- see setSide() below) and
        // stay this way permanently. middleEdit_ is the one exception --
        // Design A3's Left/Right/Backspace shortcuts (see the
        // Qt::WidgetWithChildrenShortcut wiring further down) only reach
        // this panel while focus sits somewhere *without* its own opinion on
        // those keys; a focused QPlainTextEdit intercepts Left/Right/
        // Backspace as cursor navigation/deletion before the shortcut ever
        // gets a chance (confirmed empirically -- a focused QPlainTextEdit
        // swallows Left with zero shortcut fires, not merely "unlikely to
        // fire"). Clicking a region row to hover/drag/toggle-a-line would
        // otherwise silently hand keyboard focus to that pane and break the
        // keyboard path for the rest of the session. middleEdit_ regains
        // Qt::StrongFocus, and only then, at each point it actually becomes
        // the user's free-editing buffer -- see the setReadOnly(false)/
        // setReadOnly(!resolved) call sites below, each paired with the
        // matching setFocusPolicy() call.
        edit->setFocusPolicy(Qt::NoFocus);
        edit->setLineWrapMode(QPlainTextEdit::NoWrap);
        edit->setPlainText(tr("Loading…"));
        paneLayout->addWidget(edit, 1);
        const int index = panesSplitter_->count();
        panesSplitter_->addWidget(container);
        panesSplitter_->setStretchFactor(index, 1);
        return std::tuple{container, edit, badge};
    };
    std::tie(ancestorContainer_, ancestorEdit_, std::ignore) = makePane(tr("Common ancestor"));
    ancestorContainer_->setVisible(false);
    std::tie(std::ignore, oursEdit_, oursTraitBadge_) = makePane(tr("Current branch (mine)"));
    std::tie(std::ignore, middleEdit_, std::ignore) = makePane(tr("Resolved content (editable)"));
    std::tie(std::ignore, theirsEdit_, theirsTraitBadge_) = makePane(tr("Merged branch (theirs)"));
    // Named so ConflictUiTest can locate them without depending on tr() text
    // -- matching ancestorToggle_/regionResetButton_'s own convention.
    oursTraitBadge_->setObjectName(QStringLiteral("conflictOursTraitBadge"));
    theirsTraitBadge_->setObjectName(QStringLiteral("conflictTheirsTraitBadge"));
    // Design A1: ours/theirs are hover+drag sources, the middle (result)
    // pane is the only drop target -- see ConflictTextEdit::setSide(). The
    // ancestor pane is left at its default (no region spans are ever fed
    // into it, so hover/drag is a no-op there regardless).
    oursEdit_->setSide(ConflictSide::Ours);
    theirsEdit_->setSide(ConflictSide::Theirs);
    middleEdit_->setSide(ConflictSide::Result);
    connect(middleEdit_, &ConflictTextEdit::regionDropped, this, [this](int regionIndex, ConflictSide fromSide) {
        resolveRegion(regionIndex,
                       ConflictRegionResolution{fromSide == ConflictSide::Theirs
                                                     ? ConflictRegionChoice::Theirs
                                                     : ConflictRegionChoice::Ours,
                                                 {}});
    });
    // Design A2: click-to-toggle-line composition. Both panes share one
    // handler; which side clicked is baked into the connection itself
    // rather than inferred from the sender, since ConflictSide already
    // exists to say exactly that.
    connect(oursEdit_, &ConflictTextEdit::lineToggled, this,
            [this](int regionIndex, int lineOffset, Qt::KeyboardModifiers modifiers) {
                onRegionLineToggled(regionIndex, ConflictSide::Ours, lineOffset, modifiers);
            });
    connect(theirsEdit_, &ConflictTextEdit::lineToggled, this,
            [this](int regionIndex, int lineOffset, Qt::KeyboardModifiers modifiers) {
                onRegionLineToggled(regionIndex, ConflictSide::Theirs, lineOffset, modifiers);
            });
    // Equal default split -- overridden a moment later by
    // restoreConflictPanesSizes()'s deferred restore if sizes were saved
    // from a previous session.
    const int equalShare = qMax(panesSplitter_->width(), 800) / panesSplitter_->count();
    panesSplitter_->setSizes(
        QList<int>(panesSplitter_->count(), equalShare));
    layout->addWidget(panesSplitter_, 1);
    // isHidden() rather than isVisible(): the latter also reflects ancestor
    // visibility, and the panel itself isn't shown yet at construction time
    // -- every widget's isVisible() would read false regardless of what
    // ancestorContainer_'s own explicit state is. isHidden() only reports
    // whether setVisible(false) was called directly on this widget, which
    // is exactly what ancestorToggle_ controls.
    restoreConflictPanesSizes(panesSplitter_, !ancestorContainer_->isHidden());

    connect(panesSplitter_, &QSplitter::splitterMoved, panesSplitter_, [this] {
        saveConflictPanesSizes(panesSplitter_, !ancestorContainer_->isHidden());
    });

    connect(ancestorToggle_, &QCheckBox::toggled, this, [this](bool visible) {
        ancestorContainer_->setVisible(visible);
        // Deferred: QSplitter's redistribution after a child's visibility
        // changes isn't guaranteed to have happened yet on this same call
        // stack, and both the restore-vs-borrow decision and the save
        // immediately after need splitter->sizes() to already reflect the
        // new visibility.
        QTimer::singleShot(0, panesSplitter_, [this, visible] {
            if (visible) {
                QSettings settings;
                if (settings.contains(conflictPanesSettingsKey(true))) {
                    restoreConflictPanesSizes(panesSplitter_, true);
                } else {
                    borrowWidthForAncestorPane(panesSplitter_);
                }
            }
            saveConflictPanesSizes(panesSplitter_, visible);
        });
    });

    connect(regionPrevButton_, &QPushButton::clicked, this, [this] { navigateRegion(-1); });
    connect(regionNextButton_, &QPushButton::clicked, this, [this] { navigateRegion(1); });
    connect(regionResetButton_, &QPushButton::clicked, this,
            [this] { resetRegionToUnresolved(currentRegionIndex_); });
    connect(regionTakeLeftAllButton_, &QPushButton::clicked, this, [this] {
        resolveAllRegions(ConflictRegionChoice::Ours);
    });
    connect(regionTakeRightAllButton_, &QPushButton::clicked, this, [this] {
        resolveAllRegions(ConflictRegionChoice::Theirs);
    });

    // Design A3's keyboard equivalents -- must not be omitted (must_not_do:
    // "不可省 -- 純拖曳介面無法用鍵盤操作"): a pane's hover+drag surface has
    // no keyboard path of its own, so without these, resolving a conflict
    // would be entirely unusable without a mouse. Qt::WidgetWithChildrenShortcut
    // fires while focus is anywhere in this panel's subtree -- e.g. after
    // clicking Prev/Next or the panel itself -- without needing the panel to
    // hold focus directly.
    //
    // A focused QPlainTextEdit does *not* let this shortcut through --
    // Left/Right/Backspace are its own cursor-navigation/deletion keys, and
    // it claims the QEvent::ShortcutOverride before the shortcut ever gets a
    // chance (confirmed empirically: a focused QPlainTextEdit swallows Left
    // with zero shortcut activations, not merely "less likely to fire").
    // That would have made the keyboard path this comment insists on
    // literally unreachable the moment a user clicked into ancestor/ours/
    // theirs to hover, drag, or toggle a line (Design A1/A2) -- clicking
    // hands that pane keyboard focus by default and it never gives it back.
    // Fixed at the source instead of worked around here: ancestor/ours/
    // theirs are permanently Qt::NoFocus (see makePane() above -- they are
    // pure display/hover/drag surfaces, never a typing target), and
    // middleEdit_ only gains Qt::StrongFocus at the specific points it
    // becomes the actual free-editing buffer (see each setReadOnly() call
    // site's paired setFocusPolicy()). While middleEdit_ *is* that buffer,
    // Left/Right there reverting to plain cursor movement is the expected,
    // not swallowed, behavior -- it is genuinely a text box at that point.
    // Design A5: the keyboard equivalents resolve a region to one side's
    // whole content -- the exact same outcome a completed drag from that
    // side produces (resolveRegion() with a plain Ours/Theirs choice). A
    // drag from an encoding-unsafe side can never start in the first place
    // (see refreshSidePanes()'s empty-regionSpans gate), so leaving these
    // shortcuts unguarded would be a one-keystroke bypass of that same
    // restriction -- advisor caught this before it landed.
    auto* takeLeftShortcut = new QShortcut(QKeySequence(Qt::Key_Left), this);
    takeLeftShortcut->setContext(Qt::WidgetWithChildrenShortcut);
    connect(takeLeftShortcut, &QShortcut::activated, this, [this] {
        if (regionResolutions_.empty()) {
            return;
        }
        if (summarizeConflictSideTraits(oursTraits_, theirsTraits_).oursLineOpsUnsafe) {
            return;
        }
        resolveRegion(currentRegionIndex_, ConflictRegionResolution{ConflictRegionChoice::Ours, {}});
    });
    auto* takeRightShortcut = new QShortcut(QKeySequence(Qt::Key_Right), this);
    takeRightShortcut->setContext(Qt::WidgetWithChildrenShortcut);
    connect(takeRightShortcut, &QShortcut::activated, this, [this] {
        if (regionResolutions_.empty()) {
            return;
        }
        if (summarizeConflictSideTraits(oursTraits_, theirsTraits_).theirsLineOpsUnsafe) {
            return;
        }
        resolveRegion(currentRegionIndex_,
                       ConflictRegionResolution{ConflictRegionChoice::Theirs, {}});
    });
    auto* resetShortcut = new QShortcut(QKeySequence(Qt::Key_Backspace), this);
    resetShortcut->setContext(Qt::WidgetWithChildrenShortcut);
    connect(resetShortcut, &QShortcut::activated, this,
            [this] { resetRegionToUnresolved(currentRegionIndex_); });

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
    lastAssembledMiddleText_.clear();
    wholeFileBaselineText_.clear();
    submittedCurrentEntry_ = false;
    currentRegionIndex_ = 0;
    regionStrip_->setVisible(false);
    updateDirectManipulationHintVisibility();
    customOursLineSelected_.clear();
    customTheirsLineSelected_.clear();
    customLineSelectionSeeded_.clear();
    lastLineClickAnchor_.reset();
    ancestorBlobText_.clear();
    oursBlobText_.clear();
    theirsBlobText_.clear();
    oursEdit_->setRegionSpans({});
    theirsEdit_->setRegionSpans({});
    // Design A5: reset to "nothing to disagree about" -- the previous
    // file's traits reply must not leak into this one and leave a stale
    // badge/warning showing (or a side wrongly still disabled) before the
    // new reply arrives.
    oursTraits_ = TextTraits{};
    theirsTraits_ = TextTraits{};
    updateTraitsPresentation();

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
    // showEntry() runs again for every file in a batch on a reused panel
    // (see the connect()s just below) -- a previous file that finished
    // fully resolved would have left middleEdit_ at Qt::StrongFocus (see
    // the pairing at each setReadOnly() call site), so this reset must be
    // explicit rather than assumed from the constructor's one-time default.
    // clearFocus() alongside setFocusPolicy(): dropping a focused widget's
    // policy to NoFocus does *not* by itself take focus away from it
    // (confirmed empirically -- hasFocus() stays true) -- if the user was
    // mid-edit in file A's middleEdit_ when it finished and this fires for
    // file B, leaving focus behind here would silently reopen the exact
    // swallow bug the NoFocus fix exists to close, just via the reuse path
    // instead of the first-click path. clearFocus() is a harmless no-op
    // when nothing was focused.
    middleEdit_->setFocusPolicy(Qt::NoFocus);
    middleEdit_->clearFocus();
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
    // Design A5: a separate signal from conflictSidesReady (see
    // RepositorySession::conflictSideTraitsReady's own doc comment), but the
    // same request triggers both -- requestConflictSides() computes traits
    // on the undecoded bytes before the QString conversion that
    // conflictSidesReady's payload already went through, and emits both
    // signals from the same queued callback. No separate request call
    // needed here.
    connect(session_,
            &RepositorySession::conflictSideTraitsReady,
            this,
            &ConflictResolvePanel::onConflictSideTraitsReady,
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
    // Stored rather than written straight into the edits: this reply and
    // onWorkingTreeContentReady()'s are two independent RepositorySession
    // requests with no ordering guarantee, so the actual rendering decision
    // (parsedMarkers_-driven vs. this blob) happens in refreshSidePanes(),
    // called from both handlers' tails.
    ancestorBlobText_ = ancestor;
    oursBlobText_ = ours;
    theirsBlobText_ = theirs;
    refreshSidePanes();
}

void ConflictResolvePanel::onConflictSideTraitsReady(const QString& path,
                                                      const TextTraits& /*ancestor*/,
                                                      const TextTraits& ours,
                                                      const TextTraits& theirs) {
    if (path.toStdString() != path_) {
        return;
    }
    oursTraits_ = ours;
    theirsTraits_ = theirs;
    updateTraitsPresentation();
    // refreshSidePanes() reads the same summarizeConflictSideTraits() result
    // to decide whether to feed a pane its real region spans or an empty
    // list (see there) -- re-running it here keeps that decision in sync
    // with whichever of this reply and onConflictSidesReady()'s own arrives
    // second (no ordering guarantee between them; C9b's comment on
    // RepositorySession::requestConflictSides notwithstanding -- both
    // signals share one emission there, but this handler must still be
    // correct standing alone rather than relying on that implementation
    // detail).
    refreshSidePanes();
}

void ConflictResolvePanel::updateTraitsPresentation() {
    const ConflictTraitsSummary summary = summarizeConflictSideTraits(oursTraits_, theirsTraits_);
    oursTraitBadge_->setText(summary.oursBadge);
    oursTraitBadge_->setVisible(!summary.oursBadge.isEmpty());
    theirsTraitBadge_->setText(summary.theirsBadge);
    theirsTraitBadge_->setVisible(!summary.theirsBadge.isEmpty());

    QStringList warnings;
    if (summary.lineEndingsDiffer) {
        warnings << tr("Line endings differ between the two sides (%1 vs %2). Saving always "
                       "keeps the working tree's original line ending, regardless of which "
                       "side you take.")
                        .arg(lineEndingBadgeToken(oursTraits_.lineEnding),
                             lineEndingBadgeToken(theirsTraits_.lineEnding));
    }
    if (summary.oursLineOpsUnsafe || summary.theirsLineOpsUnsafe) {
        warnings << tr("One side is not valid UTF-8 -- dragging or clicking individual lines "
                       "from that column is disabled to avoid corrupting the result. Use Take "
                       "Left or Take Right for the whole file instead.");
    }
    traitsWarningLabel_->setText(warnings.join(QStringLiteral("\n")));
    traitsWarningRow_->setVisible(!warnings.isEmpty());
}

void ConflictResolvePanel::refreshSidePanes() {
    if (!ancestorBlobMissing_) {
        // The ancestor column has no per-side segment of its own to render
        // from (diff3's ||||||| base is only sometimes present -- see
        // ConflictSegment::hasBase) -- it stays a raw blob regardless of
        // parsedMarkers_.
        ancestorEdit_->setPlainText(ancestorBlobText_);
    }

    const bool renderFromRegions = parsedMarkers_.regionCount > 0;
    // Design A5: a side whose encoding isn't valid UTF-8 never gets region
    // spans, regardless of what buildSidePaneText() computed -- with no
    // spans, spanForBlock() always returns nullptr, so hover/drag/line-click
    // are all inert on that pane (see ConflictTextEdit::mouseMoveEvent/
    // mousePressEvent/mouseReleaseEvent, and
    // emptyRegionSpansLeaveHoverInertEvenOverWhatWouldBeARegionRow() in
    // ConflictUiTest.cpp, which pins that this actually holds). This is the
    // same mechanism a regionless file already uses ({} in the `else`
    // branches below) -- Design A5 just adds a second reason to reach it.
    const ConflictTraitsSummary traits = summarizeConflictSideTraits(oursTraits_, theirsTraits_);

    if (!oursBlobMissing_) {
        if (renderFromRegions) {
            const SidePaneRender render = buildSidePaneText(parsedMarkers_, ConflictSide::Ours);
            oursEdit_->setPlainText(render.text);
            // setRegionSpans() after setPlainText(): its block numbers must
            // refer to the document that was just set, not whatever the
            // pane showed before.
            oursEdit_->setRegionSpans(traits.oursLineOpsUnsafe ? std::vector<RegionRowSpan>{}
                                                                : render.spans);
        } else {
            oursEdit_->setPlainText(oursBlobText_);
            oursEdit_->setRegionSpans({});
        }
    }

    if (!theirsBlobMissing_) {
        if (renderFromRegions) {
            const SidePaneRender render = buildSidePaneText(parsedMarkers_, ConflictSide::Theirs);
            theirsEdit_->setPlainText(render.text);
            theirsEdit_->setRegionSpans(traits.theirsLineOpsUnsafe ? std::vector<RegionRowSpan>{}
                                                                    : render.spans);
        } else {
            theirsEdit_->setPlainText(theirsBlobText_);
            theirsEdit_->setRegionSpans({});
        }
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
        // clearFocus() alongside setFocusPolicy() -- see showEntry()'s
        // matching comment on why NoFocus alone does not take focus away
        // from a widget that already has it.
        middleEdit_->setFocusPolicy(Qt::NoFocus);
        middleEdit_->clearFocus();
        middleEdit_->setPlainText(
            tr("(binary or non-UTF-8 content — use Take Left or Take Right)"));
        parsedMarkers_ = ParsedConflictFile{};
        regionResolutions_.clear();
        customOursLineSelected_.clear();
        customTheirsLineSelected_.clear();
        customLineSelectionSeeded_.clear();
        regionStrip_->setVisible(false);
        updateDirectManipulationHintVisibility();
        refreshSidePanes();
        return;
    }

    middleContentHasCrlf_ = content.contains(QStringLiteral("\r\n"));
    parsedMarkers_ = ConflictMarkerParser{}.parse(content.toStdString());
    regionResolutions_.assign(parsedMarkers_.regionCount, ConflictRegionResolution{});
    // Index-aligned with regionResolutions_ -- see
    // ensureCustomLineSelectionSeeded()/resetCustomLineSelection().
    customOursLineSelected_.assign(parsedMarkers_.regionCount, {});
    customTheirsLineSelected_.assign(parsedMarkers_.regionCount, {});
    customLineSelectionSeeded_.assign(parsedMarkers_.regionCount, false);
    lastLineClickAnchor_.reset();
    currentRegionIndex_ = 0;
    middleEdit_->setReadOnly(false);
    // Mirrors setReadOnly(false) above -- overridden a moment later by
    // refreshMiddleFromResolutions()'s own pairing when regionCount > 0 (see
    // there), but this is the one that sticks for the regionCount == 0 path
    // just below, where the raw content is immediately the free-editing
    // buffer with no per-region resolution step at all.
    middleEdit_->setFocusPolicy(Qt::StrongFocus);
    regionStrip_->setVisible(parsedMarkers_.regionCount > 0);
    updateDirectManipulationHintVisibility();
    // regionCount == 0 covers both "no markers at all" and "the parser gave
    // up on a malformed file" (parsedMarkers_.wellFormed == false) -- either
    // way there is nothing to render per-region, so the raw on-disk content
    // is shown exactly as before per-region resolution existed.
    if (parsedMarkers_.regionCount == 0) {
        middleEdit_->setPlainText(content);
        // hasUnsavedProgress()'s baseline for this path -- see its own
        // comment on why this can't reuse lastAssembledMiddleText_.
        wholeFileBaselineText_ = middleEdit_->toPlainText();
    } else {
        refreshMiddleFromResolutions();
    }
    refreshSidePanes();
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
        // Read back from the widget rather than reusing *assembled directly:
        // on a CRLF file *assembled still has \r\n (see middleContentHasCrlf_),
        // but QPlainTextEdit normalises everything it displays to bare \n --
        // comparing the two later in middleBufferHasUnsavedEdits() would
        // then read as "edited" on every CRLF file even with zero actual
        // user edits.
        lastAssembledMiddleText_ = middleEdit_->toPlainText();
    } else {
        regionTextRanges_.clear();
        // Not the buffer middleBufferHasUnsavedEdits() should ever compare
        // against -- cleared so a later reset (while still not fully
        // resolved) can't mistake a stale value from a previous
        // fully-resolved state for "what the user is looking at now".
        lastAssembledMiddleText_.clear();
        middleEdit_->setPlainText(buildMiddlePreviewText(&regionTextRanges_));
    }
    // Stays read-only until every region is resolved -- otherwise the user
    // could type into the placeholder-filled preview, only to have the next
    // Take Left/Right click silently discard it via setPlainText above.
    middleEdit_->setReadOnly(!resolved);
    // Paired with setReadOnly() above: middleEdit_ only takes keyboard focus
    // once it is genuinely the user's free-editing buffer. Kept off the rest
    // of the time so Design A3's Left/Right/Backspace shortcuts (see the
    // Qt::WidgetWithChildrenShortcut wiring in the constructor) keep
    // reaching this panel instead of being swallowed as this pane's own
    // cursor-navigation/deletion keys while it's still just a per-region
    // preview nobody is meant to type into yet.
    middleEdit_->setFocusPolicy(resolved ? Qt::StrongFocus : Qt::NoFocus);
    if (!resolved) {
        // clearFocus() alongside the drop to NoFocus: this branch runs from
        // resetRegionToUnresolved(), reachable while the user was mid-edit
        // in the just-finished result -- setFocusPolicy(NoFocus) alone
        // leaves a widget that already had focus still reporting
        // hasFocus() == true (see showEntry()'s matching comment), which
        // would reopen the Left/Right/Backspace swallow this whole fix
        // exists to close. Not needed in the `resolved` branch above --
        // focus is being granted there, not taken away.
        middleEdit_->clearFocus();
    }
    // middleEdit_ was never fed a span map before this commit (see
    // buildMiddleRegionSpans()'s doc comment) -- Commit 6's drop-target
    // highlight (dragMoveEvent()'s updateDropTargetPresentation() call) was
    // silently inert as a result, since spanForRegionIndex() always came back
    // empty. Middle-pane hover itself is still a no-op regardless (see
    // ConflictTextEdit::mouseMoveEvent()'s early return for
    // ConflictSide::Result) -- not needed now that reset is a strip button,
    // not a hover affordance on this pane.
    middleEdit_->setRegionSpans(buildMiddleRegionSpans(parsedMarkers_, regionResolutions_));
    saveButton_->setEnabled(canSave());
    updateRegionStrip();
    highlightCurrentRegion();
}

void ConflictResolvePanel::resolveRegion(int index, ConflictRegionResolution resolution) {
    if (index < 0 || static_cast<std::size_t>(index) >= regionResolutions_.size()) {
        return;
    }
    submittedCurrentEntry_ = false;
    regionResolutions_[static_cast<std::size_t>(index)] = std::move(resolution);
    resetCustomLineSelection(index);

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
    showWholeSideLineSelection(index, regionResolutions_[static_cast<std::size_t>(index)].choice);
}

void ConflictResolvePanel::resolveAllRegions(ConflictRegionChoice choice) {
    submittedCurrentEntry_ = false;
    for (std::size_t index = 0; index < regionResolutions_.size(); ++index) {
        regionResolutions_[index] = ConflictRegionResolution{choice, {}};
        resetCustomLineSelection(static_cast<int>(index));
    }
    refreshMiddleFromResolutions();
    for (std::size_t index = 0; index < regionResolutions_.size(); ++index) {
        showWholeSideLineSelection(static_cast<int>(index), choice);
    }
}

void ConflictResolvePanel::resetRegionToUnresolved(int index) {
    if (index < 0 || static_cast<std::size_t>(index) >= regionResolutions_.size()) {
        return;
    }
    if (regionResolutions_[static_cast<std::size_t>(index)].choice == ConflictRegionChoice::Unresolved) {
        return;  // Nothing to reset.
    }
    // Once every region is resolved, middleEdit_ becomes the user's freely
    // editable buffer (see refreshMiddleFromResolutions()) -- resetting one
    // region re-renders that buffer from the per-region preview, discarding
    // anything typed into it since. Unlike the drop/Take Left/Right hazard
    // this same buffer already guards against, reset must still be able to
    // go through -- "undo my last choice" is the whole point of the
    // affordance -- so this asks for confirmation instead of refusing
    // outright.
    if (middleBufferHasUnsavedEdits(middleEdit_->toPlainText(), lastAssembledMiddleText_,
                                     middleEdit_->isReadOnly())) {
        const auto answer = QMessageBox::question(
            this,
            tr("Discard edited result?"),
            tr("You've edited the resolved result since finishing this file. Resetting this "
               "conflict will discard those edits. Continue?"),
            QMessageBox::Yes | QMessageBox::Cancel,
            QMessageBox::Cancel);
        if (answer != QMessageBox::Yes) {
            return;
        }
    }
    submittedCurrentEntry_ = false;
    regionResolutions_[static_cast<std::size_t>(index)] = ConflictRegionResolution{};
    resetCustomLineSelection(index);
    currentRegionIndex_ = index;
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

void ConflictResolvePanel::ensureCustomLineSelectionSeeded(int regionIndex,
                                                            const ConflictSegment& segment) {
    const auto index = static_cast<std::size_t>(regionIndex);
    if (customLineSelectionSeeded_[index]) {
        return;
    }
    customLineSelectionSeeded_[index] = true;
    const ConflictRegionChoice choice = regionResolutions_[index].choice;
    customOursLineSelected_[index].assign(segment.ours.size(), choice == ConflictRegionChoice::Ours);
    customTheirsLineSelected_[index].assign(segment.theirs.size(),
                                             choice == ConflictRegionChoice::Theirs);
}

void ConflictResolvePanel::resetCustomLineSelection(int regionIndex) {
    if (regionIndex < 0 || static_cast<std::size_t>(regionIndex) >= customLineSelectionSeeded_.size()) {
        return;
    }
    const auto index = static_cast<std::size_t>(regionIndex);
    customLineSelectionSeeded_[index] = false;
    customOursLineSelected_[index].clear();
    customTheirsLineSelected_[index].clear();
    oursEdit_->setRegionLineSelection(regionIndex, {});
    theirsEdit_->setRegionLineSelection(regionIndex, {});
    if (lastLineClickAnchor_.has_value() && lastLineClickAnchor_->regionIndex == regionIndex) {
        lastLineClickAnchor_.reset();
    }
}

void ConflictResolvePanel::showWholeSideLineSelection(int regionIndex, ConflictRegionChoice choice) {
    const ConflictSegment* segment = regionSegment(regionIndex);
    if (segment == nullptr) {
        return;
    }
    oursEdit_->setRegionLineSelection(
        regionIndex, std::vector<bool>(segment->ours.size(), choice == ConflictRegionChoice::Ours));
    theirsEdit_->setRegionLineSelection(
        regionIndex, std::vector<bool>(segment->theirs.size(), choice == ConflictRegionChoice::Theirs));
}

void ConflictResolvePanel::onRegionLineToggled(int regionIndex, ConflictSide side, int lineOffset,
                                                Qt::KeyboardModifiers modifiers) {
    if (regionIndex < 0 || static_cast<std::size_t>(regionIndex) >= regionResolutions_.size()) {
        return;
    }
    const ConflictSegment* segment = regionSegment(regionIndex);
    if (segment == nullptr) {
        return;
    }
    ensureCustomLineSelectionSeeded(regionIndex, *segment);

    const auto index = static_cast<std::size_t>(regionIndex);
    std::vector<bool>& selected =
        (side == ConflictSide::Theirs) ? customTheirsLineSelected_[index] : customOursLineSelected_[index];
    if (lineOffset < 0 || static_cast<std::size_t>(lineOffset) >= selected.size()) {
        return;
    }

    // Shift+click extends a range from the last plain click in this same
    // region+side; anywhere else it falls back to a plain toggle rather
    // than guessing at a cross-side/region "range".
    if ((modifiers & Qt::ShiftModifier) && lastLineClickAnchor_.has_value() &&
        lastLineClickAnchor_->regionIndex == regionIndex && lastLineClickAnchor_->side == side) {
        const int lo = std::min(lastLineClickAnchor_->lineOffset, lineOffset);
        const int hi = std::max(lastLineClickAnchor_->lineOffset, lineOffset);
        for (int i = lo; i <= hi; ++i) {
            selected[static_cast<std::size_t>(i)] = true;
        }
    } else {
        selected[static_cast<std::size_t>(lineOffset)] = !selected[static_cast<std::size_t>(lineOffset)];
    }
    lastLineClickAnchor_ = LineClickAnchor{regionIndex, side, lineOffset};

    // Deliberately not resolveRegion(): that also jumps currentRegionIndex_
    // to the next unresolved region, which is right for a one-shot Take
    // Left/Right/drag but wrong here -- the user is still composing this
    // region line by line and jumping away mid-click would be jarring.
    regionResolutions_[index] = ConflictRegionResolution{
        ConflictRegionChoice::Custom,
        composeCustomRegionLines(*segment, customOursLineSelected_[index], customTheirsLineSelected_[index])};
    refreshMiddleFromResolutions();
    oursEdit_->setRegionLineSelection(regionIndex, customOursLineSelected_[index]);
    theirsEdit_->setRegionLineSelection(regionIndex, customTheirsLineSelected_[index]);
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
    regionResetButton_->setEnabled(
        regionResolutions_[static_cast<std::size_t>(currentRegionIndex_)].choice !=
        ConflictRegionChoice::Unresolved);
}

void ConflictResolvePanel::updateDirectManipulationHintVisibility() {
    // Deliberately parsedMarkers_.regionCount > 0, not
    // regionStrip_->isVisible(): the latter also reflects every ancestor's
    // visibility (see the constructor's own comment on isHidden() vs.
    // isVisible() for panesSplitter_'s persistence), and this panel is
    // typically shown as `new ConflictResolvePanel; ...; panel->show()` (or,
    // once C13 lands, inside a not-yet-exec()'d QDialog) -- isVisible()
    // would read false at every one of this function's call sites
    // regardless of regionStrip_'s own state, making the hint permanently
    // inert.
    if (parsedMarkers_.regionCount == 0) {
        directManipulationHintRow_->setVisible(false);
        return;
    }
    QSettings settings;
    const bool dismissed =
        settings.value(QStringLiteral("conflictResolve/hintDismissed"), false).toBool();
    directManipulationHintRow_->setVisible(!dismissed);
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
    // Design B1 (C13): from this point on hasUnsavedProgress() reports false
    // for this file until something changes it again -- the request above
    // already carries whatever regionResolutions_/middleEdit_ held, so there
    // is nothing left unsaved to warn about.
    submittedCurrentEntry_ = true;
    emit resolutionSubmitted();
}

bool ConflictResolvePanel::hasUnsavedProgress() const {
    if (session_ == nullptr || submittedCurrentEntry_ || !middleEditable_) {
        return false;
    }
    if (parsedMarkers_.regionCount == 0) {
        // The whole-file-edit path never goes through
        // refreshMiddleFromResolutions(), so lastAssembledMiddleText_ means
        // nothing here -- compare against the as-loaded baseline instead.
        return middleEdit_->toPlainText() != wholeFileBaselineText_;
    }
    for (const auto& resolution : regionResolutions_) {
        if (resolution.choice != ConflictRegionChoice::Unresolved) {
            return true;
        }
    }
    return middleBufferHasUnsavedEdits(middleEdit_->toPlainText(), lastAssembledMiddleText_,
                                        middleEdit_->isReadOnly());
}

}  // namespace gbm
