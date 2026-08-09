// Regression tests for ConflictResolvePanel's pane splitter. panesSplitter_
// was, until this fix, the only QSplitter in the app with none of the house
// configuration every other splitter has (see WorkingCopyView.cpp,
// SidebarPanel.cpp): no setHandleWidth, no setChildrenCollapsible(false), no
// stretch factors, no initial setSizes. The prime suspect for the reported
// "dragging feels wired wrong" behaviour is regionStrip_'s eight buttons
// being inserted directly into the middle pane's layout (see
// ConflictResolvePanel.cpp), which inflates that pane's minimumSizeHint far
// beyond its siblings' and makes the splitter refuse to let it shrink.
//
// These assertions are written to survive the fix landing in stages: the
// first commit here is expected to fail (RED) against the pre-fix source,
// proving the diagnosis with a real measurement rather than static reading.
//
// regionStripLivesOutsideAnyPane() deliberately checks ancestry rather than
// comparing minimumSizeHint() widths: regionStrip_ starts hidden
// (setVisible(false) in the constructor, only shown once a conflicted file
// with regions is loaded) and QBoxLayout excludes hidden items from a
// layout's minimum size computation, so a still-hidden strip would make a
// size-hint comparison pass for the wrong reason without a live
// RepositorySession feeding real conflict content. Ancestry survives that --
// setVisible(false) does not remove the widget from its parent's layout.
#include "app/views/ConflictResolvePanel.h"
#include "app/views/ConflictTextEdit.h"
#include "core/git/ConflictMarkerParser.h"

#include <QApplication>
#include <QCheckBox>
#include <QDropEvent>
#include <QKeySequence>
#include <QMimeData>
#include <QMouseEvent>
#include <QPushButton>
#include <QSettings>
#include <QShortcut>
#include <QSplitter>
#include <QTemporaryDir>
#include <QTextBlock>
#include <QTextEdit>
#include <QtTest>

#include <memory>

using namespace gbm;

namespace {

// Pane order is fixed regardless of the ancestor toggle's visibility: a
// hidden widget still occupies its splitter index (see
// ConflictResolvePanel.cpp's makePane() call order).
constexpr int kAncestorPaneIndex = 0;
constexpr int kOursPaneIndex = 1;
constexpr int kMiddlePaneIndex = 2;
constexpr int kTheirsPaneIndex = 3;

// A small parsed file with two regions, built by hand rather than run
// through ConflictMarkerParser::parse() -- buildSidePaneText() only cares
// about the already-split segments, so the test can pin the exact block
// (line) numbers it expects without also depending on marker-line parsing.
ParsedConflictFile makeTwoRegionParsedFile() {
    ConflictSegment leadingText;
    leadingText.kind = ConflictSegmentKind::Text;
    leadingText.lines = {"line1\n", "line2\n"};

    ConflictSegment regionZero;
    regionZero.kind = ConflictSegmentKind::Region;
    regionZero.ours = {"oursA\n"};
    regionZero.theirs = {"theirsA\n", "theirsA2\n"};

    ConflictSegment middleText;
    middleText.kind = ConflictSegmentKind::Text;
    middleText.lines = {"line3\n"};

    ConflictSegment regionOne;
    regionOne.kind = ConflictSegmentKind::Region;
    regionOne.ours = {"oursB\n", "oursB2\n"};
    regionOne.theirs = {"theirsB\n"};

    ConflictSegment trailingText;
    trailingText.kind = ConflictSegmentKind::Text;
    trailingText.lines = {"line4\n"};

    ParsedConflictFile parsed;
    parsed.segments = {leadingText, regionZero, middleText, regionOne, trailingText};
    parsed.regionCount = 2;
    return parsed;
}

// dragEnterEvent()/dropEvent() are protected overrides -- Qt's own
// Drag/Drop delivery is a separate subsystem from ordinary event()/notify()
// dispatch (unlike mouse events) and QCoreApplication::sendEvent() with a
// directly constructed QDropEvent does not reach them outside a live
// platform drag session (confirmed with a standalone plain-QWidget spike,
// so it isn't a ConflictTextEdit-specific quirk). A protected-handler-
// calling subclass is the seam this test suite actually has for exercising
// that logic -- see the plan's own note that a real QDrag::exec() drag loop
// is untestable under offscreen QPA regardless.
class DropTestableConflictTextEdit : public ConflictTextEdit {
public:
    using ConflictTextEdit::ConflictTextEdit;
    void triggerDrop(QDropEvent* event) { dropEvent(event); }
};

}  // namespace

class ConflictUiTest : public QObject {
    Q_OBJECT

private slots:
    // QSettings is redirected to a throwaway directory for the whole run --
    // conflictPanes3/conflictPanes4 must not read or write the developer's
    // real settings file. Mirrors ThemeTest.cpp's own isolation.
    void initTestCase() {
        tempDir_ = std::make_unique<QTemporaryDir>();
        QVERIFY(tempDir_->isValid());
        QSettings::setDefaultFormat(QSettings::IniFormat);
        QSettings::setPath(QSettings::IniFormat, QSettings::UserScope, tempDir_->path());
    }

