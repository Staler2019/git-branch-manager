// Verifies GbmLayout's structural size constants match the design spec
// (Flutter Desktop Spec.dc.html, pages 02/03/06/09) verbatim -- these are
// the single source of truth for chrome heights and the 8 splitter
// defaults/minimums so a future spec revision has one edit site instead of
// scattered inline literals across widgets.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/tokens.dart';

void main() {
  group('GbmLayout chrome heights', () {
    test('menu bar height matches spec (32)', () {
      expect(GbmLayout.menuBarHeight, 32);
    });

    test('top bar height matches spec (44)', () {
      expect(GbmLayout.topBarHeight, 44);
    });

    test('tab row height matches spec (36)', () {
      expect(GbmLayout.tabRowHeight, 36);
    });

    test('sidebar default width matches spec (250), not the pre-spec 240', () {
      expect(GbmLayout.sidebarDefaultWidth, 250);
    });

    test('sidebar minimum width matches spec (180)', () {
      expect(GbmLayout.sidebarMinWidth, 180);
    });

    test('working copy left column width matches spec (280)', () {
      expect(GbmLayout.workingCopyLeftColumnWidth, 280);
    });

    test('dialog default width and max height match spec (480 / 560)', () {
      expect(GbmLayout.dialogDefaultWidth, 480);
      expect(GbmLayout.dialogMaxHeight, 560);
    });

    test('context menu minimum width matches spec (220)', () {
      expect(GbmLayout.menuMinWidth, 220);
    });

    test('graph lane width is the user-ruled 11, not spec\'s 17', () {
      // This assertion has said 18, then 17, and now 11 -- and only the
      // middle one was spec. The mockup's graph geometry is
      // `const L0 = 15, L1 = 32, RH = 26` (`spec_logic.js:428`), i.e. two
      // lane centres 17px apart; 18 was drift and was corrected to 17
      // against that source. **11 is not a further correction**: the user
      // ruled the lanes should sit at about two thirds of the pitch, so this
      // is a ratified deviation and the spec citation is here to say what is
      // being deviated *from*, not to justify the number. A test that names
      // a spec value without naming where in the spec it comes from can be
      // wrong and still look authoritative, which is why the citation stays
      // even now that it no longer decides the value.
      expect(GbmLayout.graphLaneWidth, 11);
    });

    test('diff gutter widths match spec (36 old, 36 new, 14 marker)', () {
      expect(GbmLayout.diffGutterWidth, 36);
      expect(GbmLayout.diffMarkerWidth, 14);
    });
  });

  group('GbmLayout splitters (spec page 09 SPLITTERS table)', () {
    test('main.sidebar: 250px default, 180px min', () {
      expect(GbmLayout.splitterMainSidebar.defaultExtent, 250);
      expect(GbmLayout.splitterMainSidebar.minExtent, 180);
    });

    test('main.detail: 62/38 flex ratio, 160px min', () {
      expect(GbmLayout.splitterMainDetail.flexRatio, <double>[62, 38]);
      expect(GbmLayout.splitterMainDetail.minExtent, 160);
    });

    test('main.files: 186px default, 140px min', () {
      expect(GbmLayout.splitterMainFiles.defaultExtent, 186);
      expect(GbmLayout.splitterMainFiles.minExtent, 140);
    });

    // wc.columns and wc.diff are on their way out -- both dividers are being
    // rotated 90 degrees, a ruled deviation from this very table. Each is
    // asserted here until the commit that removes its last caller. See the
    // Working Copy group below for the replacements.
    test('wc.columns: 1:1 flex ratio, 200px min', () {
      expect(GbmLayout.splitterWcColumns.flexRatio, <double>[1, 1]);
      expect(GbmLayout.splitterWcColumns.minExtent, 200);
    });

    test('main.log: collapsed by default, 90px min', () {
      expect(GbmLayout.splitterMainLog.collapsedByDefault, isTrue);
      expect(GbmLayout.splitterMainLog.minExtent, 90);
    });

    test('cw.files: 158px default, 120px min', () {
      expect(GbmLayout.splitterCwFiles.defaultExtent, 158);
      expect(GbmLayout.splitterCwFiles.minExtent, 120);
    });

    test(
      'cw.panes: 1:1.12:1 flex ratio (middle column always widest), 220px min',
      () {
        expect(GbmLayout.splitterCwPanes.flexRatio, <double>[1, 1.12, 1]);
        expect(GbmLayout.splitterCwPanes.minExtent, 220);
      },
    );
  });

  // Spec page 09's SPLITTERS table has a row for each of these two dividers,
  // and both rows are overruled -- `wc.columns` is `dir: '垂直'` there and
  // `wc.diff` is `dir: '水平'`, where `dir` names the divider itself. Rotating
  // both is the whole of what the user asked for, so the spec's own numbers
  // stop deciding these: 200 was a *width* floor for a pair now stacked, and
  // 46/54 was a *height* ratio now applied across the window's width.
  // Design: docs/claude-design-demo/working-copy-layout-spec.html, sections
  // 03 (the width ruling) and 04 (every number's source, or its absence).
  group('GbmLayout Working Copy splitters (ruled deviation from page 09)', () {
    test('wc.files: 260px default, 180px min, and it is extent-mode', () {
      // Extent, not flex, is the ruling itself (option A): a wider window
      // gives every new pixel to the diff instead of widening a file list
      // that was already wide enough. Neither number has a spec source --
      // section 04 of the design page lists both as this round's proposal.
      expect(GbmLayout.splitterWcFiles.defaultExtent, 260);
      expect(GbmLayout.splitterWcFiles.minExtent, 180);
      expect(GbmLayout.splitterWcFiles.flexRatio, isNull);
    });

    test('wc.stack: 1:1 flex ratio, 96px min', () {
      // 1 : 1 survives the rotation unchanged -- it is the one value page
      // 09's `wc.columns` row still decides, because a ratio has no axis.
      // 96 replaces that row's 200: 78 of it is exact constants (a 26px
      // header, an 8px hint margin, 18px of padding and borders, and one
      // 26px file row) and the rest is the hint's own 11px text line, whose
      // height is a TextPainter fact rather than a token.
      expect(GbmLayout.splitterWcStack.flexRatio, <double>[1, 1]);
      expect(GbmLayout.splitterWcStack.minExtent, 96);
    });
  });

  // Not in spec page 09's SPLITTERS table -- that page predates P14/P19 and
  // lists no panel splitter. The minimum is P19's own 樣板規則 3:
  // 「左清單為單選，欄寬可拖曳、下限 220px」.
  group('GbmLayout panel splitters (spec page 19 樣板規則)', () {
    test('panel.list: 280px default, 220px min (P19 rule 3)', () {
      expect(GbmLayout.splitterPanelList.defaultExtent, 280);
      expect(GbmLayout.splitterPanelList.minExtent, 220);
    });
  });
}
