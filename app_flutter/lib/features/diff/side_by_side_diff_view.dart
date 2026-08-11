import 'package:flutter/material.dart';

import '../../data/models/parsed_diff.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import 'side_by_side_diff.dart';

/// Read-only side-by-side alternative to [DiffPage], built on the same
/// [ParsedDiff]. The Dart analog of `SideBySideDiffView`
/// (src/app/views/SideBySideDiffView.cpp) -- unlike the Qt original, this
/// stays read-only in every context here (no gutter-checkbox staging): the
/// working-copy tab's own Qt precedent already keeps hunk/line staging on
/// the unified view alone and never wires it into the side-by-side pane
/// (see WorkingCopyView.cpp's `buildDiffTab`), so [DiffPage]'s staging UI
/// (gap #51) is left as the one place staging happens here too.
class SideBySideDiffView extends StatelessWidget {
  const SideBySideDiffView({super.key, required this.diff});

  final ParsedDiff diff;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    if (diff.files.isEmpty) {
      return Center(child: Text('No changes', style: TextStyle(color: colors.textTertiary)));
    }

    return ListView(
      children: <Widget>[
        for (final file in diff.files) _SideBySideFileSection(file: file),
      ],
    );
  }
}

class _SideBySideFileSection extends StatelessWidget {
  const _SideBySideFileSection({required this.file});

  final DiffFile file;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    if (file.binary) {
      return Padding(
        padding: const EdgeInsets.all(GbmSpacing.space3),
        child: Text('${file.displayPath} (binary file)', style: TextStyle(color: colors.textTertiary, fontSize: GbmTypography.textSm)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final hunk in file.hunks) _SideBySideHunkSection(hunk: hunk),
      ],
    );
  }
}

class _SideBySideHunkSection extends StatelessWidget {
  const _SideBySideHunkSection({required this.hunk});

  final DiffHunk hunk;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<SideBySideRow> rows = pairHunkForSideBySide(hunk);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          color: colors.surfaceSunken,
          padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3, vertical: 2),
          child: Text(
            '@@ -${hunk.oldStart},${hunk.oldCount} +${hunk.newStart},${hunk.newCount} @@ ${hunk.heading}',
            style: TextStyle(fontFamily: GbmTypography.fontMono, fontSize: GbmTypography.textXs, color: colors.textTertiary),
          ),
        ),
        for (final row in rows)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(child: _SideBySideCell(line: row.left)),
              VerticalDivider(width: 1, color: colors.borderSubtle),
              Expanded(child: _SideBySideCell(line: row.right)),
            ],
          ),
      ],
    );
  }
}

class _SideBySideCell extends StatelessWidget {
  const _SideBySideCell({required this.line});

  final DiffLine? line;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final DiffLine? line = this.line;

    if (line == null) {
      // Blank padding row on whichever side has nothing to show -- keeps
      // the two panes vertically in lock-step (see pairHunkForSideBySide's
      // doc comment).
      return Container(color: colors.surfaceSunken, height: 20);
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
    final int lineNumber = line.kind == DiffLineKind.removed ? line.oldLine : line.newLine;

    return Semantics(
      label: '$kindLabel line ${line.text}',
      child: Container(
        color: background,
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2, vertical: 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 36,
              child: Text(
                lineNumber == 0 ? '' : '$lineNumber',
                textAlign: TextAlign.right,
                style: TextStyle(fontFamily: GbmTypography.fontMono, fontSize: GbmTypography.textXs, color: colors.textTertiary),
              ),
            ),
            const SizedBox(width: GbmSpacing.space2),
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
}
