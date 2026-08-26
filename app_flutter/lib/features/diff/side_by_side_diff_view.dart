import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/parsed_diff.dart';
import '../../data/repositories/app_preferences_repository.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/code_line_metrics.dart';
import '../../widgets/gbm_code_hscroll.dart';
import 'side_by_side_diff.dart';
import 'widgets/side_by_side_cell.dart';

/// Read-only side-by-side alternative to [DiffPage] over the same
/// [ParsedDiff]: 變更前 on the left, 變更後 on the right, paired by
/// [pairHunkForSideBySide].
///
/// **Deleted once as orphan wiring, restored on the user's ruling
/// (2026-08-26)** — see `side_by_side_diff.dart`'s header for the full
/// account and for why 「the spec does not ask for this」 is no longer a
/// reason to delete it. `docs/reports/spec-conformance-matrix.md` has been
/// corrected in place to match.
///
/// Three things differ from the version that was deleted, each because it was
/// wrong (see `side_by_side_diff_view_test.dart`, which pins all three):
/// the line number is chosen by *column* rather than by line kind; a blank
/// padding cell stretches to its partner instead of being a fixed 20px; and
/// the list sits inside a [SelectionArea].
///
/// **One known cost of two columns in one selection scope**: dragging across
/// the divider copies old and new text interleaved. The Working Copy's
/// `2 file` mode has the same shape and the same behaviour, and 05-G's
/// `Copy` on a single cell is the per-side way out. Two separate selection
/// scopes would fix the copy and break the far commoner case of selecting a
/// whole changed region, so this is a chosen trade, not an oversight.
///
/// **Wrapping follows `AppPreferences.softWrapEnabled` like every other file
/// view.** The sentence that used to stand here — 「lines wrap, exactly as
/// [DiffPage]'s do, so no `softWrap: false` and no synchronised horizontal
/// scrolling are needed」 — was true when it was written and stopped being
/// true the moment `DiffPage` gained the preference: the two branches were
/// developed in parallel and met at a merge.
///
/// Both columns scroll on **one** [GbmCodeScrollWell]-style shared
/// controller, so a pair stays aligned while the content moves. With
/// wrapping off, alignment is in fact easier than with it on — every cell is
/// exactly one line tall, so the [IntrinsicHeight] below has nothing to
/// equalise.
///
/// **Neither gutter is pinned, and that is a decision.** Two columns mean two
/// line-number gutters and only the left one sits at the viewport's edge;
/// pinning that one alone would freeze the left column's numbers while the
/// right column's slid past, which reads as a broken layout rather than a
/// helpful one. `GbmPinnedGutter` is therefore deliberately absent here,
/// unlike in [DiffLineView]'s single-column rows.
class SideBySideDiffView extends ConsumerStatefulWidget {
  const SideBySideDiffView({
    super.key,
    required this.diff,
    this.scrollController,
  });

  final ParsedDiff diff;

  /// Optional controller so a caller can save/restore scroll position, as
  /// [DiffPage] allows. One controller drives the single list, because both
  /// columns scroll together by construction.
  final ScrollController? scrollController;

  @override
  ConsumerState<SideBySideDiffView> createState() => _SideBySideDiffViewState();
}

class _SideBySideDiffViewState extends ConsumerState<SideBySideDiffView> {
  /// Keyed on the `ParsedDiff` on screen. See [CodeWidthMemo] for what the
  /// key distinguishes and what a stale entry would look like.
  final CodeWidthMemo _widthMemo = CodeWidthMemo();

  /// Both columns plus the one-pixel divider.
  ///
  /// One width for the pair, not one per column: they scroll together, and a
  /// column measured on its own content would let the wider side stop short.
  /// The same widest-line figure serves both because a hunk's before and
  /// after text are drawn in the same style.
  double _contentWidth(bool softWrap) {
    if (softWrap) return 0;
    final double widest = _widthMemo.widthOf(
      key: widget.diff,
      text: () => <String>[
        for (final DiffFile file in widget.diff.files)
          for (final DiffHunk hunk in file.hunks)
            for (final DiffLine line in hunk.lines) line.text,
      ].join('\n'),
      style: kSideBySideCodeTextStyle,
    );
    return sideBySideColumnWidth(widest) * 2 + 1;
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final bool softWrap = ref.watch(appPreferencesProvider).softWrapEnabled;

    if (widget.diff.files.isEmpty) {
      return Center(
        child: Text('No changes', style: TextStyle(color: colors.textTertiary)),
      );
    }

    // Matches DiffPage: one shared selection scope over the whole list, not
    // per-line SelectableText, so a drag can cross rows.
    return SelectionArea(
      child: GbmCodeHScroll(
        contentWidth: _contentWidth(softWrap),
        backdrop: colors.surfacePanel,
        child: ListView(
          controller: widget.scrollController,
          children: <Widget>[
            for (final DiffFile file in widget.diff.files)
              _SideBySideFileSection(file: file, softWrap: softWrap),
          ],
        ),
      ),
    );
  }
}

class _SideBySideFileSection extends StatelessWidget {
  const _SideBySideFileSection({required this.file, required this.softWrap});

  final DiffFile file;
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
          _SideBySideHunkSection(hunk: hunk, softWrap: softWrap),
      ],
    );
  }
}

class _SideBySideHunkSection extends StatelessWidget {
  const _SideBySideHunkSection({required this.hunk, required this.softWrap});

  final bool softWrap;

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
          padding: const EdgeInsets.symmetric(
            horizontal: GbmSpacing.space3,
            vertical: 2,
          ),
          child: Text(
            '@@ -${hunk.oldStart},${hunk.oldCount} '
            '+${hunk.newStart},${hunk.newCount} @@ ${hunk.heading}',
            style: TextStyle(
              fontFamily: GbmTypography.fontMono,
              fontSize: GbmTypography.textXs,
              color: colors.textTertiary,
            ),
          ),
        ),
        for (final SideBySideRow row in rows)
          IntrinsicHeight(
            // `stretch`, so the shorter cell (usually a blank one) takes the
            // full height of the pair instead of leaving the column unpainted
            // beside a wrapped line. IntrinsicHeight is what gives the Row a
            // height to stretch *to* inside an unbounded-height ListView.
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: SideBySideCell(
                    line: row.left,
                    side: SideBySideSide.left,
                    softWrap: softWrap,
                  ),
                ),
                VerticalDivider(width: 1, color: colors.borderSubtle),
                Expanded(
                  child: SideBySideCell(
                    line: row.right,
                    side: SideBySideSide.right,
                    softWrap: softWrap,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
