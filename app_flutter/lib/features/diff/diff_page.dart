import 'package:flutter/material.dart';

import '../../data/models/parsed_diff.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import 'widgets/diff_line.dart';

/// Renders a [ParsedDiff]: one hunk header + line list per file, per hunk.
/// Used embedded in `features/working_copy/working_copy_view.dart` for M2;
/// a routed `/repo/:repoId/diff/:commitId` variant for commit history diffs
/// is a later milestone (see the plan's routing table) but reuses this same
/// widget.
class DiffPage extends StatelessWidget {
  const DiffPage({super.key, required this.diff});

  final ParsedDiff diff;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    if (diff.files.isEmpty) {
      return Center(child: Text('No changes', style: TextStyle(color: colors.textTertiary)));
    }

    // SelectionArea, not per-line SelectableText: a diff is read by
    // dragging a selection across many lines at once (to copy a whole
    // hunk), which only a single shared selection scope over the list
    // supports -- isolated per-widget SelectableText instances would each
    // be their own selection island.
    return SelectionArea(
      child: ListView(
        children: <Widget>[
          for (final file in diff.files) _DiffFileSection(file: file),
        ],
      ),
    );
  }
}

class _DiffFileSection extends StatelessWidget {
  const _DiffFileSection({required this.file});

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
        for (final hunk in file.hunks) _DiffHunkSection(hunk: hunk),
      ],
    );
  }
}

class _DiffHunkSection extends StatelessWidget {
  const _DiffHunkSection({required this.hunk});

  final DiffHunk hunk;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
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
        for (final line in hunk.lines) DiffLineView(line: line),
      ],
    );
  }
}
