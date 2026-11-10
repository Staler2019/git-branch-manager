// A selection drag held past the top or bottom of a code view scrolls it.
// Flutter's own selection autoscroller (`EdgeDraggingAutoScroller._scroll`)
// does that by awaiting itself once per 20 px step, so a long hold builds a
// chain of futures that unwinds in one go on release -- measured in a
// profile build of the app: fine at ~500 steps, `StackOverflowError` at
// ~1500 (about 50 s of holding). Every code view goes through
// [GbmCodeHScroll], which drives that axis itself instead.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/widgets/gbm_code_hscroll.dart';

const Duration kFrame = Duration(milliseconds: 16);

void main() {
  const double rowHeight = 20;
  const int rowCount = 6000;

  late ScrollController vertical;
  late String? selected;

  setUp(() {
    vertical = ScrollController();
    selected = null;
  });
  tearDown(() => vertical.dispose());

  /// The code's width: 0 fits the view, 4000 builds the sideways scroller
  /// between the region and the list.
  double contentWidth = 0;

  Future<void> pumpTree(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 200,
            child: SelectionArea(
              onSelectionChanged: (SelectedContent? c) =>
                  selected = c?.plainText,
              child: GbmCodeHScroll(
                contentWidth: contentWidth,
                codeClipWidth: null,
                verticalController: vertical,
                backdrop: const Color(0xFF101010),
                child: ListView.builder(
                  controller: vertical,
                  itemExtent: rowHeight,
                  itemCount: rowCount,
                  itemBuilder: (BuildContext context, int i) => Text('row $i'),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> pump(WidgetTester tester) async {
    await pumpTree(tester);
    // Wider than the view, the selection containers nest four deep and the
    // deepest registers a frame after mount (see the scrolled-drag test's
    // `pump`); a press in the mount frame itself reaches nothing.
    await tester.pump();
  }

  Rect view(WidgetTester tester) => tester.getRect(find.byType(GbmCodeHScroll));

  /// Presses on [fromRow]'s text, holds the pointer [overshoot] px past the
  /// view's [downward] edge until the list has scrolled [px], then releases.
  Future<void> holdPastEdge(
    WidgetTester tester, {
    required String fromRow,
    required bool downward,
    required double px,
    double overshoot = 40,
  }) async {
    final Rect start = tester.getRect(find.text(fromRow));
    final double from = vertical.offset;
    final TestGesture gesture = await tester.startGesture(
      start.centerLeft + const Offset(2, 0),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    final Rect v = view(tester);
    await gesture.moveTo(
      Offset(v.left + 40, downward ? v.bottom + overshoot : v.top - overshoot),
    );
    for (int i = 0; i < 20000 && (vertical.offset - from).abs() < px; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await gesture.up();
    await tester.pump();
    await tester.pump();
  }

  /// Presses on [fromRow]'s text and moves [overshoot] px past the view's
  /// bottom (or top), without releasing.
  Future<TestGesture> pressAndLeave(
    WidgetTester tester, {
    required String fromRow,
    required double overshoot,
  }) async {
    final Rect start = tester.getRect(find.text(fromRow));
    final TestGesture gesture = await tester.startGesture(
      start.centerLeft + const Offset(2, 0),
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(gesture.removePointer);
    await tester.pump();
    final Rect v = view(tester);
    await gesture.moveTo(
      Offset(
        v.left + 40,
        overshoot > 0 ? v.bottom + overshoot : v.top + overshoot,
      ),
    );
    return gesture;
  }

  Future<void> frames(WidgetTester tester, Duration total) async {
    for (Duration t = Duration.zero; t < total; t += kFrame) {
      await tester.pump(kFrame);
    }
  }

  for (final double width in const <double>[0, 4000]) {
    group(width == 0 ? 'code that fits:' : 'code wider than the view:', () {
      setUp(() => contentWidth = width);
      testWidgets('it moves at the framework speed: the overshoot, capped at '
          '20 px, twenty times a second, as the framework ran', (tester) async {
        await pump(tester);
        final TestGesture gesture = await pressAndLeave(
          tester,
          fromRow: 'row 2',
          overshoot: 200,
        );
        await frames(tester, const Duration(seconds: 2));
        expect(vertical.offset, closeTo(2 * 20 * 20.0, 30));
        // A smaller overshoot is a slower scroll: 5 px a step.
        final double before = vertical.offset;
        final Rect v = view(tester);
        await gesture.moveTo(Offset(v.left + 40, v.bottom + 5));
        await frames(tester, const Duration(seconds: 2));
        expect(vertical.offset - before, closeTo(2 * 20 * 5.0, 30));
        await gesture.up();
      });

      testWidgets('a drag held above the view scrolls it back up', (
        tester,
      ) async {
        await pump(tester);
        vertical.jumpTo(3000);
        await tester.pump();
        final TestGesture gesture = await pressAndLeave(
          tester,
          fromRow: 'row 152',
          overshoot: -40,
        );
        await frames(tester, const Duration(seconds: 2));
        expect(vertical.offset, closeTo(3000 - 2 * 20 * 20.0, 30));
        await gesture.up();
      });

      testWidgets('the scroll stops when the pointer comes back inside, and on '
          'release', (tester) async {
        await pump(tester);
        final TestGesture gesture = await pressAndLeave(
          tester,
          fromRow: 'row 2',
          overshoot: 40,
        );
        await frames(tester, const Duration(seconds: 1));
        final Rect v = view(tester);
        await gesture.moveTo(Offset(v.left + 40, v.center.dy));
        await tester.pump(kFrame);
        final double inside = vertical.offset;
        await frames(tester, const Duration(seconds: 1));
        expect(vertical.offset, inside, reason: 'pointer back inside');

        await gesture.moveTo(Offset(v.left + 40, v.bottom + 40));
        await frames(tester, const Duration(milliseconds: 500));
        await gesture.up();
        await tester.pump(kFrame);
        final double released = vertical.offset;
        await frames(tester, const Duration(seconds: 1));
        expect(vertical.offset, released, reason: 'released');
      });

      testWidgets('the selection follows the content it scrolls in', (
        tester,
      ) async {
        await pump(tester);
        final TestGesture gesture = await pressAndLeave(
          tester,
          fromRow: 'row 2',
          overshoot: 40,
        );
        await frames(tester, const Duration(seconds: 2));
        await gesture.up();
        await tester.pump();
        // The selection ends on the row under the view's bottom edge, wherever
        // the scroll left it -- not on the rows of the first frame (row 9).
        final int bottomRow = ((vertical.offset + 200 - 0.5) / rowHeight)
            .floor();
        expect(bottomRow, greaterThan(30), reason: 'premise: it scrolled');
        expect(selected, startsWith('row 2'));
        expect(selected, contains('row ${bottomRow - 1}'));
        expect(selected, isNot(contains('row ${bottomRow + 1}')));
      });

      testWidgets('a drag held below the view for 2,000 steps scrolls, and the '
          'release does not overflow the stack', (tester) async {
        await pump(tester);
        await holdPastEdge(
          tester,
          fromRow: 'row 2',
          downward: true,
          px: 2000 * 20.0,
        );
        expect(tester.takeException(), isNull);
        expect(vertical.offset, greaterThanOrEqualTo(2000 * 20.0));
      });

      if (width > 0) {
        testWidgets('a drag held past the right edge still scrolls the code '
            'sideways: only the vertical coordinate is clamped', (
          tester,
        ) async {
          await pump(tester);
          final ScrollableState sideways = tester.state<ScrollableState>(
            find.byWidgetPredicate(
              (Widget w) =>
                  w is Scrollable && w.axisDirection == AxisDirection.right,
            ),
          );
          final Rect start = tester.getRect(find.text('row 2'));
          final TestGesture gesture = await tester.startGesture(
            start.centerLeft + const Offset(2, 0),
            kind: PointerDeviceKind.mouse,
          );
          addTearDown(gesture.removePointer);
          await tester.pump();
          final Rect v = view(tester);
          await gesture.moveTo(Offset(v.right + 40, v.top + 60));
          await frames(tester, const Duration(seconds: 1));
          expect(sideways.position.pixels, greaterThan(0));
          expect(vertical.offset, 0);
          await gesture.up();
        });
      }
    });
  }
}
