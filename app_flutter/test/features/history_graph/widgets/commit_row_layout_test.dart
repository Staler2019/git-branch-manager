// planCommitRowColumns is the one place that decides which of a commit row's
// optional columns a given width can afford. It is a pure function so this
// tier can pin the ladder exhaustively; commit_row_narrow_width_test.dart
// then checks that CommitRow renders what the plan says, and
// workspace_narrow_window_test.dart that the real nested split panes hand it
// the width it thinks it gets.
//
// Widths below are chosen relative to the function's own constants rather
// than to any measured font, so these cases say nothing about Ahem vs a real
// device -- that distinction only matters at the widget tier.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/graph_column.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row_layout.dart';

CommitRowColumnPlan _plan(
  double width, {
  int laneCount = 1,
  bool showGraph = true,
  Set<String>? hiddenByUser,
  List<GbmGraphColumnId> order = kGraphColumnOrderDefault,
  Map<GbmGraphColumnId, double> widths = const <GbmGraphColumnId, double>{},
}) {
  return planCommitRowColumns(
    availableWidth: width,
    laneCount: laneCount,
    showGraph: showGraph,
    hiddenByUser: hiddenByUser,
    order: order,
    widths: widths,
  );
}

List<String> _ids(CommitRowColumnPlan p) => <String>[
  for (final PlannedColumn column in p.columns) column.id.storageId,
];

/// The optional columns still on, as a set, for order-independent compares.
Set<String> _shown(CommitRowColumnPlan p) => <String>{
  if (p.showHash) 'hash',
  if (p.showRefs) 'refs',
  if (p.showAuthor) 'author',
  if (p.showDate) 'date',
};

