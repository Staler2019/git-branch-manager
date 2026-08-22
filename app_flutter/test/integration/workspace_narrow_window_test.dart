// The whole chain at a small window: WorkspaceScreen -> sidebar splitter ->
// HistoryPage's own two splitters -> CommitGraphView -> CommitRow.
//
// The lower tiers each hand CommitRow a width directly. Only this one proves
// the width it actually receives in production -- after the sidebar takes
// 250px, the Changed files column takes 186px, and two 5px dividers -- is a
// width the row can survive. Roughly:
//
//   commit list ~= window - 250 - 5 - 186 - 5
//     1024x768 -> ~578px      800x600 -> ~354px      1280x720 -> ~834px
//
// Those numbers grew when History's panes were recomposed to match spec P02
// (Changed files right, Commit detail below): the commit-detail splitter used
// to take 38% of the *width*, so the list was ~632px at 1280 and one rung
// further down the ladder.
//
// Two structural rules this file follows:
//
//   * every size runs a laneCount:1 CONTROL first. If the chrome (menu bar,
//     top bar, tab row, status bar) does not fit at that size, the treatment
//     case's failure is unattributable. A red control means the size is
//     wrong, not that the graph is broken.
//   * pumpWorkspace's history route is a bare Scaffold unless historyBuilder
//     is passed. Forget it and every assertion here passes against an empty
//     box.
//
// isMacOS is left at the default (false), i.e. the in-window MenuBarRow is
// rendered. An earlier plan for this file suppressed it on the assumption
// that seven menus overflow at 800px; menu_bar_row.dart:97 already wraps
// them in Expanded > SingleChildScrollView for exactly that reason, and so
// do TabRow and StatusBar. Hiding it would have tested less for no gain.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/history_graph/commit_graph_view.dart';
import 'package:gbm_flutter/features/history_graph/history_page.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';
import 'package:gbm_flutter/features/history_graph/widgets/graph_date_format.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

String _oidAt(int i) => '${i.toRadixString(16).padLeft(4, '0')}${'a' * 36}';

const String _headSubject = 'Head commit with a branch chip';
const String _plainSubject = 'A perfectly ordinary commit';

/// Rows spread one per lane, so `laneCount` really is the graph column's
/// width driver. The fixture asserts *layout*, not edge geometry, so unlike
/// graph_edge_continuity_test.dart it neither anchors its lanes to
/// GraphBuilderTest.cpp output nor carries any edges -- there is nothing
/// here for a bend to be wrong about, and saying so keeps the next reader
/// from filing it as "a shape GraphBuilder cannot produce".
GraphSnapshotView _graph(int laneCount) {
  return GraphSnapshotView(
    rows: <GraphRow>[
      for (int i = 0; i < laneCount; i++)
        GraphRow(
          parentOffset: 0,
          edgeOffset: 0,
          commitTime: 0,
          lane: i,
          color: i,
          // GraphRow.isHead is bit 0x20, not bit 0 -- an earlier comment
          // here said bit 0 and set 1, which marks nothing. Kept at 0x20 on
          // row 0 so the fixture says what it means; nothing in this file
          // depends on it either way, because the HEAD *chip* comes from
          // _refs() below and HEAD has no other representation in the row.
          flags: i == 0 ? 0x20 : 0,
        ),
    ],
    oidsHex: <String>[for (int i = 0; i < laneCount; i++) _oidAt(i)],
    parentPool: const <int>[],
    laneCount: laneCount,
    complete: true,
    truncated: false,
    edges: const <GraphEdge>[],
  );
}

CommitMeta _meta(String oid, String subject) => CommitMeta(
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
  subject: subject,
  body: '',
  signedCommit: false,
);

/// A branch on row 0 only, so the HEAD row carries a chip and every other
/// row does not -- the asymmetry the cross-row alignment test needs.
RefSnapshot _refs() => RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: _oidAt(0),
  ),
  refs: <RefInfo>[
    RefInfo(
      fullName: 'refs/heads/main',
      shortName: 'main',
      kind: RefKind.localBranch,
      target: _oidAt(0),
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isGone: false,
      isHead: true,
      isSymbolic: true,
      worktreePath: '',
    ),
  ],
  refCountGuardTripped: false,
  totalRefCount: 1,
);

RepoSessionState _state(int laneCount) {
  final GraphSnapshotView graph = _graph(laneCount);
  return RepoSessionState(
    isOpen: true,
    graph: graph,
    refs: _refs(),
    // Pre-seeded, or the rows render skeleton blocks instead of text and
    // every finder below misses.
    commitMetaCache: <String, CommitMeta>{
      for (int i = 0; i < laneCount; i++)
        _oidAt(i): _meta(_oidAt(i), i == 0 ? _headSubject : _plainSubject),
    },
  );
}

