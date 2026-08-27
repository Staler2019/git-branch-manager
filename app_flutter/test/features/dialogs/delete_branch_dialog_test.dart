// #74: `_remoteOf()` recovered the remote name by splitting `RefInfo.upstream`
// on its first slash. `upstream` is git's `%(upstream)`, the *full* ref name
// (`refs/remotes/origin/x`, not `%(upstream:short)`), so the split yielded the
// literal string "refs" and the dialog dispatched
// `git push refs --delete <branch>` -- a command that cannot succeed.
//
// The same function also gated on `hasTrackingInfo`, which mirrors
// `%(upstream:track)` and is *empty* for a branch exactly in sync with its
// upstream. So the checkbox vanished entirely on the commonest branch there
// is: one that tracks a remote and has nothing to push.
//
// Every fixture here therefore sets `hasTrackingInfo: false` with a populated
// `upstream`, which is the real in-sync shape and the one that used to hide
// the checkbox.
//
// Two more defects in the same function, found once this dialog became the
// *only* way to delete a branch's remote side (the sidebar's prune entries
// are gone):
//
// 3. It asked `upstream` alone whether the branch has a remote side, so a
//    branch pushed without `-u` -- whose same-named remote ref is alive and
//    visible in the sidebar -- got no checkbox at all. The counterpart, not
//    the tracking config, answers that question; see `remoteCounterpartOf`.
// 4. The title printed the *upstream's* branch name while the dispatch sent
//    the *local* one. For `feature/x` tracking `origin/renamed-x` the dialog
//    said "Also delete renamed-x" and then deleted `feature/x` on origin --
//    a second source of truth for one fact, shipped.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/delete_branch/delete_branch_dialog.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

RefInfo _branch(
  String name, {
  String upstream = '',
  bool isGone = false,
  bool isHead = false,
}) => RefInfo(
  fullName: 'refs/heads/$name',
  shortName: name,
  kind: RefKind.localBranch,
  target: 'a' * 40,
  upstream: upstream,
  ahead: 0,
  behind: 0,
  // Not derived from `upstream` on purpose: a fixture that computes one field
  // from another cannot falsify code that makes the same derivation, and
  // `false` with a populated upstream is exactly the in-sync case #74's
  // `hasTrackingInfo` gate got wrong.
  hasTrackingInfo: false,
  isGone: isGone,
  isHead: isHead,
  isSymbolic: false,
  worktreePath: '',
);

RefInfo _remote(String remote, String branch) => RefInfo(
  fullName: 'refs/remotes/$remote/$branch',
  shortName: '$remote/$branch',
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

RefSnapshot _snapshot(List<RefInfo> refs) => RefSnapshot(
  head: const HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: '',
  ),
  refs: refs,
  refCountGuardTripped: false,
  totalRefCount: refs.length,
);

Future<FakeRepoSessionController> _pump(
  WidgetTester tester,
  String? branchName,
  List<RefInfo> refs, {
  Map<String, List<String>> gonePendingByRemote =
      const <String, List<String>>{},
}) async {
  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    RepoSessionState(
      refs: _snapshot(refs),
      gonePendingByRemote: gonePendingByRemote,
    ),
  );
  // The dialog pops after dispatching, so it needs something underneath it.
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/dialog',
        builder: (BuildContext context, GoRouterState state) => Scaffold(
          body: DeleteBranchDialogContent(
            identity: _identity,
            branchName: branchName,
          ),
        ),
      ),
    ],
  );
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      repoSessionProvider(_identity).overrideWith((Ref ref) => fake),
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
  router.push('/dialog');
  await tester.pumpAndSettle();
  return fake;
}

List<FakeCommand> _deletes(FakeRepoSessionController fake) =>
    fake.commandLog.where((FakeCommand c) => c.name == 'deleteBranch').toList();

