import 'package:flutter/material.dart';

import '../../data/models/parsed_diff.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_button.dart';
import 'widgets/diff_line.dart';

/// Renders a [ParsedDiff]: one hunk header + line list per file, per hunk.
/// Used embedded in `features/working_copy/working_copy_view.dart` for M2;
/// a routed `/repo/:repoId/diff/:commitId` variant for commit history diffs
/// is a later milestone (see the plan's routing table) but reuses this same
/// widget.
///
/// [onStageHunk]/[onStageLines] are null in read-only contexts (a future
/// commit-diff view has nothing to stage); when set, each hunk gets a
/// whole-hunk stage/unstage button plus per-line checkboxes on added/
/// removed lines that reveal a "stage/unstage selected lines" button once
/// any are checked -- the Dart analog of `DiffView`'s hunk/line context-menu
/// actions (src/app/views/DiffView.cpp), just surfaced as buttons instead of
/// a text-selection-driven context menu, since Flutter's `SelectionArea`
/// (used here for copy -- see below) already owns click-drag selection.
class DiffPage extends StatefulWidget {
  const DiffPage({super.key, required this.diff, this.staged = false, this.onStageHunk, this.onStageLines});

  final ParsedDiff diff;
  final bool staged;
  final void Function(int fileIndex, int hunkIndex)? onStageHunk;
  final void Function(int fileIndex, int hunkIndex, List<int> lineIndices)? onStageLines;

  @override
  State<DiffPage> createState() => _DiffPageState();
}

class _DiffPageState extends State<DiffPage> {
  /// Keyed by "$fileIndex:$hunkIndex" -- line indices (within that hunk's
  /// `lines` array) currently checked for line-level staging. Reset
  /// wholesale whenever a new diff arrives (see `didUpdateWidget`), since a
  /// stage/unstage action changes hunk boundaries and stale indices would
  /// silently point at the wrong lines.
  final Map<String, Set<int>> _selectedLines = <String, Set<int>>{};

  @override
  void didUpdateWidget(DiffPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.diff, widget.diff)) {
      _selectedLines.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    if (widget.diff.files.isEmpty) {
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
          for (int fileIndex = 0; fileIndex < widget.diff.files.length; fileIndex++)
            _DiffFileSection(
              file: widget.diff.files[fileIndex],
              staged: widget.staged,
              onStageHunk: widget.onStageHunk == null ? null : (hunkIndex) => widget.onStageHunk!(fileIndex, hunkIndex),
              onStageLines: widget.onStageLines == null
                  ? null
                  : (hunkIndex, lineIndices) => widget.onStageLines!(fileIndex, hunkIndex, lineIndices),
              selectedLinesFor: (hunkIndex) => _selectedLines['$fileIndex:$hunkIndex'] ?? const <int>{},
              onToggleLine: (hunkIndex, lineIndex) => setState(() {
                final String key = '$fileIndex:$hunkIndex';
                final Set<int> selected = _selectedLines.putIfAbsent(key, () => <int>{});
                if (!selected.add(lineIndex)) selected.remove(lineIndex);
              }),
            ),
        ],
      ),
    );
  }
}

class _DiffFileSection extends StatelessWidget {
  const _DiffFileSection({
    required this.file,
    required this.staged,
    required this.onStageHunk,
    required this.onStageLines,
    required this.selectedLinesFor,
    required this.onToggleLine,
  });

  final DiffFile file;
  final bool staged;
  final void Function(int hunkIndex)? onStageHunk;
  final void Function(int hunkIndex, List<int> lineIndices)? onStageLines;
  final Set<int> Function(int hunkIndex) selectedLinesFor;
  final void Function(int hunkIndex, int lineIndex) onToggleLine;

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
        for (int hunkIndex = 0; hunkIndex < file.hunks.length; hunkIndex++)
          _DiffHunkSection(
            hunk: file.hunks[hunkIndex],
            staged: staged,
            onStageHunk: onStageHunk == null ? null : () => onStageHunk!(hunkIndex),
            onStageLines: onStageLines == null ? null : (lineIndices) => onStageLines!(hunkIndex, lineIndices),
            selectedLines: selectedLinesFor(hunkIndex),
            onToggleLine: (lineIndex) => onToggleLine(hunkIndex, lineIndex),
          ),
      ],
    );
  }
}

class _DiffHunkSection extends StatelessWidget {
  const _DiffHunkSection({
    required this.hunk,
    required this.staged,
    required this.onStageHunk,
    required this.onStageLines,
    required this.selectedLines,
    required this.onToggleLine,
  });

  final DiffHunk hunk;
  final bool staged;
  final VoidCallback? onStageHunk;
  final void Function(List<int> lineIndices)? onStageLines;
  final Set<int> selectedLines;
  final ValueChanged<int> onToggleLine;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          color: colors.surfaceSunken,
          padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3, vertical: 2),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '@@ -${hunk.oldStart},${hunk.oldCount} +${hunk.newStart},${hunk.newCount} @@ ${hunk.heading}',
                  style: TextStyle(fontFamily: GbmTypography.fontMono, fontSize: GbmTypography.textXs, color: colors.textTertiary),
                ),
              ),
              if (selectedLines.isNotEmpty && onStageLines != null)
                GbmButton(
                  label: '${staged ? 'Unstage' : 'Stage'} ${selectedLines.length} Line${selectedLines.length == 1 ? '' : 's'}',
                  onPressed: () => onStageLines!(selectedLines.toList(growable: false)..sort()),
                ),
              if (onStageHunk != null) ...<Widget>[
                const SizedBox(width: GbmSpacing.space1),
                GbmButton(label: staged ? 'Unstage Hunk' : 'Stage Hunk', onPressed: onStageHunk),
              ],
            ],
          ),
        ),
        for (int lineIndex = 0; lineIndex < hunk.lines.length; lineIndex++)
          DiffLineView(
            line: hunk.lines[lineIndex],
            selectable: onStageLines != null,
            selected: selectedLines.contains(lineIndex),
            onSelectedChanged: onStageLines == null ? null : () => onToggleLine(lineIndex),
          ),
      ],
    );
  }
}
