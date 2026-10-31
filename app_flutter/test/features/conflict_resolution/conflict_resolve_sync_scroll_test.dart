// Slice S6: the conflict window's three columns (ours, result, theirs)
// scroll as one, the way `2 file`'s two do (S3-S5a): every segment pads to
// its tallest column, the column the user moves leads, and the others take
// its offset (plan: Slice S, 「三欄互跟」, B2/C1/D1/D2/E5).
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_conflict_file.dart';
import 'package:gbm_flutter/features/conflict_resolution/conflict_resolve_window.dart';
import 'package:gbm_flutter/features/conflict_resolution/conflict_sync_estimate.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_height_reporter.dart';
import 'package:gbm_flutter/features/diff/sync_scroll/sync_slot_spacer.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:gbm_flutter/widgets/gbm_code_hscroll.dart';

import '../../support/conflict_window_harness.dart';

/// Ten text-then-region pairs whose ours and theirs differ in length, so
/// every region pads one side, and a long tail after the last so revealing
/// it is not cut short at the end; about five times the columns' height.
ParsedConflictFile _tall({int longBy = 0, int pairs = 10}) {
  final List<ConflictSegment> segments = <ConflictSegment>[];
  for (int k = 0; k < pairs; k++) {
    segments
      ..add(conflictText(<String>[for (int i = 0; i < 8; i++) 'c${k}_$i']))
      ..add(
        conflictRegion(
          <String>[for (int i = 0; i < 2; i++) 'o${k}_$i${'x' * longBy}'],
          <String>[for (int i = 0; i < 6; i++) 't${k}_$i'],
        ),
      );
  }
  segments.add(conflictText(<String>[for (int i = 0; i < 40; i++) 'z$i']));
  return ParsedConflictFile(
    segments: segments,
    regionCount: pairs,
    wellFormed: true,
  );
}

Finder _column(int c) => find.byType(GbmCodeHScroll).at(c);

Finder _vertical(int c) => find
    .descendant(
      of: _column(c),
      matching: find.byWidgetPredicate(
        (Widget w) => w is Scrollable && w.axisDirection == AxisDirection.down,
      ),
    )
    .first;

ScrollPosition _position(WidgetTester tester, int c) =>
    tester.state<ScrollableState>(_vertical(c)).position;

ScrollPosition _sideways(WidgetTester tester, int c) => tester
    .state<ScrollableState>(
      find
          .descendant(
            of: _column(c),
            matching: find.byWidgetPredicate(
              (Widget w) =>
                  w is Scrollable && w.axisDirection == AxisDirection.right,
            ),
          )
          .first,
    )
    .position;

