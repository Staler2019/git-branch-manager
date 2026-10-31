// Slice S4: the `2 file` columns scroll together. Every segment starts at
// the same height in both (S3), so the follower takes the leader's pixel
// offset, clamped to its own extent; the leader is whichever column the
// user (or a programmatic jump) last moved, and it is never moved by the
// mirror (plan: Slice S, B3/E2/F3/F4).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_scroll_controller.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_slot_spacer.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_diff_pane.dart';

import '../../../support/full_file_diffs.dart';
import '../../../support/pump_app.dart';

const int _lines = 300;
const Set<int> _unstagedEdits = <int>{10, 11, 12, 150, 151, 152, 153, 280};
const Set<int> _stagedEdits = <int>{11, 151, 280};

Future<void> _pump(
  WidgetTester tester, {
  bool fullFile = true,
  bool softWrap = false,
  ScrollController? scrollController,
  Set<int> unstagedEdits = _unstagedEdits,
  Set<int> stagedEdits = _stagedEdits,
  Set<int> unstagedLong = const <int>{},
  int longBy = 300,
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
        unstagedEdits,
        context: 3,
        long: unstagedLong,
        longBy: longBy,
      ),
      stagedFile: replacementsDiff(_lines, stagedEdits, context: 3),
      unstagedFullFile: replacementsDiff(
        _lines,
        unstagedEdits,
        context: kAllContext,
        long: unstagedLong,
        longBy: longBy,
      ),
      stagedFullFile: replacementsDiff(
        _lines,
        stagedEdits,
        context: kAllContext,
      ),
      fullFile: fullFile,
      unstagedLoading: false,
      stagedLoading: false,
      scrollController: scrollController,
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

Finder _sidewaysOf(int column) => find.descendant(
  of: _view(column),
  matching: find.byWidgetPredicate(
    (Widget w) => w is Scrollable && w.axisDirection == AxisDirection.right,
  ),
);

ScrollPosition _sideways(WidgetTester tester, int column) =>
    tester.state<ScrollableState>(_sidewaysOf(column).first).position;

SyncScrollController _sideSync(WidgetTester tester) =>
    tester.widget<ScopedDiffView>(_view(0)).sync!.sideways!;

Future<void> _wheelSideways(WidgetTester tester, int column, double dx) async {
  // The view's centre: the vertical list is as wide as the content, so its
  // own centre can lie off the pane.
  final Offset at = tester.getCenter(_view(column));
  final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(at));
  await tester.sendEventToBinding(pointer.scroll(Offset(dx, 0)));
  await _settle(tester);
}

SyncScrollController _sync(WidgetTester tester) =>
    tester.widget<ScopedDiffView>(_view(0)).sync!.scroll!;

/// Both columns show the same segment at the same height: every spacer
/// built in both sits at the same height on screen.
void _expectAligned(WidgetTester tester) {
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
      reason: 'segment ${(e.widget as SyncSlotSpacer).segment}',
    );
  }
  expect(compared, greaterThan(0));
}

/// Whether [finder]'s first match lies inside [column]'s viewport.
bool _onScreen(WidgetTester tester, int column, Finder finder) {
  final Rect viewport = tester.getRect(_vertical(column));
  final Iterable<Element> found = find
      .descendant(of: _view(column), matching: finder)
      .evaluate();
  if (found.isEmpty) return false;
  final Rect r = tester.getRect(find.byWidget(found.first.widget).first);
  return r.top >= viewport.top - 0.5 && r.bottom <= viewport.bottom + 0.5;
}

Future<void> _wheel(WidgetTester tester, int column, double dy) async {
  final Offset at = tester.getCenter(_vertical(column));
  final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(at));
  await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
  await _settle(tester);
}

