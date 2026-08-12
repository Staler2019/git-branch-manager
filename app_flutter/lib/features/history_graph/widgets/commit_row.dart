import 'package:flutter/material.dart';

import '../../../data/models/commit_meta.dart';
import '../../../data/models/graph_snapshot.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_row.dart';
import 'graph_column_painter.dart';

const double kGraphLaneWidth = 18;
const double kCommitRowHeight = GbmSpacing.rowHeightComfortable;

/// `graph · [HEAD] · hash · subject · author · date`, the design doc's
/// commit-list row order. Wrapped in [GbmRow] (Commit 1) for the shared
/// hover/selected background instead of a bare [SizedBox], so a commit list
/// looks and behaves like every other list in the app (sidebar, repo list).
class CommitRow extends StatelessWidget {
  const CommitRow({
    super.key,
    required this.row,
    required this.oidHex,
    required this.previousLane,
    required this.nextLane,
    required this.maxLane,
    this.meta,
    this.selected = false,
    this.onTap,
  });

  final GraphRow row;
  final String oidHex;
  final int? previousLane;
  final int? nextLane;
  final int maxLane;

  /// Null while [history_repository.dart]'s `commitMetaProvider` has not
  /// yet answered for this row's oid -- rendered as a skeleton placeholder
  /// rather than leaving subject/author blank, so the row does not visibly
  /// pop in a beat after the graph itself renders.
  final CommitMeta? meta;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final Color laneColor =
        colors.graphLanes[row.color % colors.graphLanes.length];
    final DateTime time = DateTime.fromMillisecondsSinceEpoch(
      row.commitTime * 1000,
      isUtc: true,
    );
    final String date = time.toIso8601String().split('T').first;
    final String subject = meta?.subject ?? '';
    final String author = meta?.author.name ?? '';

    return Semantics(
      label:
          '${row.isHead ? 'HEAD, ' : ''}commit ${oidHex.isEmpty ? '' : oidHex.substring(0, 8)}, '
          '${subject.isEmpty ? '' : '$subject, '}$date, '
          '${row.parentCount} parent${row.parentCount == 1 ? '' : 's'}${row.isMerge ? ', merge' : ''}',
      child: GbmRow(
        height: kCommitRowHeight,
        selected: selected,
        onTap: onTap,
        padding: EdgeInsets.zero,
        child: Row(
          children: <Widget>[
            SizedBox(
              width: kGraphLaneWidth * (maxLane + 1),
              height: kCommitRowHeight,
              child: ExcludeSemantics(
                child: CustomPaint(
                  painter: GraphRowPainter(
                    row: row,
                    previousLane: previousLane,
                    nextLane: nextLane,
                    color: laneColor,
                    laneWidth: kGraphLaneWidth,
                  ),
                ),
              ),
            ),
            const SizedBox(width: GbmSpacing.space2),
            if (row.isHead)
              Padding(
                padding: const EdgeInsets.only(right: GbmSpacing.space2),
                child: Text(
                  'HEAD',
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    fontWeight: GbmTypography.weightSemibold,
                    color: colors.accent,
                  ),
                ),
              ),
            Text(
              oidHex.isEmpty ? '' : oidHex.substring(0, 8),
              style: TextStyle(
                fontFamily: GbmTypography.fontMono,
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
              ),
            ),
            const SizedBox(width: GbmSpacing.space3),
            Expanded(
              child: meta == null
                  ? _SkeletonBlock(width: 220, colors: colors)
                  : Text(
                      subject,
                      style: TextStyle(
                        fontSize: GbmTypography.textSm,
                        color: colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            const SizedBox(width: GbmSpacing.space3),
            SizedBox(
              width: 110,
              child: meta == null
                  ? _SkeletonBlock(width: 80, colors: colors)
                  : Text(
                      author,
                      style: TextStyle(
                        fontSize: GbmTypography.textXs,
                        color: colors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            const SizedBox(width: GbmSpacing.space2),
            SizedBox(
              width: 80,
              child: Text(
                date,
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: colors.textTertiary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: GbmSpacing.space3),
          ],
        ),
      ),
    );
  }
}

/// A static placeholder bar standing in for not-yet-loaded subject/author
/// text -- deliberately not animated (no shimmer): [CommitMeta] batches
/// answer within one `cat-file` round trip per viewport, not a slow network
/// call, so a static block avoids extra `AnimationController` churn for a
/// state that is normally visible for a single frame or two.
class _SkeletonBlock extends StatelessWidget {
  const _SkeletonBlock({required this.width, required this.colors});

  final double width;
  final GbmColors colors;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        width: width,
        height: 10,
        decoration: BoxDecoration(
          color: colors.surfaceSunken,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}
