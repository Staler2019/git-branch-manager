// Device-tier E2E for the Tier 0c rename flow (#45).
//
// Why this file has to exist: the rename work changed the `dart:ffi`
// typedef and the exported C signature of `gbm_branch_rename` in lockstep,
// and *nothing else in the suite crosses that seam*. `test/features/**` and
// `test/integration/**` both run on `FakeGbmBindings`; `tests/capi/
// BranchApiTest.cpp` calls the C++ side directly. `lookupFunction` matches
// by symbol name, never by signature, so an arity or type mismatch between
// the two halves compiles, analyzes, and unit-tests clean, then corrupts
// the stack the first time a real user renames a branch.
//
// The two spec P13 remote options are also asserted here against a real
// bare origin rather than a mock, because their whole difference is what
// git's own refs look like afterwards -- `RefInfo.upstream` and the remote's
// branch list -- which a fake controller has no way to model.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

/// The branch these tests rename. Deliberately **not** `main`: a bare
/// repo's HEAD points at its default branch, and git refuses
/// `push --delete` on it ("By default, deleting the current branch is
/// denied"). That refusal is correct git behaviour, not an app defect --
/// the C++ side reports it honestly as "renamed locally and pushed, but
/// could not delete" and `BranchApiTest`'s
/// `RenameBranchReportsTheLocalRenameWhenTheRemoteStepFails` covers it.
/// Renaming a feature branch is the case spec P13 actually describes.
///
/// Flat, with no `/`: `branch_tree_builder.dart` groups `feature/x` under a
/// collapsible `feature` folder, so the sidebar row's text would be `x`,
/// not the full name -- a dependency on tree rendering this test has no
/// business carrying. Spec P13's own example is `feature/lane-allocator`;
/// the slash is exercised by the branch-tree tests instead.
const String _branch = 'lane-allocator';

/// Creates a bare repo next to [repoPath] and wires it up as `origin`, with
/// [_branch] pushed and tracking, mirroring `tests/capi/RemoteApiTest.cpp`'s
/// fixture. Returns the bare repo's path.
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
  runGit(repoPath, <String>['checkout', '-b', _branch]);
  runGit(repoPath, <String>['push', '--set-upstream', 'origin', _branch]);
  return originPath;
}

/// `git branch -vv`'s tracking suffix for [branch], or `''` when it has no
/// upstream. Reading porcelain here rather than the app's own state on
/// purpose: the point is what git believes, not what the UI cached.
String _upstreamOf(String repoPath, String branch) {
  final String out = runGit(repoPath, <String>[
    'for-each-ref',
    '--format=%(upstream:short)',
    'refs/heads/$branch',
  ]).stdout.toString();
  return out.trim();
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
      .toList();
}

/// Opens the rename dialog through the sidebar's own 05-B entry, which is
/// the path a user actually takes. Right-click is not reachable via
/// `tester.tap`, hence the explicit gesture.
Future<void> _openRenameDialog(WidgetTester tester, String branch) async {
  final TestGesture gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  addTearDown(gesture.removePointer);
  await gesture.down(tester.getCenter(find.text(branch).first));
  await gesture.up();
  await tester.pumpAndSettle();

  await tester.tap(find.text('Rename…'));
  await tester.pumpAndSettle(const Duration(seconds: 1));
}

Future<void> _submitRename(WidgetTester tester, String newName) async {
  await tester.enterText(find.byType(TextField).last, newName);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Rename'));
  // The dialog dispatches and pops immediately (spec page 10: progress
  // belongs to the background-task row), so this settle is waiting on the
  // operation itself, not on the dialog.
  await tester.pumpAndSettle(const Duration(seconds: 3));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repoPath;
  late String originPath;

  setUp(() {
    repoPath = createTempGitRepo();
    originPath = _setUpBareOrigin(repoPath);
  });

  tearDown(() {
    deleteTempGitRepo(repoPath);
    deleteTempGitRepo(originPath);
  });

  testWidgets('"一併更名遠端分支" pushes the new name and deletes the old one', (
    tester,
  ) async {
    expect(_remoteBranches(originPath), <String>[_branch, 'main']);
    expect(_upstreamOf(repoPath, _branch), 'origin/$_branch');

    await pumpRealAppOn(tester, repoPath);
    await _openRenameDialog(tester, _branch);
    expect(
      find.text('Rename Branch'),
      findsOneWidget,
      reason: 'the dialog is open (its GbmDialogShell title)',
    );

    // The remote-rename option is the default when the branch has an
    // upstream, so this submits without touching the radio group.
    await _submitRename(tester, 'lane-allocator-v2');

    expect(
      runGit(repoPath, <String>[
        'rev-parse',
        '--abbrev-ref',
        'HEAD',
      ]).stdout.toString().trim(),
      'lane-allocator-v2',
      reason: 'renaming the checked-out branch moves HEAD with it (spec P13)',
    );
    expect(
      _remoteBranches(originPath),
      <String>['lane-allocator-v2', 'main'],
      reason:
          'push new name then delete old -- in that order, so a failure '
          'partway never leaves the branch unpublished',
    );
    expect(
      _upstreamOf(repoPath, 'lane-allocator-v2'),
      'origin/lane-allocator-v2',
      reason: 'push --set-upstream must repoint tracking at the new ref',
    );
  });

  testWidgets('"只改本地" clears the upstream and leaves the remote alone', (
    tester,
  ) async {
    await pumpRealAppOn(tester, repoPath);
    await _openRenameDialog(tester, _branch);

    // Quoted verbatim from the P13-A mock; G1g made this the app's actual
    // UI copy (docs/rules/drift-open.md's ledger evidence).
    await tester.tap(find.textContaining('只改本地，保留遠端舊分支'));
    await tester.pumpAndSettle();
    await _submitRename(tester, 'lane-allocator-v2');

    expect(
      _remoteBranches(originPath),
      <String>[_branch, 'main'],
      reason: 'the local-only option must not touch origin at all',
    );
    expect(
      _upstreamOf(repoPath, 'lane-allocator-v2'),
      '',
      reason:
          'git branch -m *preserves* tracking config, so the local-only '
          'path needs an explicit --unset-upstream -- verified by '
          'experiment, not assumed. Without it this assertion reads '
          '"origin/$_branch", pointing the renamed branch at a ref it no '
          'longer corresponds to.',
    );
  });
}