void main() {
  testWidgets('the wheel on the unstaged column moves the staged one to '
      'the same place, and never back', (WidgetTester tester) async {
    await _pump(tester);
    final SyncScrollController sync = _sync(tester);
    final int leaderBefore = sync.jumpCount(0);
    final int followerBefore = sync.jumpCount(1);
    await _wheel(tester, 0, 1200);

    expect(_position(tester, 0).pixels, greaterThan(500));
    expect(_position(tester, 1).pixels, _position(tester, 0).pixels);
    expect(sync.jumpCount(0) - leaderBefore, 0);
    expect(sync.jumpCount(1) - followerBefore, inInclusiveRange(1, 4));
    _expectAligned(tester);
  });

  testWidgets('the wheel on the staged column leads the other way', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    await _wheel(tester, 1, 900);
    expect(_position(tester, 1).pixels, greaterThan(400));
    expect(_position(tester, 0).pixels, _position(tester, 1).pixels);
    _expectAligned(tester);
  });

  testWidgets('dragging the leader by hand is never interrupted', (
    WidgetTester tester,
  ) async {
    await _pump(tester, softWrap: true);
    final SyncScrollController sync = _sync(tester);
    final int before = sync.jumpCount(0);
    final TestGesture drag = await tester.startGesture(
      tester.getCenter(_vertical(0)),
      kind: PointerDeviceKind.touch,
    );
    for (int i = 0; i < 10; i++) {
      await drag.moveBy(const Offset(0, -40));
      await tester.pump(const Duration(milliseconds: 16));
      expect(sync.jumpCount(0), before, reason: 'step $i');
      // Every frame, not only once it settles: the follower's mirror lands
      // with what it learned from the last correction.
      _expectAligned(tester);
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(_position(tester, 0).pixels, greaterThan(300));
    expect(_position(tester, 1).pixels, _position(tester, 0).pixels);
    _expectAligned(tester);
  });

  testWidgets('scrolled to its end, the leader stays there and the follower '
      'stops at its own end', (WidgetTester tester) async {
    await _pump(tester);
    final ScrollPosition leader = _position(tester, 0);
    final ScrollPosition follower = _position(tester, 1);
    // A jump past its end would bounce the follower back through a
    // ballistic settle, so it never goes there.
    double overshoot = 0;
    void watch() {
      final double past = follower.pixels - follower.maxScrollExtent;
      if (past > overshoot) overshoot = past;
    }

    follower.addListener(watch);
    addTearDown(() => follower.removeListener(watch));
    final int before = _sync(tester).jumpCount(0);
    // The first wheel's end is an estimate: the rows it builds on the way
    // are measured, and the extent grows. The second reaches the real end.
    await _wheel(tester, 0, 1e6);
    await _wheel(tester, 0, 1e6);
    expect(leader.pixels, leader.maxScrollExtent);
    expect(overshoot, lessThan(0.01));
    expect(
      follower.pixels,
      inInclusiveRange(follower.minScrollExtent, follower.maxScrollExtent),
    );
    await _settle(tester);
    expect(_sync(tester).jumpCount(0), before);
    expect(leader.pixels, leader.maxScrollExtent);
    _expectAligned(tester);
  });

  testWidgets('a pane opened at a stored offset brings the staged column '
      'along', (WidgetTester tester) async {
    final ScrollController stored = ScrollController(initialScrollOffset: 400);
    addTearDown(stored.dispose);
    await _pump(tester, scrollController: stored);
    expect(_position(tester, 0).pixels, 400);
    expect(_position(tester, 1).pixels, 400);
    _expectAligned(tester);
  });

  testWidgets('a ruler jump to a far card leaves both columns on its '
      'segment', (WidgetTester tester) async {
    await _pump(tester, softWrap: true);
    final Finder mark = find.descendant(
      of: _view(1),
      matching: find.byKey(const ValueKey<String>('ruler-mark-3')),
    );
    await tester.tap(mark);
    await _settle(tester);
    expect(_position(tester, 1).pixels, greaterThan(1000));
    expect(_position(tester, 0).pixels, _position(tester, 1).pixels);
    expect(
      find.descendant(
        of: _view(0),
        matching: find.text('edited L280', findRichText: true),
      ),
      findsOneWidget,
    );
    _expectAligned(tester);
  });

  testWidgets('soft wrap: heights measured above the view keep its content '
      'where it was once settled', (WidgetTester tester) async {
    await _pump(tester, softWrap: true);
    // A programmatic jump far down, past rows never built: everything above
    // is still on estimates until it is measured.
    _sync(tester).lead(0);
    _position(tester, 0).jumpTo(2000);
    await _settle(tester);
    _expectAligned(tester);
    expect(_position(tester, 1).pixels, _position(tester, 0).pixels);
  });
  testWidgets('dragging the leader\'s scrollbar thumb follows the pointer '
      'to the release', (WidgetTester tester) async {
    await _pump(tester, softWrap: true);
    final SyncScrollController sync = _sync(tester);
    final ScrollPosition leader = _position(tester, 0);
    final Rect bar = tester.getRect(_vertical(0));
    // A wheel tick first: a desktop scrollbar shows its thumb on a scroll.
    await _wheel(tester, 0, 1);
    final int before = sync.jumpCount(0);
    final TestGesture drag = await tester.startGesture(
      Offset(bar.right - 3, bar.top + 5),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    double last = leader.pixels;
    for (int i = 0; i < 10; i++) {
      await drag.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
      expect(sync.jumpCount(0), before, reason: 'step $i');
      expect(leader.pixels, greaterThan(last), reason: 'step $i');
      last = leader.pixels;
    }
    await drag.up();
    await _settle(tester);
    expect(sync.jumpCount(0), before);
    _expectAligned(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('a selection drag past the bottom edge autoscrolls the staged '
      'column to the end, uninterrupted, and leads', (
    WidgetTester tester,
  ) async {
    await _pump(tester);
    final SyncScrollController sync = _sync(tester);
    final ScrollPosition leader = _position(tester, 1);
    final int before = sync.jumpCount(1);
    final Rect viewport = tester.getRect(_vertical(1));
    final TestGesture drag = await tester.startGesture(
      tester.getCenter(
        find
            .descendant(
              of: _view(1),
              matching: find.text('L5', findRichText: true),
            )
            .first,
      ),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    await drag.moveTo(Offset(viewport.center.dx, viewport.bottom + 40));
    for (int i = 0; i < 400 && leader.pixels < leader.maxScrollExtent; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(leader.pixels, leader.maxScrollExtent);
    expect(sync.jumpCount(1), before);
    await drag.up();
    await _settle(tester);
    _expectAligned(tester);
  });

  testWidgets('with the splitter off centre, the column with more to scroll '
      'reaches its end and is never pulled back', (WidgetTester tester) async {
    await _pump(tester, softWrap: true);
    await tester.drag(
      find.byKey(const Key('gbm-split-divider-0')),
      const Offset(-200, 0),
    );
    await tester.pump(const Duration(milliseconds: 400));
    // The narrower column wraps taller: more to scroll.
    final int tall =
        _position(tester, 0).maxScrollExtent >
            _position(tester, 1).maxScrollExtent
        ? 0
        : 1;
    final SyncScrollController sync = _sync(tester);
    final int before = sync.jumpCount(tall);
    await _wheel(tester, tall, 1e6);
    await _wheel(tester, tall, 1e6);
    await _settle(tester);
    final ScrollPosition leader = _position(tester, tall);
    expect(leader.pixels, leader.maxScrollExtent);
    expect(sync.jumpCount(tall), before);
    final ScrollPosition other = _position(tester, 1 - tall);
    expect(
      other.pixels,
      inInclusiveRange(other.minScrollExtent, other.maxScrollExtent),
    );
    _expectAligned(tester);
  });

  // C2: excerpt mode's estimate-driven jump is Shift+↓'s, and here it has to
  // cross the staged column's padding of a forty-line unstaged card.
  testWidgets('excerpt mode: Shift+Down across a long spacer brings the row '
      'on screen in both columns', (WidgetTester tester) async {
    await _pump(
      tester,
      fullFile: false,
      unstagedEdits: <int>{for (int l = 100; l <= 140; l++) l, 200},
      stagedEdits: const <int>{120, 200},
    );
    final Finder target = find.text('edited L200', findRichText: true);
    expect(_onScreen(tester, 1, target), isFalse, reason: 'the premise');
    await tester.tapAt(
      tester.getCenter(
        find
            .descendant(
              of: _view(1),
              matching: find.text('edited L120', findRichText: true),
            )
            .first,
      ),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    // The unstaged column leads now; the focus stays in the staged one, so
    // Shift+Down has to take the lead back.
    await _wheel(tester, 0, 20);
    for (int i = 0; i < 12 && !_onScreen(tester, 1, target); i++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await _settle(tester);
    }
    expect(_onScreen(tester, 1, target), isTrue);
    expect(_onScreen(tester, 0, target), isTrue);
    _expectAligned(tester);
  });
  testWidgets('the lead changes hands: the staged column\'s wheel, then '
      'the unstaged one\'s', (WidgetTester tester) async {
    await _pump(tester);
    final SyncScrollController sync = _sync(tester);
    await _wheel(tester, 1, 600);
    final int unstaged = sync.jumpCount(0);
    final int staged = sync.jumpCount(1);
    expect(unstaged, greaterThan(0), reason: 'it followed first');
    await _wheel(tester, 0, 900);
    expect(sync.jumpCount(0), unstaged, reason: 'it leads now');
    expect(sync.jumpCount(1), greaterThan(staged), reason: 'it follows now');
    expect(_position(tester, 0).pixels, greaterThan(1400));
    _expectAligned(tester);
  });

  testWidgets('one programmatic jump to the leader\'s estimated end brings '
      'the follower there too', (WidgetTester tester) async {
    await _pump(tester);
    final ScrollPosition leader = _position(tester, 0);
    _sync(tester).lead(0);
    leader.jumpTo(leader.maxScrollExtent);
    // Measured rows shrink the leader's estimated extent under it, and it
    // slides back to its real end through a ballistic settle.
    await tester.pumpAndSettle();
    expect(leader.pixels, leader.maxScrollExtent);
    _expectAligned(tester);
  });

  testWidgets('soft wrap: a narrower window re-wraps both columns, and they '
      'stay in line without a scroll', (WidgetTester tester) async {
    await _pump(tester, softWrap: true);
    await _wheel(tester, 0, 1500);
    final SyncScrollController sync = _sync(tester);
    final int before = sync.jumpCount(0);
    tester.view.physicalSize = const Size(500, 500);
    await _settle(tester);
    expect(sync.jumpCount(0), before);
    _expectAligned(tester);
  });
  // A column still settling a fling is jumped once another column leads;
  // `jumpTo` ends its fling and reports an idle direction from it, which
  // must not hand the lead back -- mid-drag, the follower would stop
  // following.
  testWidgets('a drag on one column while the other still flings takes the '
      'lead and keeps it to the release', (WidgetTester tester) async {
    await _pump(tester);
    final SyncScrollController sync = _sync(tester);
    await tester.fling(_vertical(1), const Offset(0, -300), 2000);
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    expect(sync.leader, 1, reason: 'the premise');
    expect(
      _position(tester, 1).activity,
      isA<BallisticScrollActivity>(),
      reason: 'the premise',
    );
    final int before = sync.jumpCount(0);
    final TestGesture drag = await tester.startGesture(
      tester.getCenter(_vertical(0)),
      kind: PointerDeviceKind.touch,
    );
    for (int i = 0; i < 8; i++) {
      await drag.moveBy(const Offset(0, -30));
      await tester.pump(const Duration(milliseconds: 16));
      expect(sync.leader, 0, reason: 'step $i');
      expect(
        _position(tester, 1).pixels,
        _position(tester, 0).pixels,
        reason: 'step $i',
      );
    }
    await drag.up();
    await tester.pumpAndSettle();
    expect(sync.jumpCount(0), before);
    _expectAligned(tester);
  });

  // S5a: one width for both columns, the wider one's, and one sideways
  // offset (plan: Slice S, E1, 「以兩側最大寬度等像素位移」).
  testWidgets('both columns scroll as far sideways as the wider one', (
    WidgetTester tester,
  ) async {
    // Only the unstaged side's line 150 runs on; the staged excerpt holds a
    // short line 150 of its own.
    await _pump(tester, fullFile: false, unstagedLong: const <int>{150});
    expect(_sideways(tester, 0).maxScrollExtent, greaterThan(0));
    expect(
      _sideways(tester, 1).maxScrollExtent,
      _sideways(tester, 0).maxScrollExtent,
    );
  });

  testWidgets('a sideways wheel on the unstaged column moves the staged one '
      'by the same pixels, and never back', (WidgetTester tester) async {
    await _pump(tester, fullFile: false, unstagedLong: const <int>{150});
    final SyncScrollController sync = _sideSync(tester);
    final int before = sync.jumpCount(0);
    await _wheelSideways(tester, 0, 300);

    expect(_sideways(tester, 0).pixels, greaterThan(100));
    expect(_sideways(tester, 1).pixels, _sideways(tester, 0).pixels);
    expect(sync.jumpCount(0), before);
    // The vertical sync is a separate axis and stays where it was.
    expect(_position(tester, 0).pixels, 0);
  });

  testWidgets('a sideways wheel on the staged column leads the other way', (
    WidgetTester tester,
  ) async {
    await _pump(tester, fullFile: false, unstagedLong: const <int>{150});
    await _wheelSideways(tester, 1, 250);
    expect(_sideways(tester, 1).pixels, greaterThan(100));
    expect(_sideways(tester, 0).pixels, _sideways(tester, 1).pixels);
  });

  testWidgets('a column whose rows fit has no sideways scroller, and the '
      'other one still scrolls without it', (WidgetTester tester) async {
    await _pump(
      tester,
      fullFile: false,
      unstagedLong: const <int>{150},
      longBy: 30,
    );
    await tester.drag(
      find.byKey(const Key('gbm-split-divider-0')),
      const Offset(-250, 0),
    );
    await tester.pump(const Duration(milliseconds: 400));
    // Premise: the narrow column scrolls sideways, the wide one fits.
    expect(_sidewaysOf(0), findsOneWidget);
    expect(_sidewaysOf(1), findsNothing);

    await _wheelSideways(tester, 0, 200);
    expect(tester.takeException(), isNull);
    expect(_sideways(tester, 0).pixels, greaterThan(50));
  });
}
