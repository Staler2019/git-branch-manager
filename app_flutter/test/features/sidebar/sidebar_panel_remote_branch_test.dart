// Verifies SidebarPanel's gap-4 wiring: the merged local/remote branch tree
// (branch_tree_builder.dart's mergeLocalAndRemoteBranches) actually reaches
// the tree, and the 05-C remote-only menu's three actions
// (Checkout as new local…, Fetch this branch, Delete remote branch…) dispatch
// through the real repoSessionProvider/GoRouter seam rather than just being
// unit-tested against BranchTreeItem in isolation -- see CLAUDE.md's
// Testing tiers: a widget test alone proves the widget renders correctly,
// not that SidebarPanel's own callback wiring reaches the controller.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/branch_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/sidebar/sidebar_panel.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_tree_item.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _testIdentity = RepoIdentity.forWorkDir('/test/repo');
final String _repoIdParam = Uri.encodeComponent(_testIdentity.workDir);

final RefInfo _localMain = RefInfo(
  fullName: 'refs/heads/main',
  shortName: 'main',
  kind: RefKind.localBranch,
  target: 'a' * 40,
  upstream: 'refs/remotes/origin/main',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: true,
  isGone: false,
  isHead: true,
  isSymbolic: true,
  worktreePath: '',
);

// Tracked by _localMain's upstream -- mergeLocalAndRemoteBranches should
// drop this one rather than showing it as a second, remote-only row.
final RefInfo _remoteMain = RefInfo(
  fullName: 'refs/remotes/origin/main',
  shortName: 'origin/main',
  kind: RefKind.remoteBranch,
  target: 'a' * 40,
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

// No local branch tracks this one -- should survive the merge as a
// remote-only leaf named "release" (remote prefix stripped).
final RefInfo _remoteOnlyRelease = RefInfo(
  fullName: 'refs/remotes/origin/release',
  shortName: 'origin/release',
  kind: RefKind.remoteBranch,
  target: 'b' * 40,
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

// A gone local branch: upstream vanished from the remote entirely --
// BRANCH_STATES's "Remote 已刪除" state. Note there is no matching
// RefInfo(kind: remoteBranch) in this snapshot's refs -- the remote-tracking
// ref really is gone, not merely unlisted.
final RefInfo _goneFeature = RefInfo(
  fullName: 'refs/heads/feature',
  shortName: 'feature',
  kind: RefKind.localBranch,
  target: 'c' * 40,
  upstream: 'refs/remotes/origin/feature',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: true,
  isGone: true,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

final RefSnapshot _testRefSnapshot = RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'a' * 40,
  ),
  refs: <RefInfo>[_localMain, _remoteMain, _remoteOnlyRelease, _goneFeature],
  refCountGuardTripped: false,
  totalRefCount: 4,
);

const WorkingCopyEntry _conflictEntry = WorkingCopyEntry(
  path: 'conflict.txt',
  oldPath: '',
  untracked: false,
  staged: false,
  indexStatus: FileChangeKind.modified,
  hasUnstagedChange: true,
  worktreeStatus: FileChangeKind.modified,
  unstagedAdded: 0,
  unstagedRemoved: 0,
  stagedAdded: 0,
  stagedRemoved: 0,
  conflict: ConflictKind.bothModified,
  ancestorBlob: '',
  oursBlob: 'ours-hash',
  theirsBlob: 'theirs-hash',
  similarity: 0,
  isSubmodule: false,
  isConflicted: true,
);

const RepoState _mergeState = RepoState(
  flags: RepoStateFlags.merge,
  isClean: false,
  isSequencerOperation: true,
  rebaseStep: 0,
  rebaseTotal: 0,
  rebaseOntoLabel: '',
  indexLocked: false,
  indexLockAgeSeconds: null,
  describe: '',
);

class _Harness {
  _Harness({required this.fake});
  final FakeRepoSessionController fake;
}

Future<_Harness> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final FakeRepoSessionController fake = FakeRepoSessionController(
    _testIdentity,
    const RepoSessionState(),
  );

  final GoRouter router = GoRouter(
    initialLocation: '/repo/$_repoIdParam/history',
    routes: <RouteBase>[
      GoRoute(
        path: '/repo/:repoId/history',
        builder: (context, state) => Scaffold(
          body: SidebarPanel(identity: _testIdentity, filterFocusNode: null),
        ),
      ),
      // A sentinel per dialog, not one shared stub: 05-B's Delete branch…
      // and 05-C's Delete remote branch… both only `context.push`, so an
      // assertion on "a route was pushed" cannot tell them apart -- and
      // telling them apart is the whole point of this round's menu change.
      GoRoute(
        path: RoutePaths.deleteBranchDialog,
        builder: (context, state) => Scaffold(
          body: Text('delete-branch:${state.uri.queryParameters['branch']}'),
        ),
      ),
      GoRoute(
        path: RoutePaths.deleteRemoteBranchDialog,
        builder: (context, state) => Scaffold(
          body: Text(
            'delete-remote-branch:'
            '${state.uri.queryParameters['remote']}/'
            '${state.uri.queryParameters['branch']}',
          ),
        ),
      ),
    ],
  );

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoRefsProvider(_testIdentity).overrideWithValue(_testRefSnapshot),
      repoSessionProvider(_testIdentity).overrideWith((ref) => fake),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();

  return _Harness(fake: fake);
}

