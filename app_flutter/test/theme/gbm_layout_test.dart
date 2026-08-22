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

    test('graph lane width matches spec (17)', () {
      // This assertion used to say 18 and to call 18 "spec". It was never
      // checked against the source: the mockup's graph geometry is
      // `const L0 = 15, L1 = 32, RH = 26` (`spec_logic.js:428`), i.e. two
      // lane centres 17px apart. A test that names a spec value without
      // naming where in the spec it comes from can be wrong in exactly this
      // way and still look authoritative, so the citation is part of the
      // assertion now.
      expect(GbmLayout.graphLaneWidth, 17);
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

    test('wc.columns: 1:1 flex ratio, 200px min', () {
      expect(GbmLayout.splitterWcColumns.flexRatio, <double>[1, 1]);
      expect(GbmLayout.splitterWcColumns.minExtent, 200);
    });

    test('wc.diff: 46/54 flex ratio, 150px min', () {
      expect(GbmLayout.splitterWcDiff.flexRatio, <double>[46, 54]);
      expect(GbmLayout.splitterWcDiff.minExtent, 150);
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
}
