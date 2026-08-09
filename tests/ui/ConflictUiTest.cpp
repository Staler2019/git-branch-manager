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

#include <QApplication>
#include <QCheckBox>
#include <QSettings>
#include <QSplitter>
#include <QTemporaryDir>
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

private:
    std::unique_ptr<QTemporaryDir> tempDir_;
    std::unique_ptr<ConflictResolvePanel> panel_;
    QSplitter* splitter_ = nullptr;
};

QTEST_MAIN(ConflictUiTest)
#include "ConflictUiTest.moc"