/// Opens the 05-C menu for the remote-only "release" row.
/// `BranchTreeItem`'s outer `InkWell.onDoubleTap` (set only for a
/// remote-only row -- see that widget's doc comment) puts a
/// `DoubleTapGestureRecognizer` in the same gesture arena as the inner
/// "more" `IconButton`'s tap recognizer; the arena can't resolve the single
/// tap until `kDoubleTapTimeout` elapses with no second tap, so a bare
/// `tester.tap()` + `pumpAndSettle()` silently never opens the menu here
/// (confirmed in isolation against a bare `BranchTreeItem` -- this is a
/// pre-existing gesture-arena quirk of the double-tap wiring, not something
/// introduced by this test). A real click has the same ~300ms hesitation;
/// not fixed here since it's a latency quirk, not a correctness bug, and
/// fixing the underlying gesture conflict is out of this gap's scope.
Future<void> _openRemoteRowMenu(WidgetTester tester) async {
  final Finder releaseItem = find.ancestor(
    of: find.text('release'),
    matching: find.byType(BranchTreeItem),
  );
  final Finder moreButton = find.descendant(
    of: releaseItem,
    matching: find.byTooltip('Branch actions'),
  );
  await tester.tap(moreButton);
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
  await tester.pumpAndSettle();
}