void main() {
  group('deleteBranchRemoteTarget', () {
    test('recovers the remote from a full upstream ref, never by splitting '
        'on the first slash (#74)', () {
      expect(
        deleteBranchRemoteTarget(
          _branch('feature/x', upstream: 'refs/remotes/upstream/feature/x'),
          <RefInfo>[_remote('upstream', 'feature/x')],
        ),
        ('upstream', 'feature/x'),
      );
    });

    test('a branch with neither an upstream nor a same-named remote has no '
        'remote side', () {
      expect(
        deleteBranchRemoteTarget(_branch('solo'), <RefInfo>[
          _remote('origin', 'main'),
        ]),
        ('', ''),
      );
    });

    test('an in-sync branch still has a remote', () {
      // hasTrackingInfo is `%(upstream:track)`, which git leaves empty when
      // a branch is exactly in sync. Asking it "does this track a remote?"
      // hides the checkbox on the commonest branch there is.
      expect(
        deleteBranchRemoteTarget(
          _branch('main', upstream: 'refs/remotes/origin/main'),
          <RefInfo>[_remote('origin', 'main')],
        ),
        ('origin', 'main'),
      );
    });

    test('a branch pushed without -u has a remote side too', () {
      // `git push origin HEAD` leaves branch.<name>.merge empty, so upstream
      // is empty while origin/feature/x is right there. Reading upstream
      // alone reports "no remote" about a branch the sidebar draws with a
      // remote counterpart -- the same premise that made the sidebar draw
      // two rows for it.
      expect(
        deleteBranchRemoteTarget(_branch('feature/x'), <RefInfo>[
          _remote('origin', 'feature/x'),
        ]),
        ('origin', 'feature/x'),
      );
    });

    test('names the branch as it exists on the remote, not the local one', () {
      // The one fixture where the two names differ. Everywhere else they
      // coincide, which is why a dialog that printed one and deleted the
      // other could ship.
      expect(
        deleteBranchRemoteTarget(
          _branch('feature/x', upstream: 'refs/remotes/origin/renamed-x'),
          <RefInfo>[_remote('origin', 'renamed-x')],
        ),
        ('origin', 'renamed-x'),
      );
    });
  });

  group('the also-delete-remote checkbox', () {
    testWidgets('dispatches the remote delete with the real remote name', (
      WidgetTester tester,
    ) async {
      final FakeRepoSessionController fake =
          await _pump(tester, 'feature/x', <RefInfo>[
            _branch('main', upstream: 'refs/remotes/origin/main', isHead: true),
            _branch('feature/x', upstream: 'refs/remotes/origin/feature/x'),
          ]);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete branch'));
      await tester.pumpAndSettle();

      // Counted, not `any`: a double dispatch would push twice.
      final List<FakeCommand> remote = _deletes(
        fake,
      ).where((FakeCommand c) => c.args['isRemote'] == true).toList();
      expect(remote.length, 1);
      expect(remote.single.args['remoteName'], 'origin');
      expect(remote.single.args['names'], <String>['feature/x']);
    });

    testWidgets('is offered for a branch that is exactly in sync', (
      WidgetTester tester,
    ) async {
      await _pump(tester, 'feature/x', <RefInfo>[
        _branch('main', upstream: 'refs/remotes/origin/main', isHead: true),
        _branch('feature/x', upstream: 'refs/remotes/origin/feature/x'),
      ]);

      expect(find.byType(CheckboxListTile), findsOneWidget);
    });

    testWidgets('is disabled for a branch whose upstream is already gone', (
      WidgetTester tester,
    ) async {
      // Ticking it would push the vanished branch back up and then delete it
      // again -- see #74's own closing note. Disabled rather than hidden, so
      // the reason stays visible.
      await _pump(tester, 'feature/x', <RefInfo>[
        _branch('main', upstream: 'refs/remotes/origin/main', isHead: true),
        _branch(
          'feature/x',
          upstream: 'refs/remotes/origin/feature/x',
          isGone: true,
        ),
      ]);

      final CheckboxListTile tile = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(tile.onChanged, isNull);
      expect(tile.value, isFalse);
    });

    testWidgets('does not carry a tick over to the next branch picked', (
      WidgetTester tester,
    ) async {
      // Picker mode. The tick was a statement about *that* branch, so
      // choosing another one has to clear it -- otherwise the box the user
      // ticked for feature/x silently arms a remote delete on feature/y.
      //
      // This pins the reset in the dropdown's onChanged. The predicate
      // behind the box is a second, independent line of defence for the
      // gone case; neither one alone is what this test is about.
      final FakeRepoSessionController fake =
          await _pump(tester, null, <RefInfo>[
            _branch('main', upstream: 'refs/remotes/origin/main', isHead: true),
            _branch('feature/x', upstream: 'refs/remotes/origin/feature/x'),
            _branch('feature/y', upstream: 'refs/remotes/origin/feature/y'),
          ]);

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('feature/x').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isTrue,
      );

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('feature/y').last);
      await tester.pumpAndSettle();

      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );

      await tester.tap(find.text('Delete branch'));
      await tester.pumpAndSettle();

      // Counted, not `any`: the local delete is expected, the remote one
      // is the regression.
      expect(
        _deletes(
          fake,
        ).where((FakeCommand c) => c.args['isRemote'] == true).length,
        0,
      );
      expect(_deletes(fake).length, 1);
    });

    testWidgets('is not offered for a branch with no remote side at all', (
      WidgetTester tester,
    ) async {
      // Remote refs exist -- just not one for this branch. An empty remote
      // list would pass whether the name rule is read or ignored.
      await _pump(tester, 'solo', <RefInfo>[
        _branch('main', upstream: 'refs/remotes/origin/main', isHead: true),
        _branch('solo'),
        _remote('origin', 'main'),
        _remote('origin', 'something-else'),
      ]);

      expect(find.byType(CheckboxListTile), findsNothing);
    });

    testWidgets('is offered for a branch pushed without -u', (
      WidgetTester tester,
    ) async {
      final FakeRepoSessionController fake =
          await _pump(tester, 'feature/x', <RefInfo>[
            _branch('main', upstream: 'refs/remotes/origin/main', isHead: true),
            _branch('feature/x'),
            _remote('origin', 'feature/x'),
          ]);

      expect(find.byType(CheckboxListTile), findsOneWidget);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete branch'));
      await tester.pumpAndSettle();

      final List<FakeCommand> remote = _deletes(
        fake,
      ).where((FakeCommand c) => c.args['isRemote'] == true).toList();
      expect(remote.length, 1);
      expect(remote.single.args['remoteName'], 'origin');
      expect(remote.single.args['names'], <String>['feature/x']);
    });

    testWidgets('deletes the branch it names, not the local one', (
      WidgetTester tester,
    ) async {
      // The title and the dispatch were two independent derivations of one
      // fact. They agree for every branch whose upstream carries its own
      // name, which is nearly all of them -- so only a renamed upstream can
      // tell a fixed dialog from a broken one.
      final FakeRepoSessionController fake =
          await _pump(tester, 'feature/x', <RefInfo>[
            _branch('main', upstream: 'refs/remotes/origin/main', isHead: true),
            _branch('feature/x', upstream: 'refs/remotes/origin/renamed-x'),
            _remote('origin', 'renamed-x'),
          ]);

      expect(find.text('Also delete renamed-x on origin'), findsOneWidget);

      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete branch'));
      await tester.pumpAndSettle();

      final List<FakeCommand> remote = _deletes(
        fake,
      ).where((FakeCommand c) => c.args['isRemote'] == true).toList();
      expect(remote.length, 1);
      expect(remote.single.args['names'], <String>['renamed-x']);

      // The local side keeps the local name -- the two are not interchangeable
      // in either direction.
      final List<FakeCommand> local = _deletes(
        fake,
      ).where((FakeCommand c) => c.args['isRemote'] != true).toList();
      expect(local.length, 1);
      expect(local.single.args['names'], <String>['feature/x']);
    });

    testWidgets('is disabled when the upstream is gone only in the preview', (
      WidgetTester tester,
    ) async {
      // `RefInfo.isGone` can only be true *after* a prune -- gone-ness before
      // that lives in the prune preview. Gating the box on `isGone` alone
      // therefore leaves it enabled during the whole window where the app
      // already knows the remote branch is gone, and ticking it dispatches a
      // push that cannot succeed. `isEffectivelyGone` is the single source
      // every other gone-aware surface reads.
      await _pump(
        tester,
        'feature/x',
        <RefInfo>[
          _branch('main', upstream: 'refs/remotes/origin/main', isHead: true),
          _branch('feature/x', upstream: 'refs/remotes/origin/feature/x'),
          _remote('origin', 'feature/x'),
        ],
        gonePendingByRemote: const <String, List<String>>{
          'origin': <String>['refs/remotes/origin/feature/x'],
        },
      );

      final CheckboxListTile tile = tester.widget<CheckboxListTile>(
        find.byType(CheckboxListTile),
      );
      expect(tile.onChanged, isNull);
      expect(tile.value, isFalse);
    });
  });
}
