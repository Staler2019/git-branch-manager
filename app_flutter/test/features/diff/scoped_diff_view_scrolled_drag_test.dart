// A drag that scrolls the lazy list (autoscroll past an edge, or the wheel
// mid-drag) frames rows the list may never have built, or has already
// disposed, so no row's own selection state can be trusted for it. Such a
// drag is resolved from its two endpoints instead (使用者裁定 ①「端點幾何」):
// every row painted between the row under the pointer-down and the row under
// the pointer-up, both included. A point between two rows -- a card's head
// or bottom border, a one-shot block's head, the space between items -- is
// the boundary there and belongs to neither. Each test writes out the
// payload that rule gives for its gesture, by hand, from the fixture's own
// line layout.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/diff_full_file_fill.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/diff/widgets/diff_line.dart';
import 'package:gbm_flutter/widgets/gbm_dashed.dart';
import 'package:gbm_flutter/widgets/seeded_sliver_list.dart';

import '../../support/pump_app.dart';

bool _everySixth(int i) => i % 6 == 3;

/// [_everySixth], plus rows 40-47: with row 39 that is one card of nine
/// changed rows, so a point can sit inside a card with changes above it.
bool _withLongCard(int i) => _everySixth(i) || (i >= 40 && i < 48);

/// One hunk of [length] rows whose row `i` is an added line when [added]
/// says so, context otherwise. Row `i`'s text is `r$i`, then [pad].
DiffFile _file({
  int length = 120,
  bool Function(int i) added = _everySixth,
  String pad = '',
}) {
  final List<DiffLine> lines = <DiffLine>[];
  int oldLine = 1;
  int newLine = 1;
  for (int i = 0; i < length; i++) {
    final bool add = added(i);
    lines.add(
      DiffLine(
        kind: add ? DiffLineKind.added : DiffLineKind.context,
        oldLine: add ? 0 : oldLine++,
        newLine: newLine++,
        text: 'r$i$pad',
      ),
    );
  }
  return _wrap(<DiffHunk>[
    DiffHunk(
      oldStart: 1,
      oldCount: oldLine - 1,
      newStart: 1,
      newCount: newLine - 1,
      heading: '',
      lines: lines,
    ),
  ]);
}

/// A staged side holding one inserted line at index line [indexLine].
DiffFile _stagedInsert(int indexLine) => _wrap(<DiffHunk>[
  DiffHunk(
    oldStart: indexLine - 1,
    oldCount: 0,
    newStart: indexLine,
    newCount: 1,
    heading: '',
    lines: <DiffLine>[
      DiffLine(
        kind: DiffLineKind.added,
        oldLine: 0,
        newLine: indexLine,
        text: 's$indexLine',
      ),
    ],
  ),
]);

DiffFile _wrap(List<DiffHunk> hunks) => DiffFile(
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
  hunks: hunks,
);

/// The changed rows from row [from] to row [to], both included.
List<int> _changedBetween(
  int from,
  int to, {
  bool Function(int i) added = _everySixth,
}) => <int>[
  for (int i = from < to ? from : to; i <= (from < to ? to : from); i++)
    if (added(i)) i,
];

final RegExp _rowText = RegExp(r'^r(\d+)');

/// The unstaged row a [DiffLineView] draws, or null for any other row.
int? _rowIndexOf(Element e) {
  final Match? m = _rowText.firstMatch((e.widget as DiffLineView).line.text);
  return m == null ? null : int.parse(m.group(1)!);
}

typedef _Call = ({int hunkIndex, List<int> lines});

