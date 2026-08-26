import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/parsed_diff.dart';
import '../../data/repositories/app_preferences_repository.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/code_line_metrics.dart';
import '../../widgets/gbm_code_hscroll.dart';
import 'widgets/diff_line.dart';

/// Renders a [ParsedDiff] **read-only**: one hunk header + line list per
/// file, per hunk. Used by History's commit detail, Compare, the file- and
/// line-history panels -- every surface that shows a diff you cannot act on.
///
/// **Staging does not live here.** It used to: each hunk carried a
/// stage/unstage button and every added/removed line an 18px checkbox, so a
/// partial stage cost one tick per line before a button even appeared. Spec
/// P03's 變體 B replaces all of it with
/// [ScopedDiffView](scoped_diff_view.dart)'s cards, whose button is present
/// from the start and acts on a whole run of changes; that widget is the
/// Working Copy's diff and this one no longer has a mutating caller. The
/// three callbacks and the checkbox selection set were removed rather than
/// left behind, because a parameter no caller passes is this repo's
/// recurring defect shape.
class DiffPage extends ConsumerStatefulWidget {
  const DiffPage({
    super.key,
    required this.diff,
    this.staged = false,
    this.scrollController,
  });

  final ParsedDiff diff;

  /// Whether this diff is the staged side, which only changes the wording of
  /// context menu 05-G's Stage/Unstage item.
  final bool staged;

  /// Optional scroll controller for the diff ListView.
  /// If provided, allows external code to save/restore scroll position.
  final ScrollController? scrollController;

  @override
  ConsumerState<DiffPage> createState() => _DiffPageState();
}

class _DiffPageState extends ConsumerState<DiffPage> {
  /// One entry, keyed by the `ParsedDiff` currently shown. See
  /// [CodeWidthMemo] for what the key distinguishes and what going stale
  /// would look like.
  final CodeWidthMemo _widthMemo = CodeWidthMemo();

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final ParsedDiff diff = widget.diff;
    final bool softWrap = ref.watch(appPreferencesProvider).softWrapEnabled;

    if (diff.files.isEmpty) {
      return Center(
        child: Text('No changes', style: TextStyle(color: colors.textTertiary)),
      );
    }

    // SelectionArea, not per-line SelectableText: a diff is read by
    // dragging a selection across many lines at once (to copy a whole
    // hunk), which only a single shared selection scope over the list
    // supports -- isolated per-widget SelectableText instances would each
    // be their own selection island.
    // One scroll extent for the whole page, not one per file: the files are
    // in a single list and a per-file extent would make the content jump
    // sideways as the user scrolled past a file boundary.
    final double contentWidth = softWrap
        ? 0
        : kDiffGutterWidth +
              _widthMemo.widthOf(
                key: diff,
                text: () => <String>[
                  for (final DiffFile file in diff.files)
                    for (final DiffHunk hunk in file.hunks)
                      for (final DiffLine line in hunk.lines) line.text,
                ].join('\n'),
                style: kDiffCodeTextStyle,
              ) +
              GbmSpacing.space3;

    return SelectionArea(
      child: GbmCodeHScroll(
        contentWidth: contentWidth,
        backdrop: colors.surfacePanel,
        child: ListView(
          controller: widget.scrollController,
          children: <Widget>[
            for (final DiffFile file in diff.files)
              _DiffFileSection(
                file: file,
                staged: widget.staged,
                softWrap: softWrap,
              ),
          ],
        ),
      ),
    );
  }
}

class _DiffFileSection extends StatelessWidget {
  const _DiffFileSection({
    required this.file,
    required this.staged,
    required this.softWrap,
  });

  final DiffFile file;
  final bool staged;
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;

    if (file.binary) {
      return Padding(
        padding: const EdgeInsets.all(GbmSpacing.space3),
        child: Text(
          '${file.displayPath} (binary file)',
          style: TextStyle(
            color: colors.textTertiary,
            fontSize: GbmTypography.textSm,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final DiffHunk hunk in file.hunks)
          _DiffHunkSection(hunk: hunk, staged: staged, softWrap: softWrap),
      ],
    );
  }
}

class _DiffHunkSection extends StatelessWidget {
  const _DiffHunkSection({
    required this.hunk,
    required this.staged,
    required this.softWrap,
  });

  final DiffHunk hunk;
  final bool staged;
  final bool softWrap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Container(
          color: colors.surfaceSunken,
          padding: const EdgeInsets.symmetric(
            horizontal: GbmSpacing.space3,
            vertical: 2,
          ),
          child: Text(
            '@@ -${hunk.oldStart},${hunk.oldCount} '
            '+${hunk.newStart},${hunk.newCount} @@ ${hunk.heading}',
            softWrap: softWrap,
            overflow: softWrap ? TextOverflow.clip : TextOverflow.visible,
            style: TextStyle(
              fontFamily: GbmTypography.fontMono,
              fontSize: GbmTypography.textXs,
              color: colors.textTertiary,
            ),
          ),
        ),
        for (final DiffLine line in hunk.lines)
          DiffLineView(line: line, staged: staged, softWrap: softWrap),
      ],
    );
  }
}
