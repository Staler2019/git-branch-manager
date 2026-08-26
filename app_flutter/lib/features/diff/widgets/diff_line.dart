import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/models/parsed_diff.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/code_line_metrics.dart';
import '../../../widgets/gbm_code_hscroll.dart';
import '../../../widgets/gbm_menu.dart';
import 'diff_line_menu_items.dart';

/// `.gbm-diffline`/`.gbm-diffline-add`/`.gbm-diffline-del`/`.gbm-diffline-ctx`
/// (docs/design/tokens-reference.md's components.css). One monospace row per
/// [DiffLine], with old/new line numbers in a fixed-width gutter like every
/// git diff viewer.
/// Width of the pinned gutter: the row's left padding plus the two
/// line-number cells and the `+`/`-` marker.
///
/// The left padding is *inside* the gutter rather than outside it on purpose.
/// With soft wrap off the code slides sideways underneath the gutter, and
/// anything the gutter does not cover shows the scrolled line text to the left
/// of its own line numbers.
const double kDiffGutterWidth = GbmSpacing.space3 + 36 + 36 + 14;

/// The style a diff line's code is drawn in, colour aside.
///
/// Single-sourced because the horizontal scroll extent is *measured* in it
/// (`widestLineWidth`) and then *drawn* in it. If the two ever drifted apart
/// the pane would scroll to the wrong place -- short by the difference, which
/// clips the end of the longest line.
const TextStyle kDiffCodeTextStyle = TextStyle(
  fontFamily: GbmTypography.fontMono,
  fontSize: GbmTypography.textSm,
  height: 1.6,
);

class DiffLineView extends StatelessWidget {
  const DiffLineView({
    super.key,
    required this.line,
    this.staged = false,
    this.onStageLine,
    this.onStageHunk,
    this.onDiscardLine,
    this.selectionCount = 1,
    this.touched = false,
    required this.softWrap,
  });

  final DiffLine line;

  /// Whether this diff is in the staged section (true) or unstaged (false).
  /// Used to determine the label for the Stage/Unstage line menu item.
  final bool staged;

  /// Callback when user selects "Stage line" or "Unstage line" from the
  /// context menu. Only visible for added/removed lines.
  final VoidCallback? onStageLine;

  /// Callback when user selects "Stage hunk" or "Unstage hunk" from the
  /// context menu.
  final VoidCallback? onStageHunk;

  /// Callback when the user selects "Discard N lines…" (05-G's danger item).
  /// Null in a read-only diff and on the staged side -- discarding rewrites
  /// the work tree, which a staged-side line has nothing to do with.
  final VoidCallback? onDiscardLine;

  /// How many lines the Stage/Discard items act on. 1 unless this row is
  /// inside a scope or a temporary text selection, in which case the parent
  /// passes that block's size so the labels read "Stage 12 lines" /
  /// "Discard 12 lines…" per spec 05-G.
  final int selectionCount;

  /// This row is inside the current one-shot scope.
  ///
  /// A drag gets its highlight free from [SelectionArea], which paints the
  /// glyphs it covers. The other two inputs `SCOPES` names -- 「點 hunk 標頭
  /// 列」 and 「Shift + ↑ ↓」 -- select no *text* at all, so without this the
  /// user would be told what they had selected only by a count on a button.
  /// Drawn for the drag too, deliberately: one selection, one appearance,
  /// and a diff line's glyphs are far narrower than its row, so the native
  /// highlight alone is easy to miss.
  final bool touched;

  /// Whether a line too long for the pane wraps onto further visual lines
  /// (`AppPreferences.softWrapEnabled`), or runs off to the right inside the
  /// enclosing [GbmCodeHScroll] with the gutter pinned.
  ///
  /// **No default, deliberately.** Every call site has to say which it wants,
  /// so none can silently keep the old unconditional wrap after the preference
  /// exists.
  final bool softWrap;

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

