// The recorded defect: 05-B's "New branch from here…" and 05-E's
// "Create branch here…" on a commit row both opened `promptText`'s
// single-field box
// with the start point folded silently into an unseen `createBranch()` call
// -- nothing on screen said where the new branch would start, and the field
// a user might look for to change it did not exist.
//
// A widget-tier pump of `NewBranchDialogContent` directly (see
// new_branch_dialog_test.dart) cannot see whether the sidebar or the commit
// row actually *reaches* that dialog -- that is exactly the shape
// [ACT-one-handler-map]'s rename-branch precedent documents, so this mirrors
// workspace_rename_branch_flow_test.dart: pump the real WorkspaceScreen,
// drive the real menu, assert the real dialog with the real query parameter.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/new_branch/new_branch_dialog.dart';
import 'package:gbm_flutter/features/history_graph/history_page.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_tree_item.dart';
import 'package:gbm_flutter/routing/dialog_route.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/widgets/gbm_row.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

const RefInfo _mainBranch = RefInfo(
  fullName: 'refs/heads/main',
  shortName: 'main',
  kind: RefKind.localBranch,
  target: 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2',
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: true,
  isSymbolic: false,
  worktreePath: '',
);

const RefInfo _releaseBranch = RefInfo(
  fullName: 'refs/heads/release',
  shortName: 'release',
  kind: RefKind.localBranch,
  target: 'b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3',
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

final RefSnapshot _refs = const RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2',
  ),
  refs: <RefInfo>[_mainBranch, _releaseBranch],
  refCountGuardTripped: false,
  totalRefCount: 2,
);

const String _commitOid = 'c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4';

/// One commit, in lane 0, so History paints a row `CommitRow` can be found
/// on. The graph half is what `CommitGraphView` needs to render anything at
/// all -- an empty `GraphSnapshotView` draws no rows.
const GraphSnapshotView _graph = GraphSnapshotView(
  rows: <GraphRow>[
    GraphRow(
      parentOffset: 0,
      edgeOffset: 0,
      commitTime: 0,
      lane: 0,
      color: 0,
      flags: 0,
    ),
  ],
  oidsHex: <String>[_commitOid],
  parentPool: <int>[],
  laneCount: 1,
  complete: true,
  truncated: false,
  edges: <GraphEdge>[],
);

RepoSessionState _session() => RepoSessionState(
  isOpen: true,
  refs: _refs,
  graph: _graph,
  commitMetaCache: const <String, CommitMeta>{
    _commitOid: CommitMeta(
      oid: _commitOid,
      tree: 'b',
      parents: <String>[],
      author: Signature(name: 'a', email: 'a@b.c', when: 0, tzOffsetMinutes: 0),
      committer: Signature(
        name: 'a',
        email: 'a@b.c',
        when: 0,
        tzOffsetMinutes: 0,
      ),
      subject: 'Fix lane allocator overflow',
      body: '',
      signedCommit: false,
    ),
  },
);

List<RouteBase> _newBranchDialogRoute() => <RouteBase>[
  dialogRoute(
    path: RoutePaths.newBranchDialog,
    builder: (context, state) => NewBranchDialogContent(
      identity: _identity,
      initialStartPoint: state.uri.queryParameters['startPoint'],
    ),
  ),
];

/// The name of the row [GbmRefPicker] is drawing as selected, scoped to
/// [scope] so History's own selection tint (a different [GbmRow] entirely)
/// cannot be mistaken for the dialog's.
///
/// `find.text('release')` alone was tried first and stayed green with the
/// start point dropped from the route entirely: the picker lists every
/// local branch regardless of which one is selected, so the name is on
/// screen either way -- the tint is the only thing that says which one the
/// dialog will actually use ([TEST-fixture-cannot-disagree] shape 8).
String? _highlightedIn(WidgetTester tester, Finder scope) {
  for (final Element element
      in find.descendant(of: scope, matching: find.byType(GbmRow)).evaluate()) {
    if (!(element.widget as GbmRow).selected) continue;
    final Finder text = find.descendant(
      of: find.byWidget(element.widget),
      matching: find.byType(Text),
    );
    return tester.widget<Text>(text.first).data;
  }
  return null;
}

Future<void> _rightClick(WidgetTester tester, Finder target) async {
  final TestGesture gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  addTearDown(gesture.removePointer);
  await gesture.down(tester.getCenter(target));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '05-B opens the real dialog with the clicked branch as start point',
    (tester) async {
      await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _session(),
        historyBuilder: (context, state) => HistoryPage(identity: _identity),
        topLevelRoutes: _newBranchDialogRoute(),
      );

      expect(find.byType(NewBranchDialogContent), findsNothing);

      await _rightClick(tester, find.widgetWithText(BranchTreeItem, 'release'));
      await tester.tap(find.text('New branch from here…'));
      await tester.pumpAndSettle();

      expect(find.byType(NewBranchDialogContent), findsOneWidget);
      // Not just that the dialog opened -- that the start point it opened
      // *with* is drawn and *selected*, which is the whole of the recorded
      // defect (the old free-text box held this value and showed nothing).
      expect(
        _highlightedIn(tester, find.byType(NewBranchDialogContent)),
        'release',
      );
    },
  );

  testWidgets('05-E opens the real dialog with the commit oid as start point', (
    tester,
  ) async {
    await pumpWorkspace(
      tester,
      identity: _identity,
      initialState: _session(),
      historyBuilder: (context, state) => HistoryPage(identity: _identity),
      topLevelRoutes: _newBranchDialogRoute(),
    );

    await _rightClick(tester, find.byType(CommitRow).first);
    // The commit row's own wording -- 05-E's item, not 05-B's.
    await tester.tap(find.text('Create branch here…'));
    await tester.pumpAndSettle();

    expect(find.byType(NewBranchDialogContent), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NewBranchDialogContent),
        matching: find.text(_commitOid),
      ),
      findsWidgets,
    );
    expect(
      find.descendant(
        of: find.byType(NewBranchDialogContent),
        matching: find.text('COMMIT'),
      ),
      findsOneWidget,
    );
  });

  testWidgets("the sidebar's own New branch button opens the dialog with no "
      'preselected start point', (tester) async {
    await pumpWorkspace(
      tester,
      identity: _identity,
      initialState: _session(),
      topLevelRoutes: _newBranchDialogRoute(),
    );

    await tester.tap(find.byTooltip('New branch…'));
    await tester.pumpAndSettle();

    expect(find.byType(NewBranchDialogContent), findsOneWidget);
    // The current branch is still the default selection, but it arrived
    // that way from the dialog's own fallback, not from a query parameter.
    expect(
      find.descendant(
        of: find.byType(NewBranchDialogContent),
        matching: find.text('目前分支'),
      ),
      findsOneWidget,
    );
  });
}
