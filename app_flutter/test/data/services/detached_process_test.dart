import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/services/detached_process.dart';

/// How the updater script, and everything `DesktopLauncher` opens, is
/// started on Windows.
///
/// `Process.start(mode: ProcessStartMode.detached)` returns a pid there and
/// reports success, and a console program never runs a single instruction:
/// measured with `powershell.exe -File` and with `cmd.exe /c`, from `dart
/// run`, from an AOT executable and from a process WMI created outside any
/// job, with the parent alive for ten seconds afterwards (GUI programs --
/// `charmap.exe`, `wt.exe` -- do run). That is the whole of the reported "a
/// gbm-update.ps1 in temp and no gbm-update.log" -- the script was written
/// and never ran.
void main() {
  group('windowsRelayArguments', () {
    const String shell =
        r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';

    String command(
      List<String> arguments, {
      String dir = r'C:\Temp',
      RelayWindow window = RelayWindow.hidden,
    }) {
      final List<String> relay = windowsRelayArguments(
        shell,
        arguments,
        workingDirectory: dir,
        window: window,
      );
      expect(relay.take(4), <String>[
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
      ]);
      expect(relay[relay.length - 2], '-Command');
      return relay.last;
    }

    test('hands the real start to Start-Process, hidden', () {
      final String c = command(<String>['-File', r'C:\Temp\gbm-update.ps1']);

      expect(c, startsWith('Start-Process -WindowStyle Hidden '));
      expect(c, contains("-FilePath '$shell'"));
      expect(
        c,
        contains(r"-WorkingDirectory ([WildcardPattern]::Escape('C:\Temp'))"),
      );
    });

    // Start-Process resolves -WorkingDirectory as a wildcard: a repository
    // under `br[1] b` failed to start anything until the brackets were
    // escaped (measured, verifier F1).
    test('escapes wildcards in the working directory', () {
      expect(
        command(<String>['-NoExit'], dir: r'C:\dev\br[1] b'),
        contains(
          r"-WorkingDirectory ([WildcardPattern]::Escape('C:\dev\br[1] b'))",
        ),
      );
    });

    // A backslash before the closing quote would escape it: `"C:\a b\"`
    // swallowed every argument after it into one (measured, verifier F2).
    // Doubled, as `Process.start` does.
    test('doubles the backslashes that end a quoted argument', () {
      expect(
        command(<String>['-d', r'C:\a b\', 'next']),
        contains(r"""-ArgumentList '-d "C:\a b\\" next'"""),
      );
    });

    // Start-Process joins an argument array with spaces and quotes nothing,
    // so the arguments travel as one string, an argument with a space in it
    // double-quoted -- the script lives under a user's temp directory, which
    // can have a space in it.
    test('passes the arguments as one string, quoting a spaced one', () {
      expect(
        command(<String>['-File', r'C:\Users\Jane Doe\Temp\gbm-update.ps1']),
        contains(
          r"""-ArgumentList '-File "C:\Users\Jane Doe\Temp\gbm-update.ps1"'""",
        ),
      );
    });

    // cmd.exe handed `"/c"` runs nothing at all (measured).
    test('never quotes an argument that needs none', () {
      expect(
        command(<String>['/c', 'echo ok>x.txt', '']),
        contains(r"""-ArgumentList '/c "echo ok>x.txt" ""'"""),
      );
    });

    // A terminal or a browser the user asked for has to be seen; only the
    // updater's own script runs hidden.
    test('shows the window when asked to', () {
      expect(
        command(<String>['-NoExit'], window: RelayWindow.normal),
        startsWith('Start-Process -WindowStyle Normal '),
      );
    });

    // Start-Process refuses an empty -ArgumentList, and a URL or a document
    // handed straight to it has no arguments at all.
    test('leaves -ArgumentList out when there are no arguments', () {
      expect(command(<String>[]), isNot(contains('-ArgumentList')));
    });

    test('keeps a quote or a dollar in a path out of the command', () {
      final String c = command(<String>[
        '-File',
        r"C:\Users\o'brien $(calc)\gbm-update.ps1",
      ], dir: r"C:\Users\o'brien $(calc)");

      expect(
        c,
        contains(
          r"-WorkingDirectory ([WildcardPattern]::Escape('C:\Users\o''brien $(calc)'))",
        ),
      );
      expect(
        c,
        contains(r"""'-File "C:\Users\o''brien $(calc)\gbm-update.ps1"'"""),
      );
    });
  });

  // The one assertion that can tell "started" from "reported started": the
  // child has to leave a mark of its own. Against the old detached start
  // this file never appeared.
  test('a started updater actually runs', () async {
    final Directory dir = Directory.systemTemp.createTempSync('gbm relay ');
    addTearDown(() => _deleteEventually(dir));
    final File script = File('${dir.path}\\probe.ps1')
      ..writeAsStringSync(
        "Set-Content -LiteralPath (Join-Path \$PSScriptRoot 'ran.txt') -Value ok\n",
      );
    final String shell =
        '${Platform.environment['SystemRoot']}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';

    final DetachedStart outcome = await startDetachedProcess(shell, <String>[
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-File',
      script.path,
    ], workingDirectory: dir.path);

    expect(outcome.started, isTrue, reason: outcome.error);
    final File ran = File('${dir.path}\\ran.txt');
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!ran.existsSync() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(ran.existsSync(), isTrue, reason: 'the script never ran');
  }, skip: Platform.isWindows ? false : 'Windows only');

  group('windowsRelayShell', () {
    test('is Windows PowerShell by absolute path', () {
      expect(
        windowsRelayShell(systemRoot: r'C:\Windows'),
        r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
      );
    });

    test('falls back to the bare name without a SystemRoot', () {
      expect(windowsRelayShell(systemRoot: ''), 'powershell.exe');
    });
  });

  // The relay used to be the program itself, asked to Start-Process itself:
  // fine for PowerShell, nonsense for anything else. Measured: cmd.exe,
  // started detached, never ran either.
  test('a console program that is not PowerShell actually runs', () async {
    final Directory dir = Directory.systemTemp.createTempSync('gbm relay ');
    addTearDown(() => _deleteEventually(dir));
    final String mark = '${dir.path}\\ran.txt';

    final DetachedStart outcome = await startDetachedProcess(
      '${Platform.environment['SystemRoot']}\\System32\\cmd.exe',
      <String>['/c', 'echo ok>ran.txt'],
      workingDirectory: dir.path,
    );

    expect(outcome.started, isTrue, reason: outcome.error);
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!File(mark).existsSync() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(File(mark).existsSync(), isTrue, reason: 'cmd.exe never ran');
  }, skip: Platform.isWindows ? false : 'Windows only');

  test('a working directory with brackets in it still starts', () async {
    final Directory dir = Directory.systemTemp.createTempSync('gbm br[1] ');
    addTearDown(() => _deleteEventually(dir));
    final String mark = '${dir.path}\\ran.txt';

    final DetachedStart outcome = await startDetachedProcess(
      '${Platform.environment['SystemRoot']}\\System32\\cmd.exe',
      <String>['/c', 'echo ok>ran.txt'],
      workingDirectory: dir.path,
    );

    expect(outcome.started, isTrue, reason: outcome.error);
    final DateTime deadline = DateTime.now().add(const Duration(seconds: 20));
    while (!File(mark).existsSync() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    expect(File(mark).existsSync(), isTrue, reason: 'cmd.exe never ran');
  }, skip: Platform.isWindows ? false : 'Windows only');

  // A spaced argument travels double-quoted; one that carries a quote of its
  // own would end that quoting early. No Windows path can, so this is refused
  // rather than escaped.
  test('an argument with a double quote is refused', () async {
    final DetachedStart outcome = await startDetachedProcess(
      'cmd.exe',
      <String>['/c', 'echo "x"'],
      workingDirectory: Directory.systemTemp.path,
    );

    expect(outcome.started, isFalse);
    expect(outcome.error, contains('double quote'));
  }, skip: Platform.isWindows ? false : 'Windows only');

  test('a shell that is not there is reported, not swallowed', () async {
    final DetachedStart outcome = await startDetachedProcess(
      r'C:\nowhere\powershell.exe',
      <String>['-File', 'x.ps1'],
      workingDirectory: Directory.systemTemp.path,
    );

    expect(outcome.started, isFalse);
    expect(outcome.error, isNotEmpty);
  }, skip: Platform.isWindows ? false : 'Windows only');
}

/// The started child can still be standing in [dir] -- its working
/// directory -- when the test ends, and Windows refuses to delete a
/// directory a live process has as its current one (errno 32; 1 in 6 runs
/// of `a started updater actually runs`). The child exits by itself within
/// moments, so keep trying for a while instead of failing the teardown.
Future<void> _deleteEventually(Directory dir) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 15));
  while (true) {
    try {
      dir.deleteSync(recursive: true);
      return;
    } on FileSystemException {
      if (DateTime.now().isAfter(deadline)) rethrow;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }
}
