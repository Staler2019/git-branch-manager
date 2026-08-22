import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../actions/gbm_selection_gesture.dart';
import '../../../data/models/commit_meta.dart';
import '../../../data/models/graph_snapshot.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_menu.dart';
import '../../../widgets/gbm_row.dart';
import '../../../widgets/gbm_tag_chip.dart';
import 'commit_menu_items.dart';
import 'graph_column_painter.dart';
import 'graph_date_format.dart';
import 'graph_ref_chips.dart';

/// Aliases [GbmLayout.graphLaneWidth] rather than repeating its value.
///
/// The token existed but had no reader anywhere under `lib/` -- this file's
/// own literal was the live number, so a spec revision had two edit sites
/// and only one of them mattered. Kept as a top-level name because the
/// painter and every graph test already import it by this name; what
/// changes is where the number comes from.
const double kGraphLaneWidth = GbmLayout.graphLaneWidth;
const double kCommitRowHeight = GbmSpacing.rowHeightComfortable;

/// `graph · [HEAD] · hash · subject · author · date`, the design doc's
/// commit-list row order. Wrapped in [GbmRow] (Commit 1) for the shared
/// hover/selected background instead of a bare [SizedBox], so a commit list
/// looks and behaves like every other list in the app (sidebar, repo list).
///
/// Right-click context menu (05-E) actions: checkout, cherry-pick, copy SHA,
/// revert, create branch. Callers supply callbacks for actions with real
/// destinations; omitted actions (merge-into-current, compare items) have no
/// backing capability at this row level.
class CommitRow extends StatelessWidget {
  const CommitRow({
    super.key,
    required this.row,
    required this.oidHex,
    required this.graph,
    required this.rowIndex,
    required this.maxLane,
    this.meta,
    this.selected = false,
    this.onTap,
    this.onSelect,
    this.onContextMenuRequested,
    this.refChips = const <RefChipData>[],
    this.isOwnCommit = false,
    this.showGraph = true,
    this.onCheckout,
    this.onCherryPick,
    this.onRevert,
    this.onCreateBranchHere,
    this.onMerge,
    this.onCompare,
    this.onRebaseOntoHere,
    this.onResetBranchHere,
    this.onExportAsPatch,
    this.onCompareWithWorkingCopy,
    this.menuSelectionCount = 1,
    this.menuSelectionIsContiguous = true,
    this.conflictActive = false,
    this.menuTitle,
    this.onCopySha,
  });

  final GraphRow row;
  final String oidHex;
  final GraphSnapshotView graph;
  final int rowIndex;
  final int maxLane;

  /// Null while [history_repository.dart]'s `commitMetaProvider` has not
  /// yet answered for this row's oid -- rendered as a skeleton placeholder
  /// rather than leaving subject/author blank, so the row does not visibly
  /// pop in a beat after the graph itself renders.
  final CommitMeta? meta;
  final bool selected;
  final VoidCallback? onTap;

  /// Reports the spec page 13 gesture a click carried (plain / Ctrl-Cmd /
  /// Shift), leaving the selection arithmetic to the caller, which is the
  /// only side that knows the list this row sits in.
  ///
  /// When null, [onTap] is used unchanged -- the pre-multi-select behaviour,
  /// which the parity and row tests still drive.
  final void Function(SelectionGesture gesture)? onSelect;

  /// Called on right-click **before** the menu is built, so the caller can
  /// make the selection match what the menu is about to act on.
  ///
  /// Spec page 13: 「右鍵點在已選中的項目上不改變 selection…；點在未選中的
  /// 項目上先改為只選它、再開選單，避免對看不見的選取做動作」 -- right-
  /// clicking an already-selected row leaves the selection alone, while
  /// right-clicking an unselected one collapses to just that row first, so
  /// no action is ever aimed at a selection the user cannot see. Only the
  /// caller knows the selection, so the rule lives there; this is the hook
  /// that lets it run first.
  final VoidCallback? onContextMenuRequested;

  /// Chip render data for this commit (from `graph_ref_chips.dart`'s
  /// `refChipsForCommit`, already carrying the local/origin merge rule),
  /// rendered as `GbmTagChip`s before the subject.
  final List<RefChipData> refChips;

  /// True when [meta]'s author email matches the effective git identity --
  /// bolds and accent-colors the author text only (never the row
  /// background, which would conflict with selection/hover states).
  final bool isOwnCommit;

  /// Whether to draw the lane column on the left.
  ///
  /// False while the commit list is filtered (Edit → Find in history): the
  /// edges in [graph] connect rows of the *unfiltered* history, so painting
  /// them beside a filtered subset would draw lines between commits that are
  /// not actually parent and child. Spec page 02 item 6 describes the lanes
  /// as a faithful picture of the DAG, so under a filter the honest thing is
  /// to omit the graph rather than draw one that lies.
  final bool showGraph;

  /// Right-click context menu callbacks for the 05-E commit menu. Null when
  /// the caller has no destination to offer for that action.
  final VoidCallback? onCheckout;
  final VoidCallback? onCherryPick;
  final VoidCallback? onRevert;
  final VoidCallback? onCreateBranchHere;
  final VoidCallback? onMerge;
  final VoidCallback? onCompare;
  final VoidCallback? onRebaseOntoHere;
  final VoidCallback? onResetBranchHere;
  final VoidCallback? onExportAsPatch;
  final VoidCallback? onCompareWithWorkingCopy;