Future<PumpedWorkspace> _pump(
  WidgetTester tester, {
  required ui.Size size,
  required int laneCount,
}) async {
  final PumpedWorkspace w = await pumpWorkspace(
    tester,
    identity: _identity,
    initialState: _state(laneCount),
    surfaceSize: size,
    historyBuilder: (context, state) => HistoryPage(identity: _identity),
  );
  await tester.pumpAndSettle();
  return w;
}

const ui.Size _small = ui.Size(1024, 768);
const ui.Size _tiny = ui.Size(800, 600);

Rect _listRect(WidgetTester tester) =>
    tester.getRect(find.byType(CommitGraphView));

Rect _graphRectOfRow(WidgetTester tester, int rowIndex) => tester.getRect(
  find
      .descendant(
        of: find.byType(CommitRow).at(rowIndex),
        matching: find.byType(CustomPaint),
      )
      .first,
);

/// What the Date column would render for the fixture's commits, derived
/// through the same formatter the row uses rather than hardcoded -- the
/// fixture's `when: 0` makes it an epoch date, whose spelling is
/// `formatGraphDate`'s business and not this test's.
String _dateLabel() =>
    formatGraphDate(DateTime.fromMillisecondsSinceEpoch(0), DateTime.now());

void main() {
  for (final (String label, ui.Size size) in <(String, ui.Size)>[
    ('1024x768', _small),
    ('800x600', _tiny),
  ]) {
    group('at $label', () {
      testWidgets('CONTROL: a one-lane history renders cleanly', (
        tester,
      ) async {
        await _pump(tester, size: size, laneCount: 1);

        expect(
          tester.takeException(),
          isNull,
          reason:
              'the chrome itself does not fit at $label -- every other case '
              'in this group is unattributable until that is fixed',
        );
        expect(find.byType(CommitGraphView), findsOneWidget);
      });

      testWidgets('a twelve-lane history does not overflow', (tester) async {
        await _pump(tester, size: size, laneCount: 12);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the graph column stays inside the commit list', (
        tester,
      ) async {
        await _pump(tester, size: size, laneCount: 12);

        final Rect list = _listRect(tester);
        final Rect graph = _graphRectOfRow(tester, 0);
        expect(graph.left, greaterThanOrEqualTo(list.left));
        expect(graph.right, lessThanOrEqualTo(list.right));
      });

      testWidgets('the commit subject is still visible', (tester) async {
        await _pump(tester, size: size, laneCount: 12);

        // Spec P02-16 locks Message. A zero-width Expanded overflows nothing
        // and shows nothing, so this is not covered by the case above.
        expect(
          tester.getSize(find.text(_plainSubject).first).width,
          greaterThan(0),
        );
      });

      testWidgets('every row shows the same set of columns', (tester) async {
        await _pump(tester, size: size, laneCount: 12);

        // The regression this exists for: if the plan were computed per row
        // rather than per list, the HEAD row -- the only one carrying a ref
        // chip -- could give up a trailing column its neighbours keep, and
        // the list would stop lining up. Comparing the graph column's own
        // geometry is the cheapest proxy that does not depend on which
        // columns happen to survive at this width.
        final Rect headRow = _graphRectOfRow(tester, 0);
        final Rect plainRow = _graphRectOfRow(tester, 1);
        expect(plainRow.left, headRow.left);
        expect(plainRow.width, headRow.width);
      });
    });
  }

  group('at the default 1280x720 window', () {
    testWidgets('a twelve-lane history gives up nothing', (tester) async {
      // The app's own default window size (my_application.cc:55,
      // main.cpp:29). Degradation biting harder than this here would mean
      // the ladder is tuned too eagerly for ordinary use.
      //
      // The title has now been true twice and false once in between, so read
      // the history before trusting it: it originally claimed "gives up
      // nothing" while asserting only the two positives, and Date was in fact
      // dropped -- the list was ~632px then. Recomposing the page to spec
      // (see history_page_layout_test.dart) gave the list ~834px, which is
      // enough for Date again. The negative assertion is gone because there
      // is nothing left to give up; the three positives are the rung lock,
      // and any of them vanishing is the regression.
      await _pump(tester, size: const ui.Size(1280, 720), laneCount: 12);

      expect(tester.takeException(), isNull);
      expect(find.text('Ada Lovelace').first, findsOneWidget);
      expect(find.text(_oidAt(1).substring(0, 8)), findsWidgets);
      expect(find.text(_dateLabel()), findsWidgets);
    });
  });
}