    // minimumSizeHint() on a never-shown widget is unreliable -- the layout
    // has not been activated yet -- so every test here shows the panel and
    // waits for exposure before measuring.
    void init() {
        QSettings settings;
        settings.clear();
        panel_ = std::make_unique<ConflictResolvePanel>();
        panel_->show();
        QVERIFY(QTest::qWaitForWindowExposed(panel_.get()));
        splitter_ = panel_->findChild<QSplitter*>();
        QVERIFY(splitter_ != nullptr);
    }

    void cleanup() { panel_.reset(); }

    // The core regression: regionStrip_ must not live inside any pane
    // container's layout -- that's what let its eight buttons inflate the
    // middle pane's minimumSizeHint far past its siblings' and made the
    // splitter refuse to shrink it. See the file header for why this is an
    // ancestry check rather than a size-hint comparison.
    void regionStripLivesOutsideAnyPane() {
        QWidget* strip = panel_->findChild<QWidget*>(QStringLiteral("conflictRegionStrip"));
        QVERIFY2(strip != nullptr,
                 "conflictRegionStrip not found -- expected regionStrip_ to carry that objectName");

        for (int i = 0; i < splitter_->count(); ++i) {
            QWidget* pane = splitter_->widget(i);
            QVERIFY2(!pane->isAncestorOf(strip),
                     qPrintable(QStringLiteral("regionStrip_ is still hosted inside pane %1's "
                                               "layout -- it must sit in a full-width row above "
                                               "panesSplitter_ instead")
                                    .arg(i)));
        }
    }

    void splitterHasHouseConfiguration() {
        QVERIFY2(!splitter_->childrenCollapsible(),
                 "panesSplitter_ must not allow panes to collapse to zero width");
        QCOMPARE(splitter_->handleWidth(), 6);
    }

    void everyPaneHasAPositiveMinimumWidth() {
        for (int index : {kAncestorPaneIndex, kOursPaneIndex, kMiddlePaneIndex, kTheirsPaneIndex}) {
            QWidget* pane = splitter_->widget(index);
            QVERIFY(pane != nullptr);
            QVERIFY2(pane->minimumWidth() > 0,
                     qPrintable(QStringLiteral("pane %1 has no explicit minimum width").arg(index)));
        }
    }

    // The ancestor column starts hidden, so its saved width (if any) came
    // from a 3-column layout and is meaningless once it's shown -- checking
    // it there first exercised the childrenCollapsible(false)/minimumWidth
    // fix; this exercises the companion fix, that showing it for the first
    // time actually lands it at a usable width instead of near zero.
    void ancestorPaneGetsAUsableWidthOnceShown() {
        auto* toggle = panel_->findChild<QCheckBox*>(QStringLiteral("conflictAncestorToggle"));
        QVERIFY(toggle != nullptr);
        QVERIFY(!toggle->isChecked());

        toggle->setChecked(true);
        // The borrow-width fallback (and the save that follows it) is
        // deferred via QTimer::singleShot(0, ...) so QSplitter's own
        // redistribution after the visibility change has already happened.
        QTest::qWait(50);

        QWidget* ancestorPane = splitter_->widget(kAncestorPaneIndex);
        QVERIFY(ancestorPane->isVisible());
        QVERIFY2(splitter_->sizes()[kAncestorPaneIndex] >= ancestorPane->minimumWidth(),
                 qPrintable(QStringLiteral("ancestor pane width %1 is under its own minimum %2 "
                                           "after being shown")
                                .arg(splitter_->sizes()[kAncestorPaneIndex])
                                .arg(ancestorPane->minimumWidth())));
    }

    // Design A0: the left/right panes render from parsedMarkers_'s segments
    // rather than the raw ours/theirs blobs, so a region on either side maps
    // to a known [firstBlock, blockCount) range -- needed by hover/drag (a
    // later commit) to know which rows belong to which region. Ours and
    // theirs diverge in line count here (1 line vs 2 for region 0, 2 vs 1 for
    // region 1) specifically so a bug that mixed up the two sides' line
    // counts would fail this rather than accidentally cancel out.
    void buildSidePaneTextMapsRegionsToBlockRanges() {
        const ParsedConflictFile parsed = makeTwoRegionParsedFile();

        const SidePaneRender oursRender = buildSidePaneText(parsed, ConflictSide::Ours);
        QCOMPARE(oursRender.text,
                 QStringLiteral("line1\nline2\noursA\nline3\noursB\noursB2\nline4\n"));
        QCOMPARE(oursRender.spans.size(), static_cast<std::size_t>(2));
        QCOMPARE(oursRender.spans[0].regionIndex, 0);
        QCOMPARE(oursRender.spans[0].firstBlock, 2);
        QCOMPARE(oursRender.spans[0].blockCount, 1);
        QCOMPARE(oursRender.spans[1].regionIndex, 1);
        QCOMPARE(oursRender.spans[1].firstBlock, 4);
        QCOMPARE(oursRender.spans[1].blockCount, 2);

        const SidePaneRender theirsRender = buildSidePaneText(parsed, ConflictSide::Theirs);
        QCOMPARE(theirsRender.text,
                 QStringLiteral("line1\nline2\ntheirsA\ntheirsA2\nline3\ntheirsB\nline4\n"));
        QCOMPARE(theirsRender.spans.size(), static_cast<std::size_t>(2));
        QCOMPARE(theirsRender.spans[0].regionIndex, 0);
        QCOMPARE(theirsRender.spans[0].firstBlock, 2);
        QCOMPARE(theirsRender.spans[0].blockCount, 2);
        QCOMPARE(theirsRender.spans[1].regionIndex, 1);
        QCOMPARE(theirsRender.spans[1].firstBlock, 5);
        QCOMPARE(theirsRender.spans[1].blockCount, 1);
    }

