// The invisible column-resize strips, at the only tier that can see them.
//
// Two of the three things this file asserts have no rendered artifact at
// all, which is why they live here rather than in a widget test:
//
//   * the strip is invisible, so "did the drag reach the right column" can
//     only be read off graphColumnWidthProvider;
//   * "a single click still selects the row underneath" is a property of
//     Flutter's gesture arena (HitTestBehavior.translucent plus *only* a
//     horizontal-drag recognizer), not of layout. Nothing about the widget
//     tree distinguishes a strip that swallows taps from one that does not.
//
// The third -- that a finished drag persists -- is asserted against
// SharedPreferences rather than by rebuilding a container, because what is
// new here is that onHorizontalDragEnd calls commitWidths() at all;
// graph_column_order_width_test.dart already owns the round trip itself.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_column.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/graph_columns_repository.dart';
import 'package:gbm_flutter/data/repositories/history_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/history_graph/commit_graph_view.dart';
import 'package:gbm_flutter/features/history_graph/history_page.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

String _oidAt(int i) => '${i.toRadixString(16).padLeft(4, '0')}${'a' * 36}';

const int _kRowCount = 6;

GraphSnapshotView _graph() => GraphSnapshotView(
  rows: <GraphRow>[
    for (int i = 0; i < _kRowCount; i++)
      const GraphRow(
        parentOffset: 0,
        edgeOffset: 0,
        commitTime: 0,
        lane: 0,
        color: 0,
        flags: 0,
      ),
  ],
  oidsHex: <String>[for (int i = 0; i < _kRowCount; i++) _oidAt(i)],
  parentPool: const <int>[],
  laneCount: 1,
  complete: true,
  truncated: false,
  edges: const <GraphEdge>[],
);

