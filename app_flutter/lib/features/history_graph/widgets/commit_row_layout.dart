import 'dart:math' as math;

import '../../../data/models/graph_column.dart';
import '../../../theme/tokens.dart';
import 'commit_row.dart' show kGraphLaneWidth;

/// The narrowest the commit subject is ever allowed to get.
///
/// Spec page 02 item 16 locks Graph and Message as the two columns the user
/// cannot switch off. `Expanded` honours that only in the sense that it never
/// overflows -- it will happily collapse to zero and take Message off screen
/// while every layout assertion still passes. This floor is what actually
/// keeps the promise; if respecting it means clipping the graph column, the
/// graph gets clipped.
const double kMinSubjectWidth = 80;

/// The order the ladder surrenders columns in, cheapest to lose first.
///
/// Least to most identifying. Changed files and Committer lead because spec
/// starts them switched off (`GbmGraphColumnId.defaultVisible`): a column the
/// user went looking for and turned on is still worth less than one they
/// never had to ask for. Then a date (the easiest thing to recover -- the
/// list is in date order), then an author (often uniform across a working
/// branch), then the hash, which names the commit. Refs go last because a
/// branch or tag chip is the only thing in the row that says *where you
/// are*, and unlike the hash it has no second home in the commit detail
/// panel.
///
/// **Nothing here is spec'd.** Neither the design spec nor `docs/` says
/// anything about narrow windows -- no breakpoints, no minimum widths. What
/// *is* spec'd is P02 item 16's "Graph and Message cannot be switched off",
/// and this ladder is derived from it: those two are the only columns it
/// will not surrender. Do not cite this ordering as a spec requirement.
const List<GbmGraphColumnId> kColumnDropOrder = <GbmGraphColumnId>[
  GbmGraphColumnId.changedFiles,
  GbmGraphColumnId.committer,
  GbmGraphColumnId.date,
  GbmGraphColumnId.author,
  GbmGraphColumnId.hash,
  GbmGraphColumnId.refs,
];

/// One column's place in a planned row.
class PlannedColumn {
  const PlannedColumn(this.id, this.width);

  final GbmGraphColumnId id;

  /// The fixed slot this column gets, or null when it has none:
  /// [GbmGraphColumnId.message] is the sole flex column and never has one,
  /// and graph has none in [CommitRowColumnPlan.full], which is the value
  /// for callers that never measured a width at all.
  final double? width;
}

/// Every column a row can show, in the spec's own order, at its default
/// width -- what [CommitRowColumnPlan.full] resolves to.
///
/// Computed from the enum rather than written out, so a column added there
/// cannot be forgotten here. Columns spec starts switched off are excluded:
/// "nothing was given up for width" is not the same claim as "everything is
/// switched on".
final List<PlannedColumn> kDefaultPlannedColumns =
    List<PlannedColumn>.unmodifiable(<PlannedColumn>[
      for (final GbmGraphColumnId id in kGraphColumnOrderDefault)
        if (id.defaultVisible)
          PlannedColumn(id, id.isLocked ? null : id.defaultWidth),
    ]);

/// Which columns a commit row can afford and how wide each one gets, plus the
/// caps that keep the variable-width parts inside their share.
///
/// Computed once per list, never per row -- see [planCommitRowColumns].
class CommitRowColumnPlan {
  /// [columns] is positional and private-typed because [full] needs to be a
  /// `const` (it is a default parameter value in `commit_row.dart`) while
  /// the default column list is computed from the enum -- so the field holds
  /// null for "not measured" and [columns] resolves it.
  const CommitRowColumnPlan(
    this._columns, {
    this.graphWidth,
    this.maxRefsWidth,
    this.graphClipped = false,
  });

  final List<PlannedColumn>? _columns;

  /// Nothing given up and nothing capped -- the value for callers that do not
  /// measure a width (existing widget tests, and any future embedding that
  /// has room to spare).
  static const CommitRowColumnPlan full = CommitRowColumnPlan(null);

  /// The visible columns in display order, each with the slot it gets.
  List<PlannedColumn> get columns => _columns ?? kDefaultPlannedColumns;

  /// The graph column's width under this plan, or null to use its natural
  /// width (`kGraphLaneWidth * (laneCount + 1)`). [planCommitRowColumns]
  /// always sets it; only [full] leaves it null.
  final double? graphWidth;