    // A file with no regions at all (regionCount == 0) is exactly the shape
    // ConflictMarkerParser produces for a malformed file too -- see
    // ConflictMarkerParserTest.cpp's wellFormed == false case, which already
    // pins regionCount == 0 for that case. buildSidePaneText() itself is only
    // ever invoked by ConflictResolvePanel when regionCount > 0 (see
    // refreshSidePanes()); called directly on a regionless file it must
    // degrade to "the text, no spans" rather than assert or misbehave.
    void buildSidePaneTextHandlesNoRegions() {
        ConflictSegment onlyText;
        onlyText.kind = ConflictSegmentKind::Text;
        onlyText.lines = {"unchanged1\n", "unchanged2\n"};
        ParsedConflictFile parsed;
        parsed.segments = {onlyText};
        parsed.regionCount = 0;

        const SidePaneRender oursRender = buildSidePaneText(parsed, ConflictSide::Ours);
        QCOMPARE(oursRender.text, QStringLiteral("unchanged1\nunchanged2\n"));
        QVERIFY(oursRender.spans.empty());
    }

    // Design A1's drag payload is just 2 packed ints -- round-tripping it
    // doesn't need a widget at all.
    void conflictRegionMimeDataRoundTrips() {
        QMimeData* mime =
            encodeConflictRegionMimeData(3, ConflictSide::Theirs, QStringLiteral("hello\n"));
        const auto decoded = decodeConflictRegionMimeData(mime);
        QVERIFY(decoded.has_value());
        QCOMPARE(decoded->regionIndex, 3);
        QCOMPARE(static_cast<int>(decoded->fromSide), static_cast<int>(ConflictSide::Theirs));
        QCOMPARE(mime->text(), QStringLiteral("hello\n"));
        delete mime;
    }

    void conflictRegionMimeDataRejectsUnrelatedMime() {
        QMimeData plainMime;
        plainMime.setText(QStringLiteral("just text, not a conflict-region drag"));
        QVERIFY(!decodeConflictRegionMimeData(&plainMime).has_value());
        QVERIFY(!decodeConflictRegionMimeData(nullptr).has_value());
    }

    // Design A1's core hazard-avoidance rule: the result pane only accepts
    // a drop while it is still read-only (some region unresolved). Once
    // every region is resolved it becomes the user's freely-editable
    // buffer, and ConflictResolvePanel::refreshMiddleFromResolutions()
    // would otherwise silently discard whatever they just typed the next
    // time a region gets (re-)resolved -- the same hazard already documented
    // for the Take Left/Right buttons.
    //
    // Delivered via DropTestableConflictTextEdit's direct call into
    // dropEvent()/dragEnterEvent() rather than QCoreApplication::sendEvent()
    // with a hand-built QDropEvent: a spike proved sendEvent() never
    // actually reaches QWidget::dropEvent() for a directly constructed
    // event outside a live platform drag session (true even for a plain
    // QWidget, not a ConflictTextEdit quirk) -- Drag/Drop delivery is a
    // separate subsystem from ordinary event()/notify() dispatch, unlike
    // mouse events. A protected-handler-calling subclass is the seam that's
    // actually left to test with; see the plan's own note that a live
    // QDrag::exec() drag loop is untestable under offscreen QPA regardless.
    void middleEditAcceptsDropWhileReadOnly() {
        DropTestableConflictTextEdit edit;
        edit.setSide(ConflictSide::Result);
        edit.setReadOnly(true);

        int droppedRegionIndex = -1;
        ConflictSide droppedSide = ConflictSide::Ours;
        int dropCount = 0;
        connect(&edit, &ConflictTextEdit::regionDropped, [&](int regionIndex, ConflictSide side) {
            droppedRegionIndex = regionIndex;
            droppedSide = side;
            ++dropCount;
        });

        QMimeData* mime =
            encodeConflictRegionMimeData(1, ConflictSide::Theirs, QStringLiteral("theirsB\n"));
        QDropEvent dropEvent(
            QPointF(5, 5), Qt::CopyAction, mime, Qt::LeftButton, Qt::NoModifier);
        edit.triggerDrop(&dropEvent);
        delete mime;

        QCOMPARE(dropCount, 1);
        QCOMPARE(droppedRegionIndex, 1);
        QCOMPARE(static_cast<int>(droppedSide), static_cast<int>(ConflictSide::Theirs));
    }

