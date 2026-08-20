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
import 'package:gbm_flutter/data/services/file_save_picker.dart';
import 'package:gbm_flutter/features/history_graph/history_page.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

import '../support/fake_repo_session.dart';
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

/// Answers the two native pickers with canned destinations instead of
/// showing a modal, so a widget test can assert *where* an action would have
/// written without a save panel appearing and hanging the run.
class _FakeFileSavePicker implements FileSavePicker {
  _FakeFileSavePicker({this.savePath, this.directoryPath});

  final String? savePath;
  final String? directoryPath;
  final List<String> suggestedNames = <String>[];

  @override
  Future<String?> saveFile({required String suggestedName}) async {
    suggestedNames.add(suggestedName);
    return savePath;
  }

  @override
  Future<String?> pickDirectory() async => directoryPath;
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

  testWidgets(
    '"Open file at this revision" exports the commit\'s version and hands '
    'that file to the OS',
    (tester) async {
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
      await tester.tap(find.text('Open file at this revision'));
      await tester.pumpAndSettle();

      final FakeCommand exported = pumped.controller.commandLog.singleWhere(
        (FakeCommand c) => c.name == 'exportFileAtRevision',
      );
      expect(exported.args['revision'], 'abc123');
      expect(exported.args['path'], 'lib/main.dart');
      final String destPath = exported.args['destPath']! as String;
      expect(
        destPath,
        endsWith('main-abc123.dart'),
        reason:
            'the extension has to survive or the OS has no file association '
            'to open, and the short oid keeps two revisions of one file from '
            'colliding in the temp directory',
      );

      // The launcher really got the exported file -- macOS `open <path>`.
      expect(starter.attempted, <String>['open']);
    },
  );

  testWidgets('a failed export surfaces the error and opens nothing', (
    tester,
  ) async {
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
    pumped.controller.failFileAtRevisionExport = true;
    pumped.router.go(
      RoutePaths.historyFor(Uri.encodeComponent(_identity.workDir)),
    );
    await tester.pumpAndSettle();

    await _openFileMenu(tester);
    await tester.tap(find.text('Open file at this revision'));
    await tester.pumpAndSettle();

    // Not silent: the user asked for a file and there is no file.
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      starter.attempted,
      isEmpty,
      reason: 'nothing was written, so there is nothing to hand the OS',
    );
  });

  testWidgets(
    '"Save this revision as…" exports to the path the native picker returned',
    (tester) async {
      final _FakeFileSavePicker picker = _FakeFileSavePicker(
        savePath: '/chosen/somewhere/main.dart',
      );
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _stateWithSelectedCommit(),
        overrides: <Override>[
          selectedCommitProvider(_identity).overrideWith((ref) => 'abc123'),
          fileSavePickerProvider.overrideWithValue(picker),
        ],
        historyBuilder: (context, state) => HistoryPage(identity: _identity),
      );
      pumped.router.go(
        RoutePaths.historyFor(Uri.encodeComponent(_identity.workDir)),
      );
      await tester.pumpAndSettle();

      await _openFileMenu(tester);
      await tester.tap(find.text('More actions'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save this revision as…'));
      await tester.pumpAndSettle();

      expect(picker.suggestedNames, <String>['main-abc123.dart']);
      final FakeCommand exported = pumped.controller.commandLog.singleWhere(
        (FakeCommand c) => c.name == 'exportFileAtRevision',
      );
      expect(exported.args['destPath'], '/chosen/somewhere/main.dart');
      expect(exported.args['revision'], 'abc123');
    },
  );

  testWidgets('cancelling the save picker exports nothing', (tester) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
      initialState: _stateWithSelectedCommit(),
      overrides: <Override>[
        selectedCommitProvider(_identity).overrideWith((ref) => 'abc123'),
        fileSavePickerProvider.overrideWithValue(_FakeFileSavePicker()),
      ],
      historyBuilder: (context, state) => HistoryPage(identity: _identity),
    );
    pumped.router.go(
      RoutePaths.historyFor(Uri.encodeComponent(_identity.workDir)),
    );
    await tester.pumpAndSettle();

    await _openFileMenu(tester);
    await tester.tap(find.text('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save this revision as…'));
    await tester.pumpAndSettle();

    expect(
      pumped.controller.commandLog.where(
        (FakeCommand c) => c.name == 'exportFileAtRevision',
      ),
      isEmpty,
    );
  });

  testWidgets('"Export as patch…" writes the whole commit to the chosen '
      'directory', (tester) async {
    final _FakeFileSavePicker picker = _FakeFileSavePicker(
      directoryPath: '/chosen/patches',
    );
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
      initialState: _stateWithSelectedCommit(),
      overrides: <Override>[
        selectedCommitProvider(_identity).overrideWith((ref) => 'abc123'),
        fileSavePickerProvider.overrideWithValue(picker),
      ],
      historyBuilder: (context, state) => HistoryPage(identity: _identity),
    );
    pumped.router.go(
      RoutePaths.historyFor(Uri.encodeComponent(_identity.workDir)),
    );
    await tester.pumpAndSettle();

    await _openFileMenu(tester);
    await tester.tap(find.text('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export as patch…'));
    await tester.pumpAndSettle();

    final FakeCommand exported = pumped.controller.commandLog.singleWhere(
      (FakeCommand c) => c.name == 'exportPatches',
    );
    // Commit-level, not per-file: gbm_patch_export is `git format-patch -1
    // <commit>`. Asserted rather than glossed over, because the menu was
    // opened on a single file's row and the difference is the kind of thing
    // a future reader would otherwise treat as a bug.
    expect(exported.args['commitHexes'], <String>['abc123']);
    expect(exported.args['outputDir'], '/chosen/patches');
  });

  testWidgets('"Restore and stage" opens the restore-file dialog for this '
      'commit and path', (tester) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
      initialState: _stateWithSelectedCommit(),
      overrides: <Override>[
        selectedCommitProvider(_identity).overrideWith((ref) => 'abc123'),
      ],
      topLevelRoutes: <RouteBase>[
        GoRoute(
          path: RoutePaths.restoreFileDialog,
          builder: (context, state) =>
              const Scaffold(body: Text('restore-file dialog')),
        ),
      ],
      historyBuilder: (context, state) => HistoryPage(identity: _identity),
    );
    pumped.router.go(
      RoutePaths.historyFor(Uri.encodeComponent(_identity.workDir)),
    );
    await tester.pumpAndSettle();

    await _openFileMenu(tester);
    await tester.tap(find.text('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Restore and stage'));
    await tester.pumpAndSettle();

    // The same dialog "Restore file to this state" opens, on purpose:
    // restore_file_dialog.dart offers both as two buttons because the
    // confirmation text is identical. This asserts by navigation because
    // that is how it dispatches -- a commandLog-only check could not see it
    // regress.
    expect(find.text('restore-file dialog'), findsOneWidget);
    expect(pumped.router.state.uri.queryParameters['oid'], 'abc123');
    expect(pumped.router.state.uri.queryParameters['path'], 'lib/main.dart');
  });
}
