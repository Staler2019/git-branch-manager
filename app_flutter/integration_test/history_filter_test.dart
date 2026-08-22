// Device-tier E2E for gbm_history_set_filter.
//
// Why this file has to exist -- the same reason `multi_push_flow_test.dart`
// and `rename_branch_flow_test.dart` do, and it is worth repeating because
// nothing else in the suite can stand in for it. `gbm_history_set_filter`
// takes five parameters on the C side and five on the Dart typedef, and
// `lookupFunction` matches by **symbol name only, never by signature**. A
// mismatch compiles, `flutter analyze`s clean, passes every `test/**` suite
// (all on `FakeGbmBindings`) and every `tests/capi/**` suite (which calls the
// C++ directly, never through FFI) -- and then corrupts the stack the first
// time a user filters. This one carries a `Pointer<Pointer<Utf8>>` array plus
// its count, which is the parameter shape most likely to go wrong quietly.
//
// It drives `RepoSessionController.setHistoryFilter` on the real session
// rather than through the sidebar's filter box: the seam under test is the
// FFI call, and going through the UI would make a signature regression
// indistinguishable from a wiring regression. The wiring is covered at
// integration tier in `test/integration/`.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/app.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

/// A trunk with two merges in it, so the filtered walk is strictly smaller
/// than the unfiltered one and the bridge over the removed merges is
/// exercised rather than merely available.
void _buildHistoryWithMerges(String repoPath) {
  for (final String side in <String>['side-one', 'side-two']) {
    runGit(repoPath, <String>['checkout', '--quiet', '-b', side]);
    File('$repoPath/$side.txt').writeAsStringSync('x\n');
    runGit(repoPath, <String>['add', '$side.txt']);
    runGit(repoPath, <String>['commit', '--quiet', '-m', 'on $side']);

    runGit(repoPath, <String>['checkout', '--quiet', 'main']);
    File('$repoPath/README.md').writeAsStringSync('before $side\n');
    runGit(repoPath, <String>['commit', '--quiet', '-am', 'main before $side']);
    runGit(repoPath, <String>[
      'merge',
      '--quiet',
      '--no-ff',
      '-m',
      'merge $side',
      side,
    ]);
  }
}

int _gitRowCount(String repoPath, List<String> revListArgs) {
  final String out = runGit(repoPath, <String>[
    'rev-list',
    ...revListArgs,
  ]).stdout.toString();
  return out
      .split('\n')
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .length;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repoPath;

  setUp(() {
    repoPath = createTempGitRepo();
    _buildHistoryWithMerges(repoPath);
  });

  tearDown(() => deleteTempGitRepo(repoPath));

  testWidgets('filtering to one branch narrows the walk across the FFI seam', (
    tester,
  ) async {
    await pumpRealAppOn(tester, repoPath);

    final RepoIdentity identity = RepoIdentity.forWorkDir(repoPath);
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(GbmApp)),
      listen: false,
    );
    final RepoSessionController controller = container.read(
      repoSessionProvider(identity).notifier,
    );

    await tester.pumpAndSettle(const Duration(seconds: 5));
    final int unfiltered = container
        .read(repoSessionProvider(identity))
        .graph
        .rows
        .length;
    expect(unfiltered, _gitRowCount(repoPath, <String>['--all']));

    // The shape the app actually sends: --no-merges alone. --first-parent is
    // deliberately absent -- it would drop every commit that arrived through a
    // merge, which is the defect this test's expected count now pins.
    controller.setHistoryFilter(
      includeRefs: const <String>['refs/heads/main'],
      noMerges: true,
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));

    final int filtered = container
        .read(repoSessionProvider(identity))
        .graph
        .rows
        .length;
    expect(
      filtered,
      _gitRowCount(repoPath, <String>['--no-merges', 'refs/heads/main']),
      reason:
          'a signature mismatch across the FFI seam would not surface as a '
          'wrong row count -- it would crash or read garbage -- so reaching '
          'this assertion at all is most of what this test proves',
    );
    expect(filtered, lessThan(unfiltered));

    // The whole point of the mode: one lane, and every row still joined to
    // the next despite the merges git was told to skip.
    expect(container.read(repoSessionProvider(identity)).graph.laneCount, 1);
    for (int row = 0; row + 1 < filtered; row++) {
      expect(
        container
            .read(repoSessionProvider(identity))
            .graph
            .rows[row]
            .isBoundary,
        isFalse,
        reason: 'row $row draws a stub instead of reaching its parent',
      );
    }
  });

  testWidgets('an empty ref list restores the full walk', (tester) async {
    // Count 0 passes a null array, which is a different marshalling path
    // from the populated one and therefore its own signature risk.
    await pumpRealAppOn(tester, repoPath);

    final RepoIdentity identity = RepoIdentity.forWorkDir(repoPath);
    final ProviderContainer container = ProviderScope.containerOf(
      tester.element(find.byType(GbmApp)),
      listen: false,
    );
    final RepoSessionController controller = container.read(
      repoSessionProvider(identity).notifier,
    );

    await tester.pumpAndSettle(const Duration(seconds: 5));
    final int unfiltered = container
        .read(repoSessionProvider(identity))
        .graph
        .rows
        .length;

    controller.setHistoryFilter(
      includeRefs: const <String>['refs/heads/main'],
      noMerges: true,
    );
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(
      container.read(repoSessionProvider(identity)).graph.rows.length,
      lessThan(unfiltered),
    );

    controller.setHistoryFilter(includeRefs: const <String>[]);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(
      container.read(repoSessionProvider(identity)).graph.rows.length,
      unfiltered,
    );
  });
}