    void middleEditRejectsDropOnceFullyResolved() {
        DropTestableConflictTextEdit edit;
        edit.setSide(ConflictSide::Result);
        edit.setReadOnly(false);  // every region resolved -- freely editable now

        int dropCount = 0;
        connect(&edit, &ConflictTextEdit::regionDropped, [&](int, ConflictSide) { ++dropCount; });

        QMimeData* mime =
            encodeConflictRegionMimeData(0, ConflictSide::Ours, QStringLiteral("oursA\n"));
        QDropEvent dropEvent(
            QPointF(5, 5), Qt::CopyAction, mime, Qt::LeftButton, Qt::NoModifier);
        edit.triggerDrop(&dropEvent);
        delete mime;

        QCOMPARE(dropCount, 0);
    }

    // Ours/theirs are drag sources only -- they must never accept a drop
    // even while read-only, or a region dragged out of one could be dropped
    // straight back onto the other and fire regionDropped with a target
    // that makes no sense.
    void oursEditNeverAcceptsDrop() {
        DropTestableConflictTextEdit edit;
        edit.setSide(ConflictSide::Ours);
        edit.setReadOnly(true);

        int dropCount = 0;
        connect(&edit, &ConflictTextEdit::regionDropped, [&](int, ConflictSide) { ++dropCount; });

        QMimeData* mime =
            encodeConflictRegionMimeData(0, ConflictSide::Ours, QStringLiteral("oursA\n"));
        QDropEvent dropEvent(
            QPointF(5, 5), Qt::CopyAction, mime, Qt::LeftButton, Qt::NoModifier);
        edit.triggerDrop(&dropEvent);
        delete mime;

        QCOMPARE(dropCount, 0);
    }

    // Hovering a region raises it (background highlight); moving off it (or
    // onto a plain-text row outside any span) must clear the highlight
    // rather than leave it stuck -- a direct-manipulation surface with no
    // visible "this is draggable" state fails ux3.rule.mental_model_alignment.
    void oursEditHighlightsHoveredRegionAndClearsOutsideIt() {
        ConflictTextEdit edit;
        edit.setSide(ConflictSide::Ours);
        edit.setPlainText(QStringLiteral("aaa\nbbb\nccc\nddd\n"));
        edit.setRegionSpans({RegionRowSpan{0, 1, 2}});  // blocks 1..2 = "bbb"/"ccc"
        edit.resize(300, 200);
        edit.show();
        QVERIFY(QTest::qWaitForWindowExposed(&edit));

        QVERIFY(edit.extraSelections().isEmpty());

        // A direct, synthetic QMouseEvent sent straight to the viewport --
        // matching how QAbstractScrollArea (a QPlainTextEdit base) routes
        // real mouse input to the outer widget's mouseMoveEvent() override
        // -- rather than QTest::mouseMove()'s global-cursor-warp path,
        // which depends on window activation/focus that offscreen QPA
        // doesn't reliably grant a never-activated widget.
        auto moveTo = [&](const QPoint& pos) {
            QMouseEvent event(QEvent::MouseMove,
                               QPointF(pos),
                               edit.viewport()->mapToGlobal(pos),
                               Qt::NoButton,
                               Qt::NoButton,
                               Qt::NoModifier);
            QCoreApplication::sendEvent(edit.viewport(), &event);
        };

        QTextCursor hoverCursor(edit.document()->findBlockByNumber(1));
        moveTo(edit.cursorRect(hoverCursor).center());

        QCOMPARE(edit.extraSelections().size(), 1);
        const QTextEdit::ExtraSelection selection = edit.extraSelections().first();
        QCOMPARE(selection.cursor.selectionStart(), edit.document()->findBlockByNumber(1).position());
        const QTextBlock lastRegionBlock = edit.document()->findBlockByNumber(2);
        QCOMPARE(selection.cursor.selectionEnd(),
                 lastRegionBlock.position() + lastRegionBlock.length() - 1);

        QTextCursor outsideCursor(edit.document()->findBlockByNumber(0));
        moveTo(edit.cursorRect(outsideCursor).center());
        QVERIFY(edit.extraSelections().isEmpty());
    }

    // Design A2's fixed composition order: every selected ours line (in
    // original order) first, then every selected theirs line (in original
    // order) -- regardless of which one was clicked more recently. Selects
    // a non-contiguous, non-"first N" subset on each side specifically so a
    // bug that only worked for prefixes or fully-contiguous selections
    // would fail this.
    void composeCustomRegionLinesOrdersOursBeforeTheirs() {
        ConflictSegment segment;
        segment.kind = ConflictSegmentKind::Region;
        segment.ours = {"ours0\n", "ours1\n"};
        segment.theirs = {"theirs0\n", "theirs1\n", "theirs2\n"};

        const std::vector<bool> oursSelected = {true, false};
        const std::vector<bool> theirsSelected = {false, true, true};

        const std::vector<std::string> result =
            composeCustomRegionLines(segment, oursSelected, theirsSelected);
        QCOMPARE(result.size(), static_cast<std::size_t>(3));
        QCOMPARE(QString::fromStdString(result[0]), QStringLiteral("ours0\n"));
        QCOMPARE(QString::fromStdString(result[1]), QStringLiteral("theirs1\n"));
        QCOMPARE(QString::fromStdString(result[2]), QStringLiteral("theirs2\n"));
    }

