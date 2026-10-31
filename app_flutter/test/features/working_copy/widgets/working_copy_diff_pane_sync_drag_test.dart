// Plan: Slice S, B5 (L3-s1..s4): a scrolled drag in a synced `2 file`
// column whose press or release lands on a segment's spacer. A spacer holds
// no row, so both its halves are the one boundary between the rows around
// it (E3), and a range across spacers takes the changed rows on either
// side and nothing from the spacers.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_slot_spacer.dart';
import 'package:gbm_flutter/features/diff/widgets/diff_line.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_diff_pane.dart';

import '../../../support/full_file_diffs.dart';
import '../../../support/pump_app.dart';

const int _lines = 300;

// Segments 11 and 151: the unstaged card is three or four replacements to
// staged's one, so the staged column pads them. Segment 200 is the mirror:
// staged's five replacements span unstaged's two cards at 200 and 202 (and
// the gap between them), so the unstaged column pads it, right below the
// changed rows of its card at 202 -- not below a gap.
const Set<int> _unstagedEdits = <int>{
  10, 11, 12, 150, 151, 152, 153, 200, 202, 280, //
};
const Set<int> _stagedEdits = <int>{11, 151, 199, 200, 201, 202, 203, 280};

typedef _Call = ({bool staged, int hunkIndex, List<int> lines});

late List<_Call> _calls;
late void Function()? _submit;

