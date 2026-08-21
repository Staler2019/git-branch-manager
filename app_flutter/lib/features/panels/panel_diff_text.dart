import 'package:flutter/material.dart';

import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';

/// Renders raw unified-diff **text** with per-line colouring.
///
/// Deliberately not [DiffPage]: that takes a `ParsedDiff`, which only the
/// C++ `UnifiedDiffParser` produces, and the two surfaces that need this
/// have git's own text and no parse of it — `LineHistoryChunk.diffText`
/// comes straight off `git log -L`, and a `.patch` file on disk was never
/// parsed at all.
///
/// This is syntax colouring, not parsing: it never builds files or hunks,
/// so nothing here can be staged, discarded or line-selected. That is the
/// point — a panel's detail column is read-only, and a half-parse that
/// looked stageable would be worse than none.
class PanelDiffText extends StatelessWidget {
  const PanelDiffText({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<String> lines = text.split('\n');

    return SelectionArea(
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: GbmSpacing.space2),
        itemCount: lines.length,
        itemBuilder: (context, i) {
          final String line = lines[i];
          final (Color? background, Color foreground) = _styleOf(line, colors);
          return Container(
            width: double.infinity,
            color: background,
            padding: const EdgeInsets.symmetric(
              horizontal: GbmSpacing.space3,
              vertical: 1,
            ),
            child: Text(
              line.isEmpty ? ' ' : line,
              style: TextStyle(
                fontFamily: GbmTypography.fontMono,
                fontSize: GbmTypography.textXs,
                color: foreground,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Order matters: `+++`/`---` are file headers, not added/removed lines,
  /// so they must be matched before the single-character prefixes.
  (Color?, Color) _styleOf(String line, GbmColors colors) {
    if (line.startsWith('+++') || line.startsWith('---')) {
      return (null, colors.textSecondary);
    }
    if (line.startsWith('diff --git') ||
        line.startsWith('index ') ||
        line.startsWith('new file') ||
        line.startsWith('deleted file') ||
        line.startsWith('rename ') ||
        line.startsWith('similarity ')) {
      return (null, colors.textSecondary);
    }
    if (line.startsWith('@@')) return (null, colors.accent);
    if (line.startsWith('+')) return (colors.diffAddBg, colors.diffAddText);
    if (line.startsWith('-')) return (colors.diffDelBg, colors.diffDelText);
    return (null, colors.textPrimary);
  }
}