  /// Upper bound on the ref-chip strip, or null for unbounded.
  final double? maxRefsWidth;

  /// True when [graphWidth] is below the natural width, i.e. the highest
  /// lanes will be clipped. Distinct from `graphWidth != null`, which is
  /// also true whenever the plan simply resolved the natural width.
  final bool graphClipped;

  bool shows(GbmGraphColumnId id) {
    for (final PlannedColumn column in columns) {
      if (column.id == id) return true;
    }
    return false;
  }

  /// [id]'s slot under this plan, or null when it has none (see
  /// [PlannedColumn.width]) or is not shown at all.
  double? widthOf(GbmGraphColumnId id) {
    for (final PlannedColumn column in columns) {
      if (column.id == id) return column.width;
    }
    return null;
  }

  bool get showHash => shows(GbmGraphColumnId.hash);
  bool get showRefs => shows(GbmGraphColumnId.refs);
  bool get showAuthor => shows(GbmGraphColumnId.author);
  bool get showDate => shows(GbmGraphColumnId.date);
  bool get showCommitter => shows(GbmGraphColumnId.committer);
  bool get showChangedFiles => shows(GbmGraphColumnId.changedFiles);

  /// What the subject column ends up with at [availableWidth] under this
  /// plan. Exposed so tests can assert the Message floor directly instead of
  /// inferring it from the flags.
  double subjectWidthFor(double availableWidth) {
    return availableWidth -
        _fixedCost(
          <GbmGraphColumnId>{
            for (final PlannedColumn column in columns) column.id,
          },
          _slotWidths(this),
          graphWidth ?? 0,
        );
  }
}

/// Decides the plan for one commit list at [availableWidth].
///
/// **Per list, not per row.** The inputs are deliberately limited to facts
/// every row shares (the width, the snapshot's lane count, the user's own
/// column settings) and exclude per-row ones like "is this HEAD" or "does
/// this commit carry ref chips". Author and date are trailing fixed-width
/// columns: if the HEAD row -- which is also the row most likely to carry
/// chips -- decided on its own to give up date, its columns would stop
/// lining up with its neighbours' and the list would stop being a table.
///
/// The ladder itself is [kColumnDropOrder]; see its doc comment for why that
/// order and why none of it is spec'd.
///
/// [order] and [widths] come from `graphColumnLayoutProvider`, i.e. from what
/// the user dragged; both default to the spec's own values so a caller that
/// does not measure anything still gets the shipped layout. [hiddenByUser] is
/// the same provider's hidden set. Width may hide a column the user asked
/// for; it can never reveal one they turned off.
CommitRowColumnPlan planCommitRowColumns({
  required double availableWidth,
  required int laneCount,
  required bool showGraph,
  List<GbmGraphColumnId> order = kGraphColumnOrderDefault,
  Map<GbmGraphColumnId, double> widths = const <GbmGraphColumnId, double>{},
  Set<String>? hiddenByUser,
}) {
  // Not `const {}`: an omitted set means "the user has configured nothing",
  // and spec's own layout has Committer and Changed files switched off. An
  // empty default would quietly make the unconfigured case eight columns
  // wide -- the same trap `isGraphColumnVisible`'s fallback exists to close,
  // one layer down. A caller wanting all eight passes an explicit `{}`.
  final Set<String> hidden = hiddenByUser ?? kDefaultHiddenGraphColumnIds;
  final Map<GbmGraphColumnId, double> slots = <GbmGraphColumnId, double>{
    for (final GbmGraphColumnId id in GbmGraphColumnId.values)
      id: widths[id] ?? id.defaultWidth,
  };

  final Set<GbmGraphColumnId> visible = <GbmGraphColumnId>{
    for (final GbmGraphColumnId id in order)
      if (id.isLocked || !hidden.contains(id.storageId)) id,
  };

  final double graphNatural = showGraph
      ? kGraphLaneWidth * (laneCount + 1)
      : GbmSpacing.space3;

  double leftover() =>
      availableWidth - _fixedCost(visible, slots, graphNatural);

  // Rung by rung, cheapest to lose first, stopping the moment the message
  // floor fits.
  for (final GbmGraphColumnId id in kColumnDropOrder) {
    if (leftover() >= kMinSubjectWidth) break;
    visible.remove(id);
  }

  // Refs is an ordinary column now: its width comes from what the user
  // dragged to, the ladder budgets that width, and the strip is capped at
  // it. Two other shapes were tried and rejected, both by measurement:
  //
  //  * Keeping the old elastic cap (reserve + everything spare beyond the
  //    message floor) makes the drag a no-op wherever there is spare space
  //    -- raising the reserve raises the cost by the same amount, so the sum
  //    is algebraically independent of it. A column whose width cannot be
  //    dragged on an ordinary window does not honour spec's "欄寬各自可拖曳
  //    並記憶".
  //  * Raising the default to a roomier 120 cost the Author column at the
  //    app's own default 1280x720 on a twelve-lane history, which
  //    `workspace_narrow_window_test.dart` exists to forbid.
  //
  // So the default stays at the 60 the row has always reserved -- no drop
  // threshold moves -- and what changes is the reach on a *wide* window: a
  // commit with several chips used to render them all and is now capped at
  // 60 until the user drags the column wider (up to `refs.maxWidth`). That
  // is a real, visible reduction and the unavoidable price of the setting:
  // a column living off leftover space has no width to remember.
  //
  // The cap is a maximum, not a fixed box: the strip shrinks to its chips,
  // so a commit carrying none leaves no hole between the message and the
  // author -- which is how the mockup draws it (`spec_raw.html:1310-1313`,
  // where the chip span has no width at all).
  final bool showRefs = visible.contains(GbmGraphColumnId.refs);

  // Last resort: the graph column itself. lane 0 is drawn leftmost, so
  // clipping always takes the highest lanes and never HEAD or the trunk.
  double resolvedGraphWidth = graphNatural;
  bool graphClipped = false;
  final double shortfall = kMinSubjectWidth - leftover();
  if (showGraph && shortfall > 0) {
    resolvedGraphWidth = math.max(0, graphNatural - shortfall);
    graphClipped = resolvedGraphWidth < graphNatural;
  }

  return CommitRowColumnPlan(
    <PlannedColumn>[
      for (final GbmGraphColumnId id in order)
        if (visible.contains(id))
          PlannedColumn(
            id,
            id == GbmGraphColumnId.graph
                ? resolvedGraphWidth
                : id == GbmGraphColumnId.message
                ? null
                : slots[id],
          ),
    ],
    graphWidth: resolvedGraphWidth,
    maxRefsWidth: showRefs ? slots[GbmGraphColumnId.refs] : null,
    graphClipped: graphClipped,
  );
}

