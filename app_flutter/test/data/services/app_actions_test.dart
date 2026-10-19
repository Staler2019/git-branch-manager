// The factories own each action's name and Log wording (ruling R4); the
// failure wording is the one the error lines already used.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/app_action.dart';
import 'package:gbm_flutter/data/models/app_action_outcome.dart';
import 'package:gbm_flutter/data/models/external_app_entry.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/services/app_action_runner.dart';
import 'package:gbm_flutter/data/services/app_actions.dart';
import 'package:gbm_flutter/data/services/desktop_launcher.dart';

class _Launcher extends DesktopLauncher {
  _Launcher({
    this.terminalOk = true,
    this.appResult = const ExternalAppStarted(),
  }) : super(operatingSystem: 'macos');

  final bool terminalOk;
  final ExternalAppLaunchResult appResult;
  final List<String> calls = <String>[];

  @override
  Future<bool> openTerminal(String path) async {
    calls.add('terminal $path');
    return terminalOk;
  }

  @override
  Future<ExternalAppLaunchResult> openExternalApp(
    ExternalAppEntry app,
    String path,
  ) async {
    calls.add('${app.label} $path');
    return appResult;
  }
}

final ExternalAppEntry _rider = (ExternalAppEntry.create(
  label: 'Rider',
  command: 'rider .',
  newId: () => 'r',
) as ExternalAppEntryAccepted).entry;

Future<(AppActionOutcome<void>, AppLogEntry)> _run(
  AppAction<void> action,
) async {
  final List<AppLogEntry> lines = <AppLogEntry>[];
  final AppActionOutcome<void> outcome = await const AppActionRunner().run(
    action,
    sink: lines.add,
  );
  expect(lines.length, 1);
  return (outcome, lines.single);
}

void main() {
  group('openTerminalAction', () {
    test('a started terminal is one info line naming the directory', () async {
      final _Launcher launcher = _Launcher();
      final AppAction<void> action = openTerminalAction(launcher, '/src/wt');
      expect(action.name, 'openTerminal');
      expect(action.cancellable, isFalse);
      final (AppActionOutcome<void> outcome, AppLogEntry line) = await _run(
        action,
      );
      expect(launcher.calls, <String>['terminal /src/wt']);
      expect(outcome, isA<AppActionSucceeded<void>>());
      expect(line.level, OperationLogLevel.info);
      expect(line.message, 'Opened a terminal in /src/wt');
    });

    test('no terminal is the error line it always was', () async {
      final (AppActionOutcome<void> outcome, AppLogEntry line) = await _run(
        openTerminalAction(_Launcher(terminalOk: false), '/src/wt'),
      );
      expect(outcome, isA<AppActionFailed<void>>());
      expect(line.level, OperationLogLevel.error);
      expect(line.message, 'No terminal emulator was found');
    });
  });

  group('openExternalAppAction', () {
    test(
      'a started app is one info line naming the app and directory',
      () async {
        final _Launcher launcher = _Launcher();
        final AppAction<void> action = openExternalAppAction(
          launcher,
          _rider,
          '/src/wt',
        );
        expect(action.name, 'openExternalApp');
        // Cancelling would only stop the 5 s wait for an early failure, not
        // the app: reporting that as Cancelled would be the lie F8 forbids.
        expect(action.cancellable, isFalse);
        final (AppActionOutcome<void> outcome, AppLogEntry line) = await _run(
          action,
        );
        expect(launcher.calls, <String>['Rider /src/wt']);
        expect(outcome, isA<AppActionSucceeded<void>>());
        expect(line.level, OperationLogLevel.info);
        expect(line.message, 'Opened /src/wt with "Rider"');
      },
    );

    test('a failed launch names the app and quotes the detail', () async {
      final (AppActionOutcome<void> outcome, AppLogEntry line) = await _run(
        openExternalAppAction(
          _Launcher(
            appResult: const ExternalAppLaunchFailed(
              'zsh:1: command not found: rider',
            ),
          ),
          _rider,
          '/src/wt',
        ),
      );
      expect(outcome, isA<AppActionFailed<void>>());
      expect(line.level, OperationLogLevel.error);
      expect(
        line.message,
        'Could not run "Rider": zsh:1: command not found: rider',
      );
    });
  });

  group('exportFileAtRevisionAction', () {
    test('a written file is one info line naming both paths', () async {
      int calls = 0;
      final AppAction<void> action = exportFileAtRevisionAction(
        path: 'lib/main.dart',
        destPath: '/tmp/main-abc.dart',
        export: () async {
          calls++;
          return null;
        },
      );
      expect(action.name, 'exportFileAtRevision');
      expect(action.cancellable, isFalse);
      final (AppActionOutcome<void> outcome, AppLogEntry line) = await _run(
        action,
      );
      expect(calls, 1);
      expect(outcome, isA<AppActionSucceeded<void>>());
      expect(line.level, OperationLogLevel.info);
      expect(line.message, 'Exported lib/main.dart to /tmp/main-abc.dart');
    });

    test('a failed export is the error line it always was', () async {
      final (AppActionOutcome<void> outcome, AppLogEntry line) = await _run(
        exportFileAtRevisionAction(
          path: 'lib/main.dart',
          destPath: '/tmp/main-abc.dart',
          export: () async => 'nope',
        ),
      );
      expect(outcome, isA<AppActionFailed<void>>());
      expect(line.level, OperationLogLevel.error);
      expect(line.message, 'Could not export lib/main.dart: nope');
    });
  });
}