  /// How many commits the menu is about to act on, and whether they form an
  /// unbroken run -- see [commitMenuItems], which turns them into counted
  /// labels and MULTIACTS' contiguity gate. Both default to the
  /// single-selection case, so a caller with no multi-select (the parity
  /// test, any future one-row surface) gets exactly the spec's singular
  /// menu with nothing disabled.
  final int menuSelectionCount;
  final bool menuSelectionIsContiguous;

  /// Spec page 07's STATES rule: mid-sequencer, the HEAD-moving items are
  /// disabled. Passed in rather than re-derived here, matching how
  /// `BranchTreeItem` and `TabRow` take the same flag.
  final bool conflictActive;

  /// Header naming the selection size, per spec page 13's
  /// 「選單標題顯示數量」. Null for a single row, which needs no header.
  final String? menuTitle;

  /// Overrides the default "copy this row's oid" -- a multi-selection copies
  /// every selected SHA, one per line, which only the caller can assemble.
  final VoidCallback? onCopySha;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final DateTime time = DateTime.fromMillisecondsSinceEpoch(
      row.commitTime * 1000,
      isUtc: true,
    );
    final String date = formatGraphDate(time, DateTime.now());
    final String dateTooltip = formatGraphDateTooltip(time);
    final String subject = meta?.subject ?? '';
    final String author = meta?.author.name ?? '';

    return Semantics(
      label:
          '${row.isHead ? 'HEAD, ' : ''}commit ${oidHex.isEmpty ? '' : oidHex.substring(0, 8)}, '
          '${subject.isEmpty ? '' : '$subject, '}$date, '
          '${row.parentCount} parent${row.parentCount == 1 ? '' : 's'}${row.isMerge ? ', merge' : ''}',
      child: GestureDetector(
        onSecondaryTapDown: oidHex.isEmpty
            ? null
            : (details) => _openContextMenu(context, details),
        child: GbmRow(
          height: kCommitRowHeight,
          selected: selected,
          onTap: onSelect == null
              ? onTap
              : () => onSelect!(currentSelectionGesture()),
          padding: EdgeInsets.zero,
          child: Row(
            children: <Widget>[
              if (showGraph)
                SizedBox(
                  width: kGraphLaneWidth * (maxLane + 1),
                  height: kCommitRowHeight,
                  child: ExcludeSemantics(
                    child: CustomPaint(
                      painter: GraphRowPainter(
                        row: row,
                        rowIndex: rowIndex,
                        graph: graph,
                        laneWidth: kGraphLaneWidth,
                        colors: context.gbmColors,
                      ),
                    ),
                  ),
                )
              else
                // Keeps the subject column aligned with the unfiltered list,
                // so results do not jump horizontally as the query changes.
                const SizedBox(width: GbmSpacing.space3),
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
              if (refChips.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: GbmSpacing.space2),
                  child: Wrap(
                    spacing: 4,
                    children: <Widget>[
                      for (final RefChipData chip in refChips)
                        GbmTagChip(
                          label: chip.label,
                          kind: chip.kind,
                          isCurrent: chip.isCurrent,
                          showCloudIcon: chip.showCloudIcon,
                          isDashed: chip.isDashed,
                        ),
                    ],
                  ),
                ),
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
                          color: isOwnCommit
                              ? colors.accent
                              : colors.textSecondary,
                          fontWeight: isOwnCommit
                              ? GbmTypography.weightSemibold
                              : null,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
              const SizedBox(width: GbmSpacing.space2),
              SizedBox(
                width: 80,
                child: Tooltip(
                  message: dateTooltip,
                  child: Text(
                    date,
                    style: TextStyle(
                      fontSize: GbmTypography.textXs,
                      color: colors.textTertiary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: GbmSpacing.space3),
            ],
          ),
        ),
      ),
    );
  }

  /// The full 05-E menu, built from the shared [commitMenuItems] catalog
  /// function rather than a hand-written list -- see its doc comment for
  /// what "disabled with a tooltip" and the counted labels mean.
  List<GbmMenuItem> _buildMenuItems() => commitMenuItems(
    count: menuSelectionCount,
    contiguous: menuSelectionIsContiguous,
    conflictActive: conflictActive,
    onCopySha:
        onCopySha ?? () => Clipboard.setData(ClipboardData(text: oidHex)),
    onCheckout: onCheckout,
    onMerge: onMerge,
    onCherryPick: onCherryPick,
    onCreateBranchHere: onCreateBranchHere,
    onCompare: onCompare,
    onRebaseOntoHere: onRebaseOntoHere,
    onResetBranchHere: onResetBranchHere,
    onRevert: onRevert,
    onExportAsPatch: onExportAsPatch,
    onCompareWithWorkingCopy: onCompareWithWorkingCopy,
  );

  void _openContextMenu(BuildContext context, TapDownDetails details) {
    onContextMenuRequested?.call();
    showGbmContextMenu(
      context,
      details.globalPosition,
      _buildMenuItems(),
      title: menuTitle,
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