Future<void> _pump(WidgetTester tester, {int generation = 0}) async {
  _calls = <_Call>[];
  _submit = null;
  tester.view.physicalSize = const Size(900, 500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpGbmWidget(
    tester,
    child: WorkingCopyDiffPane(
      // A fresh pane per spend path, so each starts unscrolled.
      key: ValueKey<int>(generation),
      softWrap: false,
      displayPath: 'lib/a.dart',
      unstagedFile: replacementsDiff(_lines, _unstagedEdits, context: 0),
      stagedFile: replacementsDiff(_lines, _stagedEdits, context: 0),
      unstagedFullFile: null,
      stagedFullFile: null,
      fullFile: false,
      unstagedLoading: false,
      stagedLoading: false,
      onStageScope: (bool staged, int h, List<int> l) =>
          _calls.add((staged: staged, hunkIndex: h, lines: l)),
      onDiscardScope: (_, _) {},
      onTemporaryScopeChanged: (void Function()? s) => _submit = s,
      onToggleFullFile: () {},
    ),
  );
  await tester.tap(find.text('2 file'));
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _view(int column) => find.byType(ScopedDiffView).at(column);

Rect _viewport(WidgetTester tester, int column) => tester.getRect(
  find
      .descendant(
        of: _view(column),
        matching: find.byWidgetPredicate(
          (Widget w) =>
              w is Scrollable && w.axisDirection == AxisDirection.down,
        ),
      )
      .first,
);

DiffFile _file(WidgetTester tester, int column) {
  final WorkingCopyDiffPane pane = tester.widget(
    find.byType(WorkingCopyDiffPane),
  );
  return (column == 0 ? pane.unstagedFile : pane.stagedFile)!;
}

/// Every built row of [column] with its box, top to bottom.
List<(Rect, DiffLine)> _rows(WidgetTester tester, int column) =>
    <(Rect, DiffLine)>[
      for (final Element e
          in find
              .descendant(
                of: _view(column),
                matching: find.byType(DiffLineView),
              )
              .evaluate())
        (
          tester.getRect(find.byWidget(e.widget)),
          (e.widget as DiffLineView).line,
        ),
    ]..sort(
      ((Rect, DiffLine) a, (Rect, DiffLine) b) => a.$1.top.compareTo(b.$1.top),
    );

/// [column]'s spacer for the segment [line] (an index line number) ends,
/// with its box: the tallest one built below a row reading `L$line`.
Rect _spacerAfter(WidgetTester tester, int column, int line) {
  final double rowTop = _rows(
    tester,
    column,
  ).firstWhere(((Rect, DiffLine) r) => r.$2.text == 'L$line').$1.top;
  final List<Rect> spacers = <Rect>[
    for (final Element e
        in find
            .descendant(
              of: _view(column),
              matching: find.byType(SyncSlotSpacer),
            )
            .evaluate())
      tester.getRect(find.byWidget(e.widget)),
  ]..retainWhere((Rect r) => r.top > rowTop && r.height > 40);
  spacers.sort((Rect a, Rect b) => a.top.compareTo(b.top));
  return spacers.first;
}

/// Wheels [column] until [line]'s row is built and sits in the top quarter
/// of the view.
Future<void> _scrollTo(WidgetTester tester, int column, int line) async {
  final Rect view = _viewport(tester, column);
  final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(view.center));
  for (int i = 0; i < 40; i++) {
    final Iterable<(Rect, DiffLine)> row = _rows(
      tester,
      column,
    ).where(((Rect, DiffLine) r) => r.$2.text == 'L$line');
    if (row.isNotEmpty &&
        row.first.$1.top >= view.top &&
        row.first.$1.top <= view.top + view.height / 3) {
      return;
    }
    final double dy = row.isEmpty
        ? view.height / 2
        : row.first.$1.top - (view.top + view.height / 4);
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await _settle(tester);
  }
  throw StateError('L$line never reached');
}

/// The last changed row wholly on [column]'s screen.
(Rect, DiffLine) _lastChangedOnScreen(WidgetTester tester, int column) {
  final Rect view = _viewport(tester, column);
  return _rows(tester, column).lastWhere(
    ((Rect, DiffLine) r) =>
        r.$1.top >= view.top &&
        r.$1.bottom <= view.bottom &&
        r.$2.kind != DiffLineKind.context,
  );
}

/// The x of [column]'s code text.
double _textX(WidgetTester tester, int column) =>
    _viewport(tester, column).left + kDiffGutterWidth + 30;

/// The changed lines from [from] to [to] in paint order (both included),
/// as the calls the submit makes: one per hunk, the last hunk first.
List<_Call> _expected(DiffFile file, bool staged, DiffLine from, DiffLine to) {
  final List<(int, int, DiffLine)> order = <(int, int, DiffLine)>[
    for (int h = 0; h < file.hunks.length; h++)
      for (int i = 0; i < file.hunks[h].lines.length; i++)
        (h, i, file.hunks[h].lines[i]),
  ];
  int a = order.indexWhere(((int, int, DiffLine) e) => identical(e.$3, from));
  int b = order.indexWhere(((int, int, DiffLine) e) => identical(e.$3, to));
  expect(a, isNonNegative);
  expect(b, isNonNegative);
  if (a > b) (a, b) = (b, a);
  final Map<int, List<int>> byHunk = <int, List<int>>{};
  for (final (int h, int i, DiffLine line) in order.sublist(a, b + 1)) {
    if (line.kind == DiffLineKind.context) continue;
    (byHunk[h] ??= <int>[]).add(i);
  }
  return <_Call>[
    for (final int h in byHunk.keys.toList().reversed)
      (staged: staged, hunkIndex: h, lines: byHunk[h]!),
  ];
}

/// [_calls] equals [expected], call by call; a record's list field
/// compares by identity, so each is compared through its printed form.
void _expectCalls(List<_Call> expected) {
  expect(
    <String>[for (final _Call c in _calls) '$c'],
    <String>[for (final _Call c in expected) '$c'],
  );
}

Finder _oneShot(int column) => find.descendant(
  of: find.descendant(
    of: _view(column),
    matching: find.byKey(const ValueKey<String>('temporary-scope-card')),
  ),
  matching: find.textContaining(RegExp(r'^(Stage|Unstage) ')),
);

/// Taps [column]'s one-shot button: the block's own, or the pinned copy
/// of its head that covers it at the top of the view, whichever is on top;
/// brought on screen first when neither is.
Future<void> _tapOneShot(WidgetTester tester, int column) async {
  // The block sits in the range's first card, which a long range may have
  // scrolled out of the built rows.
  final TestPointer pointer = TestPointer(2, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(
    pointer.hover(_viewport(tester, column).center),
  );
  for (int i = 0; i < 40 && _oneShot(column).evaluate().isEmpty; i++) {
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -200)));
    await _settle(tester);
  }
  expect(_oneShot(column), findsOneWidget);
  Finder onTop() => find
      .descendant(
        of: find.descendant(
          of: _view(column),
          matching: find.byWidgetPredicate(
            (Widget w) =>
                w.key == const ValueKey<String>('temporary-scope-card') ||
                w.key == const ValueKey<String>('temporary-scope-sticky'),
          ),
        ),
        matching: find.textContaining(RegExp(r'^(Stage|Unstage) ')),
      )
      .hitTestable();
  if (onTop().evaluate().isEmpty) {
    await tester.ensureVisible(_oneShot(column));
    await _settle(tester);
  }
  await tester.tap(onTop().first);
  await tester.pump();
}