CommitMeta _meta(String oid) => CommitMeta(
  oid: oid,
  tree: 'b' * 40,
  parents: const <String>[],
  author: const Signature(
    name: 'Ada Lovelace',
    email: 'a@b.c',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  committer: const Signature(
    name: 'Ada Lovelace',
    email: 'a@b.c',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  subject: 'Commit $oid',
  body: '',
  signedCommit: false,
);

RepoSessionState _state() => RepoSessionState(
  isOpen: true,
  graph: _graph(),
  // Pre-seeded, or the rows draw skeleton blocks instead of text.
  commitMetaCache: <String, CommitMeta>{
    for (int i = 0; i < _kRowCount; i++) _oidAt(i): _meta(_oidAt(i)),
  },
);

Future<PumpedWorkspace> _pump(WidgetTester tester) async {
  final PumpedWorkspace w = await pumpWorkspace(
    tester,
    identity: _identity,
    initialState: _state(),
    // Wide enough that the ladder gives nothing up: a dropped column has no
    // strip, and a test that grabbed a missing one would fail for the wrong
    // reason.
    surfaceSize: const ui.Size(1600, 900),
    // pumpWorkspace's history route is a bare Scaffold unless this is
    // passed. Forget it and every finder below misses against an empty box.
    historyBuilder: (context, state) => HistoryPage(identity: _identity),
  );
  await tester.pumpAndSettle();
  return w;
}

Finder _strip(GbmGraphColumnId id) => find.descendant(
  of: find.byType(CommitGraphView),
  matching: find.byKey(ValueKey<String>('graphColumnResize.${id.storageId}')),
);

void main() {
  group('column resize strips', () {
    testWidgets('every resizable column has one and the locked two do not', (
      tester,
    ) async {
      await _pump(tester);

      for (final GbmGraphColumnId id in GbmGraphColumnId.values) {
        final bool expected =
            id.isResizable &&
            !kDefaultHiddenGraphColumnIds.contains(id.storageId);
        expect(
          _strip(id),
          expected ? findsOneWidget : findsNothing,
          reason: id.storageId,
        );
      }
    });

    testWidgets('dragging outward widens the column it belongs to', (
      tester,
    ) async {
      final PumpedWorkspace w = await _pump(tester);
      final double before = w.container.read(
        graphColumnWidthProvider,
      )[GbmGraphColumnId.author]!;

      // Author sits after Message, so its strip is on its *left* edge and a
      // leftward drag is what makes it wider.
      // touchSlopX: 0 so the whole 40px counts. WidgetTester.drag otherwise
      // spends kDragSlopDefault (20px) getting the recognizer to accept,
      // and that part never reaches onHorizontalDragUpdate -- which reads
      // as "the drag lost half its travel" rather than as harness setup.
      await tester.drag(
        _strip(GbmGraphColumnId.author),
        const Offset(-40, 0),
        touchSlopX: 0,
      );
      await tester.pumpAndSettle();

      expect(
        w.container.read(graphColumnWidthProvider)[GbmGraphColumnId.author],
        before + 40,
      );
      // And only that column: a strip must not be a global width nudge.
      expect(
        w.container.read(graphColumnWidthProvider)[GbmGraphColumnId.hash],
        GbmGraphColumnId.hash.defaultWidth,
      );
    });

    testWidgets('dragging inward narrows it, and stops at minWidth', (
      tester,
    ) async {
      final PumpedWorkspace w = await _pump(tester);

      await tester.drag(
        _strip(GbmGraphColumnId.author),
        const Offset(400, 0),
        touchSlopX: 0,
      );
      await tester.pumpAndSettle();

      expect(
        w.container.read(graphColumnWidthProvider)[GbmGraphColumnId.author],
        GbmGraphColumnId.author.minWidth,
      );
    });

    testWidgets('a drag past the clamp and back tracks the pointer, not the '
        'clamped value', (tester) async {
      // The reason the drag accumulates travel from the width it started at
      // instead of adding each delta to the current (clamped) width: doing
      // the latter makes a drag that overshoots minWidth by 400px come back
      // 400px late, which reads as a stuck column.
      final PumpedWorkspace w = await _pump(tester);
      final double before = w.container.read(
        graphColumnWidthProvider,
      )[GbmGraphColumnId.author]!;

      final TestGesture gesture = await tester.startGesture(
        tester.getCenter(_strip(GbmGraphColumnId.author)),
      );
      await gesture.moveBy(const Offset(400, 0)); // well past minWidth
      await tester.pump();
      await gesture.moveBy(const Offset(-400, 0)); // straight back
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // closeTo, not equals: the accumulator is a running sum of doubles and
      // 400 - 400 lands a few ulps off. A lag would be 400, not 1e-13.
      expect(
        w.container.read(graphColumnWidthProvider)[GbmGraphColumnId.author],
        closeTo(before, 0.001),
      );
    });

    testWidgets('finishing the drag writes the width to SharedPreferences', (
      tester,
    ) async {
      await _pump(tester);
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('${GraphColumnsRepository.keyPrefix}widths'),
        isNull,
        reason: 'nothing persisted before the drag',
      );

      await tester.drag(
        _strip(GbmGraphColumnId.author),
        const Offset(-40, 0),
        touchSlopX: 0,
      );
      await tester.pumpAndSettle();

      final String? stored = prefs.getString(
        '${GraphColumnsRepository.keyPrefix}widths',
      );
      expect(stored, isNotNull);
      expect(
        stored,
        contains('"author":${GbmGraphColumnId.author.defaultWidth + 40}'),
      );
    });

    testWidgets('a single click on a strip still selects the row under it', (
      tester,
    ) async {
      // The gesture-arena property, and the whole reason the strip uses
      // HitTestBehavior.translucent with no tap recognizer of its own.
      // Mutating that to `opaque` must turn this red -- if it does not, the
      // strip is not actually over a row and the test proves nothing.
      final PumpedWorkspace w = await _pump(tester);
      expect(w.container.read(selectedCommitProvider(_identity)), isNull);

      final Offset atStrip = tester.getCenter(_strip(GbmGraphColumnId.author));
      await tester.tapAt(atStrip);
      await tester.pumpAndSettle();

      final String? selected = w.container.read(
        selectedCommitProvider(_identity),
      );
      expect(selected, isNotNull);
      // The row it landed on is the one whose rect contains the tap, not
      // simply "some row" -- otherwise a strip that swallowed the tap and a
      // stale selection would look the same. Matched on the CommitRow's own
      // box rather than on its subject Text: the strip sits to the right of
      // the Message column, so the text's rect never contains the tap even
      // when the right row was selected.
      final CommitRow under = tester
          .widgetList<CommitRow>(find.byType(CommitRow))
          .firstWhere(
            (CommitRow r) => tester.getRect(find.byWidget(r)).contains(atStrip),
          );
      expect(selected, under.oidHex);
    });

    testWidgets('the click that selects does not also change a width', (
      tester,
    ) async {
      final PumpedWorkspace w = await _pump(tester);

      await tester.tapAt(tester.getCenter(_strip(GbmGraphColumnId.author)));
      await tester.pumpAndSettle();

      expect(
        w.container.read(graphColumnWidthProvider)[GbmGraphColumnId.author],
        GbmGraphColumnId.author.defaultWidth,
      );
    });
  });
}