Future<void> _settle(WidgetTester tester) async {
  for (int i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _wheel(WidgetTester tester, int c, Offset delta) async {
  final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
  await tester.sendEventToBinding(pointer.hover(tester.getCenter(_column(c))));
  await tester.sendEventToBinding(pointer.scroll(delta));
  await _settle(tester);
}

/// Every spacer built in more than one column ends at the same height in
/// each: every segment starts level across the three.
void _expectAligned(WidgetTester tester) {
  final Map<int, double> first = <int, double>{};
  int compared = 0;
  for (int c = 0; c < 3; c++) {
    for (final Element e
        in find
            .descendant(of: _column(c), matching: find.byType(SyncSlotSpacer))
            .evaluate()) {
      final int k = (e.widget as SyncSlotSpacer).segment;
      final double bottom = tester.getRect(find.byWidget(e.widget)).bottom;
      final double? seen = first[k];
      if (seen == null) {
        first[k] = bottom;
      } else {
        compared++;
        expect(bottom, closeTo(seen, 0.5), reason: 'column $c segment $k');
      }
    }
  }
  expect(compared, greaterThan(0));
}

void main() {
  for (final bool wrap in <bool>[false, true]) {
    testWidgets('every block\'s estimate is within a line of its laid-out '
        'height (soft wrap $wrap)', (WidgetTester tester) async {
      final ParsedConflictFile parsed = ParsedConflictFile(
        segments: <ConflictSegment>[
          conflictText(const <String>[]),
          conflictText(const <String>['t1']),
          conflictText(const <String>['t1', 't2', 't3']),
          conflictRegion(const <String>[], const <String>['b']),
          conflictRegion(const <String>['a', 'x', 'y'], const <String>['b']),
        ],
        regionCount: 2,
        wellFormed: true,
      );
      await pumpConflictWindow(
        tester,
        parsed,
        prefs: <String, Object>{'appPrefs.softWrapEnabled': wrap},
      );
      final ConflictSyncMetrics metrics = conflictSyncMetrics(
        tester.element(find.byType(SyncHeightReporter).first),
        kConflictCodeTextStyle,
      );
      for (int c = 0; c < 3; c++) {
        final List<Element> blocks = find
            .descendant(
              of: _column(c),
              matching: find.byType(SyncHeightReporter),
            )
            .evaluate()
            .toList();
        expect(blocks, hasLength(parsed.segments.length));
        for (int k = 0; k < blocks.length; k++) {
          final double laidOut = blocks[k].size!.height;
          final double estimate = conflictSegmentEstimate(
            column: c,
            segment: parsed.segments[k],
            metrics: metrics,
          );
          expect(
            (laidOut - estimate).abs(),
            lessThanOrEqualTo(metrics.line),
            reason: 'column $c segment $k: $laidOut vs $estimate',
          );
        }
      }
    });
  }

  testWidgets('segment tops line up in all three columns, at the top and '
      'with each column wheeled to its end', (WidgetTester tester) async {
    await pumpConflictWindow(tester, _tall());
    _expectAligned(tester);
    for (int c = 0; c < 3; c++) {
      await _wheel(tester, c, const Offset(0, 1e6));
      await _wheel(tester, c, const Offset(0, 1e6));
      final ScrollPosition leader = _position(tester, c);
      expect(leader.pixels, leader.maxScrollExtent, reason: 'column $c');
      expect(leader.pixels, greaterThan(1000));
      for (int o = 0; o < 3; o++) {
        final ScrollPosition other = _position(tester, o);
        expect(
          other.pixels,
          closeTo(
            leader.pixels.clamp(other.minScrollExtent, other.maxScrollExtent),
            0.5,
          ),
          reason: 'column $o after column $c',
        );
      }
      _expectAligned(tester);
      await _wheel(tester, c, const Offset(0, -1e6));
      await _wheel(tester, c, const Offset(0, -1e6));
    }
  });

  testWidgets('a wheel on ours brings result and theirs to the same place, '
      'and nothing moves ours back', (WidgetTester tester) async {
    await pumpConflictWindow(tester, _tall());
    final ScrollPosition ours = _position(tester, 0);
    final List<double> seen = <double>[];
    void watch() => seen.add(ours.pixels);
    ours.addListener(watch);
    addTearDown(() => ours.removeListener(watch));

    await _wheel(tester, 0, const Offset(0, 900));
    expect(ours.pixels, greaterThan(500));
    expect(_position(tester, 1).pixels, ours.pixels);
    expect(_position(tester, 2).pixels, ours.pixels);
    // Ours moved once, by the wheel, and was never jumped after.
    expect(seen.toSet(), <double>{ours.pixels});
    _expectAligned(tester);
  });

  testWidgets('taking a side grows the result column, and the three stay '
      'aligned', (WidgetTester tester) async {
    await pumpConflictWindow(tester, _tall());
    await _wheel(tester, 1, const Offset(0, 700));
    await tester.tap(find.text('Take Theirs').hitTestable().first);
    await _settle(tester);
    // Some region's six theirs lines now stand in the result column too.
    expect(
      find.descendant(
        of: _column(1),
        matching: find.byWidgetPredicate(
          (Widget w) => w is Text && RegExp(r'^t\d_5$').hasMatch(w.data ?? ''),
        ),
      ),
      findsOneWidget,
    );
    _expectAligned(tester);
  });

  // C1/D1/D2: Previous from region 0 goes to the last region, which is not
  // built yet; only the result column is driven, the others follow it.
  testWidgets('Previous to the last region scrolls the result column alone, '
      'and the other two follow it there', (WidgetTester tester) async {
    // Long enough that three jumps by measured heights alone fall short:
    // the first lands on the estimate.
    await pumpConflictWindow(tester, _tall(pairs: 40));
    await tester.tap(find.widgetWithText(GbmButton, 'Next conflict'));
    await _settle(tester);
    expect(find.text('t39_0'), findsNothing);
    final double before = _position(tester, 1).pixels;

    final List<bool> driven = <bool>[false, false, false];
    final List<VoidCallback> listeners = <VoidCallback>[];
    for (int c = 0; c < 3; c++) {
      final ValueNotifier<bool> scrolling = _position(
        tester,
        c,
      ).isScrollingNotifier;
      void listener() {
        if (scrolling.value) driven[c] = true;
      }

      scrolling.addListener(listener);
      listeners.add(() => scrolling.removeListener(listener));
    }
    addTearDown(() {
      for (final VoidCallback remove in listeners) {
        remove();
      }
    });

    await tester.tap(find.widgetWithText(GbmButton, 'Previous'));
    await tester.pumpAndSettle();

    expect(_position(tester, 1).pixels, isNot(before));
    expect(driven, <bool>[false, true, false]);
    for (final String text in <String>['o39_0', 'Region 40 of 40', 't39_0']) {
      expect(find.text(text).hitTestable(), findsOneWidget, reason: text);
    }
    _expectAligned(tester);
  });

  testWidgets('a sideways wheel on any column moves the other two by the '
      'same pixels', (WidgetTester tester) async {
    await pumpConflictWindow(tester, _tall(longBy: 120));
    double at = 0;
    for (final int c in <int>[0, 2]) {
      await _wheel(tester, c, const Offset(150, 0));
      expect(_sideways(tester, c).pixels, greaterThan(at), reason: '$c');
      at = _sideways(tester, c).pixels;
      for (int o = 0; o < 3; o++) {
        expect(_sideways(tester, o).pixels, at, reason: '$o after $c');
      }
    }
  });

  testWidgets('dragging theirs\' scrollbar thumb leads, and the other two '
      'follow', (WidgetTester tester) async {
    await pumpConflictWindow(tester, _tall());
    // A wheel tick on ours first: a desktop scrollbar shows its thumb on a
    // scroll, and ours leading makes the drag's lead the thing under test.
    await _wheel(tester, 0, const Offset(0, 1));
    final Rect bar = tester.getRect(_column(2));
    final TestGesture drag = await tester.startGesture(
      Offset(bar.right - 3, bar.top + 5),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (int i = 0; i < 10; i++) {
      await drag.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await drag.up();
    await _settle(tester);
    final double theirs = _position(tester, 2).pixels;
    expect(theirs, greaterThan(100));
    expect(_position(tester, 0).pixels, theirs);
    expect(_position(tester, 1).pixels, theirs);
    _expectAligned(tester);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('soft wrap: a narrower window re-wraps all three, and they '
      'stay aligned', (WidgetTester tester) async {
    await pumpConflictWindow(
      tester,
      _tall(longBy: 60),
      prefs: <String, Object>{'appPrefs.softWrapEnabled': true},
    );
    await _wheel(tester, 1, const Offset(0, 1500));
    tester.view.physicalSize = const Size(1200, 900);
    await _settle(tester);
    await _settle(tester);
    _expectAligned(tester);
  });
}
