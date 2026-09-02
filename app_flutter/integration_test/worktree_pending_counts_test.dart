// Device-tier E2E for `gbm_worktree_request_pending_counts`, the C entry
// point this round added, and for the four-state count it carries back.
//
// Why this file has to exist, and why no other tier can replace it:
// `lookupFunction` matches by symbol **name only, never by signature**
// ([TEST-ffi-matches-symbol-only]), so a drift between the C prototype and
// the Dart typedef compiles, analyzes and unit-tests clean, then corrupts
// the stack the first time a real user opens this panel. `test/**` runs on
// `FakeGbmBindings` and `tests/capi/WorktreeApiTest.cpp` calls the C++ side
// directly -- neither crosses the boundary. Same trap as
// `commit_file_counts_test.dart`'s and `rename_branch_flow_test.dart`'s.
//
// It also happens to be the only tier that can show the count is *real*:
// the number comes from a `git status --porcelain=v2` run inside another
// worktree's directory, which is a fact about git's behaviour that a fake
// has no way to be wrong about.
//
// Run it as `flutter test integration_test/worktree_pending_counts_test.dart
// -d macos`, one file at a time ([TEST-device-runs-one-file]), after
// `scripts/build_capi.sh` -- a stale dylib loads happily and the symptom is
// a count that simply never arrives ([TEST-stale-dylib-is-silent]).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/features/panels/panel_widgets.dart';
import 'package:gbm_flutter/features/status_bar/status_bar.dart';
import 'package:gbm_flutter/features/workspace/widgets/workspace_action_shortcuts.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

/// Three, and each of a different kind, so the number cannot be produced by
/// a code path that only sees one of them: one tracked file modified in the
/// work tree, one modified *and staged*, and one untracked. A count that
/// read only the index, or only the work tree, would answer 1 or 2 here.
///
/// Three is also not 0, 1 or 2, which is what every other number on this
/// panel could plausibly be.
const int _pendingInLinked = 3;

/// The linked worktree's directory name, which is also the list row's title.
const String _linkedName = 'wt-linked';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repo;
  late String linked;

  setUp(() {
    repo = createTempGitRepo(prefix: 'gbm_e2e_wtcount_');

    // A sibling of the repository rather than a child: git refuses to add a
    // worktree inside the repository's own work tree in some layouts, and a
    // nested one would also show up in the parent's own `git status`, which
    // would make "this count came from inside the linked worktree" an
    // untestable claim.
    linked = '$repo-linked/$_linkedName';
    runGit(repo, <String>['worktree', 'add', '-b', 'feature/linked', linked]);

    File('$linked/README.md').writeAsStringSync('# changed in the worktree\n');
    File('$linked/staged.txt').writeAsStringSync('staged\n');
    runGit(linked, <String>['add', 'staged.txt']);
    File('$linked/untracked.txt').writeAsStringSync('untracked\n');
  });

  tearDown(() {
    deleteTempGitRepo(repo);
    final Directory parent = Directory('$repo-linked');
    if (parent.existsSync()) parent.deleteSync(recursive: true);
  });

  testWidgets('the worktrees panel reports a linked worktree\'s real count', (
    tester,
  ) async {
    await pumpRealAppOn(tester, repo);

    // Dispatched as a `GbmActionIntent` rather than through the menu bar,
    // because on macOS the menu is a real `PlatformMenuBar` that no widget
    // test can tap. This is not a bypass: it is dispatch path 1 of
    // [ACT-intent-layer], reaching the very same `actionHandlers` map the
    // menu item reads, so a handler wired only to `MenuBarRow`'s named
    // params would fail here exactly as it should.
    //
    // The context has to come from *below* `WorkspaceActionShortcuts`, which
    // `WorkspaceScreen` builds as its own child -- `Actions.invoke` searches
    // upwards, so invoking from the `WorkspaceScreen` element finds no
    // handler and throws「Unhandled GbmActionIntent」.
    Actions.invoke(
      tester.element(find.byType(StatusBar)),
      const GbmActionIntent(GbmActionId.toolsWorktrees),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(_linkedName),
      findsOneWidget,
      reason: 'Tools -> Worktrees… must open the panel with both worktrees',
    );

    await tester.tap(find.text(_linkedName));
    await tester.pumpAndSettle();

    // Pumped in fixed steps rather than `pumpAndSettle`, because the count
    // arrives from a real `git status` on the background read pool and the
    // panel keeps a spinner up while it is in flight
    // ([TEST-no-pumpandsettle-with-spinner]).
    final Finder status = find.descendant(
      of: find.byType(PanelDetailField),
      matching: find.textContaining('個未提交變更'),
    );
    for (int i = 0; i < 40 && status.evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(
      status,
      findsOneWidget,
      reason:
          'the count never arrived: either the FFI call did not reach the '
          'core, or the reply did not reach the panel',
    );
    expect(
      find.textContaining('$_pendingInLinked 個未提交變更'),
      findsOneWidget,
      reason:
          'the count must come from a status run inside the linked worktree, '
          'covering the work tree, the index and untracked files alike',
    );
    // Never the unmeasured wording once the request has been answered --
    // this is the assertion that fails if the reply decodes to the wrong
    // state, which is the shape an FFI payload mismatch takes when it does
    // not corrupt the stack outright.
    expect(find.textContaining('未量測'), findsNothing);
    expect(find.textContaining('量測失敗'), findsNothing);
  });
}
