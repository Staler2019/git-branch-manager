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
  List<RefInfo> refs,
) async {
  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    RepoSessionState(refs: _snapshot(refs)),
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
  group('deleteBranchRemoteName', () {
    test('recovers the remote from a full upstream ref, never by splitting '
        'on the first slash (#74)', () {
      expect(
        deleteBranchRemoteName(
          _branch('feature/x', upstream: 'refs/remotes/upstream/feature/x'),
        ),
        'upstream',
      );
    });

    test('a branch with no upstream has no remote', () {
      expect(deleteBranchRemoteName(_branch('solo')), '');
    });

    test('an in-sync branch still has a remote', () {
      // hasTrackingInfo is `%(upstream:track)`, which git leaves empty when
      // a branch is exactly in sync. Asking it "does this track a remote?"
      // hides the checkbox on the commonest branch there is.
      expect(
        deleteBranchRemoteName(
          _branch('main', upstream: 'refs/remotes/origin/main'),
        ),
        'origin',
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

    testWidgets('is not offered at all for a branch with no upstream', (
      WidgetTester tester,
    ) async {
      await _pump(tester, 'solo', <RefInfo>[
        _branch('main', upstream: 'refs/remotes/origin/main', isHead: true),
        _branch('solo'),
      ]);

      expect(find.byType(CheckboxListTile), findsNothing);
    });
  });
}