    void composeCustomRegionLinesHandlesNothingSelected() {
        ConflictSegment segment;
        segment.kind = ConflictSegmentKind::Region;
        segment.ours = {"ours0\n"};
        segment.theirs = {"theirs0\n"};
        const std::vector<bool> noneSelected = {false};
        QVERIFY(composeCustomRegionLines(segment, noneSelected, noneSelected).empty());
    }

    // Design A2: a plain click (press, then release without moving past
    // the drag threshold) on a region row emits lineToggled with that
    // region's index and the row's offset from the region's first line --
    // not the drag path from the previous commit.
    void oursLineClickEmitsLineToggled() {
        ConflictTextEdit edit;
        edit.setSide(ConflictSide::Ours);
        edit.setPlainText(QStringLiteral("aaa\nbbb\nccc\nddd\n"));
        edit.setRegionSpans({RegionRowSpan{0, 1, 2}});  // blocks 1..2 = "bbb"/"ccc"
        edit.resize(300, 200);
        edit.show();
        QVERIFY(QTest::qWaitForWindowExposed(&edit));

        int toggledRegionIndex = -1;
        int toggledLineOffset = -1;
        int toggleCount = 0;
        Qt::KeyboardModifiers capturedModifiers;
        connect(&edit,
                &ConflictTextEdit::lineToggled,
                [&](int regionIndex, int lineOffset, Qt::KeyboardModifiers modifiers) {
                    toggledRegionIndex = regionIndex;
                    toggledLineOffset = lineOffset;
                    capturedModifiers = modifiers;
                    ++toggleCount;
                });

        // block 2 ("ccc") is the region's second row -> lineOffset 1.
        QTextCursor targetCursor(edit.document()->findBlockByNumber(2));
        const QPoint pos = edit.cursorRect(targetCursor).center();
        auto sendMouse = [&](QEvent::Type type, Qt::MouseButton button, Qt::MouseButtons buttons,
                              Qt::KeyboardModifiers modifiers) {
            QMouseEvent event(
                type, QPointF(pos), edit.viewport()->mapToGlobal(pos), button, buttons, modifiers);
            QCoreApplication::sendEvent(edit.viewport(), &event);
        };
        // A move first: hoveredSpanIndex_ (set only by mouseMoveEvent) is
        // what mousePressEvent checks before it records a drag candidate --
        // this mirrors the real "mouse enters, then presses" sequence.
        sendMouse(QEvent::MouseMove, Qt::NoButton, Qt::NoButton, Qt::NoModifier);
        sendMouse(QEvent::MouseButtonPress, Qt::LeftButton, Qt::LeftButton, Qt::NoModifier);
        sendMouse(QEvent::MouseButtonRelease, Qt::LeftButton, Qt::NoButton, Qt::NoModifier);

        QCOMPARE(toggleCount, 1);
        QCOMPARE(toggledRegionIndex, 0);
        QCOMPARE(toggledLineOffset, 1);
        QVERIFY(!(capturedModifiers & Qt::ShiftModifier));
    }

    // Shift+click's range-select decision lives in ConflictResolvePanel
    // (lastLineClickAnchor_), not in ConflictTextEdit -- the widget's own
    // job is just to pass the modifier through faithfully.
    void oursShiftClickPassesShiftModifierThrough() {
        ConflictTextEdit edit;
        edit.setSide(ConflictSide::Ours);
        edit.setPlainText(QStringLiteral("aaa\nbbb\nccc\nddd\n"));
        edit.setRegionSpans({RegionRowSpan{0, 1, 2}});
        edit.resize(300, 200);
        edit.show();
        QVERIFY(QTest::qWaitForWindowExposed(&edit));

        int toggleCount = 0;
        Qt::KeyboardModifiers capturedModifiers;
        connect(&edit,
                &ConflictTextEdit::lineToggled,
                [&](int, int, Qt::KeyboardModifiers modifiers) {
                    capturedModifiers = modifiers;
                    ++toggleCount;
                });

        QTextCursor targetCursor(edit.document()->findBlockByNumber(1));
        const QPoint pos = edit.cursorRect(targetCursor).center();
        auto sendMouse = [&](QEvent::Type type, Qt::MouseButton button, Qt::MouseButtons buttons) {
            QMouseEvent event(type,
                               QPointF(pos),
                               edit.viewport()->mapToGlobal(pos),
                               button,
                               buttons,
                               Qt::ShiftModifier);
            QCoreApplication::sendEvent(edit.viewport(), &event);
        };
        sendMouse(QEvent::MouseMove, Qt::NoButton, Qt::NoButton);
        sendMouse(QEvent::MouseButtonPress, Qt::LeftButton, Qt::LeftButton);
        sendMouse(QEvent::MouseButtonRelease, Qt::LeftButton, Qt::NoButton);

        QCOMPARE(toggleCount, 1);
        QVERIFY(capturedModifiers & Qt::ShiftModifier);
    }