void main() {
  group('SidebarPanel remote branch merge (gap 4)', () {
    testWidgets('shows the remote-only branch but not the tracked one twice', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('main'), findsOneWidget);
      expect(find.text('release'), findsOneWidget);
      expect(find.text('origin/main'), findsNothing);
      expect(find.text('origin/release'), findsNothing);
    });

    testWidgets(
      'double-tapping the remote-only row checks out a new local branch',
      (tester) async {
        final _Harness harness = await _pump(tester);

        final Finder releaseRow = find.ancestor(
          of: find.text('release'),
          matching: find.byType(InkWell),
        );
        await tester.tap(releaseRow);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(releaseRow);
        await tester.pumpAndSettle();

        final FakeCommand checkout = harness.fake.commandLog.singleWhere(
          (c) => c.name == 'checkout',
        );
        expect(checkout.args['target'], 'refs/remotes/origin/release');
        expect(checkout.args['createBranch'], isTrue);
        expect(checkout.args['newBranchName'], 'release');
      },
    );

    testWidgets('offers no prune, through the real wiring', (tester) async {
      // 使用者裁定：選單不再出現 prune 這個字，背景做掉。This test used to
      // tap 「Prune this ref」 and assert the pruneRemote dispatch; the item
      // and its `onPruneRef` callback are both gone. Asserted here rather
      // than only against BranchTreeItem because SidebarPanel is what wires
      // the callback, and a re-added wiring would show up here first.
      final _Harness harness = await _pump(tester);

      await _openRemoteRowMenu(tester);

      expect(find.textContaining('Prune'), findsNothing);
      expect(
        harness.fake.commandLog.where((c) => c.name == 'pruneRemote').length,
        0,
      );
    });

    testWidgets(
      'Fetch this branch calls fetchRemote with the remote name and branch',
      (tester) async {
        final _Harness harness = await _pump(tester);

        await _openRemoteRowMenu(tester);
        await tester.tap(find.text('Fetch this branch'));
        await tester.pumpAndSettle();

        final FakeCommand fetch = harness.fake.commandLog.singleWhere(
          (c) => c.name == 'fetchRemote',
        );
        expect(fetch.args['remoteName'], 'origin');
        expect(fetch.args['refs'], <String>['release']);
      },
    );

    testWidgets(
      'Delete remote branch… navigates to deleteRemoteBranchDialogFor',
      (tester) async {
        await _pump(tester);

        await _openRemoteRowMenu(tester);
        await tester.tap(find.text('Delete remote branch…'));
        await tester.pumpAndSettle();

        expect(
          find.text('delete-remote-branch:origin/release'),
          findsOneWidget,
        );
        // The remote row keeps no local-branch delete: 使用者裁定 for this
        // row is 「仍叫 delete remote branch，一樣跳 dialog，但不會長勾選
        // 刪除 remote 的選項」.
        expect(find.textContaining('delete-branch:'), findsNothing);
      },
    );

    testWidgets(
      'double-tap checkout is gated by conflictActive through the real '
      'session seam, and re-enables once the conflict clears',
      (tester) async {
        final _Harness harness = await _pump(tester);

        final Finder releaseRow = find.ancestor(
          of: find.text('release'),
          matching: find.byType(InkWell),
        );

        harness.fake.emit(
          RepoSessionState(
            isOpen: true,
            refs: _testRefSnapshot,
            repoState: _mergeState,
            workingCopyStatus: const WorkingCopyStatus(
              entries: [_conflictEntry],
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(releaseRow);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(releaseRow);
        await tester.pumpAndSettle();

        expect(
          harness.fake.commandLog.any((c) => c.name == 'checkout'),
          isFalse,
        );

        harness.fake.emit(
          RepoSessionState(isOpen: true, refs: _testRefSnapshot),
        );
        await tester.pumpAndSettle();

        await tester.tap(releaseRow);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tap(releaseRow);
        await tester.pumpAndSettle();

        final FakeCommand checkout = harness.fake.commandLog.singleWhere(
          (c) => c.name == 'checkout',
        );
        expect(checkout.args['target'], 'refs/remotes/origin/release');
      },
    );
  });

  // 使用者裁定：「the local have branch should have 05-b not 05-c」. This
  // group asserted the opposite until this round -- Prune wired, and
  // Checkout/Fetch/Delete-on-remote permanently disabled -- on the strength
  // of BRANCH_STATES's 「gone 的列只留 Prune 與 Copy，其餘停用」. Overruled.
  group('SidebarPanel gone-row menu wiring (05-B)', () {
    Finder goneMoreButton() => find.descendant(
      of: find.ancestor(
        of: find.text('feature'),
        matching: find.byType(BranchTreeItem),
      ),
      // Unlike the remote-only row, a gone row has no onDoubleTap (it is a
      // real local branch), so this button has no gesture-arena conflict
      // and needs no kDoubleTapTimeout wait, unlike _openRemoteRowMenu.
      matching: find.byTooltip('Branch actions'),
    );

    testWidgets('Delete branch… opens the single-branch delete dialog', (
      tester,
    ) async {
      // The action the user was locked out of. It must reach the *dialog*,
      // not dispatch a delete: the ellipsis is the contract, and the dialog
      // is the only place 「同時刪除遠端分支」 can be asked for.
      final _Harness harness = await _pump(tester);

      await tester.tap(goneMoreButton());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete branch…'));
      await tester.pumpAndSettle();

      expect(find.text('delete-branch:feature'), findsOneWidget);
      // Counted: nothing may be deleted before the user confirms.
      expect(
        harness.fake.commandLog.where((c) => c.name == 'deleteBranch').length,
        0,
      );
    });

    testWidgets('offers the rest of 05-B, and no prune anywhere', (
      tester,
    ) async {
      final _Harness harness = await _pump(tester);

      await tester.tap(goneMoreButton());
      await tester.pumpAndSettle();

      expect(find.text('Checkout'), findsOneWidget);
      expect(find.text('Rename…'), findsOneWidget);
      expect(find.text('Merge into current'), findsOneWidget);
      expect(find.text('New branch from here…'), findsOneWidget);
      expect(find.textContaining('Prune'), findsNothing);
      expect(find.text('Checkout as new local…'), findsNothing);
      expect(
        harness.fake.commandLog.where((c) => c.name == 'pruneRemote').length,
        0,
      );
    });
  });
}
