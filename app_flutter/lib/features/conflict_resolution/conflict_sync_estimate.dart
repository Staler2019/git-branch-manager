import 'package:flutter/material.dart';

import '../../data/models/parsed_conflict_file.dart';
import '../../theme/tokens.dart';

/// What a conflict column's heights are built from: the code style's line
/// height, a `textXs` label's, and the tap target a Material button takes
/// at least (0 where the theme shrink-wraps them, desktop's default).
typedef ConflictSyncMetrics = ({double line, double label, double tapTarget});

/// [ConflictSyncMetrics] as [context] draws [codeStyle]: merged into the
/// ambient text style, which carries the line height, and scaled.
ConflictSyncMetrics conflictSyncMetrics(
  BuildContext context,
  TextStyle codeStyle,
) {
  final TextStyle ambient = DefaultTextStyle.of(context).style;
  final TextScaler scaler = MediaQuery.textScalerOf(context);
  double heightOf(TextStyle style) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: 'X', style: ambient.merge(style)),
      textDirection: TextDirection.ltr,
      textScaler: scaler,
    )..layout();
    final double h = painter.height;
    painter.dispose();
    return h;
  }

  return (
    line: heightOf(codeStyle),
    label: heightOf(const TextStyle(fontSize: GbmTypography.textXs)),
    tapTarget:
        Theme.of(context).materialTapTargetSize == MaterialTapTargetSize.padded
        ? kMinInteractiveDimension
        : 0,
  );
}

/// The height [segment] takes in [column] (0 ours, 1 result, 2 theirs)
/// before it has been laid out (plan: Slice S, E5), a result region taken
/// as unresolved. Built from each block's own padding, so it is off only
/// where a line wraps (soft wrap on) or a region has been taken, both of
/// which the measured height then replaces.
double conflictSegmentEstimate({
  required int column,
  required ConflictSegment segment,
  required ConflictSyncMetrics metrics,
}) {
  final double line = metrics.line;
  if (segment.kind == ConflictSegmentKind.text) {
    // `_ContextBlock`: 1 above and below, or a 4-high gap when blank.
    final String text = segment.lines.join();
    if (text.trim().isEmpty) return GbmSpacing.space1;
    return text.split('\n').length * line + 2;
  }
  if (column == 1) {
    // `_ResultPane` unresolved: 4 margin above and below plus a 1 border; a
    // header of 2 + 2 around its labels; 4 padding around a 'Result' label
    // and a '(nothing)' line.
    return 2 * GbmSpacing.space1 +
        2 +
        4 +
        metrics.label +
        2 * GbmSpacing.space1 +
        metrics.label +
        line;
  }
  // `_SidePane`: 4 padding all round; a header row holding the Take
  // button (at least 20, or the theme's tap target); then 4 + 4 around
  // each line, or '(nothing)'.
  final List<String> side = column == 0 ? segment.ours : segment.theirs;
  final double button = 20 > metrics.tapTarget ? 20 : metrics.tapTarget;
  final double header = metrics.label > button ? metrics.label : button;
  final double lines = side.isEmpty
      ? line
      : side.length * (line + 2 * GbmSpacing.space1);
  return 2 * GbmSpacing.space1 + header + lines;
}
