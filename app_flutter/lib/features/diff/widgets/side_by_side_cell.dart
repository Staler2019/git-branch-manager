import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/parsed_diff.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_menu.dart';
import 'diff_line_menu_items.dart';

/// Which column of a side-by-side diff a cell is in — and therefore, since
/// [DiffLine] carries both numbers, **which of them the cell may show**.
enum SideBySideSide {
  /// 變更前. Numbers come from [DiffLine.oldLine].
  left,

  /// 變更後. Numbers come from [DiffLine.newLine].
  right,
}

/// One cell of a side-by-side diff: the [DiffLine] half of a
/// [SideBySideRow](../side_by_side_diff.dart), or blank padding when that
/// side of the pair has nothing to show.
///
/// The unified counterpart is [DiffLineView] (`diff_line.dart`), which prints
/// *both* numbers in two gutters because it has one row per line. Here each
/// line appears in exactly one column, so there is one gutter and the column
/// decides what goes in it.
///
/// **[side] is what makes the number right, and getting it from [DiffLine.kind]
/// instead is the bug this widget was rewritten to fix.** The version deleted
/// in C13 used `kind == removed ? oldLine : newLine`, which is correct for a
/// removed line (left) and an added line (right) and **wrong for every context
/// line in the left column**: a context line is neither, so it fell to
/// `newLine` on both sides. Nothing showed as long as a hunk started at the
/// same number in both files; the moment an earlier hunk had added or removed
/// lines, the left column silently numbered the old file with the new file's
/// line numbers.
class SideBySideCell extends StatelessWidget {
  const SideBySideCell({super.key, required this.line, required this.side});

  /// Null means blank padding — a pure addition has no left line, a pure
  /// deletion no right line.
  final DiffLine? line;

  final SideBySideSide side;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final DiffLine? line = this.line;

    if (line == null) {
      // No height of its own. The pair's Row stretches both cells to the
      // taller one, so a wrapped line opposite this leaves no unpainted gap;
      // the fixed `height: 20` that used to be here did exactly that.
      return ColoredBox(color: colors.surfaceSunken, child: const SizedBox());
    }

    final (Color? background, Color textColor) = switch (line.kind) {
      DiffLineKind.added => (colors.diffAddBg, colors.diffAddText),
      DiffLineKind.removed => (colors.diffDelBg, colors.diffDelText),
      DiffLineKind.noNewlineMarker => (null, colors.textTertiary),
      DiffLineKind.context => (null, colors.textSecondary),
    };

    final String kindLabel = switch (line.kind) {
      DiffLineKind.added => 'added',
      DiffLineKind.removed => 'removed',
      DiffLineKind.noNewlineMarker => 'no newline at end of file',
      DiffLineKind.context => 'unchanged',
    };

    final int lineNumber = switch (side) {
      SideBySideSide.left => line.oldLine,
      SideBySideSide.right => line.newLine,
    };

    return GestureDetector(
      onSecondaryTapDown: (TapDownDetails details) =>
          _showContextMenu(context, details, line),
      child: Semantics(
        label: '$kindLabel line ${line.text}',
        child: Container(
          color: background,
          padding: const EdgeInsets.symmetric(
            horizontal: GbmSpacing.space2,
            vertical: 1,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: GbmLayout.diffGutterWidth,
                child: Text(
                  // 0 is git's "this line does not exist on this side", not
                  // line zero -- an added line has no old number and vice
                  // versa, and after the switch above that is exactly the
                  // case where this column should stay empty.
                  lineNumber == 0 ? '' : '$lineNumber',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontFamily: GbmTypography.fontMono,
                    fontSize: GbmTypography.textXs,
                    color: colors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(width: GbmSpacing.space2),
              Expanded(
                child: Text(
                  line.text,
                  style: TextStyle(
                    fontFamily: GbmTypography.fontMono,
                    fontSize: GbmTypography.textSm,
                    color: textColor,
                    height: 1.6,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Context menu 05-G, the same list [DiffLineView] builds — but with every
  /// mutating callback null. History's diff is read-only (there is no index
  /// to stage a historical commit's line into), so `Copy` is the only live
  /// item; the rest render disabled rather than hidden, which is what 05-G
  /// specifies and what the unified side already does.
  void _showContextMenu(
    BuildContext context,
    TapDownDetails details,
    DiffLine line,
  ) {
    showGbmContextMenu(
      context,
      details.globalPosition,
      diffLineMenuItems(
        count: 1,
        staged: false,
        onStageLines: null,
        onStageHunk: null,
        onCopyLines: () => Clipboard.setData(ClipboardData(text: line.text)),
        onDiscardLines: null,
      ),
    );
  }
}
