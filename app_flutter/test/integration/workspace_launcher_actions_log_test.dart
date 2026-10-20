// Ruling R4 「每個動作都要有log」: every launcher call in the workspace goes
// through AppActionRunner into the repository's Log. These are the ones
// that used to call DesktopLauncher directly and log nothing: Working
// Copy's 05-F Open file / Show in file manager / Open terminal here, and
// Help → Documentation / Report an issue.
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/services/desktop_launcher.dart';
import 'package:gbm_flutter/features/working_copy/working_copy_view.dart';
import 'package:gbm_flutter/routing/route_paths.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/launch-repo');

class _Launcher extends DesktopLauncher {
  _Launcher() : super(operatingSystem: 'linux');

  final List<String> calls = <String>[];

  @override
  Future<bool> openFile(String path) async {
    calls.add('file $path');
    return true;
  }

  @override
  Future<bool> openInFileManager(String path) async {
    calls.add('manager $path');
    return true;
  }

  @override
  Future<bool> openTerminal(String path) async {
    calls.add('terminal $path');
    return true;
  }

  @override
  Future<bool> openUrl(String url) async {
    calls.add('url $url');
    return true;
  }
}

WorkingCopyEntry _entry(String path) => WorkingCopyEntry(
  path: path,
  oldPath: '',
  untracked: false,
  staged: false,
  indexStatus: FileChangeKind.modified,
  hasUnstagedChange: true,
  worktreeStatus: FileChangeKind.modified,
  unstagedAdded: 1,
  unstagedRemoved: 0,
  stagedAdded: 0,
  stagedRemoved: 0,
  conflict: ConflictKind.none,
  ancestorBlob: '',
  oursBlob: '',
  theirsBlob: '',
  similarity: 0,
  isSubmodule: false,
  isConflicted: false,
);

List<String> _appLog(PumpedWorkspace pumped) => pumped
    .controller
    .state
    .operationLog
    .whereType<AppLogEntry>()
    .map((AppLogEntry e) => e.message)
    .toList();

Future<(PumpedWorkspace, _Launcher)> _pump(WidgetTester tester) async {
  final _Launcher launcher = _Launcher();
  final PumpedWorkspace pumped = await pumpWorkspace(
    tester,
    identity: _identity,
    initialState: RepoSessionState(
      isOpen: true,
      workingCopyStatus: WorkingCopyStatus(
        entries: <WorkingCopyEntry>[_entry('lib/a.dart')],
      ),
    ),
    overrides: <Override>[desktopLauncherProvider.overrideWithValue(launcher)],
    workingCopyBuilder: (context, state) =>
        WorkingCopyView(identity: _identity),
  );
  pumped.router.go(
    RoutePaths.workingCopyFor(Uri.encodeComponent(_identity.workDir)),
  );
  await tester.pumpAndSettle();
  return (pumped, launcher);
}

Future<void> _fileMenu(WidgetTester tester, String item) async {
  await tester.tap(find.text('lib/a.dart'), buttons: kSecondaryMouseButton);
  await tester.pumpAndSettle();
  await tester.tap(find.text(item));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('05-F Open file is a Log line', (tester) async {
    final (PumpedWorkspace pumped, _Launcher launcher) = await _pump(tester);
    await _fileMenu(tester, 'Open file');

    final String path = '${_identity.workDir}/lib/a.dart';
    expect(launcher.calls, <String>['file $path']);
    expect(_appLog(pumped), <String>['Opened $path']);
  });

  testWidgets('05-F Show in file manager is a Log line', (tester) async {
    final (PumpedWorkspace pumped, _Launcher launcher) = await _pump(tester);
    await _fileMenu(tester, 'Show in file manager');

    final String path = '${_identity.workDir}/lib/a.dart';
    expect(launcher.calls, <String>['manager $path']);
    expect(_appLog(pumped), <String>['Showed $path in the file manager']);
  });

  testWidgets('05-F Open terminal here is a Log line', (tester) async {
    final (PumpedWorkspace pumped, _Launcher launcher) = await _pump(tester);
    await _fileMenu(tester, 'Open terminal here');

    expect(launcher.calls, <String>['terminal ${_identity.workDir}']);
    expect(_appLog(pumped), <String>[
      'Opened a terminal in ${_identity.workDir}',
    ]);
  });

  for (final (String item, String url) in <(String, String)>[
    ('Documentation', GbmUrls.documentation),
    ('Report an issue', GbmUrls.reportAnIssue),
  ]) {
    testWidgets('Help → $item is a Log line', (tester) async {
      final (PumpedWorkspace pumped, _Launcher launcher) = await _pump(tester);
      await tester.tap(find.text('Help'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();

      expect(launcher.calls, <String>['url $url']);
      expect(_appLog(pumped), <String>['Opened $url']);
    });
  }
}
