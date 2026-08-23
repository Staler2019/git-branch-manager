import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../actions/gbm_selection_gesture.dart';
import '../../../data/models/commit_meta.dart';
import '../../../data/models/graph_column.dart';
import '../../../data/models/graph_snapshot.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_menu.dart';
import '../../../widgets/gbm_row.dart';
import '../../../widgets/gbm_tag_chip.dart';
import 'commit_menu_items.dart';
import 'commit_row_layout.dart';
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

/// One commit row's height.
///
/// **26, spec's compact row -- not the comfortable 34 this used to be.**
/// The mockup draws History's rows at `height:26px`
/// (`spec_raw.html:1311`), its graph SVG is `height="182"` for seven rows
/// (182 ÷ 7 = 26), and the geometry constants behind those lines say so
/// outright: `const L0 = 15, L1 = 32, RH = 26` (`spec_logic.js:428`).
///
/// So the 34 was a pre-existing drift, and shrinking the list is a
/// conformance fix rather than a density preference. `rowHeightCompact` is
/// spec's own token (`--row-h-compact:26px`) and is already what the sidebar
/// and the working copy lists use, so nothing new is invented here.
const double kCommitRowHeight = GbmSpacing.rowHeightCompact;

/// `graph · subject · refs · author · date · hash`, spec page 02's own
/// column order -- see [planCommitRowColumns], which decides which of them
/// this row can afford. HEAD has no column of its own: it is a ref chip in
/// the Refs column (`refChipsForCommit`), which is the only way the mockup
/// draws it. Wrapped in [GbmRow] (Commit 1) for the shared
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
    this.plan = CommitRowColumnPlan.full,
    this.meta,
    this.fileCount,
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

  /// Which optional columns this row may draw at the list's current width.
  ///
  /// Computed once per list by CommitGraphView, never per row: author and
  /// date are trailing fixed-width columns, so a row deciding on its own
  /// would stop lining up with its neighbours. Defaults to
  /// [CommitRowColumnPlan.full] so callers that do not measure -- widget
  /// tests, mostly -- keep the pre-degradation layout.
  final CommitRowColumnPlan plan;

  /// Null while [history_repository.dart]'s `commitMetaProvider` has not
  /// yet answered for this row's oid -- rendered as a skeleton placeholder
  /// rather than leaving subject/author blank, so the row does not visibly
  /// pop in a beat after the graph itself renders.
  final CommitMeta? meta;

  /// How many files this commit changed, or null while
  /// `commitFileCountProvider` has not answered for this oid -- which,
  /// unlike [meta], is also the permanent state for a commit git could not
  /// answer for at all. Null renders a skeleton, `0` renders "0"; the two
  /// are deliberately different, because a commit really can change nothing
  /// (an empty commit, or a merge with no first-parent delta).
  final int? fileCount;
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
    final String committer = meta?.committer.name ?? '';

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
          // Built from plan.columns rather than a hardcoded child list, so
          // the order the user dragged in the picker is the order drawn --
          // and so the gaps come from `gapAfterColumn`, the same function
          // the width budget charges. The default is spec's own order
          // (`spec_raw.html:1310-1316`, and GRAPH_COLS in the same order):
          // graph, message, refs, author, date, hash.
          child: Row(
            children: <Widget>[
              for (final PlannedColumn column in plan.columns)
                ..._columnChildren(context, column, colors, <String, String>{
                  'subject': subject,
                  'author': author,
                  'committer': committer,
                  'date': date,
                  'dateTooltip': dateTooltip,
                }),
              const SizedBox(width: kRowTrailingGap),
            ],
          ),
        ),
      ),
    );
  }

  /// One column's widget plus the gap after it, or nothing at all when the
  /// column has nothing to draw (a commit with no ref chips, or a column
  /// whose feature has not landed yet).
  List<Widget> _columnChildren(
    BuildContext context,
    PlannedColumn column,
    GbmColors colors,
    Map<String, String> text,
  ) {
    final Widget? child = switch (column.id) {
      GbmGraphColumnId.graph => _graphColumn(context),
      GbmGraphColumnId.message => Expanded(
        child: meta == null
            ? _SkeletonBlock(width: 220, colors: colors)
            : Text(
                text['subject']!,
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
      ),
      // The strip sizes itself to its chips and is capped at the column's
      // width; a commit carrying none draws nothing and costs no gap, so the
      // message runs straight into the author exactly as the mockup shows.
      GbmGraphColumnId.refs =>
        refChips.isEmpty
            ? null
            : _RefChipStrip(chips: refChips, maxWidth: column.width),
      GbmGraphColumnId.hash => SizedBox(
        // A slot, not the glyphs' intrinsic width: the test font makes eight
        // hex characters ~88px against ~53px on a device, and the plan
        // budgets the column's width either way.
        width: column.width,
        child: Text(
          oidHex.isEmpty ? '' : oidHex.substring(0, 8),
          style: TextStyle(
            fontFamily: GbmTypography.fontMono,
            fontSize: GbmTypography.textXs,
            color: colors.textTertiary,
          ),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
      GbmGraphColumnId.author => SizedBox(
        width: column.width,
        child: meta == null
            ? _SkeletonBlock(width: 80, colors: colors)
            : Text(
                text['author']!,
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: isOwnCommit ? colors.accent : colors.textSecondary,
                  fontWeight: isOwnCommit ? GbmTypography.weightSemibold : null,
                ),
                overflow: TextOverflow.ellipsis,
              ),
      ),
      GbmGraphColumnId.date => SizedBox(
        width: column.width,
        child: Tooltip(
          message: text['dateTooltip']!,
          child: Text(
            text['date']!,
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.textTertiary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      // Styled like the author column but deliberately *without* its
      // own-commit accent: spec singles out the Author column for that
      // ("Author 欄以 accent 色加粗顯示"), and applying it here too would
      // make a rebased or cherry-picked commit -- where the committer is you
      // and the author is not -- claim to be yours in the wrong column.
      GbmGraphColumnId.committer => SizedBox(
        width: column.width,
        child: meta == null
            ? _SkeletonBlock(width: 80, colors: colors)
            : Text(
                text['committer']!,
                style: TextStyle(
                  fontSize: GbmTypography.textXs,
                  color: colors.textSecondary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
      ),
      // Right-aligned, unlike every other column: it is the row's only
      // numeric field, and a column of numbers that do not share a ones
      // place is markedly harder to compare down the list.
      GbmGraphColumnId.changedFiles => SizedBox(
        width: column.width,
        child: fileCount == null
            ? Align(
                alignment: Alignment.centerRight,
                child: _SkeletonBlock(width: 18, colors: colors),
              )
            : Text(
                '$fileCount',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontFamily: GbmTypography.fontMono,
                  fontSize: GbmTypography.textXs,
                  color: colors.textTertiary,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
      ),
    };
    if (child == null) return const <Widget>[];

    final double gap = gapAfterColumn(column.id);
    return <Widget>[child, if (gap > 0) SizedBox(width: gap)];
  }

  Widget _graphColumn(BuildContext context) {
    if (!showGraph) {
      // Keeps the subject column aligned with the unfiltered list, so
      // results do not jump horizontally as the query changes.
      return const SizedBox(width: GbmSpacing.space3);
    }
    return SizedBox(
      // plan.graphWidth is the natural width unless the row is too narrow to
      // hold it and the message floor at once, in which case it is clipped --
      // lane 0 paints leftmost, so what goes is always the highest lanes,
      // never HEAD or the trunk. ClipRect is what keeps that a clip rather
      // than a CustomPaint drawing outside its box.
      width: plan.graphWidth ?? kGraphLaneWidth * (maxLane + 1),
      height: kCommitRowHeight,
      child: ClipRect(
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

/// The ref chips, as one clipped line rather than a Wrap.
///
/// A Wrap in a Row receives an unbounded width constraint, so it never
/// actually wrapped -- it just took as much as its chips wanted and pushed
/// the rest of the row, which is one of the ways a commit row overflowed. A
/// bounded, clipped Row renders identically whenever there is room and
/// simply runs out of view when there is not. Wrapping is not an option
/// either way: the row is a fixed kCommitRowHeight tall, so a second line of
/// chips would overflow vertically instead.
class _RefChipStrip extends StatelessWidget {
  const _RefChipStrip({required this.chips, this.maxWidth});

  final List<RefChipData> chips;

  /// Null for "unbounded", which is what [CommitRowColumnPlan.full] means --
  /// the pre-existing behaviour, kept for unmeasured callers.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final Widget strip = Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 4,
      children: <Widget>[
        for (final RefChipData chip in chips)
          GbmTagChip(
            label: chip.label,
            kind: chip.kind,
            isCurrent: chip.isCurrent,
            showCloudIcon: chip.showCloudIcon,
            isDashed: chip.isDashed,
          ),
      ],
    );
    if (maxWidth == null) return strip;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth!),
      child: ClipRect(
        // OverflowBox is what lets the inner Row keep its natural width
        // inside a narrower box; without it the Row would itself overflow
        // and throw before ClipRect ever got to hide anything.
        child: OverflowBox(
          alignment: Alignment.centerLeft,
          maxWidth: double.infinity,
          child: strip,
        ),
      ),
    );
  }
}
