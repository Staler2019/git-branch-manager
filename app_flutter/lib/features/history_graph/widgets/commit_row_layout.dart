import 'dart:math' as math;

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

/// Fixed slots for the three optional columns that have a predictable width.
///
/// The hash column is a slot here rather than the intrinsic width of eight
/// hex characters on purpose: a widget test renders in the Ahem font, where
/// every glyph is one em wide, so an intrinsic hash measures ~88px in a test
/// and ~53px on a device. Sizing it explicitly makes the row's width budget
/// mean the same thing in both.
const double kHashColumnWidth = 64;
const double kAuthorColumnWidth = 110;
const double kDateColumnWidth = 80;

/// The smallest ref-chip strip worth drawing.
///
/// Refs have no natural fixed width -- one commit carries none and another
/// carries four -- so the ladder reserves this much whenever the strip is on
/// and caps the strip at whatever is actually spare. Giving refs a reserve
/// rather than letting them live purely off leftover space is what makes the
/// ladder monotonic: a purely budget-driven strip *reappears* as narrower
/// widths knock out other columns and free space up, which is the opposite
/// of a degradation ladder. `commit_row_layout_test.dart`'s monotonicity
/// property is what caught that.
const double kRefsReserveWidth = 60;

/// Which optional columns a commit row can afford, plus the caps that keep
/// the variable-width parts inside their share.
///
/// Computed once per list, never per row -- see [planCommitRowColumns].
class CommitRowColumnPlan {
  const CommitRowColumnPlan({
    this.graphWidth,
    this.maxRefsWidth,
    this.graphClipped = false,
    this.showHash = true,
    this.showRefs = true,
    this.showAuthor = true,
    this.showDate = true,
  });

  /// Nothing given up and nothing capped -- the value for callers that do not
  /// measure a width (existing widget tests, and any future embedding that
  /// has room to spare).
  static const CommitRowColumnPlan full = CommitRowColumnPlan();

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

  final bool showHash;
  final bool showRefs;
  final bool showAuthor;
  final bool showDate;

  /// What the subject column ends up with at [availableWidth] under this
  /// plan. Exposed so tests can assert the Message floor directly instead of
  /// inferring it from the flags.
  double subjectWidthFor(double availableWidth) {
    return availableWidth - _fixedCost(this, graphWidth ?? 0);
  }
}

/// Decides the plan for one commit list at [availableWidth].
///
/// **Per list, not per row.** The inputs are deliberately limited to facts
/// every row shares (the width, the snapshot's lane count) and exclude
/// per-row ones like "is this HEAD" or "does this commit carry ref chips".
/// Author and date are trailing fixed-width columns: if the HEAD row -- which
/// is also the row most likely to carry chips -- decided on its own to give
/// up date, its columns would stop lining up with its neighbours' and the
/// list would stop being a table.
///
/// **The ladder is date, then author, then hash, then refs.** Least to most
/// identifying: a date is the easiest thing to recover (the list is in date
/// order), an author is often uniform across a working branch, and the hash
/// names the commit. Refs go last because a branch or tag chip is the only
/// thing in the row that says *where you are*, and unlike the hash it has no
/// second home in the commit detail panel.
///
/// Only `date -> author -> hash` was agreed up front; appending refs at the
/// end is this function's own decision, recorded here rather than presented
/// as a requirement.
///
/// **Nothing here is spec'd.** Neither the design spec nor `docs/` says
/// anything about narrow windows -- no breakpoints, no minimum widths. What
/// *is* spec'd is P02 item 16's "Graph and Message cannot be switched off",
/// and this ladder is derived from it: those two are the only columns the
/// function will not surrender. Do not cite this ordering as a spec
/// requirement.
///
/// [hiddenByUser] is the column-picker's own set (ids as
/// `GraphColumnsSelector` writes them: `refs`, `author`, `date`, `hash`).
/// Width may hide a column the user asked for; it can never reveal one they
/// turned off.
CommitRowColumnPlan planCommitRowColumns({
  required double availableWidth,
  required int laneCount,
  required bool showGraph,
  Set<String> hiddenByUser = const <String>{},
}) {
  bool showHash = !hiddenByUser.contains('hash');
  bool showRefs = !hiddenByUser.contains('refs');
  bool showAuthor = !hiddenByUser.contains('author');
  bool showDate = !hiddenByUser.contains('date');

  final double graphNatural = showGraph
      ? kGraphLaneWidth * (laneCount + 1)
      : GbmSpacing.space3;

  CommitRowColumnPlan candidate() => CommitRowColumnPlan(
    showHash: showHash,
    showRefs: showRefs,
    showAuthor: showAuthor,
    showDate: showDate,
  );

  double leftover() => availableWidth - _fixedCost(candidate(), graphNatural);

  // Rung by rung, cheapest to lose first, stopping the moment the message
  // floor fits.
  if (leftover() < kMinSubjectWidth && showDate) showDate = false;
  if (leftover() < kMinSubjectWidth && showAuthor) showAuthor = false;
  if (leftover() < kMinSubjectWidth && showHash) showHash = false;
  if (leftover() < kMinSubjectWidth && showRefs) showRefs = false;

  // Whatever the strip did not need of its reserve, plus anything spare
  // beyond the message floor, is what the chips may actually use.
  final double refsBudget = showRefs
      ? kRefsReserveWidth + math.max(0, leftover() - kMinSubjectWidth)
      : 0;

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
    graphWidth: resolvedGraphWidth,
    maxRefsWidth: showRefs ? refsBudget : null,
    graphClipped: graphClipped,
    showHash: showHash,
    showRefs: showRefs,
    showAuthor: showAuthor,
    showDate: showDate,
  );
}

/// Everything in a row that is not the subject or the ref chips, at
/// [graphWidth]. Mirrors CommitRow's own child list; the two have to move
/// together.
double _fixedCost(CommitRowColumnPlan plan, double graphWidth) {
  double total = graphWidth + GbmSpacing.space2;
  if (plan.showHash) total += kHashColumnWidth + GbmSpacing.space3;
  if (plan.showAuthor) total += kAuthorColumnWidth + GbmSpacing.space3;
  if (plan.showDate) total += kDateColumnWidth + GbmSpacing.space2;
  if (plan.showRefs) total += kRefsReserveWidth + GbmSpacing.space2;
  return total + GbmSpacing.space3;
}
