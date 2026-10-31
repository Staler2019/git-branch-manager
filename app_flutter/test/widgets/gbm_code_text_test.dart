// Slice W (code-line-width-cap-spec.html, ruled 「c, ok」): a code line
// longer than the clip width ends in an ellipsis inside it; a shorter one is
// drawn exactly as before; soft wrap ignores the clip.
//
// Widths are compared with what the same text measures on its own
// ([widestLineWidth]), never with a pixel constant: the test font's glyphs
// are not exactly `fontSize` wide.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/widgets/gbm_code_hscroll.dart';
import 'package:gbm_flutter/widgets/code_line_metrics.dart';
import 'package:gbm_flutter/widgets/gbm_code_text.dart';

// letterSpacing pinned: MaterialApp's default text style would add its own.
const TextStyle _style = TextStyle(fontSize: 10, letterSpacing: 0);

Future<void> _pump(
  WidgetTester tester, {
  required String text,
  required double? clip,
  bool softWrap = false,
  double viewport = 400,
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: viewport,
            height: 300,
            child: GbmCodeHScroll(
              contentWidth: 0,
              verticalController: ScrollController(),
              backdrop: const Color(0xFF000000),
              codeClipWidth: clip,
              child: Align(
                alignment: Alignment.topLeft,
                child: GbmCodeText(
                  text,
                  key: const Key('code'),
                  style: _style,
                  softWrap: softWrap,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

List<RenderParagraph> _paragraphs(WidgetTester tester) => tester
    .renderObjectList<RenderParagraph>(
      find.descendant(
        of: find.byKey(const Key('code')),
        matching: find.byType(RichText),
      ),
    )
    .toList();

void main() {
  testWidgets('a line past the clip ends in an ellipsis inside it', (
    tester,
  ) async {
    await _pump(tester, text: 'a' * 30, clip: 100);
    final RenderParagraph p = _paragraphs(tester).single;
    expect(p.size.width, lessThanOrEqualTo(100));
    expect(p.didExceedMaxLines, isTrue);
    expect(p.overflow, TextOverflow.ellipsis);
  });

  testWidgets('the clip applies even when the view is wider than it', (
    tester,
  ) async {
    // WB1: no scroller is built here (contentWidth 0), and the line must
    // still stop at the clip, not at the view's edge.
    await _pump(tester, text: 'a' * 30, clip: 100, viewport: 1000);
    expect(_paragraphs(tester).single.size.width, lessThanOrEqualTo(100));
  });

  testWidgets('a line within the clip is drawn as before', (tester) async {
    await _pump(tester, text: 'a' * 5, clip: 100);
    final RenderParagraph p = _paragraphs(tester).single;
    expect(p.size.width, widestLineWidth('a' * 5, _style));
    expect(p.didExceedMaxLines, isFalse);
  });

  testWidgets('no clip in scope keeps the visible overflow', (tester) async {
    await _pump(tester, text: 'a' * 30, clip: null, viewport: 1000);
    final RenderParagraph p = _paragraphs(tester).single;
    expect(p.overflow, TextOverflow.visible);
    expect(p.size.width, widestLineWidth('a' * 30, _style));
  });

  testWidgets('soft wrap wraps and ignores the clip', (tester) async {
    await _pump(tester, text: 'a b ' * 40, clip: 100, softWrap: true);
    final RenderParagraph p = _paragraphs(tester).single;
    expect(p.overflow, TextOverflow.clip);
    expect(p.size.height, greaterThan(_style.fontSize! * 2));
  });

  // Flutter's ellipsis on a multi-line paragraph keeps only the first line,
  // measured on 2026-10-25 before this widget existed: a 3-line Text came
  // out 14 high. Each line therefore gets its own paragraph.
  testWidgets('every line of a multi-line string is kept and cut alone', (
    tester,
  ) async {
    await _pump(tester, text: '${'a' * 30}\nbb\n${'c' * 30}', clip: 100);
    final List<RenderParagraph> ps = _paragraphs(tester);
    expect(ps, hasLength(3));
    expect(ps.map((RenderParagraph p) => p.didExceedMaxLines), <bool>[
      true,
      false,
      true,
    ]);
  });

  testWidgets('copying a cut line gives the whole line', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    final FocusNode node = FocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectionArea(
            focusNode: node,
            child: SizedBox(
              width: 400,
              height: 300,
              child: GbmCodeHScroll(
                contentWidth: 0,
                verticalController: ScrollController(),
                backdrop: const Color(0xFF000000),
                codeClipWidth: 100,
                child: const Align(
                  alignment: Alignment.topLeft,
                  child: GbmCodeText(
                    'abcdefghijklmnopqrstuvwxyz',
                    style: _style,
                    softWrap: false,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    node.requestFocus();
    await tester.pump();
    for (final LogicalKeyboardKey mod in <LogicalKeyboardKey>[
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.controlLeft,
    ]) {
      await tester.sendKeyDownEvent(mod);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(mod);
    }
    await tester.pump();
    expect(copied, 'abcdefghijklmnopqrstuvwxyz');
  });

  testWidgets('a tight parent does not stretch the clip', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 300,
            child: GbmCodeHScroll(
              contentWidth: 0,
              verticalController: ScrollController(),
              backdrop: const Color(0xFF000000),
              codeClipWidth: 100,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: GbmCodeText(
                      'a' * 30,
                      key: const Key('code'),
                      style: _style,
                      softWrap: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(_paragraphs(tester).single.size.width, lessThanOrEqualTo(100));
  });

  testWidgets('an ambient letter spacing does not widen the line', (
    tester,
  ) async {
    // The measured width is a bare TextPainter in the code style; the
    // painted one must match it, or the longest line overruns its extent.
    const TextStyle bare = TextStyle(fontSize: 10);
    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTextStyle(
          style: const TextStyle(letterSpacing: 0.25),
          child: Align(
            alignment: Alignment.topLeft,
            child: GbmCodeText(
              'a' * 30,
              key: const Key('code'),
              style: bare,
              softWrap: false,
            ),
          ),
        ),
      ),
    );
    expect(
      _paragraphs(tester).single.size.width,
      widestLineWidth('a' * 30, bare),
    );
  });
}
