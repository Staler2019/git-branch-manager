import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'gbm_code_hscroll.dart';

/// One line (or block) of code text in any file view.
///
/// With [softWrap] on, it wraps. With it off, a long line runs off to the
/// right for the enclosing [GbmCodeHScroll] to scroll -- unless that scroller
/// hands down a clip width (`AppPreferences.maxCodeLineChars`, 「最長200字中文」),
/// in which case a longer line ends in an ellipsis inside the clip width
/// (code-line-width-cap-spec.html, ruled 「c, ok」). The clip applies even when
/// the view is wider than it: no scroller is built then, so the view's edge
/// is not where the line has to stop.
///
/// A multi-line [text] is cut line by line. Flutter's ellipsis on a
/// multi-line paragraph keeps only its first line (measured 2026-10-25), so
/// each line gets its own paragraph. Copying still yields the whole line: the
/// ellipsis changes what is painted, not the paragraph's text.
///
/// **Letter spacing is pinned to 0** unless [style] sets it. Every view
/// measures its scroll extent with a bare `TextPainter` in [style], but a
/// `Text` merges the ambient `DefaultTextStyle` first, and Material's body
/// style carries `letterSpacing: 0.25`: the painted line came out 0.25 px
/// per character wider than measured, so the longest line's last characters
/// sat past the scroll extent -- and, with a clip, were cut at the default
/// 200 (found 2026-10-25 by `code_line_width_cap_flow_test.dart`).
///
/// A parent no wider than the clip gets the line exactly as before, filling
/// it. Only a wider one -- the clip narrower than the view, or an `Expanded`
/// side-by-side cell, whose tight width would override a [ConstrainedBox] --
/// lays the line out loose and no wider than the clip ([_HoldToWidth]). Not a
/// `LayoutBuilder`: side-by-side rows sit in an `IntrinsicHeight`, which a
/// `LayoutBuilder` refuses to answer.
class GbmCodeText extends StatelessWidget {
  const GbmCodeText(
    this.text, {
    super.key,
    required this.style,
    required this.softWrap,
  });

  final String text;
  final TextStyle style;
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    final TextStyle style = this.style.letterSpacing == null
        ? this.style.copyWith(letterSpacing: 0)
        : this.style;
    final double? clip = softWrap
        ? null
        : GbmCodeHScroll.maybeCodeClipWidthOf(context);
    if (clip == null) {
      return Text(
        text,
        softWrap: softWrap,
        overflow: softWrap ? TextOverflow.clip : TextOverflow.visible,
        style: style,
      );
    }
    final List<String> lines = text.split('\n');
    Widget line(String l) => Text(
      l,
      softWrap: false,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
    final Widget cut = lines.length == 1
        ? line(text)
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[for (final String l in lines) line(l)],
          );
    return _HoldToWidth(width: clip, child: cut);
  }
}

/// Passes its constraints through unless they allow more than [width]; then
/// lays the child out loose up to [width], sized itself as its parent asks
/// and the child at its start.
class _HoldToWidth extends SingleChildRenderObjectWidget {
  const _HoldToWidth({required this.width, required super.child});

  final double width;

  @override
  _RenderHoldToWidth createRenderObject(BuildContext context) =>
      _RenderHoldToWidth(width);

  @override
  void updateRenderObject(BuildContext context, _RenderHoldToWidth r) =>
      r.width = width;
}

class _RenderHoldToWidth extends RenderProxyBox {
  _RenderHoldToWidth(this._width);

  double _width;
  set width(double value) {
    if (value == _width) return;
    _width = value;
    markNeedsLayout();
  }

  BoxConstraints _forChild(BoxConstraints c) => c.maxWidth <= _width
      ? c
      : BoxConstraints(
          maxWidth: _width,
          minHeight: c.minHeight,
          maxHeight: c.maxHeight,
        );

  @override
  void performLayout() {
    final RenderBox? child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_forChild(constraints), parentUsesSize: true);
    size = constraints.constrain(child.size);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final Size? child = this.child?.getDryLayout(_forChild(constraints));
    return constraints.constrain(child ?? Size.zero);
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      super.computeMinIntrinsicWidth(height).clamp(0, _width);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      super.computeMaxIntrinsicWidth(height).clamp(0, _width);

  @override
  double computeMinIntrinsicHeight(double width) =>
      super.computeMinIntrinsicHeight(width < _width ? width : _width);

  @override
  double computeMaxIntrinsicHeight(double width) =>
      super.computeMaxIntrinsicHeight(width < _width ? width : _width);
}
