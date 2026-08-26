// Where a code pane's scrollbars are *painted*, not whether they exist.
//
// `GbmCodeHScroll` puts its child inside `SizedBox(width: contentWidth)` when
// soft wrap is off and the file is wide. A `Scrollbar` paints along the edges
// of its own box, so the ambient desktop scrollbar that Material wraps around
// the child `ListView` was painted against that SizedBox -- the vertical thumb
// landed at x = contentWidth, off the right of the pane (measured: right edge
// 1025 against a pane ending at 610). The fix is `GbmCodeHScroll` owning both
// scrollbars and suppressing the ambient ones underneath.
//
// **This file must run on a desktop `TargetPlatform`.** `flutter_test` reports
// `TargetPlatform.android`, where `ScrollBehavior.buildScrollbar` adds nothing
// at all, so the whole suite was blind to the defect -- the same false green
// that hid it from `working_copy_diff_pane`'s tests until one of them switched
// platform. The override is reset inside the test body rather than in a
// tearDown: flutter_test's "a foundation debug variable was changed" check
// runs before tearDowns do.
//
// Widths are in test-font units (`flutter_test` draws every glyph `fontSize`
// wide), and every assertion is a rect compared to the pane's rect, never to a
// pixel constant.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/diff_page.dart';

import '../../support/pump_app.dart';

/// Sub-pixel slack: a scrollbar paints a track with a hairline border, so an
/// exact `<=` against the pane's edge is brittle by a fraction of a logical
/// pixel without being wrong.
const double _tolerance = 0.5;

ParsedDiff _wideDiff({int lineCount = 60}) {
  final List<DiffLine> lines = <DiffLine>[
    for (int i = 0; i < lineCount; i++)
      DiffLine(
        kind: i.isEven ? DiffLineKind.context : DiffLineKind.added,
        oldLine: i + 1,
        newLine: i + 1,
        text: 'const result$i = compute(alpha, beta, gamma, delta, zeta);',
      ),
  ];
  return ParsedDiff(
    truncated: false,
    inputBytes: 0,
    files: <DiffFile>[
      DiffFile(
        oldPath: 'lib/wide.dart',
        newPath: 'lib/wide.dart',
        kind: FileChangeKind.modified,
        oldMode: '100644',
        newMode: '100644',
        oldBlob: 'a' * 40,
        newBlob: 'b' * 40,
        binary: false,
        similarity: 0,
        addedLines: lineCount ~/ 2,
        removedLines: 0,
        displayPath: 'lib/wide.dart',
        hunks: <DiffHunk>[
          DiffHunk(
            oldStart: 1,
            oldCount: lineCount,
            newStart: 1,
            newCount: lineCount,
            heading: '',
            lines: lines,
          ),
        ],
      ),
    ],
  );
}

void main() {
  const double paneWidth = 420;
  const double paneHeight = 300;

  Future<void> pumpPane(WidgetTester tester, ParsedDiff diff) => pumpGbmWidget(
    tester,
    child: Center(
      child: SizedBox(
        width: paneWidth,
        height: paneHeight,
        child: DiffPage(diff: diff),
      ),
    ),
  );

  testWidgets(
    'every scrollbar of a wide unwrapped diff paints inside the pane',
    (WidgetTester tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await pumpPane(tester, _wideDiff());

        final Rect pane = tester.getRect(find.byType(DiffPage));
        final Finder bars = find.descendant(
          of: find.byType(DiffPage),
          matching: find.byType(Scrollbar),
        );
        // Exactly one per axis. Three would mean the ambient desktop
        // scrollbar came back on top of ours -- which is the defect, and a
        // rect loop alone cannot see it, because the two correctly-placed
        // bars would still pass every bound below.
        expect(bars, findsNWidgets(2));

        for (final Element element in bars.evaluate()) {
          final Rect bar = tester.getRect(
            find.byElementPredicate((Element e) => e == element),
          );
          // The horizontal thumb sits on the bottom edge of its own box and
          // the vertical one on the right edge, so these two bounds are the
          // ones that go off-screen when the box is the content rather than
          // the viewport.
          expect(
            bar.right,
            lessThanOrEqualTo(pane.right + _tolerance),
            reason:
                'a scrollbar box extends past the pane\'s right edge, so '
                'the vertical thumb paints off-screen: $bar vs $pane',
          );
          expect(
            bar.bottom,
            lessThanOrEqualTo(pane.bottom + _tolerance),
            reason:
                'a scrollbar box extends below the pane, so the '
                'horizontal thumb paints off-screen: $bar vs $pane',
          );
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    },
  );

  testWidgets('both axes really are scrollable, not merely bounded', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await pumpPane(tester, _wideDiff());

      // Selecting by axis rather than by `.first`/`.last`: which order the
      // two Scrollables come out in is an implementation detail of the tree,
      // and picking the wrong one would let this pass for the wrong reason.
      final Iterable<ScrollableState> states = find
          .byType(Scrollable)
          .evaluate()
          .map((Element e) => (e as StatefulElement).state as ScrollableState);

      final ScrollableState horizontal = states.firstWhere(
        (ScrollableState s) => s.position.axis == Axis.horizontal,
      );
      final ScrollableState vertical = states.firstWhere(
        (ScrollableState s) => s.position.axis == Axis.vertical,
      );

      expect(horizontal.position.maxScrollExtent, greaterThan(0));
      expect(vertical.position.maxScrollExtent, greaterThan(0));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a diff that fits sideways builds no horizontal scroller', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final ParsedDiff narrow = ParsedDiff(
        truncated: false,
        inputBytes: 0,
        files: <DiffFile>[
          DiffFile(
            oldPath: 'a',
            newPath: 'a',
            kind: FileChangeKind.modified,
            oldMode: '100644',
            newMode: '100644',
            oldBlob: '',
            newBlob: '',
            binary: false,
            similarity: 0,
            addedLines: 1,
            removedLines: 0,
            displayPath: 'a',
            hunks: <DiffHunk>[
              DiffHunk(
                oldStart: 1,
                oldCount: 1,
                newStart: 1,
                newCount: 1,
                heading: '',
                lines: <DiffLine>[
                  DiffLine(
                    kind: DiffLineKind.added,
                    oldLine: 0,
                    newLine: 1,
                    text: 'x',
                  ),
                ],
              ),
            ],
          ),
        ],
      );
      await pumpPane(tester, narrow);

      final Iterable<Axis> axes = find
          .byType(Scrollable)
          .evaluate()
          .map(
            (Element e) =>
                ((e as StatefulElement).state as ScrollableState).position.axis,
          );
      expect(axes, isNot(contains(Axis.horizontal)));
      expect(axes, contains(Axis.vertical));
      // The vertical bar is still drawn by us, not by the ambient behaviour:
      // one, and only one.
      expect(
        find.descendant(
          of: find.byType(DiffPage),
          matching: find.byType(Scrollbar),
        ),
        findsOneWidget,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
