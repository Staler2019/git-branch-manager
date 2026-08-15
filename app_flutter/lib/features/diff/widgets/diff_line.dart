import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/parsed_diff.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_menu.dart';

/// `.gbm-diffline`/`.gbm-diffline-add`/`.gbm-diffline-del`/`.gbm-diffline-ctx`
/// (docs/design/tokens-reference.md's components.css). One monospace row per
/// [DiffLine], with old/new line numbers in a fixed-width gutter like every
/// git diff viewer.
class DiffLineView extends StatelessWidget {
  const DiffLineView({
    super.key,
    required this.line,
    this.selectable = false,
    this.selected = false,
    this.onSelectedChanged,
    this.staged = false,
    this.onStageLine,
    this.onStageHunk,
  });

  final DiffLine line;

  /// Whether this line can be checked for line-level staging -- only added/
  /// removed lines are ever selectable (context and no-newline-marker lines
  /// always pass through a rebuilt patch regardless, see
  /// UnifiedDiffParser::buildLineSelectionPatch's doc comment), so this is
  /// false for those even when the caller passes true.
  final bool selectable;
  final bool selected;
  final VoidCallback? onSelectedChanged;

  /// Whether this diff is in the staged section (true) or unstaged (false).
  /// Used to determine the label for the Stage/Unstage line menu item.
  final bool staged;

  /// Callback when user selects "Stage line" or "Unstage line" from the
  /// context menu. Only visible for added/removed lines.
  final VoidCallback? onStageLine;

  /// Callback when user selects "Stage hunk" or "Unstage hunk" from the
  /// context menu.
  final VoidCallback? onStageHunk;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final (
      Color? background,
      Color textColor,
      String marker,
    ) = switch (line.kind) {
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

    final bool showCheckbox =
        selectable &&
        onSelectedChanged != null &&
        (line.kind == DiffLineKind.added || line.kind == DiffLineKind.removed);

    return GestureDetector(
      onSecondaryTapDown: (details) => _showContextMenu(context, details),
      child: Semantics(
        label: '$kindLabel line ${line.text}',
        child: Container(
          color: background,
          padding: const EdgeInsets.symmetric(
            horizontal: GbmSpacing.space3,
            vertical: 1,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 18,
                child: showCheckbox
                    ? Semantics(
                        label:
                            '${selected ? 'Unselect' : 'Select'} line for partial staging',
                        child: Checkbox(
                          value: selected,
                          onChanged: (_) => onSelectedChanged!(),
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                        ),
                      )
                    : null,
              ),
              SizedBox(
                width: 36,
                child: _lineNumberText(line.oldLine, colors.textTertiary),
              ),
              SizedBox(
                width: 36,
                child: _lineNumberText(line.newLine, colors.textTertiary),
              ),
              SizedBox(
                width: 14,
                child: Text(
                  marker,
                  style: TextStyle(
                    fontFamily: GbmTypography.fontMono,
                    fontSize: GbmTypography.textSm,
                    color: textColor,
                  ),
                ),
              ),
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

  void _showContextMenu(BuildContext context, TapDownDetails details) {
    final bool isAddedOrRemoved =
        line.kind == DiffLineKind.added || line.kind == DiffLineKind.removed;
    final items = <GbmMenuItem>[
      if (isAddedOrRemoved && onStageLine != null)
        GbmMenuItem(
          label: staged ? 'Unstage line' : 'Stage line',
          icon: staged ? Icons.remove : Icons.add,
          onTap: onStageLine,
        ),
      if (onStageHunk != null)
        GbmMenuItem(
          label: staged ? 'Unstage hunk' : 'Stage hunk',
          onTap: onStageHunk,
        ),
      GbmMenuItem(
        label: 'Copy line',
        icon: Icons.copy,
        onTap: () => Clipboard.setData(ClipboardData(text: line.text)),
      ),
    ];

    showGbmContextMenu(context, details.globalPosition, items);
  }

  Widget _lineNumberText(int lineNumber, Color color) {
    return Text(
      lineNumber == 0 ? '' : '$lineNumber',
      textAlign: TextAlign.right,
      style: TextStyle(
        fontFamily: GbmTypography.fontMono,
        fontSize: GbmTypography.textXs,
        color: color,
      ),
    );
  }
}