    // setRegionLineSelection()'s persistent highlight must coexist with the
    // transient hover highlight from the previous commit -- both are real
    // extraSelections() entries at once, not one clobbering the other.
    void setRegionLineSelectionPersistsAndCoexistsWithHover() {
        ConflictTextEdit edit;
        edit.setSide(ConflictSide::Ours);
        edit.setPlainText(QStringLiteral("aaa\nbbb\nccc\nddd\n"));
        edit.setRegionSpans({RegionRowSpan{0, 1, 2}});
        edit.resize(300, 200);
        edit.show();
        QVERIFY(QTest::qWaitForWindowExposed(&edit));

        QVERIFY(edit.extraSelections().isEmpty());

        edit.setRegionLineSelection(0, {true, false});  // select block 1 ("bbb") only
        QCOMPARE(edit.extraSelections().size(), 1);

        auto moveTo = [&](const QPoint& pos) {
            QMouseEvent event(QEvent::MouseMove,
                               QPointF(pos),
                               edit.viewport()->mapToGlobal(pos),
                               Qt::NoButton,
                               Qt::NoButton,
                               Qt::NoModifier);
            QCoreApplication::sendEvent(edit.viewport(), &event);
        };
        // Hover over block 2 ("ccc"), the region's other (unselected) row --
        // the persistent selection on block 1 must survive alongside it.
        QTextCursor hoverCursor(edit.document()->findBlockByNumber(2));
        moveTo(edit.cursorRect(hoverCursor).center());
        QCOMPARE(edit.extraSelections().size(), 2);

        edit.setRegionLineSelection(0, {});  // clear
        QCOMPARE(edit.extraSelections().size(), 1);  // hover selection remains
    }

    // Design A3: the middle pane's own span map, mirroring
    // buildSidePaneTextMapsRegionsToBlockRanges() above but keyed off each
    // region's *resolution* rather than always both raw sides -- an Ours
    // region only occupies as many rows as segment.ours has, an Unresolved
    // one occupies exactly the one placeholder line
    // buildMiddlePreviewText() emits for it.
    void buildMiddleRegionSpansCountsResolvedAndUnresolvedRegions() {
        const ParsedConflictFile parsed = makeTwoRegionParsedFile();
        std::vector<ConflictRegionResolution> resolutions(2);
        resolutions[0] = ConflictRegionResolution{ConflictRegionChoice::Ours, {}};       // 1 line
        resolutions[1] = ConflictRegionResolution{ConflictRegionChoice::Unresolved, {}}; // 1 placeholder

        const std::vector<RegionRowSpan> spans = buildMiddleRegionSpans(parsed, resolutions);
        QCOMPARE(spans.size(), static_cast<std::size_t>(2));
        QCOMPARE(spans[0].regionIndex, 0);
        QCOMPARE(spans[0].firstBlock, 2);  // after "line1\n", "line2\n"
        QCOMPARE(spans[0].blockCount, 1);
        QCOMPARE(spans[1].regionIndex, 1);
        QCOMPARE(spans[1].firstBlock, 4);  // 2 text + 1 (region 0, Ours) + 1 ("line3\n")
        QCOMPARE(spans[1].blockCount, 1);
    }

    // A Custom resolution's row count comes from customLines, not either raw
    // side -- neither segment.ours.size() nor segment.theirs.size() would
    // give the right answer here (2 and 1 respectively; the custom
    // resolution below picks a 3-line combination of both).
    void buildMiddleRegionSpansCountsCustomLines() {
        ConflictSegment region;
        region.kind = ConflictSegmentKind::Region;
        region.ours = {"a\n", "b\n"};
        region.theirs = {"c\n"};
        ParsedConflictFile parsed;
        parsed.segments = {region};
        parsed.regionCount = 1;
        std::vector<ConflictRegionResolution> resolutions(1);
        resolutions[0] = ConflictRegionResolution{ConflictRegionChoice::Custom, {"x\n", "y\n", "z\n"}};

        const std::vector<RegionRowSpan> spans = buildMiddleRegionSpans(parsed, resolutions);
        QCOMPARE(spans.size(), static_cast<std::size_t>(1));
        QCOMPARE(spans[0].firstBlock, 0);
        QCOMPARE(spans[0].blockCount, 3);
    }

    // Design A3's reset-confirmation gate: "unsaved edits" only means
    // anything once the buffer is actually the user's free-editing one
    // (isReadOnly == false, i.e. every region already resolved) -- while
    // still previewing (isReadOnly == true) the two strings are expected to
    // differ constantly and that must never be mistaken for user edits.
    void middleBufferHasUnsavedEditsDetectsDivergenceOnlyWhenEditable() {
        QVERIFY(!middleBufferHasUnsavedEdits(
            QStringLiteral("same"), QStringLiteral("same"), /*isReadOnly=*/false));
        QVERIFY(middleBufferHasUnsavedEdits(
            QStringLiteral("edited"), QStringLiteral("original"), /*isReadOnly=*/false));
        QVERIFY(!middleBufferHasUnsavedEdits(
            QStringLiteral("edited"), QStringLiteral("original"), /*isReadOnly=*/true));
    }

