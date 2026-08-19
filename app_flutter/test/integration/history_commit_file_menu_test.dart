// Integration coverage for 05-K's two newly-wired items (#53). The widget
// tier (changed_files_panel_test.dart) proves ChangedFilesPanelCore renders
// them and calls back with the path, but it feeds the callbacks in directly
// -- it cannot prove that ChangedFilesPanel, the container half, binds them
// to anything real. That seam is exactly where these two could silently
// no-op: "Compare with working copy" dispatches by *navigation* rather than
// by a session command, and "Open terminal here" dispatches to an injected
// service, so neither shows up in FakeRepoSessionController's commandLog at
// all.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/changed_file.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/compare_tabs_repository.dart';
import 'package:gbm_flutter/data/repositories/history_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/services/desktop_launcher.dart';
import 'package:gbm_flutter/features/history_graph/history_page.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/commit-file-menu-repo',
  gitDir: '/test/commit-file-menu-repo/.git',
);

const Signature _signature = Signature(
  name: 'Test Author',
  email: 'author@example.com',
  when: 0,
  tzOffsetMinutes: 0,
);

ChangedFile _file(String path) => ChangedFile(
  path: path,
  oldPath: path,
  kind: FileChangeKind.modified,
  oldMode: '100644',
  newMode: '100644',
  oldBlob: 'aaa',
  newBlob: 'bbb',
  similarity: 0,
);

/// Records launch attempts instead of spawning anything, mirroring
/// `desktop_launcher_test.dart`'s own starter.
class _RecordingStarter {
  final List<String> attempted = <String>[];
  final List<String?> workingDirs = <String?>[];

  Future<bool> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    attempted.add(executable);
    workingDirs.add(workingDirectory);
    return true;
  }
}

RepoSessionState _stateWithSelectedCommit() => RepoSessionState(
  isOpen: true,
  commitFiles: <ChangedFile>[_file('lib/main.dart')],
  // Seeded so CommitDetailPanel resolves immediately rather than leaving an
  // indeterminate spinner that pumpAndSettle would time out on.
  commitMetaCache: const <String, CommitMeta>{
    'abc123': CommitMeta(
      oid: 'abc123',
      tree: 'tree123',
      parents: <String>[],
      author: _signature,
      committer: _signature,
      subject: 'Test commit',
      body: '',
      signedCommit: false,
    ),
  },
);

Future<void> _openFileMenu(WidgetTester tester) async {
  await tester.tap(find.text('lib/main.dart'), buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    '"Compare with working copy" opens a Compare tab for the selected commit '
    'and navigates to it',
    (tester) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _stateWithSelectedCommit(),
        overrides: <Override>[
          selectedCommitProvider(_identity).overrideWith((ref) => 'abc123'),
        ],
        // A Compare tab is a ShellRoute child, so it belongs in extraRoutes
        // (not topLevelRoutes) -- and it has to exist at all, or the
        // navigation this test is checking resolves to nothing and
        // `router.state` throws.
        extraRoutes: <RouteBase>[
          GoRoute(
            path: RoutePaths.compare,
            builder: (context, state) => const Scaffold(body: Text('compare')),
          ),
        ],
        historyBuilder: (context, state) => HistoryPage(identity: _identity),
      );
      final String repoId = Uri.encodeComponent(_identity.workDir);
      pumped.router.go(RoutePaths.historyFor(repoId));
      await tester.pumpAndSettle();

      await _openFileMenu(tester);
      await tester.tap(find.text('Compare with working copy'));
      await tester.pumpAndSettle();

      // A tab really exists, with the commit on the left and Working Copy
      // (a null `right`) on the right...
      final List<CompareTabSpec> tabs = pumped.container.read(
        compareTabsProvider(_identity),
      );
      expect(tabs, hasLength(1));
      expect(tabs.single.left, 'abc123');
      expect(
        tabs.single.rightIsWorkingCopy,
        isTrue,
        reason: 'a null right is what CompareTabSpec means by Working Copy',
      );

      // ...and the router actually went there. `context.go`, not `push`:
      // Compare is a ShellRoute child, so pushing would stack it over
      // History rather than switching to it.
      expect(
        pumped.router.state.uri.toString(),
        RoutePaths.compareFor(repoId, tabs.single.id),
      );
    },
  );

  testWidgets('"Open terminal here" reaches the real DesktopLauncher with '
      'the repository work dir', (tester) async {
    final _RecordingStarter starter = _RecordingStarter();
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
      initialState: _stateWithSelectedCommit(),
      overrides: <Override>[
        selectedCommitProvider(_identity).overrideWith((ref) => 'abc123'),
        desktopLauncherProvider.overrideWithValue(
          DesktopLauncher(start: starter.call, operatingSystem: 'macos'),
        ),
      ],
      historyBuilder: (context, state) => HistoryPage(identity: _identity),
    );
    pumped.router.go(
      RoutePaths.historyFor(Uri.encodeComponent(_identity.workDir)),
    );
    await tester.pumpAndSettle();

    await _openFileMenu(tester);
    await tester.tap(find.text('Open terminal here'));
    await tester.pumpAndSettle();

    expect(starter.attempted, <String>['open']);
    expect(
      starter.workingDirs.single,
      _identity.workDir,
      reason:
          'a historical commit\'s file has no directory of its own, so '
          'this opens the repository work dir like 05-A and 05-F do',
    );
  });
}
