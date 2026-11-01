// Plan: Slice H. Each segment's first code row sits at the same height in
// both `2 file` columns: whatever a column draws above it -- a card's head,
// a hunk's `@@` heading, a one-shot block's head -- the other column pads
// at the segment's start (使用者回報「變更1變更2等等那行，也需要留空行」,
// ruled 「所有非程式碼列」).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_slot_heights.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_slot_spacer.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_diff_pane.dart';

import '../../../support/full_file_diffs.dart';
import '../../../support/pump_app.dart';

Future<void> _pump(
  WidgetTester tester, {
  required Set<int> unstagedEdits,
  required Set<int> stagedEdits,
  bool fullFile = false,
}) async {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpGbmWidget(
    tester,
    child: WorkingCopyDiffPane(
      softWrap: false,
      displayPath: 'lib/a.dart',
      unstagedFile: replacementsDiff(40, unstagedEdits, context: 3),
      stagedFile: replacementsDiff(40, stagedEdits, context: 3),
      unstagedFullFile: replacementsDiff(
        40,
        unstagedEdits,
        context: kAllContext,
      ),
      stagedFullFile: replacementsDiff(40, stagedEdits, context: kAllContext),
      fullFile: fullFile,
      unstagedLoading: false,
      stagedLoading: false,
      onStageScope: (_, _, _) {},
      onDiscardScope: (_, _) {},
      onTemporaryScopeChanged: (_) {},
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

Finder _row(int column, String text) => find.descendant(
  of: _view(column),
  matching: find.text(text, findRichText: true),
);

void _expectLevel(WidgetTester tester, String text, {String reason = ''}) {
  expect(
    tester.getRect(_row(1, text)).top,
    moreOrLessEquals(tester.getRect(_row(0, text)).top, epsilon: 0.5),
    reason: '$reason $text',
  );
}

SyncSlotHeights _heights(WidgetTester tester) =>
    tester.widget<ScopedDiffView>(_view(0)).sync!.heights;

/// Selects from [from]'s row to [to]'s in [column] with the mouse, without
/// scrolling, and lets the one-shot block appear.
Future<void> _select(
  WidgetTester tester,
  int column,
  String from,
  String to,
) async {
  final Rect a = tester.getRect(_row(column, from));
  final Rect b = tester.getRect(_row(column, to));
  final TestGesture gesture = await tester.startGesture(
    a.centerLeft + const Offset(1, 0),
    kind: PointerDeviceKind.mouse,
  );
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(b.centerRight - const Offset(1, 0));
  await tester.pump();
  await gesture.up();
  await _settle(tester);
}

Finder _oneShot(int column) => find.descendant(
  of: _view(column),
  matching: find.byKey(const ValueKey<String>('temporary-scope-card')),
);

void main() {
  // Excerpts. Unstaged replaces 10 and 16 (one hunk, 7..19); staged
  // replaces 13 (its hunk 10..16). The segment unstaged opens with its card
  // at 10 opens in staged with that hunk's `@@` heading and then its gap
  // row L10: the heading is drawn in one column only.
  const Set<int> headingUnstaged = <int>{10, 16};
  const Set<int> headingStaged = <int>{13};

  testWidgets('a hunk heading in one column only: the segment\'s first code '
      'row is level in both', (WidgetTester tester) async {
    await _pump(
      tester,
      unstagedEdits: headingUnstaged,
      stagedEdits: headingStaged,
    );
    _expectLevel(tester, 'L10');
  });

  // The start spacer is its own item, so what it pads cannot move the lead
  // it is padded for (plan: Slice H, HB2): the heights settle and stay.
  testWidgets('different leads settle: no further notification, the start '
      'pads unchanged', (WidgetTester tester) async {
    await _pump(
      tester,
      unstagedEdits: headingUnstaged,
      stagedEdits: headingStaged,
    );
    final SyncSlotHeights heights = _heights(tester);
    List<double> pads() => <double>[
      for (int k = 0; k < heights.segmentCount; k++)
        for (int c = 0; c < 2; c++) heights.topPad(c, k),
    ];
    final List<double> before = pads();
    expect(before.any((double p) => p > 1), isTrue, reason: 'leads differ');
    int notified = 0;
    void count() => notified++;
    heights.addListener(count);
    addTearDown(() => heights.removeListener(count));
    for (int i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(notified, 0);
    expect(pads(), before);
  });

  // Segment 0 holds only the leading items and their spacer (plan: Slice
  // H, HB3); every later segment opens with a start spacer.
  testWidgets('no start spacer in segment 0, one in every later segment', (
    WidgetTester tester,
  ) async {
    await _pump(
      tester,
      unstagedEdits: headingUnstaged,
      stagedEdits: headingStaged,
    );
    for (int c = 0; c < 2; c++) {
      final List<int> starts = <int>[
        for (final SyncSlotSpacer s in tester.widgetList<SyncSlotSpacer>(
          find.descendant(of: _view(c), matching: find.byType(SyncSlotSpacer)),
        ))
          if (s.atStart) s.segment,
      ];
      expect(starts, isNot(contains(0)), reason: 'column $c');
      expect(starts..sort(), <int>[
        for (int k = 1; k < _heights(tester).segmentCount; k++) k,
      ], reason: 'column $c');
    }
  });

  // Full file. Unstaged replaces 10..12, one card of six rows; staged has
  // nothing there, so its fill rows 10..12 share the card's segment.
  const Set<int> cardUnstaged = <int>{10, 11, 12};
  const Set<int> cardStaged = <int>{30};

  // The one-shot block's head sits between the card's head and its first
  // selected row (plan: Slice H, HB4).
  testWidgets('a selection from a card\'s first row: its one-shot head is '
      'padded beside it too', (WidgetTester tester) async {
    await _pump(
      tester,
      unstagedEdits: cardUnstaged,
      stagedEdits: cardStaged,
      fullFile: true,
    );
    _expectLevel(tester, 'L10', reason: 'before');
    await _select(tester, 0, 'L10', 'edited L10');
    expect(_oneShot(0), findsOneWidget);
    _expectLevel(tester, 'L10', reason: 'after');
  });

  // Two rows either way, so the card keeps its height and only its first
  // row moves: the report has to carry the lead alone.
  testWidgets('a selection of the same size moved to the card\'s first rows: '
      'only the lead changes, and it is padded', (WidgetTester tester) async {
    await _pump(
      tester,
      unstagedEdits: cardUnstaged,
      stagedEdits: cardStaged,
      fullFile: true,
    );
    await _select(tester, 0, 'L11', 'edited L11');
    expect(_oneShot(0), findsOneWidget);
    _expectLevel(tester, 'L10', reason: 'rows 3-4');
    final double cardBottom = tester.getRect(_row(0, 'edited L12')).bottom;
    await _select(tester, 0, 'L10', 'edited L10');
    expect(_oneShot(0), findsOneWidget);
    expect(
      tester.getRect(_row(0, 'edited L12')).bottom,
      moreOrLessEquals(cardBottom, epsilon: 0.5),
      reason: 'premise: the card kept its height',
    );
    _expectLevel(tester, 'L10', reason: 'rows 1-2');
  });
}
