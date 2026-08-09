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
#include <QMimeData>
#include <QMouseEvent>
#include <QSettings>
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

private:
    std::unique_ptr<QTemporaryDir> tempDir_;
    std::unique_ptr<ConflictResolvePanel> panel_;
    QSplitter* splitter_ = nullptr;
};

QTEST_MAIN(ConflictUiTest)
#include "ConflictUiTest.moc"