    return GestureDetector(
      onSecondaryTapDown: (details) => _showContextMenu(context, details),
      child: Semantics(
        label: '$kindLabel line ${line.text}',
        child: Container(
          color: background,
          // `foregroundDecoration`, not a blended background: these rows sit
          // on two different backdrops (the well's surfaceSunken and a scope
          // card's surfacePanel), and an overlay composites over whichever
          // is actually there instead of having to know which.
          foregroundDecoration: touched
              ? BoxDecoration(color: colors.accent.withValues(alpha: 0.18))
              : null,
          padding: EdgeInsets.only(
            left: softWrap ? GbmSpacing.space3 : 0,
            right: GbmSpacing.space3,
            top: 1,
            bottom: 1,
          ),
          child: softWrap
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _gutterCells(colors, textColor, marker),
                    Expanded(child: _codeText(textColor)),
                  ],
                )
              // Not a Row: the gutter has to leave the flow entirely so it can
              // be counter-translated back to the viewport edge while the code
              // scrolls. It is painted *after* the code, and opaquely, because
              // the code passes underneath it rather than stopping at it.
              : Stack(
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(left: kDiffGutterWidth),
                      child: _codeText(textColor),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: GbmPinnedGutter(
                        width: kDiffGutterWidth,
                        background: background,
                        child: Padding(
                          padding: const EdgeInsets.only(
                            left: GbmSpacing.space3,
                          ),
                          child: _gutterCells(colors, textColor, marker),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// Context menu 05-G. The item list itself lives in
  /// `diff_line_menu_items.dart` so `context_menu_parity_test.dart` can check
  /// it against the spec catalog without pumping a widget.
  void _showContextMenu(BuildContext context, TapDownDetails details) {
    final bool isAddedOrRemoved =
        line.kind == DiffLineKind.added || line.kind == DiffLineKind.removed;
    showGbmContextMenu(
      context,
      details.globalPosition,
      diffLineMenuItems(
        count: selectionCount,
        staged: staged,
        onStageLines: isAddedOrRemoved ? onStageLine : null,
        onStageHunk: onStageHunk,
        onCopyLines: () => Clipboard.setData(ClipboardData(text: line.text)),
        onDiscardLines: isAddedOrRemoved ? onDiscardLine : null,
      ),
    );
  }

  Widget _codeText(Color textColor) {
    return Text(
      line.text,
      softWrap: softWrap,
      overflow: softWrap ? TextOverflow.clip : TextOverflow.visible,
      style: kDiffCodeTextStyle.copyWith(color: textColor),
    );
  }

  Widget _gutterCells(GbmColors colors, Color textColor, String marker) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
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
      ],
    );
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

/// How wide a well has to be for [diffFile]'s longest line to fit unwrapped.
///
/// Lives next to [kDiffGutterWidth] and [kDiffCodeTextStyle] because it is
/// the sum of exactly those two things and the measured text -- put it
/// anywhere else and the three drift apart silently, which shows up as a
/// scroll extent that stops a few characters short of the longest line.
///
/// `0` when [softWrap] is on: a wrapped line never exceeds its pane, so
/// there is nothing to scroll.
///
/// [memo] is the caller's, not a global: the answer is keyed on the
/// `DiffFile` identity and each pane holds its own file. See [CodeWidthMemo]
/// for why measuring is worth caching at all.
double diffFileContentWidth(
  DiffFile? diffFile, {
  required bool softWrap,
  required CodeWidthMemo memo,
}) {
  if (softWrap || diffFile == null) return 0;
  return kDiffGutterWidth +
      memo.widthOf(
        key: diffFile,
        text: () => <String>[
          for (final DiffHunk hunk in diffFile.hunks)
            for (final DiffLine line in hunk.lines) line.text,
        ].join('\n'),
        style: kDiffCodeTextStyle,
      ) +
      GbmSpacing.space3;
}
