// Slice J: a far jump builds only the rows near where it lands, in unified
// and in both `2 file` columns, and a synced column seeds from the slot
// tops both columns share, so the two still meet segment for segment when
// the estimate is wrong (plan: Slice J, J2/JB3/JC1/JD1).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_scroll_controller.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_slot_spacer.dart';
import 'package:gbm_flutter/features/diff/widgets/diff_line.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_diff_pane.dart';
import 'package:gbm_flutter/widgets/seeded_sliver_list.dart';

import '../../../support/full_file_diffs.dart';
import '../../../support/pump_app.dart';

const int _lines = 5000;
const Set<int> _unstagedEdits = <int>{10, 11, 1200, 1201, 1202, 2600, 4100};
const Set<int> _stagedEdits = <int>{11, 1201, 3300, 4100};

Future<void> _pump(
  WidgetTester tester, {
  bool twoFile = true,
  bool softWrap = false,
  Set<int> unstagedEdits = _unstagedEdits,
  Set<int> stagedEdits = _stagedEdits,
  double textScale = 1,
  ScrollController? scrollController,
}) async {
  // Narrower with soft wrap on, so a row wraps in a `2 file` column.
  tester.view.physicalSize = Size(softWrap ? 700 : 900, 500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpGbmWidget(
    tester,
    child: Builder(
      builder: (BuildContext context) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: WorkingCopyDiffPane(
          softWrap: softWrap,
          displayPath: 'lib/a.dart',
          unstagedFile: replacementsDiff(_lines, unstagedEdits, context: 3),
          stagedFile: replacementsDiff(_lines, stagedEdits, context: 3),
          unstagedFullFile: replacementsDiff(
            _lines,
            unstagedEdits,
            context: kAllContext,
          ),
          stagedFullFile: replacementsDiff(
            _lines,
            stagedEdits,
            context: kAllContext,
          ),
          fullFile: true,
          unstagedLoading: false,
          stagedLoading: false,
          scrollController: scrollController,
          onStageScope: (_, _, _) {},
          onDiscardScope: (_, _) {},
          onTemporaryScopeChanged: (_) {},
          onToggleFullFile: () {},
        ),
      ),
    ),
  );
  if (twoFile) {
    await tester.tap(find.text('2 file'));
  }
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _view(int column) => find.byType(ScopedDiffView).at(column);

ScrollPosition _position(WidgetTester tester, int column) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: _view(column),
            matching: find.byWidgetPredicate(
              (Widget w) =>
                  w is Scrollable && w.axisDirection == AxisDirection.down,
            ),
          )
          .first,
    )
    .position;

SyncScrollController _sync(WidgetTester tester) =>
    tester.widget<ScopedDiffView>(_view(0)).sync!.scroll!;

int _seeds(WidgetTester tester, int column) => tester
    .renderObject<RenderSeededSliverList>(
      find.descendant(
        of: _view(column),
        matching: find.byType(SeededSliverList),
      ),
    )
    .seedCount;

/// How many [DiffLineView]s [action] builds, in every column, or only in
/// [column] when given.
Future<int> _rowsBuilt(
  WidgetTester tester,
  Future<void> Function() action, {
  int? column,
}) async {
  final ScopedDiffView? only = column == null
      ? null
      : tester.widget<ScopedDiffView>(_view(column));
  int rows = 0;
  debugOnRebuildDirtyWidget = (Element e, bool _) {
    if (e.widget is! DiffLineView) return;
    if (only != null &&
        !identical(e.findAncestorWidgetOfExactType<ScopedDiffView>(), only)) {
      return;
    }
    rows++;
  };
  try {
    await action();
  } finally {
    debugOnRebuildDirtyWidget = null;
  }
  return rows;
}

/// Every spacer built in both columns ends at the same height.
void _expectAligned(WidgetTester tester, {String reason = ''}) {
  final Map<int, Rect> left = <int, Rect>{};
  for (final Element e
      in find
          .descendant(of: _view(0), matching: find.byType(SyncSlotSpacer))
          .evaluate()) {
    left[(e.widget as SyncSlotSpacer).segment] = tester.getRect(
      find.byWidget(e.widget),
    );
  }
  int compared = 0;
  for (final Element e
      in find
          .descendant(of: _view(1), matching: find.byType(SyncSlotSpacer))
          .evaluate()) {
    final Rect? l = left[(e.widget as SyncSlotSpacer).segment];
    if (l == null) continue;
    compared++;
    expect(
      tester.getRect(find.byWidget(e.widget)).bottom,
      closeTo(l.bottom, 0.5),
      reason: '$reason segment ${(e.widget as SyncSlotSpacer).segment}',
    );
  }
  expect(compared, greaterThan(0), reason: reason);
}