    // Design A3's keyboard equivalents rely on Qt::WidgetWithChildrenShortcut
    // firing for plain Left/Right/Backspace on an ordinary QWidget under
    // offscreen QPA -- not something to assume without checking (advisor
    // flag: a focused QPlainTextEdit could plausibly swallow these first, or
    // a never-activated offscreen window might not grant focus the way this
    // needs). This is a standalone mechanism check, isolated from
    // ConflictResolvePanel's own session-backed state (which has no light
    // way to construct in this test file -- see the file header/plan's own
    // note that RepositorySession "has no test harness" and is deliberately
    // kept thin, with the interesting logic pulled out into pure functions
    // like the two above instead).
    void widgetScopedShortcutFiresOnArrowKeysAndBackspaceWhenFocused() {
        QWidget host;
        host.setFocusPolicy(Qt::StrongFocus);
        auto* leftShortcut = new QShortcut(QKeySequence(Qt::Key_Left), &host);
        leftShortcut->setContext(Qt::WidgetWithChildrenShortcut);
        auto* backspaceShortcut = new QShortcut(QKeySequence(Qt::Key_Backspace), &host);
        backspaceShortcut->setContext(Qt::WidgetWithChildrenShortcut);
        int leftFired = 0;
        int backspaceFired = 0;
        connect(leftShortcut, &QShortcut::activated, [&] { ++leftFired; });
        connect(backspaceShortcut, &QShortcut::activated, [&] { ++backspaceFired; });

        host.resize(200, 100);
        host.show();
        QVERIFY(QTest::qWaitForWindowExposed(&host));
        host.setFocus();
        QTRY_VERIFY(host.hasFocus());

        QTest::keyClick(&host, Qt::Key_Left);
        QTest::keyClick(&host, Qt::Key_Backspace);

        QCOMPARE(leftFired, 1);
        QCOMPARE(backspaceFired, 1);
    }

    // Design A3's strip changes: per-region Take Left/Take Right are gone
    // (superseded by drag + keyboard Left/Right), replaced by a Reset
    // button named by objectName (this file's own convention -- see
    // ancestorToggle_/regionStrip_ -- for not depending on tr() text); the
    // first-use hint row exists alongside it, but must start hidden since
    // no conflict is loaded yet (parsedMarkers_.regionCount == 0) --
    // regressing updateDirectManipulationHintVisibility() back to an
    // isVisible()-based check wouldn't be caught by "the row exists", only
    // by this default-hidden assertion (isVisible() also reads false before
    // the panel itself is shown, which happened to coincide with this fixture's
    // parsedMarkers_-empty state -- see the function's own comment on why
    // isVisible() was wrong for a *different*, session-driven reason too).
    void regionStripHasResetButtonAndHiddenHintRowByDefault() {
        QWidget* strip = panel_->findChild<QWidget*>(QStringLiteral("conflictRegionStrip"));
        QVERIFY(strip != nullptr);

        QPushButton* resetButton =
            panel_->findChild<QPushButton*>(QStringLiteral("conflictRegionResetButton"));
        QVERIFY2(resetButton != nullptr, "expected a per-region Reset button in regionStrip_");
        QCOMPARE(strip->isAncestorOf(resetButton), true);

        bool foundLegacyTakeLeft = false;
        bool foundLegacyTakeRight = false;
        for (QPushButton* button : strip->findChildren<QPushButton*>()) {
            if (button->text() == QStringLiteral("Take Left")) {
                foundLegacyTakeLeft = true;
            }
            if (button->text() == QStringLiteral("Take Right")) {
                foundLegacyTakeRight = true;
            }
        }
        QVERIFY2(!foundLegacyTakeLeft && !foundLegacyTakeRight,
                 "per-region Take Left/Take Right should have been removed (Design A3)");

        QWidget* hintRow =
            panel_->findChild<QWidget*>(QStringLiteral("conflictDirectManipulationHint"));
        QVERIFY2(hintRow != nullptr, "expected the first-use direct-manipulation hint row");
        QVERIFY2(!hintRow->isVisible(),
                 "hint row must start hidden -- no conflict with regions is loaded yet");
    }

    // Regression for the bug advisor caught before this landed: an earlier
    // version compared middleEdit_'s displayed text (QPlainTextEdit
    // normalises everything to bare \n) against the *raw* assembled string
    // (still \r\n on a CRLF file -- see middleContentHasCrlf_), which read
    // as "edited" on every CRLF file even with zero actual user edits. The
    // fix is to always read lastAssembledMiddleText_ back from the widget
    // after setPlainText(), never from the pre-normalisation string.
    void middleBufferHasUnsavedEditsIgnoresCrlfNormalisationNoise() {
        QPlainTextEdit edit;
        edit.setPlainText(QStringLiteral("a\r\nb\r\n"));
        const QString lastAssembled = edit.toPlainText();  // normalised to bare \n by Qt

        QVERIFY(!middleBufferHasUnsavedEdits(edit.toPlainText(), lastAssembled,
                                              /*isReadOnly=*/false));
    }

