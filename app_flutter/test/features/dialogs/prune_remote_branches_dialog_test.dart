// Regression coverage for a fixed crash: `_selectedRemote` is assigned
// inside a `Future.microtask` in `initState`, so it is null on the first
// build regardless of remote count. The dialog's preview guard now reads
// `preview != null && preview.remote == _selectedRemote` for exactly this
// reason -- see the guard's own comment in the dialog for the fix.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/remote_info.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/prune_remote_branches/prune_remote_branches_dialog.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

const RepoIdentity _identity = RepoIdentity(
  workDir: '/tmp/repo',
  gitDir: '/tmp/repo/.git',
);

Future<(FakeRepoSessionController, GoRouter)> _pump(
  WidgetTester tester,
  RepoSessionState state,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final FakeRepoSessionController controller = FakeRepoSessionController(
    _identity,
    state,
  );
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/dialog',
        builder: (context, state) =>
            const PruneRemoteBranchesDialogContent(identity: _identity),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        repoSessionProvider(_identity).overrideWith((ref) => controller),
      ],
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.push('/dialog');
  await tester.pumpAndSettle();
  return (controller, router);
}

RefInfo _local(String shortName) => RefInfo(
  fullName: 'refs/heads/$shortName',
  shortName: shortName,
  kind: RefKind.localBranch,
  target: 'a' * 40,
  upstream: '',
  ahead: 0,
  behind: 0,
  // Never derived from `upstream`: %(upstream:track) is empty for a branch
  // exactly in sync, so a fixture computing one from the other cannot
  // falsify code making the same derivation.
  hasTrackingInfo: false,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

RefInfo _remote(String fullName) => RefInfo(
  fullName: fullName,
  shortName: fullName.substring('refs/remotes/'.length),
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
  head: RefSnapshot.empty.head,
  refs: refs,
  refCountGuardTripped: false,
  totalRefCount: refs.length,
);

GbmEvent _fetchFinished() => GbmEvent(
  GbmEventType.workingCopyOperationFinished,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'succeeded': true,
      'error': null,
      'choices': <dynamic>[],
      'summary': 'Fetch',
      'kind': 'fetch',
    }),
  ),
);

GbmEvent _previewReady(String remote, List<String> shortRefs) => GbmEvent(
  GbmEventType.remotePrunePreviewReady,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'remote': remote,
      'refs': <dynamic>[
        for (final String ref in shortRefs) <String, dynamic>{'ref': ref},
      ],
    }),
  ),
);

List<FakeCommand> _prunes(FakeRepoSessionController c) =>
    c.commandLog.where((FakeCommand cmd) => cmd.name == 'pruneRemote').toList();

void main() {
  testWidgets(
    'a repository with no remotes gets the empty state, not a crash',
    (tester) async {
      await _pump(tester, const RepoSessionState(isOpen: true));

      expect(tester.takeException(), isNull);
      // The title, deliberately, and not the empty-state wording: the claim
      // here is 「it renders at all」, and pinning it to copy would make this
      // test move every time the copy does.
      expect(find.text('Prune Remote Branches'), findsOneWidget);
    },
  );

  testWidgets('one remote and no preview yet still renders', (tester) async {
    // Covers the case a remotes-empty fixture cannot: `_selectedRemote` is
    // still null on the dialog's first build even when a remote exists,
    // because it is only assigned inside `initState`'s `Future.microtask`.
    await _pump(
      tester,
      const RepoSessionState(
        isOpen: true,
        remotes: <RemoteInfo>[
          RemoteInfo(name: 'origin', fetchUrl: 'u', pushUrl: 'u'),
        ],
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Prune Remote Branches'), findsOneWidget);
  });

  testWidgets('對話框開著時不會把它正在列的 ref 掃掉，關掉之後才掃', (tester) async {
    // 這一顆釘的是對話框真的有宣告自己 -- controller 分不出
    // requestRemotePrunePreview 是誰呼叫的，所以閘門完全靠這兩個生命週期呼叫。
    final (FakeRepoSessionController c, GoRouter router) = await _pump(
      tester,
      RepoSessionState(
        isOpen: true,
        remotes: const <RemoteInfo>[
          RemoteInfo(name: 'origin', fetchUrl: 'u', pushUrl: 'u'),
        ],
        refs: _snapshot(<RefInfo>[
          _local('mine'),
          _remote('refs/remotes/origin/mine'),
        ]),
      ),
    );

    // fetch 的 preview 說 origin/mine 已經 gone，但本機 mine 還占用它，所以自動
    // prune 放過它 -- 延後，不是終局。
    c.debugRecordFetch(remoteName: 'origin');
    c.debugHandleEvent(_fetchFinished());
    c.debugHandleEvent(_previewReady('origin', <String>['origin/mine']));
    await tester.pumpAndSettle();

    // 本機 mine 在別處被刪掉（終端機、另一個視窗），refs 更新流進來。
    c.publishRefs(_snapshot(<RefInfo>[_remote('refs/remotes/origin/mine')]));
    await tester.pumpAndSettle();
    expect(_prunes(c).length, 0, reason: '對話框正在列它');

    router.pop();
    await tester.pumpAndSettle();

    expect(_prunes(c).length, 1);
  });
}