Future<void> _wheel(WidgetTester tester, int column, double dy) async {
  final Offset at = tester.getCenter(_view(column));
  final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(at));
  await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
  await _settle(tester);
}

void main() {
  testWidgets('unified: a far jump builds only the rows near where it lands, '
      'forward and back', (WidgetTester tester) async {
    await _pump(tester, twoFile: false);
    final ScrollPosition p = _position(tester, 0);
    for (final double f in <double>[.25, .75, .1]) {
      final int rows = await _rowsBuilt(tester, () async {
        p.jumpTo(p.maxScrollExtent * f);
        await tester.pump();
      });
      expect(rows, lessThan(200), reason: 'jump to $f');
    }
    expect(_seeds(tester, 0), greaterThan(0));
  });

  testWidgets('2 file: a far jump builds only the rows near where it lands '
      'in both columns', (WidgetTester tester) async {
    await _pump(tester);
    await _wheel(tester, 0, 1);
    final ScrollPosition p = _position(tester, 0);
    for (final double f in <double>[.25, .75, .1]) {
      final int rows = await _rowsBuilt(tester, () async {
        p.jumpTo(p.maxScrollExtent * f);
        await tester.pump();
      });
      expect(rows, lessThan(200), reason: 'jump to $f, both columns');
    }
    expect(_seeds(tester, 0), greaterThan(0));
    expect(_seeds(tester, 1), greaterThan(0));
  });

  testWidgets('2 file: a far jump into a segment the other column fills with '
      'hundreds of rows builds only the follower\'s rows near where it lands', (
    WidgetTester tester,
  ) async {
    // Lines 1500..2499 replaced in unstaged only: one card there, a
    // thousand unchanged rows beside it in staged, all one segment.
    await _pump(
      tester,
      unstagedEdits: <int>{for (int n = 1500; n < 2500; n++) n},
    );
    await _wheel(tester, 0, 1);
    final ScrollPosition p = _position(tester, 0);
    final int rows = await _rowsBuilt(tester, () async {
      p.jumpTo(p.maxScrollExtent * .45);
      await tester.pump();
    }, column: 1);
    expect(rows, lessThan(200));
    expect(_seeds(tester, 1), greaterThan(0));
  });

  testWidgets('opening at a stored offset builds only the rows near it, and '
      'keeps the offset', (WidgetTester tester) async {
    final ScrollController stored = ScrollController(
      initialScrollOffset: 60000,
    );
    addTearDown(stored.dispose);
    final int rows = await _rowsBuilt(
      tester,
      () => _pump(tester, twoFile: false, scrollController: stored),
    );
    expect(rows, lessThan(200));
    expect(_position(tester, 0).pixels, 60000);
  });

  testWidgets('2 file at the test font: after a far jump the follower is '
      'jumped once, by the mirror, and never corrected', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await _wheel(tester, 0, 1);
    final SyncScrollController sync = _sync(tester);
    final int before = sync.jumpCount(1);
    final ScrollPosition p = _position(tester, 0);
    p.jumpTo(p.maxScrollExtent * .6);
    await _settle(tester);
    expect(sync.jumpCount(1) - before, 1);
    _expectAligned(tester);
  });

  testWidgets('2 file with every row taller than the estimate: after a far '
      'jump and five wheel steps the columns still meet, each step costing '
      'the follower at most four jumps', (WidgetTester tester) async {
    await _pump(tester, textScale: 1.3);
    // The premise: what is laid out is not what the model estimated (22).
    final double row = tester
        .getRect(
          find
              .descendant(of: _view(0), matching: find.byType(DiffLineView))
              .first,
        )
        .height;
    expect(row, greaterThan(25));

    await _wheel(tester, 0, 1);
    final ScrollPosition p = _position(tester, 0);
    p.jumpTo(p.maxScrollExtent * .5);
    await _settle(tester);
    expect(_seeds(tester, 0), greaterThan(0));
    _expectAligned(tester, reason: 'after the jump');

    final SyncScrollController sync = _sync(tester);
    for (int i = 0; i < 5; i++) {
      final int before = sync.jumpCount(1);
      await _wheel(tester, 0, 200);
      expect(
        sync.jumpCount(1) - before,
        inInclusiveRange(1, 4),
        reason: 'step $i',
      );
      _expectAligned(tester, reason: 'step $i');
    }
  });

  testWidgets('2 file with a measured segment the columns misjudge by '
      'different amounts: after a far jump below it both columns end at the '
      'same place and meet, the mirror the follower\'s only jump', (
    WidgetTester tester,
  ) async {
    // Lines 20..219 replaced in unstaged only, at 1.3x: one card of 400
    // rows beside 200 unchanged ones, all one segment, each column's rows
    // taller than estimated by a different total.
    await _pump(
      tester,
      textScale: 1.3,
      unstagedEdits: <int>{for (int n = 20; n < 220; n++) n},
      stagedEdits: <int>{4000},
    );
    final double row = tester
        .getRect(
          find
              .descendant(of: _view(1), matching: find.byType(DiffLineView))
              .first,
        )
        .height;
    expect(row, greaterThan(25), reason: 'the premise: taller than 22');
    // Through the segment in wheel steps, so both columns measure it.
    for (int i = 0; i < 16; i++) {
      await _wheel(tester, 0, 500);
    }
    // Any rebuild after the measuring -- a refresh, a hover -- rebuilds
    // each column's model from what it measured.
    for (int c = 0; c < 2; c++) {
      tester.element(_view(c)).markNeedsBuild();
    }
    await tester.pump();
    final SyncScrollController sync = _sync(tester);
    final int before = sync.jumpCount(1);
    final ScrollPosition p = _position(tester, 0);
    p.jumpTo(p.maxScrollExtent * .6);
    await _settle(tester);
    // Seeded by each model's own estimate, the two would differ by the
    // two columns' different errors above (about 1,200 px here).
    expect(
      _position(tester, 1).maxScrollExtent,
      closeTo(_position(tester, 0).maxScrollExtent, 0.5),
      reason: 'both columns end at the same place',
    );
    _expectAligned(tester);
    expect(sync.jumpCount(1) - before, 1);
    expect(_seeds(tester, 0), greaterThan(0));
  });

  for (final bool twoFile in <bool>[false, true]) {
    testWidgets('${twoFile ? '2 file' : 'unified'} with every row taller than '
        'the estimate: wheeling back up from a far jump reaches the top '
        'without running out of layout passes', (WidgetTester tester) async {
      await _pump(tester, twoFile: twoFile, textScale: 1.3);
      await _wheel(tester, 0, 1);
      _position(tester, 0).jumpTo(9000);
      await _settle(tester);
      expect(_seeds(tester, 0), greaterThan(0), reason: 'the premise');
      for (int guard = 0; _position(tester, 0).pixels > 0; guard++) {
        expect(guard, lessThan(200), reason: 'stuck');
        await _wheel(tester, 0, -300);
      }
      expect(tester.takeException(), isNull);
      final Rect top = tester.getRect(
        find
            .descendant(of: _view(0), matching: find.byType(DiffLineView))
            .first,
      );
      expect(top.top, greaterThan(tester.getRect(_view(0)).top));
    });
  }

  testWidgets('2 file with soft wrap: a jump to the end stays at the end '
      'while the rows there are measured taller', (WidgetTester tester) async {
    await _pump(tester, softWrap: true);
    await _wheel(tester, 0, 1);
    final ScrollPosition p = _position(tester, 0);
    p.jumpTo(p.maxScrollExtent);
    await _settle(tester);
    await tester.pumpAndSettle();
    expect(_seeds(tester, 0), greaterThan(0), reason: 'the premise');
    final ScrollPosition q = _position(tester, 0);
    expect(q.pixels, q.maxScrollExtent);
    double lowest = 0;
    for (final Element e
        in find
            .descendant(of: _view(0), matching: find.byType(DiffLineView))
            .evaluate()) {
      final Rect r = tester.getRect(find.byWidget(e.widget));
      if (r.bottom > lowest) lowest = r.bottom;
    }
    expect(lowest, lessThanOrEqualTo(tester.getRect(_view(0)).bottom));
    _expectAligned(tester);
  });
}
