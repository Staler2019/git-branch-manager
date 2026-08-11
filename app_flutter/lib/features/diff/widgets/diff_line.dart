import 'package:flutter/material.dart';

import '../../../data/models/parsed_diff.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';

/// `.gbm-diffline`/`.gbm-diffline-add`/`.gbm-diffline-del`/`.gbm-diffline-ctx`
/// (docs/design/tokens-reference.md's components.css). One monospace row per
/// [DiffLine], with old/new line numbers in a fixed-width gutter like every
/// git diff viewer.
class DiffLineView extends StatelessWidget {
  const DiffLineView({super.key, required this.line});

  final DiffLine line;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final (Color? background, Color textColor, String marker) = switch (line.kind) {
      DiffLineKind.added => (colors.diffAddBg, colors.diffAddText, '+'),
      DiffLineKind.removed => (colors.diffDelBg, colors.diffDelText, '-'),
      DiffLineKind.noNewlineMarker => (null, colors.textTertiary, ' '),
      DiffLineKind.context => (null, colors.textSecondary, ' '),
    };

    final String kindLabel = switch (line.kind) {
      DiffLineKind.added => 'added',
      DiffLineKind.removed => 'removed',
      DiffLineKind.noNewlineMarker => 'no newline at end of file',
      DiffLineKind.context => 'unchanged',
    };

    return Semantics(
      label: '$kindLabel line ${line.text}',
      child: Container(
        color: background,
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3, vertical: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(width: 36, child: _lineNumberText(line.oldLine, colors.textTertiary)),
            SizedBox(width: 36, child: _lineNumberText(line.newLine, colors.textTertiary)),
            SizedBox(
              width: 14,
              child: Text(marker, style: TextStyle(fontFamily: GbmTypography.fontMono, fontSize: GbmTypography.textSm, color: textColor)),
            ),
            Expanded(
              child: Text(
                line.text,
                style: TextStyle(fontFamily: GbmTypography.fontMono, fontSize: GbmTypography.textSm, color: textColor, height: 1.6),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _lineNumberText(int lineNumber, Color color) {
    return Text(
      lineNumber == 0 ? '' : '$lineNumber',
      textAlign: TextAlign.right,
      style: TextStyle(fontFamily: GbmTypography.fontMono, fontSize: GbmTypography.textXs, color: color),
    );
  }
}
