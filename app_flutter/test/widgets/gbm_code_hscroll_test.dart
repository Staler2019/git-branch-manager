// The pinned-gutter contract. A finder proves the scroller exists; only a
// rect comparison proves the gutter actually stays put while the code moves,
// which is the whole behaviour the "soft wrap off" mode is built around.
//
// Every width here is in test-font units (`flutter_test` draws each glyph
// `fontSize` wide). The assertions compare rects to each other, never to a
// pixel constant.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/widgets/gbm_code_hscroll.dart';

void main() {
  const Key gutterKey = Key('gutter');
  const Key codeKey = Key('code');
  const double gutterWidth = 60;
  const double viewportWidth = 300;

  Future<void> pump(WidgetTester tester, {required double contentWidth}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: viewportWidth,
              height: 200,
              child: GbmCodeHScroll(
                contentWidth: contentWidth,
                backdrop: const Color(0xFF101010),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Stack(
                      children: <Widget>[
                        const Padding(
                          padding: EdgeInsets.only(left: gutterWidth),
                          child: Text(
                            'a very long line of code',
                            key: codeKey,
                            softWrap: false,
                            overflow: TextOverflow.visible,
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: GbmPinnedGutter(
                            width: gutterWidth,
                            background: const Color(0xFF202020),
                            child: const Text('12', key: gutterKey),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('builds no scroller at all when the content already fits', (
    WidgetTester tester,
  ) async {
    await pump(tester, contentWidth: viewportWidth - 50);

    expect(find.byType(SingleChildScrollView), findsNothing);
    // With no scroller there is no offset to counter, so the gutter sits at
    // the pane's own left edge and the code starts one gutter to its right.
    final Rect gutter = tester.getRect(find.byKey(gutterKey));
    final Rect code = tester.getRect(find.byKey(codeKey));
    expect(code.left, closeTo(gutter.left + gutterWidth, 0.5));
  });

  testWidgets('the gutter holds its place while the code scrolls under it', (
    WidgetTester tester,
  ) async {
    await pump(tester, contentWidth: 1000);

    final double gutterBefore = tester.getRect(find.byKey(gutterKey)).left;
    final double codeBefore = tester.getRect(find.byKey(codeKey)).left;

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-120, 0),
    );
    await tester.pump();

    final double gutterAfter = tester.getRect(find.byKey(gutterKey)).left;
    final double codeAfter = tester.getRect(find.byKey(codeKey)).left;

    // The code really moved -- otherwise the gutter "staying put" is vacuous.
    expect(codeAfter, lessThan(codeBefore));
    expect(codeBefore - codeAfter, closeTo(120, 0.5));
    // And the gutter did not move with it.
    expect(gutterAfter, closeTo(gutterBefore, 0.5));
  });

  testWidgets('the clip companion tracks the gutter in viewport coordinates', (
    WidgetTester tester,
  ) async {
    // `GbmPinnedGutterClip` is what lets a row keep a *transparent* gutter --
    // the mode a GbmRow needs, since its hover and selection tints are drawn
    // by an ancestor an opaque strip would cover. Nothing is painted over the
    // code; instead the code is clipped away exactly where the gutter ends,
    // which means the clip's left edge has to move with the scroll offset.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: viewportWidth,
              height: 200,
              child: GbmCodeHScroll(
                contentWidth: 1000,
                backdrop: const Color(0xFF101010),
                child: const GbmPinnedGutterClip(
                  gutterWidth: gutterWidth,
                  child: Padding(
                    padding: EdgeInsets.only(left: gutterWidth),
                    child: Text('a very long line of code', softWrap: false),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Rect clipOf(WidgetTester tester) {
      // Scoped: the viewport draws its own ClipRect, so an unscoped finder
      // matches more than one and picks the wrong geometry.
      final ClipRect rect = tester.widget<ClipRect>(
        find.descendant(
          of: find.byType(GbmPinnedGutterClip),
          matching: find.byType(ClipRect),
        ),
      );
      return rect.clipper!.getClip(const Size(1000, 20));
    }

    expect(clipOf(tester).left, closeTo(gutterWidth, 0.5));

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-140, 0),
    );
    await tester.pump();

    // Not `gutterWidth` any more: the row has moved 140 to the left, so the
    // gutter now covers row-local 140..140+gutterWidth.
    expect(clipOf(tester).left, closeTo(gutterWidth + 140, 0.5));
  });

  testWidgets('a mouse drag does not scroll, so a selection drag survives', (
    WidgetTester tester,
  ) async {
    // This pins the premise the whole design rests on: `ScrollBehavior`'s
    // default `dragDevices` (`_kTouchLikeDeviceTypes`) has no
    // `PointerDeviceKind.mouse` in it, and a desktop selection drag -- the
    // one `ScopedDiffView` builds staging scopes out of -- arrives as mouse.
    // If a future Flutter upgrade added mouse to that set, this goes red and
    // the diff's drag-to-select would be the thing that broke.
    await pump(tester, contentWidth: 1000);

    final double codeBefore = tester.getRect(find.byKey(codeKey)).left;

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-120, 0),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    expect(tester.getRect(find.byKey(codeKey)).left, codeBefore);
  });
}
