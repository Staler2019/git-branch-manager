// Where the Working Copy diff pane's two scrollbars land.
//
// The bug this pins: with wrapping off, the horizontal scrollbar was drawn
// by `GbmCodeHScroll` inside the pane's vertical `SingleChildScrollView`,
// whose child gets *unbounded* height. `Scrollbar` paints along the bottom
// edge of its own box, so the thumb sat at the bottom of the whole diff --
// measured at y=1428 against a 300px viewport -- and was off-screen for any
// file taller than a screen. Scrolling still worked (trackpad pan,
// Shift+wheel); the at-rest signal that there is more to the right did not.
//
// The claim is therefore about *position*, and a finder cannot make it: both
// the broken and the fixed tree contain exactly one horizontal Scrollbar.
// Every assertion below compares a rect against the pane's own rect.
//
// Widths and heights are test-font units (`flutter_test` draws every glyph
// `fontSize` wide), so the fixture overflows both axes far more readily than
// the same content would in JetBrains Mono -- the safe direction for a test
// that needs both overflows to exist.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_diff_pane.dart';
import 'package:gbm_flutter/widgets/gbm_code_hscroll.dart';

import '../../support/pump_app.dart';

const Size _paneSize = Size(520, 320);

/// Sub-pixel slack: the pane's own border is painted, not laid out, so an
/// exact equality here would be asserting the border width by accident.
const double _tolerance = 0.5;

DiffFile _tallWideFile() {
  final List<DiffLine> lines = <DiffLine>[
    for (int i = 0; i < 60; i++)
      DiffLine(
        kind: i.isEven ? DiffLineKind.context : DiffLineKind.added,
        oldLine: i + 1,
        newLine: i + 1,
        text: 'const result$i = compute(alpha, beta, gamma, delta, zeta);',
      ),
  ];
  return DiffFile(
    oldPath: 'lib/a.dart',
    newPath: 'lib/a.dart',
    kind: FileChangeKind.modified,
    oldMode: '',
    newMode: '',
    oldBlob: '',
    newBlob: '',
    binary: false,
    similarity: 0,
    addedLines: 30,
    removedLines: 0,
    displayPath: 'lib/a.dart',
    hunks: <DiffHunk>[
      DiffHunk(
        oldStart: 1,
        oldCount: 60,
        newStart: 1,
        newCount: 60,
        heading: '',
        lines: lines,
      ),
    ],
  );
}

Future<void> _pump(WidgetTester tester, {required bool softWrap}) =>
    pumpGbmWidget(
      tester,
      child: Center(
        child: SizedBox(
          width: _paneSize.width,
          height: _paneSize.height,
          child: WorkingCopyDiffPane(
            displayPath: 'lib/a.dart',
            unstagedFile: _tallWideFile(),
            stagedFile: null,
            unstagedLoading: false,
            stagedLoading: false,
            softWrap: softWrap,
            onStageScope: (bool s, int h, List<int> l) {},
            onDiscardScope: (int h, List<int> l) {},
            onTemporaryScopeChanged: (void Function()? s) {},
          ),
        ),
      ),
    );

void main() {
  testWidgets('the horizontal scrollbar stays inside the pane on a tall diff', (
    WidgetTester tester,
  ) async {
    await _pump(tester, softWrap: false);

    final Rect pane = tester.getRect(find.byType(WorkingCopyDiffPane));

    // The direct claim, not a proxy for it: every Scrollbar the pane builds
    // paints along the edges of *its own* box, so asserting those boxes sit
    // inside the pane is asserting where the thumbs are. Measuring the well
    // instead would only establish the necessary condition.
    final Iterable<Element> bars = find
        .descendant(
          of: find.byType(WorkingCopyDiffPane),
          matching: find.byType(Scrollbar),
        )
        .evaluate();
    expect(bars, isNotEmpty, reason: 'both axes are scrollable here');

    for (final Element bar in bars) {
      final Rect r = tester.getRect(
        find.byElementPredicate((Element e) => e == bar),
      );
      expect(
        r.bottom,
        lessThanOrEqualTo(pane.bottom + _tolerance),
        reason: 'a thumb below the pane is a thumb nobody can see',
      );
      expect(r.right, lessThanOrEqualTo(pane.right + _tolerance));
      expect(
        r.height,
        lessThan(pane.height),
        reason: 'bounded by the pane, so the box really is a viewport',
      );
    }
  });

  testWidgets('on a desktop platform the ambient scrollbars stay suppressed', (
    WidgetTester tester,
  ) async {
    // `flutter_test` reports `TargetPlatform.android` by default, and
    // Material's ambient `ScrollBehavior` only adds its own scrollbars on
    // desktop -- so on the default platform the suppression inside
    // `GbmCodeScrollWell` is invisible and a test that omits this override
    // passes with it deleted. The app ships on macOS, Windows and Linux
    // only, so the default platform is the one case that never happens.
    //
    // Reset inside the body rather than via `addTearDown`: flutter_test
    // asserts no foundation debug variable outlives the test, and that check
    // runs before tearDowns do.
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await _pump(tester, softWrap: false);
      final Rect pane = tester.getRect(find.byType(WorkingCopyDiffPane));

      for (final Element bar
          in find
              .descendant(
                of: find.byType(WorkingCopyDiffPane),
                matching: find.byType(Scrollbar),
              )
              .evaluate()) {
        final Rect r = tester.getRect(
          find.byElementPredicate((Element e) => e == bar),
        );
        expect(
          r.right,
          lessThanOrEqualTo(pane.right + _tolerance),
          reason:
              'an ambient scrollbar wraps the inner scrollable, so it paints '
              'against a box contentWidth wide -- off the right of the pane',
        );
        expect(r.bottom, lessThanOrEqualTo(pane.bottom + _tolerance));
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the diff still scrolls vertically past the pane', (
    WidgetTester tester,
  ) async {
    await _pump(tester, softWrap: false);

    // Bounding the well must not turn a tall diff into a clipped one: the
    // vertical extent has to exceed the viewport and still be reachable.
    // `.first` scopes this to the unstaged well: `2 file` mode builds two,
    // and the staged side of this fixture has no file, so its extent is 0 --
    // a `.last` here would assert against the empty one and pass for the
    // wrong reason on a broken build.
    final Iterable<ScrollableState> inFirstWell = tester
        .stateList<ScrollableState>(
          find.descendant(
            of: find.byType(GbmCodeScrollWell).first,
            matching: find.byType(Scrollable),
          ),
        );
    final ScrollableState horizontal = inFirstWell.firstWhere(
      (ScrollableState s) => s.position.axis == Axis.horizontal,
    );
    final ScrollableState vertical = inFirstWell.firstWhere(
      (ScrollableState s) => s.position.axis == Axis.vertical,
    );

    expect(
      vertical.position.maxScrollExtent,
      greaterThan(0),
      reason: 'bounding the well must not clip a tall diff',
    );
    expect(
      horizontal.position.maxScrollExtent,
      greaterThan(0),
      reason: 'and the sideways axis is still the one the round added',
    );
  });

  testWidgets('with wrapping on there is no horizontal well to place', (
    WidgetTester tester,
  ) async {
    await _pump(tester, softWrap: true);

    final Rect pane = tester.getRect(find.byType(WorkingCopyDiffPane));
    final Rect well = tester.getRect(find.byType(GbmCodeScrollWell).first);
    expect(well.bottom, lessThanOrEqualTo(pane.bottom + _tolerance));
    expect(find.byType(GbmPinnedGutter), findsNothing);
  });
}
