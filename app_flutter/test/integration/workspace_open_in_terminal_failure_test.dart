// Repository → Open in terminal (Ctrl/Cmd+`) finding no terminal: one error
// line in the log, which lights the status bar's red summary -- never a
// toast (P10 #3, open-with-apps-spec.html screen 3). `_openInTerminal`'s doc
// comment always said 「reported into the operation log」; the code showed a
// SnackBar.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/services/desktop_launcher.dart';
import 'package:gbm_flutter/features/status_bar/status_bar.dart';

import '../support/pump_workspace.dart';

class _Terminal extends DesktopLauncher {
  const _Terminal() : super(operatingSystem: 'linux');

  @override
  Future<bool> openTerminal(String path) async => true;
}

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

class _NoTerminal extends DesktopLauncher {
  const _NoTerminal() : super(operatingSystem: 'linux');

  @override
  Future<bool> openTerminal(String path) async => false;
}

void main() {
  testWidgets('no terminal is an error line and a red summary', (tester) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
      overrides: <Override>[
        desktopLauncherProvider.overrideWithValue(const _NoTerminal()),
      ],
    );

    // pumpWorkspace is non-macOS, so the chord is Ctrl+`.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.backquote);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backquote);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      pumped.controller.state.operationLog
          .where((GbmLogEntry e) => e.level == OperationLogLevel.error)
          .map((GbmLogEntry e) => e.message),
      <String>['No terminal emulator was found'],
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(
      find.descendant(
        of: find.byType(StatusBar),
        matching: find.text('No terminal emulator was found'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a terminal that starts is one info line', (tester) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
      overrides: <Override>[
        desktopLauncherProvider.overrideWithValue(const _Terminal()),
      ],
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.backquote);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.backquote);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final List<GbmLogEntry> lines = pumped.controller.state.operationLog
        .whereType<AppLogEntry>()
        .toList();
    expect(lines.map((GbmLogEntry e) => e.message), <String>[
      'Opened a terminal in /test/repo',
    ]);
    expect(lines.single.level, OperationLogLevel.info);
  });
}
