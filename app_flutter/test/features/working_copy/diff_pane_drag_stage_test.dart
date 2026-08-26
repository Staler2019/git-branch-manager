// Drag-to-stage, in the composition that actually ships.
//
// `scoped_diff_view_test.dart` pumps `ScopedDiffView` bare, and after the
// scroll well was hoisted up to `WorkingCopyDiffPane` that tree has **no
// scrollable above the SelectionArea** -- a shape no user ever sees. The claim
// those twenty-odd drag tests rest on is that the well's two `Scrollable`s do
// not contest a mouse-kind drag in the gesture arena, and nothing at any tier
// was checking it for `GbmCodeScrollWell`.
//
// The premise (CLAUDE.md, and pinned for `GbmCodeHScroll` in
// `gbm_code_hscroll_test.dart`): `ScrollBehavior.dragDevices` defaults to
// `_kTouchLikeDeviceTypes`, which contains no `PointerDeviceKind.mouse`, and a
// desktop selection drag -- trackpad included -- arrives as `mouse`. So the
// scrollers never enter the arena. This file is that premise stated as a
// behaviour: with both axes genuinely overflowing, spec `SCOPES` row 7's drag
// still raises a one-shot scope and still stages what it framed.
//
// Widths and heights are test-font units (`flutter_test` draws every glyph
// `fontSize` wide), which makes the fixture overflow both axes more readily
// than real content would -- the safe direction here, since the whole point is
// to have scrollers present to compete.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_diff_pane.dart';
import 'package:gbm_flutter/widgets/gbm_code_hscroll.dart';

import '../../support/pump_app.dart';

const Size _paneSize = Size(520, 320);

/// Long enough to overflow 520 test-font pixels, short enough that the first
/// few lines are all inside the viewport before any scrolling.
String _lineText(int i) => 'const result$i = compute(alpha, beta, gamma);';

DiffFile _tallWideFile() {
  final List<DiffLine> lines = <DiffLine>[
    for (int i = 0; i < 40; i++)
      DiffLine(
        kind: i.isEven ? DiffLineKind.context : DiffLineKind.added,
        oldLine: i + 1,
        newLine: i + 1,
        text: _lineText(i),
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
    addedLines: 20,
    removedLines: 0,
    displayPath: 'lib/a.dart',
    hunks: <DiffHunk>[
      DiffHunk(
        oldStart: 1,
        oldCount: 40,
        newStart: 1,
        newCount: 40,
        heading: '',
        lines: lines,
      ),
    ],
  );
}

void main() {
  late List<({bool staged, int hunk, List<int> lines})> staged;

  setUp(() => staged = <({bool staged, int hunk, List<int> lines})>[]);

  Future<void> pumpPane(WidgetTester tester) => pumpGbmWidget(
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
          // Off is the shipped default, and it is the only value that builds
          // the scrollers this test exists to compete with.
          softWrap: false,
          onStageScope: (bool s, int h, List<int> l) =>
              staged.add((staged: s, hunk: h, lines: l)),
          onDiscardScope: (int h, List<int> l) {},
          onTemporaryScopeChanged: (void Function()? s) {},
        ),
      ),
    ),
  );

  /// The `SelectableRegion` drag idiom from `scoped_diff_view_test.dart`,
  /// anchored on the text's left edge rather than its box centre for the same
  /// reason: a diff line's `Text` sits in an `Expanded` far wider than its
  /// glyphs. The trailing pumps are for `SelectionTouchTracker`, which defers
  /// its notification by a frame.
  Future<void> dragSelect(WidgetTester tester, String from, String to) async {
    final Rect fromRect = tester.getRect(find.text(from));
    final Rect toRect = tester.getRect(find.text(to));

    final TestGesture gesture = await tester.startGesture(
      Offset(fromRect.left + 1, fromRect.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    // Deliberately not `toRect.right - 1`: with wrapping off the line runs
    // past the pane's right edge, and a move to a point outside the viewport
    // would be testing hit-testing, not the arena.
    await gesture.moveTo(Offset(toRect.left + 20, toRect.center.dy));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('the fixture really does overflow both axes', (
    WidgetTester tester,
  ) async {
    await pumpPane(tester);

    final Finder well = find.byType(GbmCodeScrollWell).first;
    final Iterable<Axis> axes = find
        .descendant(of: well, matching: find.byType(Scrollable))
        .evaluate()
        .map(
          (Element e) =>
              ((e as StatefulElement).state as ScrollableState).position.axis,
        );
    // Without both of these the test below would pass with nothing to
    // compete against, which is exactly the false green it exists to avoid.
    expect(axes, contains(Axis.horizontal));
    expect(axes, contains(Axis.vertical));
  });

  testWidgets('a drag inside the scroll well still raises a one-shot scope', (
    WidgetTester tester,
  ) async {
    await pumpPane(tester);
    await dragSelect(tester, _lineText(0), _lineText(2));

    expect(
      find.byKey(const ValueKey<String>('temporary-scope-card')),
      findsOneWidget,
      reason:
          'the well\'s scrollers claimed the drag, so the selection that '
          'spec SCOPES row 7 stages from never formed',
    );
  });

  testWidgets('and the one-shot button stages the lines it framed', (
    WidgetTester tester,
  ) async {
    await pumpPane(tester);
    await dragSelect(tester, _lineText(0), _lineText(2));

    final Finder button = find.descendant(
      of: find.byKey(const ValueKey<String>('temporary-scope-card')),
      matching: find.byType(TextButton),
    );
    expect(button, findsOneWidget);

    // **The scope button is off-screen to the right, and that is the
    // documented trade-off, not a defect.** Only each row's line-number
    // gutter is pinned; the scope card, the hunk heading and this button all
    // ride the horizontal scroller, so on a file wider than the pane the
    // button's centre lands past the viewport (measured at x=638.8 against a
    // pane ending at 660) and a plain `tap` hit-tests a diff line instead.
    // Scrolling to it is the honest way to reach it, and having to do so here
    // is what keeps that trade-off written down in executable form.
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pump();

    expect(staged, hasLength(1));
    // The pane's first argument is *which column the action came from*, so
    // `false` is the unstaged side -- that is, "stage this". Asserting
    // `isTrue` here would be asserting an unstage.
    expect(staged.single.staged, isFalse);
    // Rows 0..2 of the hunk are context, added, context; `onStageScope`
    // carries the *changed* indices, not the framed ones, so exactly one
    // index comes through. This is the assertion that would have caught the
    // drag framing the wrong rows -- `isNotEmpty` would not.
    expect(staged.single.lines, equals(<int>[1]));
  });
}