void main() {
  late List<_Call> stageCalls;
  late List<_Call> unstageCalls;
  late void Function()? submit;
  late ScrollController vertical;

  setUp(() {
    stageCalls = <_Call>[];
    unstageCalls = <_Call>[];
    submit = null;
    vertical = ScrollController();
  });
  tearDown(() => vertical.dispose());

  ScopedDiffSource unstagedSource(DiffFile file) => ScopedDiffSource(
    title: 'Unstaged',
    file: file,
    staged: false,
    onStageScope: (int h, List<int> l) =>
        stageCalls.add((hunkIndex: h, lines: l)),
  );

  ScopedDiffSource stagedSource(DiffFile file) => ScopedDiffSource(
    title: 'Staged',
    file: file,
    staged: true,
    onStageScope: (int h, List<int> l) =>
        unstageCalls.add((hunkIndex: h, lines: l)),
  );

  Future<void> pump(
    WidgetTester tester, {
    DiffFile? file,
    List<ScopedDiffSource>? sources,
    double contentWidth = 0,
    List<DiffFillRow>? fill,
    double width = 500,
  }) => pumpGbmWidget(
    tester,
    child: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        height: 300,
        child: ScopedDiffView(
          softWrap: false,
          verticalController: vertical,
          contentWidth: contentWidth,
          fill: fill,
          onTemporaryScopeChanged: (void Function()? s) => submit = s,
          sources:
              sources ?? <ScopedDiffSource>[unstagedSource(file ?? _file())],
        ),
      ),
    ),
  );

  Rect viewport(WidgetTester tester) =>
      tester.getRect(find.byType(ScopedDiffView).first);

  /// Every built unstaged row with its box, top to bottom.
  List<(Rect, int)> builtRows(WidgetTester tester) {
    final List<(Rect, int)> rows = <(Rect, int)>[
      for (final Element e in find.byType(DiffLineView).evaluate())
        if (_rowIndexOf(e) case final int row)
          (tester.getRect(find.byWidget(e.widget)), row),
    ]..sort(((Rect, int) a, (Rect, int) b) => a.$1.top.compareTo(b.$1.top));
    return rows;
  }

  Rect rowRect(WidgetTester tester, int row) =>
      builtRows(tester).firstWhere(((Rect, int) r) => r.$2 == row).$1;

  /// The rows wholly inside the viewport, top to bottom.
  List<int> visibleRows(WidgetTester tester) {
    final Rect view = viewport(tester);
    return <int>[
      for (final (Rect rect, int row) in builtRows(tester))
        if (rect.top >= view.top && rect.bottom <= view.bottom) row,
    ];
  }

  /// The row a downward drag released at the bottom edge ends on: the row
  /// under the edge, or the last row above it when the edge is between rows.
  int rowAtBottomEdge(WidgetTester tester) {
    final double edge = viewport(tester).bottom - 0.5;
    return builtRows(tester).lastWhere(((Rect, int) r) => r.$1.top <= edge).$2;
  }

  /// The mirror for an upward drag released at the top edge.
  int rowAtTopEdge(WidgetTester tester) {
    final double edge = viewport(tester).top;
    return builtRows(tester)
        .firstWhere(((Rect, int) r) => r.$1.bottom > edge)
        .$2;
  }

  /// A point on row [row]'s text, as a drag that starts on the text does.
  Offset textOf(WidgetTester tester, int row) =>
      rowRect(tester, row).centerLeft + const Offset(kDiffGutterWidth + 4, 0);

  /// Scrolls without a gesture until [row] and the three rows after it are
  /// wholly on screen.
  Future<void> bringIntoView(WidgetTester tester, int row) async {
    while (!visibleRows(tester).contains(row + 3)) {
      vertical.jumpTo(vertical.offset + 40);
      await tester.pump();
    }
  }

  Future<TestGesture> press(WidgetTester tester, Offset at) async {
    final TestGesture gesture = await tester.startGesture(
      at,
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    return gesture;
  }

  /// Holds the pointer at [at] for [frames] frames of autoscroll.
  Future<void> hold(
    WidgetTester tester,
    TestGesture gesture,
    Offset at, {
    int frames = 100,
  }) async {
    await gesture.moveTo(at);
    for (int i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> release(WidgetTester tester, TestGesture gesture) async {
    await gesture.up();
    await tester.pump();
    await tester.pump();
  }

  Offset below(WidgetTester tester, double x) =>
      Offset(x, viewport(tester).bottom + 3000);
  Offset above(WidgetTester tester, double x) =>
      Offset(x, viewport(tester).top - 3000);

  /// Presses on row [from]'s text, drags far below the view for [frames]
  /// frames of autoscroll, then releases on the last row wholly on screen.
  /// Returns that row.
  Future<int> overdragDown(
    WidgetTester tester,
    int from, {
    int frames = 100,
  }) async {
    final Offset start = textOf(tester, from);
    final TestGesture gesture = await press(tester, start);
    await hold(tester, gesture, below(tester, start.dx), frames: frames);
    final int end = visibleRows(tester).last;
    await gesture.moveTo(textOf(tester, end));
    await tester.pump();
    await release(tester, gesture);
    return end;
  }

  Finder oneShotButton(String verb) => find.descendant(
    of: find.byKey(const ValueKey<String>('temporary-scope-card')),
    matching: find.textContaining(RegExp('^$verb ')),
  );

  /// Spends the range through the one-shot block's own button, which must
  /// be on screen.
  Future<void> tapOneShot(WidgetTester tester, {String verb = 'Stage'}) async {
    expect(oneShotButton(verb), findsOneWidget);
    await tester.tap(oneShotButton(verb));
    await tester.pump();
  }

  /// Spends the range through the published submitter, the one
  /// `repositoryStageSelectedLines` (Ctrl/Cmd+Alt+S) calls.
  Future<void> submitByKeyboardPath(WidgetTester tester) async {
    expect(submit, isNotNull, reason: 'a one-shot scope exists');
    submit!();
    await tester.pump();
  }

  /// One stage (or unstage) call, on hunk 0, with exactly [lines].
  void expectOneCall(List<_Call> calls, List<int> lines) {
    expect(calls, hasLength(1));
    expect(calls.single.hunkIndex, 0);
    expect(calls.single.lines, lines);
  }

  Future<void> shiftArrow(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();
    await tester.pump();
  }

  group('L3-a downward overdrag', () {
    testWidgets('frames every changed row from the press to the release, '
        'rows never built included', (WidgetTester tester) async {
      await pump(tester);
      final int end = await overdragDown(tester, 3);
      // The premise: autoscroll jumped over rows it never built.
      expect(end, greaterThan(40), reason: 'the overdrag must reach far down');
      // A kept-alive item rebuilt off screen once registered a selectable
      // with no layout, and the framework's screen-order sort threw.
      expect(tester.takeException(), isNull);

      await submitByKeyboardPath(tester);
      expectOneCall(stageCalls, _changedBetween(3, end));
    });

    testWidgets('Shift+Down afterwards grows it by one row', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      final int end = await overdragDown(tester, 3);

      // Changed rows are six apart, so six steps always reach one more.
      for (int i = 0; i < 6; i++) {
        await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
      }
      await submitByKeyboardPath(tester);
      expect(stageCalls.single.lines, _changedBetween(3, end + 6));
      expect(
        _changedBetween(3, end + 6),
        hasLength(_changedBetween(3, end).length + 1),
      );
    });

    // L3-g with it: in unified the staged side's change sits inside the
    // range, and the drag reached an unstaged card first, so it stages and
    // leaves the staged change alone (U5).
    testWidgets('in unified, across both sources, it stages only the '
        'unstaged rows', (WidgetTester tester) async {
      await pump(
        tester,
        sources: <ScopedDiffSource>[
          unstagedSource(_file()),
          stagedSource(_stagedInsert(30)),
        ],
      );
      final int end = await overdragDown(tester, 3);
      expect(end, greaterThan(40), reason: 'the staged row lies inside');

      await submitByKeyboardPath(tester);
      expectOneCall(stageCalls, _changedBetween(3, end));
      expect(unstageCalls, isEmpty);
    });
  });

  testWidgets('L3-b: down, then back up past the press, frames from the '
      'release up to the press', (WidgetTester tester) async {
    await pump(tester);
    await bringIntoView(tester, 6);
    final Offset start = textOf(tester, 9);
    final TestGesture gesture = await press(tester, start);
    await hold(tester, gesture, below(tester, start.dx), frames: 60);
    expect(vertical.offset, greaterThan(600));
    await hold(tester, gesture, above(tester, start.dx));
    expect(vertical.offset, 0);
    await gesture.moveTo(textOf(tester, 1));
    await tester.pump();
    await release(tester, gesture);

    // An upward range ends on the press, so its anchor is row 9: Shift+Down
    // walks the top end down by one, from row 1 to row 2 -- and two more
    // steps past row 3 drop it.
    await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
    await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
    await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
    await submitByKeyboardPath(tester);
    expectOneCall(stageCalls, _changedBetween(4, 9));
  });

  group('L3-c a press between two rows is a boundary, not a row', () {
    // Card 9 holds row 9 alone. Between row 8's bottom and row 9's top lie
    // the gap's bottom margin, the card's top margin and its head; between
    // row 9's bottom and row 10's top, the card's bottom border and margin.
    Future<void> dragFrom(
      WidgetTester tester, {
      required double Function(Rect r8, Rect r9, Rect r10) y,
      required bool down,
    }) async {
      await pump(tester);
      await bringIntoView(tester, 8);
      final double at = y(
        rowRect(tester, 8),
        rowRect(tester, 9),
        rowRect(tester, 10),
      );
      final double x = textOf(tester, 9).dx;
      final TestGesture gesture = await press(tester, Offset(x, at));
      if (down) {
        await hold(tester, gesture, below(tester, x));
        final int end = visibleRows(tester).last;
        await gesture.moveTo(textOf(tester, end));
      } else {
        await hold(tester, gesture, above(tester, x), frames: 30);
        expect(vertical.offset, 0);
        await gesture.moveTo(textOf(tester, 1));
      }
      await tester.pump();
      await release(tester, gesture);
    }

    double headUpper(Rect r8, Rect r9, Rect _) =>
        r8.bottom + (r9.top - r8.bottom) / 4;
    double headLower(Rect r8, Rect r9, Rect _) =>
        r8.bottom + (r9.top - r8.bottom) * 3 / 4;
    double footUpper(Rect _, Rect r9, Rect r10) =>
        r9.bottom + (r10.top - r9.bottom) / 4;
    double footLower(Rect _, Rect r9, Rect r10) =>
        r9.bottom + (r10.top - r9.bottom) * 3 / 4;

    for (final (String, double Function(Rect, Rect, Rect)) head
        in <(String, double Function(Rect, Rect, Rect))>[
          ('upper', headUpper),
          ('lower', headLower),
        ]) {
      testWidgets('card head, ${head.$1} half, downward: from row 9', (
        WidgetTester tester,
      ) async {
        await dragFrom(tester, y: head.$2, down: true);
        final int end = visibleRows(tester).last;
        await submitByKeyboardPath(tester);
        expect(stageCalls.single.lines, _changedBetween(9, end));
      });

      testWidgets('card head, ${head.$1} half, upward: down to row 8', (
        WidgetTester tester,
      ) async {
        await dragFrom(tester, y: head.$2, down: false);
        await tapOneShot(tester);
        expectOneCall(stageCalls, _changedBetween(1, 8));
      });
    }

    for (final (String, double Function(Rect, Rect, Rect)) foot
        in <(String, double Function(Rect, Rect, Rect))>[
          ('upper', footUpper),
          ('lower', footLower),
        ]) {
      testWidgets('card bottom, ${foot.$1} half, downward: from row 10', (
        WidgetTester tester,
      ) async {
        await dragFrom(tester, y: foot.$2, down: true);
        final int end = visibleRows(tester).last;
        await submitByKeyboardPath(tester);
        expect(stageCalls.single.lines, _changedBetween(10, end));
      });

      testWidgets('card bottom, ${foot.$1} half, upward: down to row 9', (
        WidgetTester tester,
      ) async {
        await dragFrom(tester, y: foot.$2, down: false);
        await tapOneShot(tester);
        expectOneCall(stageCalls, _changedBetween(1, 9));
      });
    }
  });

  group('L3-d a release outside the view is clamped to its edge', () {
    testWidgets('below: ends on the row under the bottom edge', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      final Offset start = textOf(tester, 3);
      final TestGesture gesture = await press(tester, start);
      await hold(tester, gesture, below(tester, start.dx), frames: 60);
      final int end = rowAtBottomEdge(tester);
      await release(tester, gesture);

      await submitByKeyboardPath(tester);
      expect(stageCalls.single.lines, _changedBetween(3, end));
    });

    testWidgets('above: ends on the row under the top edge', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      vertical.jumpTo(1500);
      await tester.pump();
      final int from = visibleRows(tester)[5];
      final Offset start = textOf(tester, from);
      final TestGesture gesture = await press(tester, start);
      await hold(tester, gesture, above(tester, start.dx), frames: 20);
      expect(vertical.offset, greaterThan(0), reason: 'still mid-list');
      final int end = rowAtTopEdge(tester);
      await release(tester, gesture);

      await submitByKeyboardPath(tester);
      expect(stageCalls.single.lines, _changedBetween(end, from));
    });
  });

  testWidgets('L3-e: a wheel scroll mid-drag is a scrolled drag', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    final Offset start = textOf(tester, 3);
    final TestGesture gesture = await press(tester, start);
    await gesture.moveTo(textOf(tester, 4));
    await tester.pump();
    tester.binding.handlePointerEvent(
      PointerScrollEvent(
        position: viewport(tester).center,
        scrollDelta: const Offset(0, 900),
        kind: PointerDeviceKind.mouse,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(vertical.offset, greaterThan(500));
    final int end = visibleRows(tester).last;
    await gesture.moveTo(textOf(tester, end));
    await tester.pump();
    await release(tester, gesture);

    await submitByKeyboardPath(tester);
    expect(stageCalls.single.lines, _changedBetween(3, end));
  });

  group('L3-f an unscrolled gesture keeps the live-state rule', () {
    testWidgets('a click raises nothing', (WidgetTester tester) async {
      await pump(tester);
      final TestGesture gesture = await press(tester, textOf(tester, 3));
      await release(tester, gesture);
      expect(submit, isNull);
      expect(
        find.byKey(const ValueKey<String>('temporary-scope-card')),
        findsNothing,
      );
    });

    testWidgets('a double-click on a changed row frames that row', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      await tester.tapAt(textOf(tester, 3), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(textOf(tester, 3), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await tester.pump();
      await tapOneShot(tester);
      expectOneCall(stageCalls, const <int>[3]);
    });

    // The case the two rules answer differently: a drag starting past the
    // end of row 3's text selects nothing on row 3, so the live-state rule
    // leaves it out; the endpoint rule would put it in.
    testWidgets('a drag from past the end of a row leaves that row out', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      await bringIntoView(tester, 6);
      expect(visibleRows(tester), containsAll(<int>[3, 9]));
      final double before = vertical.offset;
      final Rect r3 = tester.getRect(find.text('r3', findRichText: true));
      final TestGesture gesture = await press(
        tester,
        r3.centerRight + const Offset(60, 0),
      );
      await gesture.moveTo(textOf(tester, 9) + const Offset(4, 0));
      await tester.pump();
      expect(vertical.offset, before, reason: 'the premise: nothing scrolled');
      await release(tester, gesture);

      await tapOneShot(tester);
      expectOneCall(stageCalls, const <int>[9]);
    });
  });

  testWidgets('L3-h: Shift+press after a scrolled drag extends it from its '
      'start', (WidgetTester tester) async {
    await pump(tester);
    await overdragDown(tester, 3, frames: 40);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
    final int from = visibleRows(tester)[2];
    final Offset start = textOf(tester, from);
    final TestGesture gesture = await press(tester, start);
    await hold(tester, gesture, below(tester, start.dx), frames: 40);
    final int end = visibleRows(tester).last;
    await gesture.moveTo(textOf(tester, end));
    await tester.pump();
    await release(tester, gesture);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
    await tester.pump();

    await submitByKeyboardPath(tester);
    expect(stageCalls.single.lines, _changedBetween(3, end));
  });

  // Slice J: the rows a far jump lands on were seeded, not walked to; a
  // drag from among them still frames exactly its two ends' rows.
  for (final bool keyboard in <bool>[false, true]) {
    testWidgets(
      'a scrolled drag right after a far jump frames every changed '
      'row from the press to the release (${keyboard ? 'Ctrl/Cmd+Alt+S' : 'the pinned head'})',
      (WidgetTester tester) async {
        await pump(tester, file: _file(length: 400));
        vertical.jumpTo(5000);
        await tester.pump();
        expect(
          tester
              .renderObject<RenderSeededSliverList>(
                find.byType(SeededSliverList),
              )
              .seedCount,
          1,
          reason: 'the premise: the jump seeded',
        );
        final int from = visibleRows(tester)[1];
        final int end = await overdragDown(tester, from, frames: 40);
        expect(end - from, greaterThan(20), reason: 'the premise: it scrolled');
        await tester.pump();

        if (keyboard) {
          await submitByKeyboardPath(tester);
        } else {
          final Finder pinned = find.descendant(
            of: find.byKey(const ValueKey<String>('temporary-scope-sticky')),
            matching: find.textContaining(RegExp('^Stage ')),
          );
          expect(pinned, findsOneWidget);
          await tester.tap(pinned);
          await tester.pump();
        }
        expectOneCall(stageCalls, _changedBetween(from, end));
      },
    );
  }

  group('L3-i a drag that scrolls and comes back still took the endpoint '
      'rule', () {
    testWidgets('from offset 0, down and back above the top', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      final int from = visibleRows(tester).last;
      final Offset start = textOf(tester, from);
      final TestGesture gesture = await press(tester, start);
      await hold(tester, gesture, below(tester, start.dx), frames: 40);
      await hold(tester, gesture, above(tester, start.dx), frames: 60);
      expect(vertical.offset, 0, reason: 'both ends at offset 0');
      await release(tester, gesture);

      await tapOneShot(tester);
      expectOneCall(stageCalls, _changedBetween(0, from));
    });

    testWidgets('from the end, up and back below the bottom', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      vertical.jumpTo(vertical.position.maxScrollExtent);
      await tester.pump();
      final double max = vertical.offset;
      final int from = visibleRows(tester).first;
      final Offset start = textOf(tester, from);
      final TestGesture gesture = await press(tester, start);
      await hold(tester, gesture, above(tester, start.dx), frames: 40);
      await hold(tester, gesture, below(tester, start.dx));
      expect(
        vertical.offset,
        vertical.position.maxScrollExtent,
        reason: 'both ends at the end',
      );
      expect(max, greaterThan(0));
      await release(tester, gesture);

      await submitByKeyboardPath(tester);
      expectOneCall(stageCalls, _changedBetween(from, 119));
    });
  });

  group('L3-j a press on a one-shot block head mid-card', () {
    // Card 39-47, with a one-shot block over rows 43-44: the block's head
    // sits between rows 42 and 43, with changed rows 39-42 above it.
    Future<void> dragFromBlockHead(
      WidgetTester tester, {
      required double fraction,
      required bool down,
    }) async {
      await pump(tester, file: _file(added: _withLongCard));
      await bringIntoView(tester, 41);
      final TestGesture select = await press(tester, textOf(tester, 43));
      await select.moveTo(textOf(tester, 44) + const Offset(20, 0));
      await tester.pump();
      await release(tester, select);
      expect(
        find.byKey(const ValueKey<String>('temporary-scope-card')),
        findsOneWidget,
      );
      final Rect r42 = rowRect(tester, 42);
      final Rect r43 = rowRect(tester, 43);
      expect(r43.top - r42.bottom, greaterThan(20), reason: 'a head between');
      final double x = textOf(tester, 43).dx;
      final TestGesture gesture = await press(
        tester,
        Offset(x, r42.bottom + (r43.top - r42.bottom) * fraction),
      );
      if (down) {
        await hold(tester, gesture, below(tester, x));
        await gesture.moveTo(textOf(tester, visibleRows(tester).last));
      } else {
        await hold(tester, gesture, above(tester, x), frames: 60);
        expect(vertical.offset, 0);
        await gesture.moveTo(textOf(tester, 1));
      }
      await tester.pump();
      await release(tester, gesture);
    }

    for (final double fraction in <double>[0.25, 0.75]) {
      testWidgets('at $fraction of it, downward: from row 43', (
        WidgetTester tester,
      ) async {
        await dragFromBlockHead(tester, fraction: fraction, down: true);
        final int end = visibleRows(tester).last;
        await submitByKeyboardPath(tester);
        expect(
          stageCalls.single.lines,
          _changedBetween(43, end, added: _withLongCard),
        );
      });

      testWidgets('at $fraction of it, upward: down to row 42', (
        WidgetTester tester,
      ) async {
        await dragFromBlockHead(tester, fraction: fraction, down: false);
        await tapOneShot(tester);
        expectOneCall(stageCalls, _changedBetween(1, 42, added: _withLongCard));
      });
    }
  });

  testWidgets('L3-l: a press in the well padding beside a mid-card row starts '
      'on that row', (WidgetTester tester) async {
    await pump(tester, file: _file(added: _withLongCard));
    await bringIntoView(tester, 43);
    final Rect view = viewport(tester);
    final TestGesture gesture = await press(
      tester,
      Offset(view.left + 3, rowRect(tester, 44).center.dy),
    );
    await hold(tester, gesture, below(tester, view.left + 3));
    final int end = visibleRows(tester).last;
    await gesture.moveTo(
      Offset(view.left - 200, rowRect(tester, end).center.dy),
    );
    await tester.pump();
    await release(tester, gesture);

    await submitByKeyboardPath(tester);
    expect(
      stageCalls.single.lines,
      _changedBetween(44, end, added: _withLongCard),
    );
  });

  group('L3-m the probe follows the visible gutter', () {
    const String pad = ' xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';

    testWidgets('with the code scrolled sideways past the gutter', (
      WidgetTester tester,
    ) async {
      await pump(tester, file: _file(pad: pad), contentWidth: 3000);
      final ScrollableState sideways = tester.state<ScrollableState>(
        find.byWidgetPredicate(
          (Widget w) =>
              w is Scrollable && w.axisDirection == AxisDirection.right,
        ),
      );
      sideways.position.jumpTo(kDiffGutterWidth * 3);
      await tester.pump();

      final double x = viewport(tester).left + 200;
      final TestGesture gesture = await press(
        tester,
        Offset(x, rowRect(tester, 3).center.dy),
      );
      await hold(tester, gesture, below(tester, x));
      final int end = visibleRows(tester).last;
      await gesture.moveTo(Offset(x, rowRect(tester, end).center.dy));
      await tester.pump();
      await release(tester, gesture);

      await submitByKeyboardPath(tester);
      expect(stageCalls.single.lines, _changedBetween(3, end));
    });

    // `2 file`'s right column: its own `GbmCodeHScroll`, not the pane's.
    testWidgets('in 2 file, the right-hand view', (WidgetTester tester) async {
      final ScrollController left = ScrollController();
      addTearDown(left.dispose);
      await pumpGbmWidget(
        tester,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 1000,
            height: 300,
            child: Row(
              children: <Widget>[
                Expanded(
                  child: ScopedDiffView(
                    softWrap: false,
                    verticalController: left,
                    sources: <ScopedDiffSource>[unstagedSource(_file())],
                  ),
                ),
                Expanded(
                  child: ScopedDiffView(
                    softWrap: false,
                    verticalController: vertical,
                    onTemporaryScopeChanged: (void Function()? s) => submit = s,
                    sources: <ScopedDiffSource>[stagedSource(_file())],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      final Rect right = tester.getRect(find.byType(ScopedDiffView).last);
      double rowY(int row) => builtRows(tester)
          .firstWhere(((Rect, int) r) => r.$2 == row && r.$1.left >= right.left)
          .$1
          .center
          .dy;
      int lastVisibleRight() => builtRows(tester)
          .where(
            ((Rect, int) r) =>
                r.$1.left >= right.left && r.$1.bottom <= right.bottom,
          )
          .last
          .$2;

      final double x = right.left + kDiffGutterWidth + 30;
      final TestGesture gesture = await press(tester, Offset(x, rowY(3)));
      await hold(tester, gesture, Offset(x, right.bottom + 3000));
      expect(left.offset, 0, reason: 'only the right column scrolled');
      final int end = lastVisibleRight();
      await gesture.moveTo(Offset(x, rowY(end)));
      await tester.pump();
      await release(tester, gesture);

      await submitByKeyboardPath(tester);
      expect(unstageCalls.single.lines, _changedBetween(3, end));
      expect(stageCalls, isEmpty);
    });
  });

  testWidgets('L3-n: with a sideways scrollbar under the rows, a release '
      'below the view ends at the bottom edge, not the list end', (
    WidgetTester tester,
  ) async {
    await pump(tester, file: _file(pad: ' ${'x' * 400}'), contentWidth: 4000);
    final Offset start = textOf(tester, 3);
    final TestGesture gesture = await press(tester, start);
    await hold(tester, gesture, below(tester, start.dx), frames: 60);
    final int end = rowAtBottomEdge(tester);
    await release(tester, gesture);

    await submitByKeyboardPath(tester);
    expect(stageCalls.single.lines, _changedBetween(3, end));
    expect(end, lessThan(110), reason: 'the list end would be row 119');
  });

  testWidgets('L3-k: a diff swapped mid-drag leaves no range behind', (
    WidgetTester tester,
  ) async {
    await pump(tester);
    final Offset start = textOf(tester, 3);
    final TestGesture gesture = await press(tester, start);
    await hold(tester, gesture, below(tester, start.dx), frames: 30);
    await pump(tester, file: _file());
    await hold(tester, gesture, below(tester, start.dx), frames: 10);
    final int end = visibleRows(tester).last;
    await gesture.moveTo(textOf(tester, end));
    await tester.pump();
    await release(tester, gesture);

    expect(
      find.byKey(const ValueKey<String>('temporary-scope-card')),
      findsNothing,
    );
    expect(submit, isNull, reason: 'no submitter for Ctrl/Cmd+Alt+S either');
  });

  // 使用者裁定（2026-10-25）「長距離拖曳後 => 改」→ sticky head; design:
  // docs/claude-design-demo/wc-sticky-temp-head-spec.html. While the
  // one-shot block runs past the top of the view with its head above it,
  // a copy of the head is pinned there; it is the same press.
  group('the one-shot head pinned to the top', () {
    final Finder sticky = find.byKey(
      const ValueKey<String>('temporary-scope-sticky'),
    );
    Finder stickyButton() => find.descendant(
      of: sticky,
      matching: find.textContaining(RegExp('^Stage ')),
    );

    testWidgets('after a long drag it sits at the top, between the block '
        'edges, and stages the same range', (WidgetTester tester) async {
      await pump(tester);
      final Offset start = textOf(tester, 3);
      final TestGesture gesture = await press(tester, start);
      await hold(tester, gesture, below(tester, start.dx), frames: 60);
      expect(sticky, findsNothing, reason: 'no block while the drag runs');
      final int end = visibleRows(tester).last;
      await gesture.moveTo(textOf(tester, end));
      await tester.pump();
      await release(tester, gesture);
      // One frame after the block: the head is measured once laid out.
      await tester.pump();
      expect(tester.takeException(), isNull);

      expect(sticky, findsOneWidget);
      final Rect view = viewport(tester);
      final Rect head = tester.getRect(sticky);
      expect(head.top, view.top);
      // 8 margin + 8 padding + 1 border + the card's 3px left edge; on the
      // right the same 17 and the card's 1px ring (no ruler: excerpt mode).
      expect(head.left - view.left, 20);
      expect(view.right - head.right, 18);
      expect(oneShotButton('Stage'), findsNothing, reason: 'one button only');

      await tester.tap(stickyButton());
      await tester.pump();
      expectOneCall(stageCalls, _changedBetween(3, end));
    });

    testWidgets('with the ruler, it stops short of it', (
      WidgetTester tester,
    ) async {
      final List<DiffFillRow> fill = <DiffFillRow>[
        for (int l = 121; l <= 130; l++)
          (
            sourceIndex: 0,
            indexLine: l,
            line: DiffLine(
              kind: DiffLineKind.context,
              oldLine: l,
              newLine: l,
              text: 'fill $l',
            ),
          ),
      ];
      await pump(tester, fill: fill);
      expect(
        find.byKey(const ValueKey<String>('diff-overview-ruler')),
        findsOneWidget,
      );
      await overdragDown(tester, 3, frames: 60);
      await tester.pump();
      final Rect view = viewport(tester);
      // 17 + the ruler's 14 + the card's 1px ring.
      expect(view.right - tester.getRect(sticky).right, 32);
    });

    // verifier F1: a new drag begun while an older scope's copy is up left
    // the copy -- and its button, bound to the old scope -- on screen until
    // the release.
    for (final bool autoscroll in const <bool>[false, true]) {
      testWidgets('gone while a new drag runs '
          '(${autoscroll ? 'autoscrolling' : 'in place'})', (
        WidgetTester tester,
      ) async {
        await pump(tester);
        await overdragDown(tester, 3, frames: 60);
        await tester.pump();
        expect(sticky, findsOneWidget);

        final int row = visibleRows(tester)[3];
        final TestGesture gesture = await press(tester, textOf(tester, row));
        await gesture.moveTo(
          autoscroll
              // Upward: the view walks back through the old block with its
              // head still above, where the old scope would pin it again.
              ? above(tester, textOf(tester, row).dx)
              : textOf(tester, visibleRows(tester)[5]),
        );
        for (int i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          expect(sticky, findsNothing, reason: 'frame $i of the new drag');
        }
        await release(tester, gesture);
      });
    }

    // 使用者裁定（2026-10-25）「對齊 block 實際位置」: with code wider than
    // the view the real head runs to the content's edge and scrolls
    // sideways, so a copy fixed at 20 / 18 left a strip of it showing on
    // either side. The copy now spans the block as it lies on screen,
    // clipped to the view, and draws a dashed side only where the block's
    // own edge is on screen.
    group('code wider than the view', () {
      Future<void> pinAfterScrollingSideways(
        WidgetTester tester,
        double dx, {
        DiffFile? file,
      }) async {
        await pump(tester, file: file, contentWidth: 1200);
        final TestGesture gesture = await press(tester, textOf(tester, 3));
        await gesture.moveTo(textOf(tester, 5));
        await tester.pump();
        await release(tester, gesture);
        final double headTop =
            tester
                .getRect(
                  find.descendant(
                    of: find.byKey(
                      const ValueKey<String>('temporary-scope-card'),
                    ),
                    matching: find.text('臨時選取'),
                  ),
                )
                .top -
            viewport(tester).top;
        vertical.jumpTo(vertical.offset + headTop + 1);
        await tester.pump();
        await tester.pump();
        tester
            .state<ScrollableState>(
              find
                  .byWidgetPredicate(
                    (Widget w) =>
                        w is Scrollable &&
                        w.axisDirection == AxisDirection.right,
                  )
                  .first,
            )
            .position
            .jumpTo(dx);
        await tester.pump();
        await tester.pump();
        expect(sticky, findsOneWidget);
      }

      int dashedSides(WidgetTester tester) => tester
          .widgetList<GbmDashedLine>(
            find.descendant(of: sticky, matching: find.byType(GbmDashedLine)),
          )
          .where((GbmDashedLine l) => l.axis == Axis.vertical)
          .length;

      // (sideways offset, left inset, right inset, dashed sides drawn): the
      // content is 1200 wide in a 500 view, so the block spans content x
      // 20..1182 and is on screen at 20 - dx .. 1182 - dx. A block running
      // past the right edge stops 10 short of it, clear of the vertical
      // scrollbar (使用者裁定「右緣留出捲軸的寬度」).
      for (final (double, double, double, int) c
          in const <(double, double, double, int)>[
            (0, 20, 10, 1),
            (60, 0, 10, 0),
            // The block's edge at 496 lies under the scrollbar: cut there.
            (686, 0, 10, 0),
            (700, 0, 18, 1),
          ]) {
        testWidgets('scrolled ${c.$1}: insets ${c.$2} / ${c.$3}, '
            '${c.$4} dashed side(s)', (WidgetTester tester) async {
          await pinAfterScrollingSideways(tester, c.$1);
          final Rect view = viewport(tester);
          final Rect head = tester.getRect(sticky);
          expect(head.left - view.left, c.$2);
          expect(view.right - head.right, c.$3);
          expect(dashedSides(tester), c.$4);
          // The real block's own box, cut to the view, is what it covers.
          final Rect block = tester
              .getRect(
                find.byKey(const ValueKey<String>('temporary-scope-card')),
              )
              .intersect(view);
          expect(head.left, block.left);
          expect(head.right, math.min(block.right, view.right - 10));
          // The scrollbar's strip is not the copy's to take.
          final RenderObject copy = tester.renderObject(sticky);
          expect(
            tester
                .hitTestOnBinding(Offset(view.right - 4, head.center.dy))
                .path
                .any((HitTestEntry e) => e.target == copy),
            isFalse,
          );
        });
      }

      // Running to the view's edge, the copy reaches under the ruler; the
      // real head lies under it too, so the ruler stays on top and
      // pressable.
      testWidgets('the ruler stays above it', (WidgetTester tester) async {
        await pump(
          tester,
          contentWidth: 1200,
          fill: <DiffFillRow>[
            for (int l = 121; l <= 130; l++)
              (
                sourceIndex: 0,
                indexLine: l,
                line: DiffLine(
                  kind: DiffLineKind.context,
                  oldLine: l,
                  newLine: l,
                  text: 'fill $l',
                ),
              ),
          ],
        );
        await overdragDown(tester, 3, frames: 60);
        await tester.pump();
        expect(sticky, findsOneWidget);
        final Finder ruler = find.byKey(
          const ValueKey<String>('diff-overview-ruler'),
        );
        final Rect r = tester.getRect(ruler);
        expect(
          tester.getRect(sticky).overlaps(r),
          isTrue,
          reason: 'the premise: the copy reaches under the ruler',
        );
        final HitTestResult hit = tester.hitTestOnBinding(
          Offset(r.center.dx, tester.getRect(sticky).bottom - 2),
        );
        final RenderObject rulerBox = tester.renderObject(ruler);
        expect(hit.path.any((HitTestEntry e) => e.target == rulerBox), isTrue);
      });

      // A wider view lowers the sideways maximum, and the offset is clamped
      // to it without a scroll notification -- only a metrics one.
      testWidgets('a resize that clamps the sideways offset is followed', (
        WidgetTester tester,
      ) async {
        // One file: a new DiffFile is a new diff, and drops the selection.
        final DiffFile file = _file();
        await pinAfterScrollingSideways(tester, 700, file: file);
        await pump(tester, file: file, contentWidth: 1200, width: 800);
        await tester.pump();
        final Rect view = viewport(tester);
        final Rect block = tester
            .getRect(find.byKey(const ValueKey<String>('temporary-scope-card')))
            .intersect(view);
        expect(tester.getRect(sticky).left, block.left);
        expect(tester.getRect(sticky).right, block.right);
        expect(view.right - block.right, 18, reason: 'the premise: clamped');
      });

      testWidgets('code that fits keeps both dashed sides', (
        WidgetTester tester,
      ) async {
        await pump(tester);
        await overdragDown(tester, 3, frames: 60);
        await tester.pump();
        expect(dashedSides(tester), 2);
      });
    });

    testWidgets('gone once the real head is back on screen', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      await overdragDown(tester, 3, frames: 60);
      await tester.pump();
      expect(sticky, findsOneWidget);

      vertical.jumpTo(0);
      await tester.pump();
      await tester.pump();
      expect(sticky, findsNothing);
      expect(oneShotButton('Stage'), findsOneWidget);
    });

    testWidgets('gone once the whole block is above the top', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      final TestGesture gesture = await press(tester, textOf(tester, 3));
      await gesture.moveTo(textOf(tester, 5));
      await tester.pump();
      await release(tester, gesture);
      expect(oneShotButton('Stage'), findsOneWidget);

      vertical.jumpTo(vertical.position.maxScrollExtent / 2);
      await tester.pump();
      await tester.pump();
      expect(sticky, findsNothing);
    });

    testWidgets('a scroll that puts the head just above the top pins it', (
      WidgetTester tester,
    ) async {
      await pump(tester);
      final TestGesture gesture = await press(tester, textOf(tester, 3));
      await gesture.moveTo(textOf(tester, 5));
      await tester.pump();
      await release(tester, gesture);
      // The label, not the block: the block's box starts 4px above its
      // head (its margin sits inside the dashed outline).
      final Finder label = find.descendant(
        of: find.byKey(const ValueKey<String>('temporary-scope-card')),
        matching: find.text('臨時選取'),
      );
      final double headTop = tester.getRect(label).top - viewport(tester).top;

      vertical.jumpTo(vertical.offset + headTop + 1);
      await tester.pump();
      await tester.pump();
      expect(sticky, findsOneWidget);
    });
  });
}
