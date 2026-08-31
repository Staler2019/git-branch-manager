import 'package:flutter/material.dart';

import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_badge.dart';
import '../../../widgets/gbm_row.dart';
import 'commit_row.dart' show kCommitRowHeight;
import 'graph_column_painter.dart' show kGraphLaneInset;

/// History's uncommitted-changes row, pinned above the commit list.
///
/// **Not a list item, deliberately.** Prepending a row to `CommitGraphView`'s
/// `ListView` would shift every index the graph's edge lookups, its span index
/// and its selection ranges are keyed on -- and `UnfilteredRowIndices` is an
/// O(1) identity view precisely because those indices are the row numbers. The
/// row therefore lives above the scrollable, reads
/// `RepoSessionState.workingCopyStatus` directly, and costs no history walk:
/// saving a file republishes the working-copy status, never the graph, so this
/// updates on the same frame as the tab badge without a `publish()` (which is
/// O(rows) and would stutter on every save).
///
/// It occupies lane 0 because lane 0 is HEAD's branch (spec P02's 「目前開發中
/// 的分支永遠佔 lane 0」, implemented by `GraphOptions::trunkTip`), and the
/// uncommitted work sits on top of HEAD. When the trunk really is the row
/// underneath, [connectsDown] draws the segment that says so.
///
/// **No spec entry.** The 21-page spec has no uncommitted row anywhere, and
/// `spec_logic.js`'s own History mock starts at a real commit. This is a
/// user-requested addition like the soft-wrap preference, not a conformance
/// item -- see docs/rules/arch-structure.md.
class HistoryWorkingCopyRow extends StatelessWidget {
  const HistoryWorkingCopyRow({
    super.key,
    required this.pendingChangeCount,
    required this.selected,
    required this.connectsDown,
    required this.onTap,
  });

  /// From `WorkingCopyStatus.pendingChangeCount`, the same getter the Working
  /// Copy tab badge reads. The row is not built at all when this is zero.
  final int pendingChangeCount;

  final bool selected;

  /// Whether to draw the segment from this row's dot down into the list.
  ///
  /// Only true when the topmost commit row really is HEAD's tip. Under a branch
  /// filter that excludes HEAD the row still shows -- the working copy exists
  /// regardless of what the graph is narrowed to -- but the line is omitted,
  /// because a segment drawn to an unrelated commit asserts a parent
  /// relationship that is not there. `HistoryQuery::isLinearWalk`'s bridge is
  /// allowed to mean "the next row" only because its doc comment says so in as
  /// many words; nothing grants that licence here.
  ///
  /// **Implementer's judgement, not a user ruling.**
  final bool connectsDown;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return GbmRow(
      key: const Key('history-working-copy-row'),
      height: kCommitRowHeight,
      padding: EdgeInsets.zero,
      selected: selected,
      onTap: onTap,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: kGraphLaneInset * 2,
            height: kCommitRowHeight,
            child: CustomPaint(
              painter: _WorkingCopyDotPainter(
                color: colors.graphLanes.first,
                connectsDown: connectsDown,
              ),
              // The measurable centre. A CustomPaint has no child widget to
              // find, and a test that asserts a painted position needs
              // something with a rect -- so the dot's box is a real, keyed
              // SizedBox sitting exactly where the paint puts the diamond.
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: kGraphLaneInset - _kDotRadius,
                  ),
                  child: SizedBox(
                    key: const Key('history-working-copy-dot'),
                    width: _kDotRadius * 2,
                    height: _kDotRadius * 2,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: GbmSpacing.space2),
          Expanded(
            child: Text(
              'Uncommitted changes',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
          GbmBadge(label: '$pendingChangeCount'),
          const SizedBox(width: GbmSpacing.space3),
        ],
      ),
    );
  }
}

/// Half the dot's width. Deliberately the same 5.0 the commit dots use
/// (docs/rules/ops-spec-reading.md's [SPEC-graph-lane-pitch]), so the two read
/// as one column rather than as a marker beside one.
const double _kDotRadius = 5.0;

class _WorkingCopyDotPainter extends CustomPainter {
  const _WorkingCopyDotPainter({
    required this.color,
    required this.connectsDown,
  });

  final Color color;
  final bool connectsDown;

  @override
  void paint(Canvas canvas, Size size) {
    final double centerY = size.height / 2;
    const double centerX = kGraphLaneInset;

    if (connectsDown) {
      canvas.drawLine(
        Offset(centerX, centerY),
        Offset(centerX, size.height),
        Paint()
          ..color = color
          ..strokeWidth = 1.75
          ..style = PaintingStyle.stroke,
      );
    }

    // A hollow diamond, not a filled circle: this is not a commit, and the
    // difference has to survive a glance down the column.
    final Path diamond = Path()
      ..moveTo(centerX, centerY - _kDotRadius)
      ..lineTo(centerX + _kDotRadius, centerY)
      ..lineTo(centerX, centerY + _kDotRadius)
      ..lineTo(centerX - _kDotRadius, centerY)
      ..close();
    canvas.drawPath(
      diamond,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(_WorkingCopyDotPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.connectsDown != connectsDown;
}
