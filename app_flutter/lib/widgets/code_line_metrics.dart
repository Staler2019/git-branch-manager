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

double _measureText(String text, TextStyle style) {
  final TextPainter painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  final double width = painter.width;
  painter.dispose();
  return width;
}

/// The width of one CJK character in a code style -- the unit of
/// `AppPreferences.maxCodeLineChars` (「最長200字中文」).
///
/// **Key**: the [TextStyle] alone; a CJK glyph's width depends on nothing
/// else. **Invalidation**: none -- a style is a value, so a theme or font
/// change arrives as a different key. **Symptom if it goes stale**: lines are
/// cut at the wrong place.
///
/// [measure] is injectable because the test font draws '中' and '0' the same
/// width, so only a recording measurer can show which one was measured.
class CjkCharWidthMemo {
  CjkCharWidthMemo({double Function(String text, TextStyle style)? measure})
    : _measure = measure ?? _measureText;

  final double Function(String text, TextStyle style) _measure;
  TextStyle? _style;
  double _width = 0;
  int _hits = 0;
  int _misses = 0;

  int get hits => _hits;
  int get misses => _misses;

  double widthOf(TextStyle style) {
    if (_style == style) {
      _hits++;
      return _width;
    }
    _misses++;
    _style = style;
    _width = _measure('中', style);
    return _width;
  }
}

/// What [capCodeWidth] decides: the scroll extent to hand `GbmCodeHScroll`,
/// and the width each row's code text is cut at.
class CappedCodeWidth {
  const CappedCodeWidth({required this.totalWidth, required this.clipWidth});

  final double totalWidth;
  final double clipWidth;
}

/// Caps a code view at [maxChars] CJK characters of code per column, the
/// gutter not counted. [columns] is 2 for side-by-side, whose two halves are
/// capped each on its own (「每一欄各 N 字」) with [columnGap] between them.
CappedCodeWidth capCodeWidth({
  required double naturalWidth,
  required int maxChars,
  required double charWidth,
  required double gutterWidth,
  int columns = 1,
  double columnGap = 0,
}) {
  final double clip = maxChars * charWidth;
  final double cap = columns * (gutterWidth + clip) + (columns - 1) * columnGap;
  return CappedCodeWidth(
    totalWidth: naturalWidth < cap ? naturalWidth : cap,
    clipWidth: clip,
  );
}
