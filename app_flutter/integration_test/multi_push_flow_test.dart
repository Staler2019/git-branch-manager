// Device-tier E2E for the multi-branch push added alongside spec P13's
// branch multi-select.
//
// Why this file has to exist -- the same reason
// `rename_branch_flow_test.dart` does, and the reason is worth repeating
// because nothing else in the suite can stand in for it: `gbm_push` grew
// two parameters (`branches`, `branchCount`) on the C side and the matching
// `dart:ffi` typedef grew them on the Dart side. `lookupFunction` matches by
// **symbol name only, never by signature**, so if those two halves ever
// disagree the mismatch compiles, `flutter analyze`s, and passes every
// `test/**` suite (all of which run on `FakeGbmBindings`) and every
// `tests/capi/**` suite (which calls the C++ directly, never through FFI) --
// and then corrupts the stack the first time a real user pushes.
//
// This drives `RepoSessionController.pushChanges` on the real session rather
// than through the sidebar's multi-select menu: the seam under test is the
// FFI call itself, and going through the UI would make a signature
// regression indistinguishable from a menu-wiring regression. The menu's own
// wiring is covered at widget/integration tier in `test/`.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/app.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

/// Creates a bare `origin` and pushes only `main` to it, so the two feature
/// branches below start out unpublished -- otherwise a no-op push would
/// satisfy the assertions without ever exercising the refspec list.
String _setUpBareOrigin(String repoPath) {
  final Directory bare = Directory.systemTemp.createTempSync('gbm_e2e_origin_');
  final String originPath = bare.resolveSymbolicLinksSync();
  Process.runSync('git', <String>[
    'init',
    '--bare',
    '--initial-branch=main',
    originPath,
  ]);
  runGit(repoPath, <String>['remote', 'add', 'origin', originPath]);
  runGit(repoPath, <String>['push', '--set-upstream', 'origin', 'main']);
  return originPath;
}

List<String> _remoteBranches(String originPath) {
  final String out = runGit(originPath, <String>[
    'for-each-ref',
    '--format=%(refname:short)',
    'refs/heads',
  ]).stdout.toString();
  return out
      .split('\n')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList()
    ..sort();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repoPath;
  late String originPath;

  setUp(() {
    repoPath = createTempGitRepo();
    originPath = _setUpBareOrigin(repoPath);
    runGit(repoPath, <String>['branch', 'lane-allocator']);
    runGit(repoPath, <String>['branch', 'ref-chips']);
  });

  tearDown(() {
    deleteTempGitRepo(repoPath);
    deleteTempGitRepo(originPath);
  });

  testWidgets('pushing several branches sends one push that lands them all', (
    tester,
  ) async {
    expect(_remoteBranches(originPath), <String>['main']);

    await pumpRealAppOn(tester, repoPath);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(GbmApp)),
      listen: false,
    );
    final RepoSessionController controller = container.read(
      repoSessionProvider(RepoIdentity.forWorkDir(repoPath)).notifier,
    );

    controller.pushChanges(
      remoteName: 'origin',
      branches: const <String>['lane-allocator', 'ref-chips'],
      setUpstream: true,
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(
      _remoteBranches(originPath),
      <String>['lane-allocator', 'main', 'ref-chips'],
      reason:
          'both selected branches must land. A signature mismatch across the '
          'FFI seam would not surface as a wrong branch list -- it would '
          'crash or push garbage -- so reaching this assertion at all is '
          'most of what this test proves.',
    );
  });

  testWidgets('pushing with no branches still pushes the current one', (
    tester,
  ) async {
    // branchCount 0 is the pre-existing "no refspec, let git decide"
    // behaviour, which the multi-branch change had to preserve. Asserted
    // here because it is the argument shape every existing push button in
    // the app still uses.
    File('$repoPath/README.md').writeAsStringSync('# changed\n');
    runGit(repoPath, <String>['commit', '-am', 'second']);
    final String head = runGit(repoPath, <String>[
      'rev-parse',
      'HEAD',
    ]).stdout.toString().trim();

    await pumpRealAppOn(tester, repoPath);

    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(GbmApp)),
      listen: false,
    );
    container
        .read(repoSessionProvider(RepoIdentity.forWorkDir(repoPath)).notifier)
        .pushChanges(remoteName: 'origin');
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(
      runGit(originPath, <String>[
        'rev-parse',
        'refs/heads/main',
      ]).stdout.toString().trim(),
      head,
    );
  });
}
