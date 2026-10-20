import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/external_app_entry.dart';
import 'package:gbm_flutter/data/services/desktop_launcher.dart';

/// `DesktopLauncher.openExternalApp` -- the worktree panel's ▾ entries.
/// Rules: open-with-apps-spec.html's rules table, security review F2/F3/F6,
/// rulings D3 (5-second exit-code window) and D6 (`-lic`, empty stdin).
class _FakeProcess implements Process {
  _FakeProcess();

  final Completer<int> exit = Completer<int>();
  final StreamController<List<int>> err = StreamController<List<int>>();
  final StreamController<List<int>> out = StreamController<List<int>>();
  final _FakeSink sink = _FakeSink();

  void emitErr(String text) => err.add(utf8.encode(text));

  Future<void> finish(int code) async {
    await err.close();
    await out.close();
    exit.complete(code);
  }

  @override
  Future<int> get exitCode => exit.future;
  @override
  Stream<List<int>> get stderr => err.stream;
  @override
  Stream<List<int>> get stdout => out.stream;
  @override
  IOSink get stdin => sink;
  @override
  int get pid => 1;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
}

class _FakeSink implements IOSink {
  bool closed = false;

  @override
  Future<void> close() async => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _Spawned {
  _Spawned(this.executable, this.arguments, this.workingDirectory);

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
}

void main() {
  ExternalAppEntry entry(String command, {String label = 'App'}) =>
      (ExternalAppEntry.create(
        label: label,
        command: command,
        newId: () => 'i',
      ) as ExternalAppEntryAccepted).entry;

  late List<_Spawned> spawned;
  late _FakeProcess process;
  late List<(String, List<String>, String?)> started;

  setUp(() {
    spawned = <_Spawned>[];
    process = _FakeProcess();
    started = <(String, List<String>, String?)>[];
  });

  Future<Process> spawn(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    spawned.add(_Spawned(executable, arguments, workingDirectory));
    return process;
  }

  DesktopLauncher posix({
    Map<String, String> env = const <String, String>{'SHELL': '/bin/zsh'},
    Duration wait = const Duration(seconds: 5),
    ProcessSpawner? spawner,
  }) => DesktopLauncher(
    operatingSystem: 'macos',
    spawn: spawner ?? spawn,
    environment: env,
    exitWait: wait,
    start: (String e, List<String> a, {String? workingDirectory}) async =>
        fail('detached start used on POSIX'),
  );

  DesktopLauncher windows({bool relayOk = true}) => DesktopLauncher(
    operatingSystem: 'windows',
    environment: const <String, String>{'SystemRoot': r'C:\Windows'},
    spawn: (String e, List<String> a, {String? workingDirectory}) async =>
        fail('spawn used on Windows'),
    start: (String e, List<String> a, {String? workingDirectory}) async {
      started.add((e, a, workingDirectory));
      return relayOk;
    },
  );

  group('POSIX argv', () {
    test(
      'runs the command in a login interactive shell, path as \$1',
      () async {
        final Future<ExternalAppLaunchResult> r = posix().openExternalApp(
          entry('code {path}'),
          '/w/repo',
        );
        await process.finish(0);
        expect(await r, isA<ExternalAppStarted>());

        final _Spawned s = spawned.single;
        expect(s.executable, '/bin/zsh');
        expect(s.arguments, <String>[
          '-lic',
          '{ code "\$1"\n} </dev/null >/dev/null',
          'gbm',
          '/w/repo',
        ]);
        expect(s.workingDirectory, '/w/repo');
      },
    );

    test('never puts the path into the script', () async {
      const String path = '/w/\$(touch X) `id` "q" \'s\'\nnl';
      final Future<ExternalAppLaunchResult> r = posix().openExternalApp(
        entry('code {path}'),
        path,
      );
      await process.finish(0);
      await r;
      expect(spawned.single.arguments[1], isNot(contains('touch')));
      expect(spawned.single.arguments.last, path);
    });

    test('closes stdin as soon as the shell starts', () async {
      final Future<ExternalAppLaunchResult> r = posix().openExternalApp(
        entry('rider .'),
        '/w',
      );
      await process.finish(0);
      await r;
      expect(process.sink.closed, isTrue);
    });

    // F3: `$1` means something else, or nothing, outside the POSIX family.
    test('uses an allowlisted absolute \$SHELL, otherwise /bin/sh', () async {
      final Map<String, String> cases = <String, String>{
        '/bin/zsh': '/bin/zsh',
        '/opt/homebrew/bin/bash': '/opt/homebrew/bin/bash',
        '/usr/local/bin/fish': '/bin/sh',
        '/usr/local/bin/pwsh': '/bin/sh',
        'zsh': '/bin/sh',
        '': '/bin/sh',
      };
      for (final MapEntry<String, String> c in cases.entries) {
        spawned.clear();
        process = _FakeProcess();
        final Future<ExternalAppLaunchResult> r = posix(
          env: <String, String>{'SHELL': c.key},
        ).openExternalApp(entry('rider .'), '/w');
        await process.finish(0);
        await r;
        expect(spawned.single.executable, c.value, reason: c.key);
      }
      spawned.clear();
      process = _FakeProcess();
      final Future<ExternalAppLaunchResult> r = posix(
        env: const <String, String>{},
      ).openExternalApp(entry('rider .'), '/w');
      await process.finish(0);
      await r;
      expect(spawned.single.executable, '/bin/sh');
    });
  });

  group('POSIX outcome (D3)', () {
    test('a non-zero exit inside the window is a failure with stderr\'s last '
        'line', () async {
      final Future<ExternalAppLaunchResult> r = posix().openExternalApp(
        entry('rider .'),
        '/w',
      );
      process.emitErr('noise\nzsh:1: command not found: rider\n');
      await process.finish(127);
      final ExternalAppLaunchResult result = await r;
      expect(result, isA<ExternalAppLaunchFailed>());
      expect(
        (result as ExternalAppLaunchFailed).message,
        'zsh:1: command not found: rider',
      );
    });

    test('a non-zero exit with no stderr still names the exit code', () async {
      final Future<ExternalAppLaunchResult> r = posix().openExternalApp(
        entry('rider .'),
        '/w',
      );
      await process.finish(3);
      final ExternalAppLaunchResult result = await r;
      expect((result as ExternalAppLaunchFailed).message, contains('3'));
    });

    test('a zero exit is started', () async {
      final Future<ExternalAppLaunchResult> r = posix().openExternalApp(
        entry('rider .'),
        '/w',
      );
      await process.finish(0);
      expect(await r, isA<ExternalAppStarted>());
    });

    test('still running when the window closes is started, and stderr keeps '
        'draining', () async {
      final ExternalAppLaunchResult result = await posix(
        wait: const Duration(milliseconds: 20),
      ).openExternalApp(entry('code .'), '/w');
      expect(result, isA<ExternalAppStarted>());
      // A listener is still attached after the window: a pipe nobody reads
      // would fill and stall the child.
      expect(process.err.hasListener, isTrue);
      process.emitErr('late output\n');
      await process.finish(0);
    });

    test('keeps only the last 512 characters of a long stderr line', () async {
      final Future<ExternalAppLaunchResult> r = posix().openExternalApp(
        entry('rider .'),
        '/w',
      );
      process.emitErr('${'a' * 600}${'b' * 512}');
      await process.finish(1);
      final String message = ((await r) as ExternalAppLaunchFailed).message;
      expect(message, 'b' * 512);
    });

    // A prunable worktree's directory is gone; Process.start throws for a
    // working directory that does not exist (closing plan review).
    test('a spawner that throws is a failure, not an exception', () async {
      final ExternalAppLaunchResult result = await posix(
        spawner: (String e, List<String> a, {String? workingDirectory}) =>
            throw const ProcessException(
              '/bin/zsh',
              <String>[],
              'No such file or directory',
              2,
            ),
      ).openExternalApp(entry('rider .'), '/gone');
      expect(result, isA<ExternalAppLaunchFailed>());
      expect(
        (result as ExternalAppLaunchFailed).message,
        contains('No such file or directory'),
      );
    });

    test('a relative path is refused without starting anything', () async {
      final ExternalAppLaunchResult result = await posix().openExternalApp(
        entry('rider .'),
        'w/repo',
      );
      expect(result, isA<ExternalAppLaunchFailed>());
      expect(spawned, isEmpty);
    });
  });

  group('Windows (F2)', () {
    test(
      'runs cmd by absolute path with the path never in the command',
      () async {
        final ExternalAppLaunchResult result = await windows().openExternalApp(
          entry('code {path}'),
          r'C:\dev\a%CMDCMDLINE:~-1%&calc',
        );
        expect(result, isA<ExternalAppStarted>());
        final (String exe, List<String> args, String? dir) = started.single;
        expect(exe, r'C:\Windows\System32\cmd.exe');
        expect(args, <String>['/d', '/s', '/v:off', '/c', 'code .']);
        expect(dir, r'C:\dev\a%CMDCMDLINE:~-1%&calc');
      },
    );

    test('a UNC path is refused without starting anything', () async {
      final ExternalAppLaunchResult result = await windows().openExternalApp(
        entry('explorer .'),
        r'\\server\share\repo',
      );
      // Named as UNC, not as "not absolute": a UNC path is absolute, and the
      // user needs to know which rule refused it.
      expect((result as ExternalAppLaunchFailed).message, contains('UNC'));
      expect(started, isEmpty);
    });

    // The relay refuses any argument with a double quote, so this could
    // never run; say so instead of failing somewhere deeper.
    test('a command with a double quote is refused without starting', () async {
      final ExternalAppLaunchResult result = await windows().openExternalApp(
        entry(r'"C:\Program Files\Code\code.cmd" .'),
        r'C:\dev\repo',
      );
      expect(result, isA<ExternalAppLaunchFailed>());
      expect((result as ExternalAppLaunchFailed).message, contains('雙引號'));
      expect(started, isEmpty);
    });

    test('a relay that fails is a failure', () async {
      final ExternalAppLaunchResult result = await windows(relayOk: false)
          .openExternalApp(entry('code .'), r'C:\dev\repo');
      expect(result, isA<ExternalAppLaunchFailed>());
    });

    test('a relative path is refused', () async {
      final ExternalAppLaunchResult result = await windows().openExternalApp(
        entry('code .'),
        r'dev\repo',
      );
      expect(result, isA<ExternalAppLaunchFailed>());
      expect(started, isEmpty);
    });
  });

  // The one real shell run: the script the launcher builds, with a hostile
  // path, writes the path back byte for byte and runs nothing from it.
  test('a real /bin/sh treats the path as data', () async {
    final Directory tmp = await Directory.systemTemp.createTemp('gbm-ow');
    addTearDown(() => tmp.delete(recursive: true));
    final Directory hostile = await Directory(
      '${tmp.path}/a \$(touch PWNED) `touch PWNED2` "q" \'s\'',
    ).create();
    final File out = File('${tmp.path}/out.txt');
    final ExternalAppLaunchResult result = await DesktopLauncher(
      operatingSystem: Platform.operatingSystem,
      environment: const <String, String>{'SHELL': '/bin/sh'},
    ).openExternalApp(entry("printf %s {path} > '${out.path}'"), hostile.path);
    expect(result, isA<ExternalAppStarted>());
    expect(await out.readAsString(), hostile.path);
    expect(File('${hostile.path}/PWNED').existsSync(), isFalse);
    expect(File('${hostile.path}/PWNED2').existsSync(), isFalse);
    expect(File('${tmp.path}/PWNED').existsSync(), isFalse);
  }, skip: Platform.isWindows ? 'POSIX shell only' : false);
}
