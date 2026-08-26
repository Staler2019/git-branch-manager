import 'package:flutter/painting.dart';

/// Width of the widest single line in [text], laid out in [style].
///
/// **One** `TextPainter.layout` for the whole blob, not one per line: the
/// `maxIntrinsicWidth` of a multi-line paragraph is by definition the maximum
/// over its lines, so splitting on `\n` first would cost N layouts to learn
/// the same number.
///
/// Deliberately not `charWidth * longestRuneCount`, which the monospace font
/// would seem to allow: a CJK or full-width glyph is two cells wide, so that
/// formula under-measures exactly the lines most likely to need the scroll
/// room, and the shortfall shows up as a clipped line end.
double widestLineWidth(String text, TextStyle style) {
  if (text.isEmpty) return 0;
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final double width = painter.maxIntrinsicWidth;
  painter.dispose();
  return width;
}

/// Memoises [widestLineWidth] for one widget's current content.
///
/// **Key**: the content's own identity (a `DiffFile`, or the raw diff `String`
/// for the surfaces that never parse one) together with the [TextStyle] it is
/// drawn in. Both halves are load-bearing -- the same file at a different font
/// size is a different width, and the style changes with the theme.
///
/// **Invalidation**: the key *is* the invalidation. There is no event to
/// subscribe to here: the models are immutable and republished by
/// `copyWith()`, so new content is always a new object, and a `TextStyle` is a
/// value. This is the same shape as the core's `UntrackedLineCountCache`, and
/// it is written down rather than left blank because "no events" reads like a
/// gap otherwise.
///
/// **Symptom if it goes stale**: the horizontal scroll extent stops matching
/// what is drawn -- either the longest line is clipped at its end, or the pane
/// scrolls into empty space past the content.
class CodeWidthMemo {
  Object? _key;
  TextStyle? _style;
  double _width = 0;
  int _hits = 0;
  int _misses = 0;

  /// Recomputations avoided. Counted so a test can tell a working cache from
  /// one that recomputes every call and happens to answer correctly -- those
  /// two are indistinguishable by the returned value alone.
  int get hits => _hits;

  /// Recomputations actually performed.
  int get misses => _misses;

  /// [text] is a callback, not a `String`: assembling every line of a diff
  /// into one blob is itself work, and on a hit there is no reason to do it.
  double widthOf({
    required Object key,
    required String Function() text,
    required TextStyle style,
  }) {
    if (_style == style && _key == key) {
      _hits++;
      return _width;
    }
    _misses++;
    _key = key;
    _style = style;
    _width = widestLineWidth(text(), style);
    return _width;
  }
}