void main() {
  group('a width with room to spare', () {
    test('keeps every optional column', () {
      final CommitRowColumnPlan p = _plan(2000);
      expect(_shown(p), <String>{'hash', 'refs', 'author', 'date'});
    });

    test('does not cap the graph column', () {
      final CommitRowColumnPlan p = _plan(2000, laneCount: 12);
      expect(p.graphClipped, isFalse);
      expect(p.graphWidth, kGraphLaneWidth * 13);
    });
  });

  group('the degradation ladder', () {
    // Spec P02 item 16 locks Graph and Message; everything else is listed as
    // hideable, so the ladder can only ever touch the other four.
    test('gives up date first', () {
      // Just under what the full set needs.
      final double full = _widthThatFits();
      final CommitRowColumnPlan p = _plan(full - 1);
      expect(p.showDate, isFalse);
      expect(p.showAuthor, isTrue);
      expect(p.showHash, isTrue);
    });

    test('gives up author second', () {
      final CommitRowColumnPlan p = _plan(_widthThatFits() - 1 - 90);
      expect(p.showDate, isFalse);
      expect(p.showAuthor, isFalse);
      expect(p.showHash, isTrue);
    });

    test('gives up hash last of the fixed columns', () {
      final CommitRowColumnPlan p = _plan(120);
      expect(p.showHash, isFalse);
    });

    test('holds the message floor even against a 30-lane graph', () {
      // Message is locked by P02-16, and an Expanded that collapses to zero
      // would satisfy "no overflow" while hiding it -- so the plan gives up
      // every optional column and then clips the graph rather than let the
      // subject fall below kMinSubjectWidth.
      for (final double w in <double>[160, 320, 640, 1280]) {
        final CommitRowColumnPlan p = _plan(w, laneCount: 30);
        expect(
          p.subjectWidthFor(w),
          greaterThanOrEqualTo(kMinSubjectWidth),
          reason: 'at width $w',
        );
      }
    });

    test('degrades without going negative below the floor', () {
      // Under ~160px the floor is arithmetically unreachable: the row still
      // owes its inter-column spacing even with every column gone and the
      // graph clipped to zero. The contract there is only that the plan
      // stays sane -- no negative widths, nothing left switched on.
      for (final double w in <double>[0, 20, 40, 80]) {
        final CommitRowColumnPlan p = _plan(w, laneCount: 30);
        expect(p.graphWidth, greaterThanOrEqualTo(0), reason: 'at width $w');
        expect(_shown(p), isEmpty, reason: 'at width $w');
      }
    });

    test('shrinking width never brings a column back', () {
      // Monotonicity. A ladder written as independent thresholds can easily
      // re-enable a column at a narrower width; nothing else here would
      // notice.
      Set<String> previous = _shown(_plan(2000));
      for (double w = 2000; w >= 40; w -= 7) {
        final Set<String> current = _shown(_plan(w));
        expect(
          current.difference(previous),
          isEmpty,
          reason: 'width $w re-enabled ${current.difference(previous)}',
        );
        previous = current;
      }
    });
  });

  group('graph column clamping', () {
    test('caps the graph rather than starving the message', () {
      final CommitRowColumnPlan p = _plan(200, laneCount: 30);
      expect(p.graphClipped, isTrue);
      expect(p.graphWidth, isNotNull);
      expect(p.graphWidth, lessThan(kGraphLaneWidth * 31));
    });

    test('never caps below zero', () {
      final CommitRowColumnPlan p = _plan(10, laneCount: 30);
      expect(p.graphWidth, greaterThanOrEqualTo(0));
    });

    test('a hidden graph column is not clamped', () {
      final CommitRowColumnPlan p = _plan(200, laneCount: 30, showGraph: false);
      expect(p.graphClipped, isFalse);
    });
  });

  group('refs budget', () {
    test('refs get a cap, never unbounded, once width is measured', () {
      final CommitRowColumnPlan p = _plan(2000);
      expect(p.maxRefsWidth, isNotNull);
      expect(p.maxRefsWidth, greaterThan(0));
    });

    test('refs are dropped when there is nothing left for them', () {
      final CommitRowColumnPlan p = _plan(120, laneCount: 12);
      expect(p.showRefs, isFalse);
    });
  });

  group('column order', () {
    test('columns follow the given order', () {
      final List<GbmGraphColumnId> reversed = <GbmGraphColumnId>[
        GbmGraphColumnId.graph,
        GbmGraphColumnId.message,
        GbmGraphColumnId.hash,
        GbmGraphColumnId.date,
        GbmGraphColumnId.author,
        GbmGraphColumnId.refs,
      ];
      expect(_ids(_plan(2000, order: reversed)), <String>[
        'graph',
        'message',
        'hash',
        'date',
        'author',
        'refs',
      ]);
    });

    // Reordering must not change *what* is affordable, only where it sits:
    // the ladder walks kColumnDropOrder, which is independent of display
    // order. Without this a user's drag would silently change which columns
    // survive a narrow window.
    test('display order does not change which columns survive', () {
      final List<GbmGraphColumnId> reordered = <GbmGraphColumnId>[
        GbmGraphColumnId.graph,
        GbmGraphColumnId.message,
        GbmGraphColumnId.hash,
        GbmGraphColumnId.refs,
        GbmGraphColumnId.date,
        GbmGraphColumnId.author,
      ];
      for (double w = 1000; w >= 40; w -= 5) {
        expect(
          _ids(_plan(w, order: reordered)).toSet(),
          _ids(_plan(w)).toSet(),
          reason: 'width \$w',
        );
      }
    });

    // Only the six spec starts switched on -- "nothing was given up for
    // width" is a different claim from "every column is enabled".
    test('full is the spec default layout', () {
      expect(
        <String>[
          for (final PlannedColumn c in CommitRowColumnPlan.full.columns)
            c.id.storageId,
        ],
        <String>['graph', 'message', 'refs', 'author', 'date', 'hash'],
      );
    });
  });

  group('column widths', () {
    test('a wider column is charged to the budget', () {
      const double width = 700;
      final double base = _plan(width).subjectWidthFor(width);
      final double dragged = _plan(
        width,
        widths: <GbmGraphColumnId, double>{GbmGraphColumnId.author: 210},
      ).subjectWidthFor(width);

      expect(dragged, base - 100);
    });

    test('the planned slot is what the caller dragged to', () {
      final CommitRowColumnPlan plan = _plan(
        2000,
        widths: <GbmGraphColumnId, double>{GbmGraphColumnId.date: 137},
      );
      expect(plan.widthOf(GbmGraphColumnId.date), 137);
    });

    // A dragged column can push the row past the message floor, and that has
    // to go through the same ladder rather than overflowing.
    test('dragging wide enough makes the ladder give a column up', () {
      const double width = 600;
      expect(_plan(width).showDate, isTrue);
      expect(
        _plan(
          width,
          widths: <GbmGraphColumnId, double>{GbmGraphColumnId.author: 320},
        ).showDate,
        isFalse,
      );
    });

    // Refs is charged its own width now instead of a hardcoded reserve, so
    // dragging it moves the budget like any other column. The previous
    // commit deliberately exempted it so this change is attributable here.
    test('refs is charged its stored width like any other column', () {
      const double width = 700;
      final double base = _plan(width).subjectWidthFor(width);
      final double dragged = _plan(
        width,
        widths: <GbmGraphColumnId, double>{GbmGraphColumnId.refs: 200},
      ).subjectWidthFor(width);

      // Expressed against the default rather than as a literal: the drag
      // costs the subject exactly the difference, whatever the default is.
      expect(dragged, base - (200 - GbmGraphColumnId.refs.defaultWidth));
      expect(
        _plan(2000).widthOf(GbmGraphColumnId.refs),
        GbmGraphColumnId.refs.defaultWidth,
      );
    });

    // The cap is the column's width, full stop. It used to be the reserve
    // plus everything spare, which made it differ between a wide and a
    // merely-adequate window and made the drag a no-op on the former.
    test('the chip cap is the column width, not the spare space', () {
      expect(_plan(2000).maxRefsWidth, _plan(700).maxRefsWidth);
      expect(_plan(2000).maxRefsWidth, GbmGraphColumnId.refs.defaultWidth);
      expect(
        _plan(
          2000,
          widths: <GbmGraphColumnId, double>{GbmGraphColumnId.refs: 200},
        ).maxRefsWidth,
        200,
      );
    });
  });

  group('user preference (the column picker)', () {
    test('a user-hidden column stays hidden at any width', () {
      final CommitRowColumnPlan p = _plan(
        2000,
        hiddenByUser: <String>{'author', 'date'},
      );
      expect(p.showAuthor, isFalse);
      expect(p.showDate, isFalse);
      expect(p.showHash, isTrue);
    });

    test('a hidden column and a ladder-dropped one converge', () {
      // Not "hiding frees extra width" -- it does not, and an earlier version
      // of this test asserted that and could never pass. Once the ladder has
      // dropped date and author on its own, the plan is indistinguishable
      // from the user having switched the same two off, which is the
      // property that matters: there is one set of rules, not two.
      const double narrow = 240;
      final CommitRowColumnPlan byLadder = _plan(narrow);
      expect(byLadder.showDate, isFalse);
      expect(byLadder.showAuthor, isFalse);

      final CommitRowColumnPlan byUser = _plan(
        narrow,
        hiddenByUser: <String>{'author', 'date'},
      );
      expect(_shown(byUser), _shown(byLadder));
      expect(byUser.graphWidth, byLadder.graphWidth);
    });

    test(
      'width can hide a column the user wanted, never show one they hid',
      () {
        final CommitRowColumnPlan p = _plan(
          120,
          hiddenByUser: <String>{'author'},
        );
        expect(p.showAuthor, isFalse);
      },
    );
  });
}

/// The narrowest width at which nothing is given up, found by probing the
/// function itself rather than by re-deriving its arithmetic here -- a test
/// that recomputes the formula it is checking cannot disagree with it.
double _widthThatFits() {
  for (double w = 100; w < 3000; w += 1) {
    final CommitRowColumnPlan p = planCommitRowColumns(
      availableWidth: w,
      laneCount: 1,
      showGraph: true,
      hiddenByUser: const <String>{},
    );
    if (p.showDate && p.showAuthor && p.showHash && p.showRefs) return w;
  }
  fail('no width kept every column');
}
