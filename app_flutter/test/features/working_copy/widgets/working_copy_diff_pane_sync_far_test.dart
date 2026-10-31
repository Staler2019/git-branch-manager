// Slice S, verifier F1: once a far move settles, both `2 file` columns show
// the same segment. A far jump leaves the follower where the mirror put it,
// and its pixels mean a different place from the leader's once heights were
// measured; with no spacer built in both, the geometric correction has
// nothing to compare, so the follower first goes to the slot top of the
// segment the leader shows.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_scroll_controller.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_slot_spacer.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_diff_pane.dart';

import '../../../support/full_file_diffs.dart';
import '../../../support/pump_app.dart';

/// 5,000 lines, soft wrap on, every other unstaged edit 400 characters
/// longer: measured heights differ from the estimate, and differently in
/// the two columns.
const int _lines = 5000;
final Set<int> _un = <int>{
  for (int i = 5; i < _lines; i += 37) ...<int>{i, i + 1, i + 2},
};
final Set<int> _st = <int>{for (int i = 5; i < _lines; i += 111) i};
final Set<int> _long = <int>{
  for (final int i in _un)
    if (i % 2 == 0) i,
};

Future<void> _pump(
  WidgetTester tester, {
  bool softWrap = true,
  bool fullFile = true,
}) async {
  tester.view.physicalSize = const Size(900, 500);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await pumpGbmWidget(
    tester,
    child: WorkingCopyDiffPane(
      softWrap: softWrap,
      displayPath: 'lib/a.dart',
      unstagedFile: replacementsDiff(
        _lines,
        _un,
        context: 3,
        long: _long,
        longBy: 400,
      ),
      stagedFile: replacementsDiff(_lines, _st, context: 3),
      unstagedFullFile: replacementsDiff(
        _lines,
        _un,
        context: kAllContext,
        long: _long,
        longBy: 400,
      ),
      stagedFullFile: replacementsDiff(_lines, _st, context: kAllContext),
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
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Finder _view(int column) => find.byType(ScopedDiffView).at(column);
Finder _vertical(int column) => find
    .descendant(
      of: _view(column),
      matching: find.byWidgetPredicate(
        (Widget w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    )
    .first;
ScrollPosition _position(WidgetTester tester, int column) =>
    tester.state<ScrollableState>(_vertical(column)).position;
SyncScrollController _sync(WidgetTester tester) =>
    tester.widget<ScopedDiffView>(_view(0)).sync!.scroll!;

Map<int, double> _spacerBottoms(
  WidgetTester tester,
  int column,
) => <int, double>{
  for (final Element e
      in find
          .descendant(of: _view(column), matching: find.byType(SyncSlotSpacer))
          .evaluate())
    (e.widget as SyncSlotSpacer).segment: tester
        .getRect(find.byWidget(e.widget))
        .bottom,
};

/// Every segment end [leader] shows on screen, the follower shows at the
/// same height (verifier F1 showed two disjoint sets of segments). A
/// segment end off screen may differ by the follower's own estimate error
/// inside that segment, which settles once its rows are built.
/// Returns how many it compared.
int _expectAligned(WidgetTester tester, int leader) {
  final Rect viewport = tester.getRect(_vertical(leader));
  final Map<int, double> follower = _spacerBottoms(tester, 1 - leader);
  int compared = 0;
  for (final MapEntry<int, double> e in _spacerBottoms(
    tester,
    leader,
  ).entries) {
    if (e.value <= viewport.top || e.value >= viewport.bottom) continue;
    compared++;
    expect(
      follower[e.key],
      isNotNull,
      reason: 'segment ${e.key} ends on screen in the leader only',
    );
    expect(follower[e.key], closeTo(e.value, 0.5), reason: 'segment ${e.key}');
  }
  return compared;
}

Future<void> _wheel(WidgetTester tester, int column, double dy) async {
  final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(
    pointer.hover(tester.getCenter(_view(column))),
  );
  await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
  await _settle(tester);
}

void main() {
  for (final int lead in <int>[0, 1]) {
    testWidgets('column $lead jumped far and then to its end: both columns '
        'show the same segments once it settles', (WidgetTester tester) async {
      await _pump(tester);
      final SyncScrollController sync = _sync(tester);
      int compared = 0;
      // Twice: the second time every height is measured already, so no
      // batch of heights earns a correction; only the move itself does.
      for (final double at in <double>[.7, .2, .5, 1.0, .7, .2, .5, 1.0]) {
        sync.lead(lead);
        final ScrollPosition p = _position(tester, lead);
        p.jumpTo(p.maxScrollExtent * at);
        await _settle(tester);
        compared += _expectAligned(tester, lead);
      }
      expect(compared, greaterThan(0));
      expect(sync.jumpCount(lead), 0, reason: 'the leader is never jumped');
    });

    testWidgets('column $lead\'s scrollbar thumb dragged down, back and to '
        'the end: both columns show the same segments once it settles', (
      WidgetTester tester,
    ) async {
      await _pump(tester);
      await _wheel(tester, lead, 1);
      final Rect bar = tester.getRect(_view(lead));
      final TestGesture drag = await tester.startGesture(
        Offset(bar.right - 3, bar.top + 4),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      for (final double dy in <double>[300, -220, 130, 400]) {
        for (int i = 0; i < 4; i++) {
          await drag.moveBy(Offset(0, dy / 4));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(const Duration(milliseconds: 200));
      }
      await drag.up();
      await _settle(tester);
      expect(_expectAligned(tester, lead), greaterThan(0));
      expect(_sync(tester).jumpCount(lead), 0);
    }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
  }
}
