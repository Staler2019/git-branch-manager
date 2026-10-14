import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/services/detached_process.dart';

/// How the updater script is started on Windows.
///
/// `Process.start(mode: ProcessStartMode.detached)` returns a pid there and
/// reports success, and the child never runs a single instruction: measured
/// with `powershell.exe -File` and with `cmd.exe /c`, from `dart run`, from
/// an AOT executable and from a process WMI created outside any job, with
/// the parent alive for ten seconds afterwards. That is the whole of the
/// reported "a gbm-update.ps1 in temp and no gbm-update.log" -- the script
/// was written and never ran.
void main() {
  group('windowsRelayArguments', () {
    const String shell =
        r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe';

    String command(List<String> arguments, {String dir = r'C:\Temp'}) {
      final List<String> relay = windowsRelayArguments(
        shell,
        arguments,
        workingDirectory: dir,
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
      expect(c, contains(r"-WorkingDirectory 'C:\Temp'"));
    });

    // Start-Process joins an argument array with spaces and quotes nothing,
    // so the arguments travel as one string with each one double-quoted --
    // the script lives under a user's temp directory, which can have a
    // space in it.
    test('passes the arguments as one string, each one double-quoted', () {
      expect(
        command(<String>['-File', r'C:\Users\Jane Doe\Temp\gbm-update.ps1']),
        contains(
          r"""-ArgumentList '"-File" "C:\Users\Jane Doe\Temp\gbm-update.ps1"'""",
        ),
      );
    });

    test('keeps a quote or a dollar in a path out of the command', () {
      final String c = command(<String>[
        '-File',
        r"C:\Users\o'brien $(calc)\gbm-update.ps1",
      ], dir: r"C:\Users\o'brien $(calc)");

      expect(c, contains(r"-WorkingDirectory 'C:\Users\o''brien $(calc)'"));
      expect(
        c,
        contains(r"""'"-File" "C:\Users\o''brien $(calc)\gbm-update.ps1"'"""),
      );
    });
  });

  // The one assertion that can tell "started" from "reported started": the
  // child has to leave a mark of its own. Against the old detached start
  // this file never appeared.
  test('a started updater actually runs', () async {
    final Directory dir = Directory.systemTemp.createTempSync('gbm relay ');
    addTearDown(() => dir.deleteSync(recursive: true));
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
