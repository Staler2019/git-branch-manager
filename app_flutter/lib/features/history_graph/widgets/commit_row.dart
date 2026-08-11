import 'package:flutter/material.dart';

import '../../../data/models/graph_snapshot.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import 'graph_column_painter.dart';

const double kGraphLaneWidth = 18;
const double kCommitRowHeight = GbmSpacing.rowHeightComfortable;

class CommitRow extends StatelessWidget {
  const CommitRow({
    super.key,
    required this.row,
    required this.oidHex,
    required this.previousLane,
    required this.nextLane,
    required this.maxLane,
  });

  final GraphRow row;
  final String oidHex;
  final int? previousLane;
  final int? nextLane;
  final int maxLane;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final Color laneColor = colors.graphLanes[row.color % colors.graphLanes.length];
    final DateTime time = DateTime.fromMillisecondsSinceEpoch(row.commitTime * 1000, isUtc: true);
    final String date = time.toIso8601String().split('T').first;

    return Semantics(
      label:
          '${row.isHead ? 'HEAD, ' : ''}commit ${oidHex.isEmpty ? '' : oidHex.substring(0, 8)}, $date, '
          '${row.parentCount} parent${row.parentCount == 1 ? '' : 's'}${row.isMerge ? ', merge' : ''}',
      child: SizedBox(
        height: kCommitRowHeight,
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
                  style: TextStyle(fontSize: GbmTypography.textXs, fontWeight: GbmTypography.weightSemibold, color: colors.accent),
                ),
              ),
            Text(
              oidHex.isEmpty ? '' : oidHex.substring(0, 8),
              style: TextStyle(fontFamily: GbmTypography.fontMono, fontSize: GbmTypography.textXs, color: colors.textTertiary),
            ),
            const SizedBox(width: GbmSpacing.space3),
            Expanded(
              child: Text(
                '$date · ${row.parentCount} parent${row.parentCount == 1 ? '' : 's'}${row.isMerge ? ' · merge' : ''}',
                style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textPrimary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