    // Regression for a reachability gap advisor caught before this landed:
    // Qt::WidgetWithChildrenShortcut (see widgetScopedShortcutFiresOn...
    // above) only fires while focus sits *somewhere without its own opinion
    // on that key*. A focused QPlainTextEdit is not such a place -- it
    // claims Left/Right/Backspace as cursor-navigation/deletion via
    // QEvent::ShortcutOverride before the shortcut ever gets a look (proven
    // by the companion negative-control test right below). Since clicking a
    // conflict region to hover/drag/toggle-a-line (Design A1/A2) hands that
    // pane keyboard focus by ordinary QWidget click-to-focus behaviour, the
    // very first mouse interaction with ancestor/ours/theirs would have
    // permanently broken the keyboard path this file's own shortcut test
    // insists on. The fix: those three panes are never keyboard-focusable
    // at all (pure display/hover/drag surfaces -- see makePane() in
    // ConflictResolvePanel.cpp), and middleEdit_ starts the same way,
    // gaining focus only once it becomes the actual free-editing buffer.
    void sidePanesStayKeyboardUnfocusableSoShortcutsAlwaysReachThePanel() {
        for (int index : {kAncestorPaneIndex, kOursPaneIndex, kTheirsPaneIndex}) {
            QWidget* pane = splitter_->widget(index);
            auto* edit = pane->findChild<ConflictTextEdit*>();
            QVERIFY2(edit != nullptr,
                     qPrintable(QStringLiteral("pane %1 has no ConflictTextEdit child").arg(index)));
            QCOMPARE(edit->focusPolicy(), Qt::NoFocus);
        }
        // Nothing has been loaded into this fresh panel_ yet (showEntry() is
        // never called in this fixture -- see the file header's note on
        // RepositorySession having no light test harness), so middleEdit_ is
        // still in makePane()'s initial "Loading…"/read-only state and must
        // not be focusable either.
        auto* middleEdit = splitter_->widget(kMiddlePaneIndex)->findChild<ConflictTextEdit*>();
        QVERIFY(middleEdit != nullptr);
        QCOMPARE(middleEdit->focusPolicy(), Qt::NoFocus);
    }

    // The other half of the reachability fix above: every setFocusPolicy(
    // Qt::NoFocus) call site on middleEdit_ (showEntry(), the non-editable
    // branch, refreshMiddleFromResolutions()'s unresolved branch) can run
    // while middleEdit_ *already has* keyboard focus -- e.g. a batch of
    // several conflicted files reuses one ConflictResolvePanel (see
    // showEntry()'s own doc comment), so finishing file A with middleEdit_
    // focused and StrongFocus, then showEntry() advancing to file B, calls
    // setFocusPolicy(NoFocus) on a widget that still owns focus at that
    // instant. Naively assuming Qt evicts focus as a side effect of the
    // policy change was wrong -- confirmed empirically: hasFocus() stayed
    // true with setFocusPolicy(NoFocus) alone, no clearFocus(). Left as-is
    // that would have reopened the Left/Right/Backspace swallow bug through
    // the reuse path instead of the first-click path (see the two fixed
    // call sites' own comments). This pins the corrected pattern instead --
    // setFocusPolicy(NoFocus) *paired with* clearFocus(), which is what all
    // three real call sites now do.
    void settingNoFocusAloneDoesNotEvictFocusButPairingWithClearFocusDoes() {
        QWidget host;
        auto* edit = new QPlainTextEdit(&host);
        host.resize(200, 100);
        host.show();
        QVERIFY(QTest::qWaitForWindowExposed(&host));
        edit->setFocus();
        QTRY_VERIFY(edit->hasFocus());

        edit->setFocusPolicy(Qt::NoFocus);
        QVERIFY2(edit->hasFocus(),
                 "setFocusPolicy(NoFocus) alone does not evict existing focus -- "
                 "if this now fails, Qt's behaviour changed and every "
                 "clearFocus() paired with it in ConflictResolvePanel.cpp is dead "
                 "code, not a bug");

        edit->clearFocus();
        QVERIFY(!edit->hasFocus());
    }

    // Negative control for the regression above: proves *why* the fix is
    // needed, not just that it exists. A focused QPlainTextEdit intercepts
    // Left as its own cursor-navigation key -- the ambient
    // Qt::WidgetWithChildrenShortcut never fires at all here (contrast with
    // widgetScopedShortcutFiresOnArrowKeysAndBackspaceWhenFocused above,
    // where the same shortcut fires cleanly on a plain QWidget).
    void focusedPlainTextEditSwallowsLeftBeforeAnyAmbientShortcut() {
        QWidget host;
        host.setFocusPolicy(Qt::StrongFocus);
        auto* leftShortcut = new QShortcut(QKeySequence(Qt::Key_Left), &host);
        leftShortcut->setContext(Qt::WidgetWithChildrenShortcut);
        int leftFired = 0;
        connect(leftShortcut, &QShortcut::activated, [&] { ++leftFired; });

        auto* edit = new QPlainTextEdit(&host);
        edit->setPlainText(QStringLiteral("hello world"));
        edit->resize(180, 80);

        host.resize(200, 100);
        host.show();
        QVERIFY(QTest::qWaitForWindowExposed(&host));
        edit->setFocus();
        QTRY_VERIFY(edit->hasFocus());

        QTest::keyClick(edit, Qt::Key_Left);

        QCOMPARE(leftFired, 0);
    }

private:
    std::unique_ptr<QTemporaryDir> tempDir_;
    std::unique_ptr<ConflictResolvePanel> panel_;
    QSplitter* splitter_ = nullptr;
};

QTEST_MAIN(ConflictUiTest)
#include "ConflictUiTest.moc"
