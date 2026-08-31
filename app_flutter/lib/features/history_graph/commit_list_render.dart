import 'package:flutter/foundation.dart';

import '../../data/models/commit_meta.dart';
import '../../data/models/graph_snapshot.dart';
import '../../data/models/list_selection.dart';
import '../../data/models/ref_snapshot.dart';
import 'commit_search.dart';

/// Everything one build of History's commit list needs, gathered once.
///
/// It exists because the list's builders had grown to twelve positional
/// parameters, and — more to the point — because three of the values are
/// *derived*, and each derivation had been sitting inline at its point of
/// use. `connectsToHead` is the cautionary one: it was two conditions written
/// separately, one in the uncommitted row and one in the first commit row, so
/// the two halves of a single line could and did disagree. A derived value
/// with one home cannot ([CULT-single-source-of-truth]).
///
/// **Deliberately not holding `CommitRowColumnPlan`.** That one is a function
/// of the width this build actually got, so it is computed inside the
/// `LayoutBuilder` and passed alongside. Folding it in here would mean either
/// rebuilding the whole model per layout pass or freezing a plan taken at the
/// wrong width.
@immutable
class CommitListRender {
  const CommitListRender._({
    required this.graph,
    required this.visibleRows,
    required this.visibleOids,
    required this.query,
    required this.metaCache,
    required this.selection,
    required this.refs,
    required this.effectiveEmail,
    required this.conflictActive,
    required this.contiguous,
    required this.pendingChangeCount,
    required this.showWorkingCopyRow,
    required this.workingCopyRowSelected,
    required this.connectsToHead,
  });

  /// Gathers the raw inputs and derives the three values below them.
  ///
  /// Private constructor plus this factory on purpose: the derived trio is
  /// the reason the type exists, so there must be no way to build one with a
  /// `contiguous` or a `connectsToHead` that disagrees with the snapshot it
  /// claims to describe.
  factory CommitListRender.from({
    required GraphSnapshotView graph,
    required List<int> visibleRows,
    required String query,
    required Map<String, CommitMeta> metaCache,
    required ListSelection<String> selection,
    required RefSnapshot refs,
    required String effectiveEmail,
    required bool conflictActive,
    required int pendingChangeCount,
    required bool workingCopyRowSelected,
  }) {
    // The rendered order, as oids. Every selection transition is expressed
    // against this rather than against `visibleRows` (snapshot indices), so
    // a range never silently spans rows a filter is hiding.
    //
    // With nothing filtered this list *is* `graph.oidsHex` -- position
    // equals row index -- so the copy is skipped rather than rebuilt on
    // every scroll tick and every metadata reply. The length guard is what
    // makes the two provably identical: the comprehension below drops any
    // index past the end of `oidsHex`, so it can only equal `oidsHex`
    // outright when the two lengths already agree. They always do in
    // practice; the mismatch branch exists so a malformed snapshot keeps
    // the old, defensive behaviour instead of a wrong-length selection
    // list. See UnfilteredRowIndices for the measured cost of the twin
    // allocation this pairs with.
    final List<String> visibleOids =
        visibleRows is UnfilteredRowIndices &&
            graph.rows.length == graph.oidsHex.length
        ? graph.oidsHex
        : <String>[
            for (final int index in visibleRows)
              if (index < graph.oidsHex.length) graph.oidsHex[index],
          ];

    // Suppressed while a commit search is active, for the same reason the
    // lanes themselves are (`showGraph: query.isEmpty`, and
    // CommitRowColumnPlan.drawsGraph's doc): with the rows underneath drawing
    // a bare spacer instead of lanes, the row's dot would be the only graph
    // mark on screen and its connector would descend into nothing. The count
    // is still on the Working Copy tab badge throughout.
    final bool showWorkingCopyRow = pendingChangeCount > 0 && query.isEmpty;

    return CommitListRender._(
      graph: graph,
      visibleRows: visibleRows,
      visibleOids: visibleOids,
      query: query,
      metaCache: metaCache,
      selection: selection,
      refs: refs,
      effectiveEmail: effectiveEmail,
      conflictActive: conflictActive,
      // Contiguity is judged against the **unfiltered** snapshot, not the
      // rendered list: three commits that look adjacent under a filter are
      // not a range git can replay, so cherry-pick and revert correctly stay
      // disabled for them (MULTIACTS).
      contiguous: selection.isContiguousIn(graph.oidsHex),
      pendingChangeCount: pendingChangeCount,
      showWorkingCopyRow: showWorkingCopyRow,
      workingCopyRowSelected: workingCopyRowSelected,
      // **One value, two consumers.** The uncommitted row paints the upper
      // half of the join to HEAD's dot and the first commit row the lower
      // half, and each can only paint inside its own box (commit_row.dart
      // clips). Deriving the two conditions separately is precisely how the
      // line came to stop dead on the row boundary, half a row short of the
      // dot it pointed at.
      //
      // Lane 0 is part of the condition, not an assumption: the diamond is
      // fixed at lane 0, so a HEAD tip sitting anywhere else would be joined
      // by a line that changes lane without any commit having done so. The
      // trunk reservation puts it in lane 0 for an unfiltered walk, but
      // `Session.cpp` skips that reservation when the walk is filtered, and
      // a filter can still leave HEAD's tip on top.
      connectsToHead:
          showWorkingCopyRow &&
          visibleRows.isNotEmpty &&
          visibleOids.isNotEmpty &&
          visibleOids.first == refs.head.target &&
          graph.rows[visibleRows.first].lane == 0,
    );
  }

  final GraphSnapshotView graph;

  /// Row indices into [graph], in painted order -- an `UnfilteredRowIndices`
  /// identity view whenever nothing is filtered ([STATE-unfiltered-row-indices]).
  final List<int> visibleRows;

  /// The same rows as oids. Derived; see the factory.
  final List<String> visibleOids;

  final String query;
  final Map<String, CommitMeta> metaCache;
  final ListSelection<String> selection;
  final RefSnapshot refs;
  final String effectiveEmail;
  final bool conflictActive;

  /// Whether [selection] is a range git could replay. Derived.
  final bool contiguous;

  /// How many files the working copy has pending -- the badge on the
  /// uncommitted row, and the same getter the Working Copy tab badge reads.
  final int pendingChangeCount;

  /// Whether History pins its uncommitted-changes row above the list. Derived.
  final bool showWorkingCopyRow;

  /// Whether that row is the current selection. Not derived here -- it comes
  /// from `workingCopyRowSelectedProvider`, which is the one place the answer
  /// is composed.
  final bool workingCopyRowSelected;

  /// Whether that row and the topmost commit row draw the two halves of the
  /// line between them. Derived; read by both, never re-derived by either.
  final bool connectsToHead;
}
