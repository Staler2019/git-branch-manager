import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/widgets/code_line_metrics.dart';

/// Every width here is in **test-font units**: `flutter_test`'s default font
/// draws every glyph exactly `fontSize` wide, so an N-character line measures
/// `N * fontSize`. A real proportional-ish mono font is narrower. The
/// assertions are therefore all relative -- "the widest line wins", "a longer
/// line is wider" -- and never a pixel constant, which would only be true
/// under the test font.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const TextStyle style = TextStyle(fontSize: 10);

  group('widestLineWidth', () {
    test('returns zero for empty text', () {
      expect(widestLineWidth('', style), 0);
    });

    test('measures the widest line, not the first or the last', () {
      // The long line is deliberately in the middle: a bug that measured only
      // the first or only the last line would still pass with it at an end.
      const String blob = 'ab\nabcdefghij\nabcd';
      expect(
        widestLineWidth(blob, style),
        widestLineWidth('abcdefghij', style),
      );
    });

    test('a single line measures the same alone as inside a blob', () {
      expect(
        widestLineWidth('short\nlonger line here', style),
        widestLineWidth('longer line here', style),
      );
    });

    test('a wider line measures wider', () {
      expect(
        widestLineWidth('aaaaaaaaaa', style) > widestLineWidth('aaaaa', style),
        isTrue,
      );
    });
  });

  group('CodeWidthMemo', () {
    test('recomputes once per key, then hits', () {
      final CodeWidthMemo memo = CodeWidthMemo();
      final Object key = Object();
      int built = 0;
      String text() {
        built++;
        return 'aaaaa\naaaaaaaaaa';
      }

      final double first = memo.widthOf(key: key, text: text, style: style);
      final double second = memo.widthOf(key: key, text: text, style: style);

      expect(second, first);
      expect(memo.misses, 1);
      expect(memo.hits, 1);
      // The blob callback is the point of the laziness: a hit must not pay to
      // assemble it.
      expect(built, 1);
    });

    test('a new key really recomputes, and the answer changes with it', () {
      final CodeWidthMemo memo = CodeWidthMemo();
      final double narrow = memo.widthOf(
        key: Object(),
        text: () => 'aa',
        style: style,
      );
      final double wide = memo.widthOf(
        key: Object(),
        text: () => 'aaaaaaaaaaaaaaaaaaaa',
        style: style,
      );

      expect(memo.misses, 2);
      expect(memo.hits, 0);
      // Counting alone cannot tell a recompute from a stale answer returned
      // twice, so assert the value moved too.
      expect(wide > narrow, isTrue);
    });

    test('the same key at a different style recomputes', () {
      final CodeWidthMemo memo = CodeWidthMemo();
      final Object key = Object();
      final double small = memo.widthOf(
        key: key,
        text: () => 'aaaaa',
        style: const TextStyle(fontSize: 10),
      );
      final double large = memo.widthOf(
        key: key,
        text: () => 'aaaaa',
        style: const TextStyle(fontSize: 20),
      );

      expect(memo.misses, 2);
      expect(large > small, isTrue);
    });
  });
}