Map<GbmGraphColumnId, double> _slotWidths(CommitRowColumnPlan plan) {
  return <GbmGraphColumnId, double>{
    for (final PlannedColumn column in plan.columns)
      if (column.width != null) column.id: column.width!,
  };
}

/// The gap drawn to the right of [id].
///
/// Not uniform, and deliberately so -- these are the paddings `CommitRow`
/// has always drawn. `CommitRow` now calls this function rather than
/// repeating the numbers, so the rendered row and the width budget cannot
/// disagree about what a column costs.
double gapAfterColumn(GbmGraphColumnId id) {
  switch (id) {
    case GbmGraphColumnId.hash:
    case GbmGraphColumnId.author:
    case GbmGraphColumnId.committer:
      return GbmSpacing.space3;
    case GbmGraphColumnId.date:
    case GbmGraphColumnId.refs:
    case GbmGraphColumnId.changedFiles:
    case GbmGraphColumnId.graph:
      return GbmSpacing.space2;
    case GbmGraphColumnId.message:
      return 0;
  }
}

/// The gap after the last column, drawn once whatever the row shows.
const double kRowTrailingGap = GbmSpacing.space3;

/// Everything in a row that is not the subject or the ref chips, at
/// [graphWidth]. Mirrors CommitRow's own child list; the two have to move
/// together.
double _fixedCost(
  Set<GbmGraphColumnId> visible,
  Map<GbmGraphColumnId, double> slots,
  double graphWidth,
) {
  double total = 0;
  for (final GbmGraphColumnId id in visible) {
    if (id == GbmGraphColumnId.message) continue;
    total +=
        (id == GbmGraphColumnId.graph
            ? graphWidth
            : slots[id] ?? id.defaultWidth) +
        gapAfterColumn(id);
  }
  return total + kRowTrailingGap;
}
