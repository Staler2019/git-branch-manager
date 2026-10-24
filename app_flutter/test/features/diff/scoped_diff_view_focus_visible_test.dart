// `Shift + ↑ ↓` moves the focus end of the range one painted row at a time.
// In a lazy list the row it moves to may be below the viewport, or never
// built at all; the list follows it, so the end the user is moving is always
// the one on screen (L4).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/diff/widgets/diff_line.dart';

import '../../support/pump_app.dart';

bool _everySixth(int i) => i % 6 == 3;

/// 120 rows, row `i` an added line when [added] says so; its text is `r$i`.
DiffFile _file({bool Function(int i) added = _everySixth}) {
  final List<DiffLine> lines = <DiffLine>[];
  int oldLine = 1;
  for (int i = 0; i < 120; i++) {
    final bool add = added(i);
    lines.add(
      DiffLine(
        kind: add ? DiffLineKind.added : DiffLineKind.context,
        oldLine: add ? 0 : oldLine++,
        newLine: i + 1,
        text: 'r$i',
      ),
    );
  }
  return DiffFile(
    oldPath: 'a.dart',
    newPath: 'a.dart',
    kind: FileChangeKind.modified,
    oldMode: '',
    newMode: '',
    oldBlob: '',
    newBlob: '',
    binary: false,
    similarity: 0,
    addedLines: 0,
    removedLines: 0,
    displayPath: 'a.dart',
    hunks: <DiffHunk>[
      DiffHunk(
        oldStart: 1,
        oldCount: oldLine - 1,
        newStart: 1,
        newCount: 120,
        heading: '',
        lines: lines,
      ),
    ],
  );
}

void main() {
  late ScrollController vertical;
  setUp(() => vertical = ScrollController());
  tearDown(() => vertical.dispose());

  Future<void> pump(WidgetTester tester, {DiffFile? file}) => pumpGbmWidget(
    tester,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: 500,
        height: 300,
        child: ScopedDiffView(
          softWrap: false,
          verticalController: vertical,
          sources: <ScopedDiffSource>[
            ScopedDiffSource(
              title: 'Unstaged',
              file: file ?? _file(),
              staged: false,
              onStageScope: (_, _) {},
            ),
          ],
        ),
      ),
    ),
  );

  /// Whether row [row] is built and wholly inside the view.
  bool onScreen(WidgetTester tester, int row) {
    final Finder f = find.byWidgetPredicate(
      (Widget w) => w is DiffLineView && w.line.text == 'r$row',
    );
    if (f.evaluate().isEmpty) return false;
    final Rect view = tester.getRect(find.byType(ScopedDiffView));
    final Rect rect = tester.getRect(f);
    return rect.top >= view.top && rect.bottom <= view.bottom;
  }

  Future<void> shiftArrow(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  Future<void> focusWell(WidgetTester tester) async {
    await tester.tapAt(
      tester.getCenter(find.text('r1', findRichText: true)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
  }

  testWidgets('Shift+Down past the bottom edge brings the focus row on '
      'screen', (WidgetTester tester) async {
    await pump(tester);
    await focusWell(tester);
    // The seed is row 3; fifteen more steps put the focus on row 18.
    for (int i = 0; i < 16; i++) {
      await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(onScreen(tester, 18), isTrue);
  });

  testWidgets('after the view was scrolled far from the range, the next '
      'step brings the focus row back, built or not', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    await focusWell(tester);
    await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
    await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
    vertical.jumpTo(vertical.position.maxScrollExtent);
    await tester.pump();
    expect(onScreen(tester, 4), isFalse, reason: 'the premise');

    await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
    expect(onScreen(tester, 5), isTrue);
  });

  testWidgets('Shift+Up past the top edge brings the focus row on screen', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    vertical.jumpTo(vertical.position.maxScrollExtent);
    await tester.pump();
    final Rect view = tester.getRect(find.byType(ScopedDiffView));
    await tester.tapAt(view.center, kind: PointerDeviceKind.mouse);
    await tester.pump();
    // The upward seed is the last changed row, 117.
    final double start = vertical.offset;
    for (int i = 0; i < 41; i++) {
      await shiftArrow(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(vertical.offset, lessThan(start));
    expect(onScreen(tester, 77), isTrue);
  });

  // The first step raises the one-shot block, whose head lands above the
  // seed row and pushes it down: revealed against the layout from before
  // that, the last row -- the upward seed, on the bottom edge -- ends up
  // below it, the opposite side from the way the key moved.
  testWidgets('the seed row on the bottom edge stays on screen when its '
      'block head appears above it', (WidgetTester tester) async {
    await pump(
      tester,
      file: _file(added: (int i) => _everySixth(i) || i == 119),
    );
    // The extent is an estimate until the end is built, so jump until it
    // stops moving.
    double max = -1;
    while (vertical.position.maxScrollExtent != max) {
      max = vertical.position.maxScrollExtent;
      vertical.jumpTo(max);
      await tester.pump();
    }
    final Rect view = tester.getRect(find.byType(ScopedDiffView));
    expect(onScreen(tester, 119), isTrue, reason: 'the premise: on screen');
    expect(
      view.bottom -
          tester.getRect(find.text('r119', findRichText: true)).bottom,
      lessThan(30),
      reason: 'the premise: near enough the edge for a head to push it off',
    );
    await tester.tapAt(
      tester.getCenter(find.text('r116', findRichText: true)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    await shiftArrow(tester, LogicalKeyboardKey.arrowUp);
    expect(
      find.byKey(const ValueKey<String>('temporary-scope-card')),
      findsOneWidget,
    );
    expect(onScreen(tester, 119), isTrue);
  });

  // A card taller than the view: the jump lands on the card's top, and the
  // focus row is still far below it until the second pass reveals it.
  testWidgets('a focus row deep inside a card taller than the view is '
      'revealed, not just its card', (WidgetTester tester) async {
    await pump(tester, file: _file(added: (int i) => i >= 40 && i < 80));
    await tester.tapAt(
      tester.getCenter(find.text('r1', findRichText: true)),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (int i = 0; i < 21; i++) {
      await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(onScreen(tester, 60), isTrue);
    vertical.jumpTo(0);
    await tester.pump();
    expect(
      find.text('r61', findRichText: true),
      findsNothing,
      reason: 'the premise: the next focus row is not built',
    );

    await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
    expect(onScreen(tester, 61), isTrue);
  });
}
