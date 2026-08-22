// Where the invisible column-resize strips sit, as a pure function.
//
// This is the half a widget test cannot check cheaply: a strip is invisible
// by design, so "is it in the right place" has no rendered artifact to find
// -- only a number. The integration tier proves a drag reaches the notifier;
// this tier proves it would land on the right column.
//
// Every expected value below is written as the sum it comes from rather than
// as a single literal, so a spacing-token change reads as an arithmetic
// change and not as a mystery.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/graph_column.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row_layout.dart';
import 'package:gbm_flutter/theme/tokens.dart';

const double _g2 = GbmSpacing.space2;
const double _g3 = GbmSpacing.space3;

ColumnResizeHandle _handleFor(
  List<ColumnResizeHandle> handles,
  GbmGraphColumnId id,
) => handles.firstWhere((ColumnResizeHandle h) => h.id == id);

void main() {
  group('resizeHandlesFor', () {
    test('gives one strip to each resizable column and none to Message', () {
      final List<ColumnResizeHandle> handles = resizeHandlesFor(
        CommitRowColumnPlan.full,
      );

      expect(
        handles.map((ColumnResizeHandle h) => h.id).toSet(),
        <GbmGraphColumnId>{
          GbmGraphColumnId.graph,
          GbmGraphColumnId.refs,
          GbmGraphColumnId.author,
          GbmGraphColumnId.date,
          GbmGraphColumnId.hash,
        },
      );
      // Message is the sole flex column: its width is whatever is left, so
      // there is nothing to drag. Graph *is* here now -- dragging it moves
      // the cap on how many lanes are drawn, never whether the column
      // exists, so spec's "Graph 與 Message 固定不可關" is untouched.
      expect(
        handles.map((ColumnResizeHandle h) => h.id),
        isNot(contains(GbmGraphColumnId.message)),
      );
    });

    test('anchors trailing columns right and Graph left', () {
      // In spec's order Message comes second, so every draggable column
      // *except Graph* sits after it and keeps a fixed distance from the
      // row's right edge. Graph is the one column before Message, so its
      // strip is measured from the left and a rightward drag widens it
      // rather than narrowing it -- the opposite sign, and the reason
      // `dragSign` is derived from `fromRight` instead of stored beside it.
      for (final ColumnResizeHandle h in resizeHandlesFor(
        CommitRowColumnPlan.full,
      )) {
        final bool isGraph = h.id == GbmGraphColumnId.graph;
        expect(h.fromRight, isGraph ? isFalse : isTrue, reason: h.id.storageId);
        expect(h.dragSign, isGraph ? 1 : -1, reason: h.id.storageId);
      }
    });

    test('measures each strip to the column boundary with Message', () {
      final List<ColumnResizeHandle> handles = resizeHandlesFor(
        CommitRowColumnPlan.full,
      );

      // Walking in from the right edge: the trailing gap, then hash and its
      // own gap, then date, author and refs the same way. Each strip lands
      // on the column's *left* edge, so its offset includes that column.
      const double hash = _g3 + _g3 + 64; // trailing + gapAfter(hash) + width
      const double date = hash + _g2 + 80;
      const double author = date + _g3 + 110;
      const double refs = author + _g2 + 104;

      expect(_handleFor(handles, GbmGraphColumnId.hash).offset, hash);
      expect(_handleFor(handles, GbmGraphColumnId.date).offset, date);
      expect(_handleFor(handles, GbmGraphColumnId.author).offset, author);
      expect(_handleFor(handles, GbmGraphColumnId.refs).offset, refs);
    });

    test('strips are ordered outermost-first and never overlap', () {
      // They are 8px wide and straddle their boundary, so two adjacent
      // strips would fight for the same pixels if a column were ever
      // narrower than the strip. minWidth is 40 at the tightest, so this is
      // a property the widths already guarantee -- asserted, not assumed.
      final List<ColumnResizeHandle> handles = resizeHandlesFor(
        CommitRowColumnPlan.full,
      );
      for (int i = 1; i < handles.length; i++) {
        expect(
          handles[i].offset - handles[i - 1].offset,
          greaterThanOrEqualTo(kColumnResizeHandleWidth),
          reason:
              '${handles[i].id.storageId} vs ${handles[i - 1].id.storageId}',
        );
      }
    });

    test(
      'a column dragged in front of Message anchors to the left instead',
      () {
        // The order is the user's to change, so "everything is right-anchored"
        // is a property of the default, not of the function.
        final CommitRowColumnPlan plan = planCommitRowColumns(
          availableWidth: 1200,
          laneCount: 2,
          showGraph: true,
          order: <GbmGraphColumnId>[
            GbmGraphColumnId.graph,
            GbmGraphColumnId.hash,
            GbmGraphColumnId.message,
            GbmGraphColumnId.refs,
            GbmGraphColumnId.author,
            GbmGraphColumnId.date,
            GbmGraphColumnId.committer,
            GbmGraphColumnId.changedFiles,
          ],
        );

        final ColumnResizeHandle hash = _handleFor(
          resizeHandlesFor(plan),
          GbmGraphColumnId.hash,
        );
        expect(hash.fromRight, isFalse);
        expect(hash.dragSign, 1);
        // Graph's own width plus its gap, then hash's width -- the strip sits
        // on hash's right edge, before its gap.
        expect(hash.offset, plan.graphWidth! + _g2 + 64);
      },
    );

    test('a column the plan gave up has no strip', () {
      // Dragging a column that is not on screen would be a gesture with no
      // visible target, and would silently move a width the user cannot see.
      final CommitRowColumnPlan plan = planCommitRowColumns(
        availableWidth: 320,
        laneCount: 8,
        showGraph: true,
      );
      expect(plan.showDate, isFalse, reason: 'fixture must exercise a drop');
      expect(
        resizeHandlesFor(plan).map((ColumnResizeHandle h) => h.id),
        isNot(contains(GbmGraphColumnId.date)),
      );
    });
  });
}