/// A scrolled drag on [column]: presses at [start], holds below the view
/// for [frames] of autoscroll, then releases where [end] says once the
/// autoscroll is done.
Future<void> _drag(
  WidgetTester tester,
  int column,
  Offset start,
  Offset Function() end, {
  int frames = 6,
}) async {
  final TestGesture gesture = await tester.startGesture(
    start,
    kind: PointerDeviceKind.mouse,
  );
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(
    Offset(start.dx, _viewport(tester, column).bottom + 400),
  );
  for (int i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  await gesture.moveTo(end());
  await tester.pump();
  await gesture.up();
  await tester.pump();
  await tester.pump();
}

enum _Path { submitter, button, shiftDownThenButton }

/// A gesture on a freshly pumped pane, returning the calls its range should
/// make and the calls once Shift+Down has grown it by one row.
typedef _Gesture = Future<(List<_Call>, List<_Call>)> Function();

/// Runs [gesture] once per path [column] spends a range by -- the
/// published submitter Ctrl/Cmd+Alt+S calls (the unstaged column only: the
/// staged one publishes none), the one-shot button, and Shift+Down then
/// the button -- on a fresh pane each time, since spending clears the
/// selection Shift+Down would grow.
Future<void> _everyPath(
  WidgetTester tester,
  int column,
  _Gesture gesture,
) async {
  int generation = 0;
  for (final _Path path in _Path.values) {
    if (path == _Path.submitter && column != 0) continue;
    await _pump(tester, generation: generation++);
    final (List<_Call> expected, List<_Call> grown) = await gesture();
    _calls.clear();
    switch (path) {
      case _Path.submitter:
        expect(_submit, isNotNull);
        _submit!();
        await tester.pump();
        _expectCalls(expected);
      case _Path.button:
        await _tapOneShot(tester, column);
        _expectCalls(expected);
      case _Path.shiftDownThenButton:
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
        await _settle(tester);
        await _tapOneShot(tester, column);
        _expectCalls(grown);
    }
  }
}

/// [line]'s index in [file]'s paint order.
int _paintIndex(DiffFile file, DiffLine line) =>
    <DiffLine>[for (final DiffHunk hunk in file.hunks) ...hunk.lines]
        .indexWhere((DiffLine l) => identical(l, line));

/// The row after [line] in [file]'s paint order: the next line of its
/// hunk, or the first of the next hunk. Shift+Down grows a range by this
/// row, which adds a changed line only when it is one; on the last row it
/// has nowhere to go, and [line] itself is returned.
DiffLine _nextRow(DiffFile file, DiffLine line) {
  bool past = false;
  for (final DiffHunk hunk in file.hunks) {
    for (final DiffLine l in hunk.lines) {
      if (past) return l;
      if (identical(l, line)) past = true;
    }
  }
  expect(past, isTrue, reason: '${line.text} is in the file');
  return line;
}

void main() {
  // (column, the index line its padded segment's card starts at). With no
  // context lines, the rows on both sides of every spacer are changed
  // ones, so a range that took one row too many or too few on a spacer
  // changes the payload.
  const List<(int, int)> cases = <(int, int)>[(1, 11), (0, 200)];
  for (final (int column, int line) in cases) {
    for (final (String half, double at) in <(String, double)>[
      ('upper', 0.25),
      ('lower', 0.75),
    ]) {
      testWidgets('L3-s1/s2 column $column: a press on the $half half of a '
          'spacer starts at the row after it', (WidgetTester tester) async {
        await _everyPath(tester, column, () async {
          await _scrollTo(tester, column, line);
          final Rect spacer = _spacerAfter(tester, column, line);
          // The row after the spacer, in paint order: it may not be built
          // (a gap can follow the card), so it is read off the file.
          final DiffLine first = _nextRow(
            _file(tester, column),
            _rows(
              tester,
              column,
            ).lastWhere(((Rect, DiffLine) r) => r.$1.bottom <= spacer.top).$2,
          );
          late DiffLine last;
          await _drag(
            tester,
            column,
            Offset(_textX(tester, column), spacer.top + spacer.height * at),
            () {
              final (Rect, DiffLine) row = _lastChangedOnScreen(tester, column);
              last = row.$2;
              return Offset(_textX(tester, column), row.$1.center.dy);
            },
            frames: 20,
          );
          // Premise: the autoscroll carried the range past the spacer, so
          // the release is below the press and the range runs down.
          expect(
            _paintIndex(_file(tester, column), last),
            greaterThanOrEqualTo(_paintIndex(_file(tester, column), first)),
          );
          final DiffFile file = _file(tester, column);
          return (
            _expected(file, column == 1, first, last),
            _expected(file, column == 1, first, _nextRow(file, last)),
          );
        });
      });
    }

    testWidgets('L3-s3 column $column: a release on a mid-list spacer ends at '
        'the row before it', (WidgetTester tester) async {
      await _everyPath(tester, column, () async {
        await _scrollTo(tester, column, line);
        final (Rect, DiffLine) start = _rows(
          tester,
          column,
        ).firstWhere(((Rect, DiffLine) r) => r.$2.text == 'L$line');
        late DiffLine last;
        await _drag(
          tester,
          column,
          Offset(_textX(tester, column), start.$1.center.dy),
          () {
            final Rect spacer = _spacerAfter(tester, column, line);
            expect(
              spacer.center.dy,
              lessThan(_viewport(tester, column).bottom),
              reason: 'the spacer is still on screen to release on',
            );
            last = _rows(
              tester,
              column,
            ).lastWhere(((Rect, DiffLine) r) => r.$1.bottom <= spacer.top).$2;
            return Offset(_textX(tester, column), spacer.center.dy);
          },
          frames: 2,
        );
        final DiffFile file = _file(tester, column);
        return (
          _expected(file, column == 1, start.$2, last),
          _expected(file, column == 1, start.$2, _nextRow(file, last)),
        );
      });
    });
  }

  testWidgets('L3-s4: a range across two spacers takes the changed rows on '
      'every side of them', (WidgetTester tester) async {
    await _everyPath(tester, 1, () async {
      // In the staged column, segment 11's card (the unstaged one covers
      // 10..12) and segment 151's (150..153) are both padded.
      final (Rect, DiffLine) start = _rows(
        tester,
        1,
      ).firstWhere(((Rect, DiffLine) r) => r.$2.text == 'L11');
      late DiffLine last;
      await _drag(tester, 1, Offset(_textX(tester, 1), start.$1.center.dy), () {
        final (Rect, DiffLine) row = _lastChangedOnScreen(tester, 1);
        last = row.$2;
        return Offset(_textX(tester, 1), row.$1.center.dy);
      }, frames: 30);
      final DiffFile file = _file(tester, 1);
      final List<_Call> expected = _expected(file, true, start.$2, last);
      // Premise: the range runs through at least two padded segments.
      expect(expected.length, greaterThanOrEqualTo(2));
      return (expected, _expected(file, true, start.$2, _nextRow(file, last)));
    });
  });
}
