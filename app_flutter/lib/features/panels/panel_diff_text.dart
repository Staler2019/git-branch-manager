import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/app_preferences_repository.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/code_line_metrics.dart';
import '../../widgets/gbm_code_hscroll.dart';

/// The style this panel's lines are drawn in, colour aside. Single-sourced
/// for the same reason `kDiffCodeTextStyle` is: the scroll extent is measured
/// in it and then drawn in it, and a drift between the two clips the longest
/// line by the difference.
const TextStyle kPanelDiffTextStyle = TextStyle(
  fontFamily: GbmTypography.fontMono,
  fontSize: GbmTypography.textXs,
);

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
class PanelDiffText extends ConsumerStatefulWidget {
  const PanelDiffText({super.key, required this.text});

  final String text;

  @override
  ConsumerState<PanelDiffText> createState() => _PanelDiffTextState();
}

class _PanelDiffTextState extends ConsumerState<PanelDiffText> {
  /// Keyed by the raw diff text itself -- this surface never parses one, so
  /// the string *is* the content's identity. See [CodeWidthMemo] for the key,
  /// the invalidation and the symptom.
  final CodeWidthMemo _widthMemo = CodeWidthMemo();

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final String text = widget.text;
    final bool softWrap = ref.watch(appPreferencesProvider).softWrapEnabled;
    final List<String> lines = text.split('\n');

    // Nothing to pin here: a raw unified diff carries its own `+`/`-` in the
    // line text and this surface draws no line-number gutter, so with soft
    // wrap off the whole line simply scrolls.
    final double contentWidth = softWrap
        ? 0
        : GbmSpacing.space3 * 2 +
              _widthMemo.widthOf(
                key: text,
                text: () => text,
                style: kPanelDiffTextStyle,
              );

    return SelectionArea(
      child: GbmCodeHScroll(
        contentWidth: contentWidth,
        backdrop: colors.surfacePanel,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: GbmSpacing.space2),
          itemCount: lines.length,
          itemBuilder: (context, i) {
            final String line = lines[i];
            final (Color? background, Color foreground) = _styleOf(
              line,
              colors,
            );
            return Container(
              width: double.infinity,
              color: background,
              padding: const EdgeInsets.symmetric(
                horizontal: GbmSpacing.space3,
                vertical: 1,
              ),
              child: Text(
                line.isEmpty ? ' ' : line,
                softWrap: softWrap,
                overflow: softWrap ? TextOverflow.clip : TextOverflow.visible,
                style: kPanelDiffTextStyle.copyWith(color: foreground),
              ),
            );
          },
        ),
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
