import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/services/update_installer.dart';

/// The half of the installer that must not be executed: platform derivation,
/// the degradation checks, extraction, and the ordering of the three things
/// that happen when the app hands over to the updater.
///
/// The script's own control flow is covered by actually running it -- see
/// `update_installer_script_test.dart`.
void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('gbm-installer');
  });

  tearDown(() {
    if (root.existsSync()) {
      // A test that made a directory read-only has to hand write permission
      // back before the tree can be removed.
      Process.runSync('chmod', <String>['-R', 'u+w', root.path]);
      root.deleteSync(recursive: true);
    }
  });

  group('installTarget', () {
    // macOS is the only platform where the executable is not in the
    // directory that gets replaced -- getting this wrong would swap
    // `Contents/MacOS` and leave a bundle with no Info.plist.
    test('is the .app bundle on macOS, three levels above the binary', () {
      const UpdateInstaller installer = UpdateInstaller(
        operatingSystem: 'macos',
        executablePath:
            '/Applications/gbm_flutter.app/Contents/MacOS/gbm_flutter',
      );

      expect(installer.installTarget().path, '/Applications/gbm_flutter.app');
    });

    test('is the executable\'s own directory elsewhere', () {
      const UpdateInstaller linux = UpdateInstaller(
        operatingSystem: 'linux',
        executablePath: '/opt/gbm/gbm_flutter',
      );
      const UpdateInstaller windows = UpdateInstaller(
        operatingSystem: 'windows',
        executablePath: r'C:\Program Files\gbm\gbm_flutter.exe',
      );

      expect(linux.installTarget().path, '/opt/gbm');
      expect(windows.installTarget().path, isNot(contains('gbm_flutter.exe')));
    });
  });

  group('selfInstallBlocker', () {
    UpdateInstaller installerFor(Directory target, {Abi abi = Abi.linuxX64}) {
      return UpdateInstaller(
        operatingSystem: 'linux',
        executablePath: '${target.path}/gbm_flutter',
        abi: abi,
      );
    }

    test('passes for a writable install directory on a published platform', () {
      final Directory install = Directory('${root.path}/opt/gbm')
        ..createSync(recursive: true);

      expect(installerFor(install).selfInstallBlocker(), isNull);
    });

    // An Intel Mac is the live case: release.yml publishes arm64 only, so
    // there is nothing to install even though everything else would work.
    test('blocks when no asset is published for this ABI', () {
      final Directory install = Directory('${root.path}/opt/gbm')
        ..createSync(recursive: true);

      final String? reason = installerFor(
        install,
        abi: Abi.macosX64,
      ).selfInstallBlocker();

      expect(reason, isNotNull);
      expect(reason, contains('releases page'));
    });

    // Probed by writing rather than by reading a mode bit, so this test has
    // to make a directory genuinely unwritable rather than fake a stat.
    test('blocks when the install directory cannot be written', () {
      final Directory parent = Directory('${root.path}/readonly')
        ..createSync(recursive: true);
      final Directory install = Directory('${parent.path}/gbm')
        ..createSync(recursive: true);
      Process.runSync('chmod', <String>['555', parent.path]);

      final String? reason = installerFor(install).selfInstallBlocker();

      expect(reason, isNotNull);
      expect(reason, contains('not writable'));
    });

    test('blocks a translocated macOS bundle', () {
      const UpdateInstaller installer = UpdateInstaller(
        operatingSystem: 'macos',
        executablePath:
            '/private/var/folders/x/AppTranslocation/ABC/d/'
            'gbm_flutter.app/Contents/MacOS/gbm_flutter',
        abi: Abi.macosArm64,
      );

      expect(installer.selfInstallBlocker(), contains('Applications folder'));
    });

    // Windows is the live risk. Its release artifact is a **flat** zip
    // (release.yml's `Compress-Archive .../Release/*`), so extracting it
    // straight into Downloads puts gbm_flutter.exe directly there and makes
    // Downloads the "install directory" -- which the updater would rename to
    // `Downloads.gbm-old` wholesale. macOS cannot reach this (the target is
    // the .app bundle) and the Linux tarball carries its own wrapper.
    group('isSharedUserFolder', () {
      const String home = r'C:\Users\jane';

      test('takes a well-known folder whatever the separator or case', () {
        for (final String path in <String>[
          r'C:\Users\jane\Downloads',
          'C:/Users/jane/Downloads',
          r'C:\Users\jane\desktop',
          r'C:\Users\jane\Documents\',
        ]) {
          expect(isSharedUserFolder(path, home), isTrue, reason: path);
        }
      });

      test('takes the home directory itself and a drive root', () {
        expect(isSharedUserFolder(home, home), isTrue);
        expect(isSharedUserFolder(r'C:\', home), isTrue);
        expect(isSharedUserFolder('/', '/home/jane'), isTrue);
      });

      test('leaves a folder of its own alone', () {
        for (final String path in <String>[
          r'C:\Users\jane\Apps\gbm',
          r'C:\Users\jane\git-branch-manager-0.35.0-windows-x64',
          r'C:\Program Files\gbm',
          '/home/jane/Downloads/gbm',
        ]) {
          expect(isSharedUserFolder(path, home), isFalse, reason: path);
        }
      });

      // A name that merely looks like one is not one: only a *direct* child
      // of home counts.
      test('does not take a Downloads nested somewhere else', () {
        expect(isSharedUserFolder(r'D:\Backup\Downloads', home), isFalse);
        // The case a "sits under home and ends with a known name" rule gets
        // wrong: it is under home and it is called Downloads, and it is
        // still somebody's own folder.
        expect(
          isSharedUserFolder(r'C:\Users\jane\Apps\Downloads', home),
          isFalse,
        );
      });

      test('decides nothing when the home directory is unknown', () {
        expect(isSharedUserFolder(r'C:\Users\jane\Downloads', null), isFalse);
      });
    });

    test('blocks installing directly in a shared folder', () {
      final Directory home = Directory('${root.path}/home/jane')
        ..createSync(recursive: true);
      final Directory install = Directory('${home.path}/Downloads')
        ..createSync(recursive: true);

      final String? reason = UpdateInstaller(
        operatingSystem: 'linux',
        executablePath: '${install.path}/gbm_flutter',
        abi: Abi.linuxX64,
        homeDirectory: home.path,
      ).selfInstallBlocker();

      expect(reason, isNotNull);
      expect(reason, contains('folder of its own'));
    });

    test('leaves a dedicated folder inside a shared one alone', () {
      final Directory home = Directory('${root.path}/home/jane')
        ..createSync(recursive: true);
      final Directory install = Directory('${home.path}/Downloads/gbm')
        ..createSync(recursive: true);

      expect(
        UpdateInstaller(
          operatingSystem: 'linux',
          executablePath: '${install.path}/gbm_flutter',
          abi: Abi.linuxX64,
          homeDirectory: home.path,
        ).selfInstallBlocker(),
        isNull,
      );
    });

    test('leaves no probe file behind', () {
      final Directory install = Directory('${root.path}/opt/gbm')
        ..createSync(recursive: true);

      installerFor(install).selfInstallBlocker();

      expect(
        Directory('${root.path}/opt').listSync().map((e) => e.path),
        everyElement(isNot(contains('write-probe'))),
      );
    });
  });

  group('stage', () {
    late List<List<String>> ran;

    /// Records every command and reports success. [onRun] lets a test give a
    /// command a real side effect (an extraction that produces files).
    ProcessRunner recorder({
      void Function(String exe, List<String> args)? onRun,
      ProcessRunResult Function(String exe)? result,
    }) {
      return (String exe, List<String> args) async {
        ran.add(<String>[exe, ...args]);
        onRun?.call(exe, args);
        return result?.call(exe) ?? const ProcessRunResult(0, '');
      };
    }

    setUp(() => ran = <List<String>>[]);

    test('descends the Linux tarball\'s single wrapper directory', () async {
      final UpdateInstaller installer = UpdateInstaller(
        operatingSystem: 'linux',
        run: recorder(
          onRun: (String exe, List<String> args) {
            // `tar xzf <bundle> -C <payload>` -- reproduce what release.yml's
            // `tar czf … "$name"` actually produces.
            Directory(
              '${args.last}/git-branch-manager-0.31.0-linux-x86_64',
            ).createSync(recursive: true);
          },
        ),
      );

      final Directory staged = await installer.stage(
        bundle: File('${root.path}/x.tar.gz'),
        into: root,
      );

      expect(ran.single.take(2), <String>['tar', 'xzf']);
      expect(
        staged.path,
        endsWith('git-branch-manager-0.31.0-linux-x86_64'),
        reason:
            'swapping the wrapper in would nest the install one level '
            'deeper than it belongs',
      );
    });

    test('does not descend when the archive has no single wrapper', () async {
      final UpdateInstaller installer = UpdateInstaller(
        operatingSystem: 'linux',
        run: recorder(
          onRun: (String exe, List<String> args) {
            Directory('${args.last}/data').createSync(recursive: true);
            File('${args.last}/gbm_flutter').writeAsStringSync('');
          },
        ),
      );

      final Directory staged = await installer.stage(
        bundle: File('${root.path}/x.tar.gz'),
        into: root,
      );

      expect(staged.path, endsWith('payload'));
    });

    // The Windows zip is flat (`Compress-Archive .../Release/*`), so the
    // payload directory is the swap unit as-is.
    test('unpacks the Windows zip with tar and does not descend', () async {
      final UpdateInstaller installer = UpdateInstaller(
        operatingSystem: 'windows',
        run: recorder(
          onRun: (String exe, List<String> args) {
            File('${args.last}/gbm_flutter.exe').writeAsStringSync('');
          },
        ),
      );

      final Directory staged = await installer.stage(
        bundle: File('${root.path}/x.zip'),
        into: root,
      );

      expect(ran.single.take(2), <String>['tar', '-xf']);
      expect(staged.path, endsWith('payload'));
    });

    test('mounts, dittos out of, and unmounts the macOS disk image', () async {
      final UpdateInstaller installer = UpdateInstaller(
        operatingSystem: 'macos',
        run: recorder(
          onRun: (String exe, List<String> args) {
            if (exe == 'hdiutil' && args.first == 'attach') {
              Directory(
                '${root.path}/mnt/gbm_flutter.app',
              ).createSync(recursive: true);
            }
          },
        ),
      );

      await installer.stage(bundle: File('${root.path}/x.dmg'), into: root);

      expect(ran.map((c) => c.first), <String>[
        'hdiutil', // attach
        'ditto',
        'hdiutil', // detach -- a leaked mount would outlive the app
      ]);
      expect(ran.first, contains('-readonly'));
      expect(ran[1][1], endsWith('gbm_flutter.app'));
    });

    // The whole reason extraction happens before the app quits: a corrupt
    // archive has to be reportable while there is still a window to report
    // it in.
    test('throws with the tool\'s own stderr when unpacking fails', () async {
      final UpdateInstaller installer = UpdateInstaller(
        operatingSystem: 'linux',
        run: recorder(
          result: (String exe) =>
              const ProcessRunResult(1, 'tar: unexpected end of file\n'),
        ),
      );

      expect(
        () => installer.stage(bundle: File('${root.path}/x'), into: root),
        throwsA(
          isA<UpdateInstallException>().having(
            (UpdateInstallException e) => e.message,
            'message',
            contains('unexpected end of file'),
          ),
        ),
      );
    });

    test(
      'retries a busy hdiutil detach rather than failing the update',
      () async {
        int detachAttempts = 0;
        final UpdateInstaller installer = UpdateInstaller(
          operatingSystem: 'macos',
          run: (String exe, List<String> args) async {
            if (exe == 'hdiutil' && args.first == 'attach') {
              Directory(
                '${root.path}/mnt/gbm_flutter.app',
              ).createSync(recursive: true);
              return const ProcessRunResult(0, '');
            }
            if (exe == 'hdiutil') {
              detachAttempts++;
              return const ProcessRunResult(16, 'Resource busy');
            }
            return const ProcessRunResult(0, '');
          },
        );

        // Returns normally: a mount that would not release is not a reason to
        // fail an update whose payload is already staged.
        await installer.stage(bundle: File('${root.path}/x.dmg'), into: root);

        expect(detachAttempts, greaterThan(1));
      },
    );
  });

  group('launchUpdater', () {
    late List<String> events;
    late List<String?> startedIn;
    late Directory staged;
    late Directory scriptDir;

    setUp(() {
      events = <String>[];
      startedIn = <String?>[];
      staged = Directory('${root.path}/staged')..createSync(recursive: true);
      scriptDir = Directory('${root.path}/script')..createSync(recursive: true);
    });

    UpdateInstaller installerWith({
      required bool startSucceeds,
      String os = 'linux',
      String? systemRoot,
      bool watchdogArms = true,
    }) {
      return UpdateInstaller(
        operatingSystem: os,
        executablePath: '${root.path}/install/gbm_flutter',
        systemRoot: systemRoot,
        exitProcess: (int code) => events.add('exit:$code'),
        armWatchdog: (Duration after) async {
          events.add('watchdog:${after.inSeconds}s');
          return watchdogArms;
        },
        start:
            (String exe, List<String> args, {String? workingDirectory}) async {
              events.add('start:$exe');
              startedIn.add(workingDirectory);
              return startSucceeds
                  ? const DetachedStart.ok()
                  : const DetachedStart.failed('no such file');
            },
      );
    }

    Future<String?> run(UpdateInstaller installer) => installer.launchUpdater(
      staged: staged,
      scriptDir: scriptDir,
      processId: 999999,
      beforeExit: () async => events.add('beforeExit'),
    );

    // The ordering is the safety property, and it is the opposite of what it
    // was. This used to close the FFI sessions *first*, defended on the
    // grounds that a hang there "leaves the app alive with no script running
    // -- recoverable -- instead of a detached swap racing a live process".
    // Both halves were wrong: the script's first act is to poll for the
    // parent's exit, so it cannot race a live process; and the hang is not
    // recoverable, because `installing` renders no buttons at all. A user on
    // Windows hit exactly that and was left with a dialog frozen on
    // "Installing…" and an updater that had never been started.
    test('starts the script, then closes down, then exits', () async {
      final String? reason = await run(installerWith(startSucceeds: true));

      expect(reason, isNull);
      expect(events, <String>[
        'start:sh',
        'watchdog:20s',
        'beforeExit',
        'exit:0',
      ]);
    });

    // The watchdog is what makes the reordering worth anything, and it must
    // be armed only past a successful start -- that is what lets the failed
    // start below stay alive without a cancellation handshake it could not
    // perform anyway if the isolate were the thing that had wedged.
    test('does not arm the watchdog when the script never started', () async {
      await run(installerWith(startSucceeds: false));

      expect(events, isNot(contains('watchdog:20s')));
      expect(events, isNot(contains('exit:0')));
    });

    // The reported bug, as close as any tier here can get to it. On the
    // user's machine `beforeExit` blocked the *isolate* -- a synchronous
    // `gbm_session_close` whose C++ destructor waits in
    // `operations_->drain()` -- and the dialog sat on "Installing…", which
    // renders no buttons, forever.
    //
    // **This test cannot reproduce that shape, and saying so is the point.**
    // A `Future.timeout` provably cannot bound synchronous work on its own
    // isolate (measured: `.timeout(100ms)` around a body that sleeps three
    // seconds completes at 3009ms without firing), so a fixture that really
    // blocked would hang this runner rather than fail it. What is pinned
    // here is the half that is testable -- a `beforeExit` that never
    // completes no longer strands the handover -- while the blocked-isolate
    // half is pinned by the ordering assertion above, which is what puts the
    // watchdog in place before `beforeExit` is ever called.
    test('exits anyway when the sessions never finish closing', () async {
      final UpdateInstaller installer = UpdateInstaller(
        operatingSystem: 'linux',
        executablePath: '${root.path}/install/gbm_flutter',
        sessionCloseDeadline: const Duration(milliseconds: 50),
        exitProcess: (int code) => events.add('exit:$code'),
        armWatchdog: (Duration after) async => true,
        start: (String e, List<String> a, {String? workingDirectory}) async =>
            const DetachedStart.ok(),
      );

      final String? reason = await installer.launchUpdater(
        staged: staged,
        scriptDir: scriptDir,
        processId: 999999,
        beforeExit: () => Completer<void>().future,
      );

      expect(reason, isNull);
      expect(events, contains('exit:0'));
      expect(
        File('${scriptDir.path}/$kUpdateLogName').readAsStringSync(),
        contains('the repository sessions did not close'),
      );
    });

    // Everything the app does before handing over used to be written
    // nowhere at all: the transcript had exactly one writer, the script,
    // and on the reported failure the script was never started. A `.ps1` on
    // disk with no `.log` beside it was the whole of the evidence.
    test('writes the handover to the transcript', () async {
      await run(installerWith(startSucceeds: true));

      final String log = File(
        '${scriptDir.path}/$kUpdateLogName',
      ).readAsStringSync();
      expect(log, contains('target=${root.path}/install'));
      expect(log, contains('staged=${staged.path}'));
      expect(log, contains('starting sh '));
      expect(log, contains('updater started'));
      expect(log, contains('watchdog armed for 20s'));
      expect(log, contains('closing repository sessions'));
      expect(log, contains('sessions closed'));
      expect(log, contains('exiting'));
    });

    test('names every shell it tried when none of them start', () async {
      await run(
        installerWith(startSucceeds: false, os: 'windows', systemRoot: ''),
      );

      final String log = File(
        '${scriptDir.path}/$kUpdateLogName',
      ).readAsStringSync();
      expect(log, contains('powershell.exe did not start: no such file'));
      expect(log, contains('pwsh.exe did not start: no such file'));
      expect(log, isNot(contains('updater started')));
    });

    test('records a watchdog that could not be armed', () async {
      await run(installerWith(startSucceeds: true, watchdogArms: false));

      expect(
        File('${scriptDir.path}/$kUpdateLogName').readAsStringSync(),
        contains('the watchdog could not be armed'),
      );
    });

    test('does not exit when the script could not be started', () async {
      final String? reason = await run(installerWith(startSucceeds: false));

      expect(reason, isNotNull);
      expect(
        events,
        isNot(contains('exit:0')),
        reason: 'a machine with no usable shell must keep its running app',
      );
    });

    test('writes the script outside the directory being replaced', () async {
      await run(installerWith(startSucceeds: true));

      // The transcript now sits beside the script, so this filters rather
      // than counting: `UpdateLog` deliberately writes into the same
      // directory, which is how `updateLogPath()` and `$(dirname "$0")` name
      // one file.
      final List<String> written = scriptDir
          .listSync()
          .map((e) => e.path)
          .where((String path) => !path.endsWith(kUpdateLogName))
          .toList();
      expect(written, hasLength(1));
      expect(written.single, endsWith('.sh'));
      expect(
        written.single,
        isNot(startsWith('${root.path}/install')),
        reason: 'a script inside the target would be moved aside mid-run',
      );
      expect(
        startedIn.single,
        isNot(startsWith('${root.path}/install')),
        reason:
            'nor may the updater stand inside it -- on Windows that '
            'alone is enough to make the rename impossible',
      );
    });

    test('uses ditto and a Finder relaunch on macOS', () async {
      await run(
        UpdateInstaller(
          operatingSystem: 'macos',
          executablePath:
              '${root.path}/install/gbm_flutter.app/Contents/MacOS/gbm_flutter',
          exitProcess: (int code) => events.add('exit:$code'),
          start: (String e, List<String> a, {String? workingDirectory}) async =>
              const DetachedStart.ok(),
        ),
      );

      final String script = File(
        '${scriptDir.path}/gbm-update.sh',
      ).readAsStringSync();
      expect(script, contains('ditto "\$STAGED" "\$TARGET"'));
      expect(
        script,
        contains('open "\$TARGET"'),
        reason:
            'launching the inner binary gives a process with no Dock '
            'entry and no menu bar',
      );
      expect(script, contains('.app.gbm-old'));
    });

    test('uses cp -a and launches the binary directly on Linux', () async {
      await run(installerWith(startSucceeds: true));

      final String script = File(
        '${scriptDir.path}/gbm-update.sh',
      ).readAsStringSync();
      expect(script, contains('cp -a "\$STAGED" "\$TARGET"'));
      expect(script, contains('gbm_flutter'));
    });

    test('writes a .ps1 and starts powershell on Windows', () async {
      await run(
        installerWith(
          startSucceeds: true,
          os: 'windows',
          systemRoot: r'C:\Windows',
        ),
      );

      expect(events.first, startsWith('start:'));
      expect(
        events,
        contains(
          r'start:C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
        ),
      );
      expect(File('${scriptDir.path}/gbm-update.ps1').existsSync(), isTrue);
    });

    // A bare `powershell` is resolved by CreateProcess walking PATH, and a
    // mangled PATH is a real Windows condition -- one that would take out
    // the only route this app has to update itself, for a file that never
    // moves. The absolute path goes first for that reason; the bare names
    // stay as fallbacks for a machine whose %SystemRoot% is unset or whose
    // PowerShell is 7-only.
    test('prefers the absolute Windows PowerShell path', () async {
      await run(
        installerWith(
          startSucceeds: true,
          os: 'windows',
          systemRoot: r'C:\Windows',
        ),
      );

      expect(
        events.first,
        r'start:C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
      );
    });

    test('falls back through powershell.exe to pwsh.exe', () async {
      final List<String> tried = <String>[];
      await UpdateInstaller(
        operatingSystem: 'windows',
        executablePath: '${root.path}/install/gbm_flutter.exe',
        systemRoot: r'C:\Windows',
        exitProcess: (int code) => events.add('exit:$code'),
        armWatchdog: (Duration after) async => true,
        start:
            (String exe, List<String> args, {String? workingDirectory}) async {
              tried.add(exe);
              // Only the last candidate works, so every earlier one has to be
              // tried for this to reach an exit at all.
              return exe == 'pwsh.exe'
                  ? const DetachedStart.ok()
                  : const DetachedStart.failed('not found');
            },
      ).launchUpdater(
        staged: staged,
        scriptDir: scriptDir,
        processId: 999999,
        beforeExit: () async {},
      );

      expect(tried, <String>[
        r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
        'powershell.exe',
        'pwsh.exe',
      ]);
      expect(events, contains('exit:0'));
    });

    test('omits the absolute path when %SystemRoot% is unset', () async {
      await run(
        installerWith(startSucceeds: true, os: 'windows', systemRoot: ''),
      );

      expect(events.first, 'start:powershell.exe');
    });

    // The bool this used to answer threw the platform's own message away --
    // and "The system cannot find the file specified" and "Access is denied"
    // send the user somewhere completely different.
    test('reports why the updater could not be started', () async {
      final String? reason = await run(
        installerWith(startSucceeds: false, os: 'windows', systemRoot: ''),
      );

      expect(reason, contains('no such file'));
      expect(reason, contains(kUpdateLogName));
    });

    // THE Windows bug. `Process.start` with no `workingDirectory` inherits
    // the parent's, and an app launched by double-clicking its .exe has the
    // install directory as its own -- so the detached updater was standing
    // inside the very folder it then tried to rename. Windows refuses to
    // rename or delete any process's current directory (the handle carries
    // no FILE_SHARE_DELETE), so `Move-Item` failed all 20 retries and the
    // script exited having closed the app and changed nothing. POSIX allows
    // it, which is why only Windows broke.
    for (final String os in <String>['windows', 'linux', 'macos']) {
      test('starts the updater from the script directory on $os', () async {
        await run(installerWith(startSucceeds: true, os: os));

        expect(startedIn, <String>[scriptDir.path]);
      });
    }

    // `powershell.exe` -- Windows PowerShell 5.1, which is what `-File`
    // resolves to on a stock machine -- reads a BOM-less .ps1 as ANSI, not
    // UTF-8. The three paths are baked into the script as literals, so a
    // user name in Chinese is enough to mojibake all of them and leave every
    // Move-Item and Copy-Item pointing nowhere: the same silent exit 3 the
    // inherited working directory produced.
    test('writes the Windows script as UTF-8 with a BOM', () async {
      await run(installerWith(startSucceeds: true, os: 'windows'));

      final Uint8List bytes = File(
        '${scriptDir.path}/gbm-update.ps1',
      ).readAsBytesSync();
      expect(bytes.take(3), <int>[0xEF, 0xBB, 0xBF]);
    });

    // `sh` has the opposite requirement: a BOM on the first line is a syntax
    // error, not a hint.
    test('writes the sh script without a BOM', () async {
      await run(installerWith(startSucceeds: true));

      final Uint8List bytes = File(
        '${scriptDir.path}/gbm-update.sh',
      ).readAsBytesSync();
      expect(bytes.first, 0x23, reason: 'must start with the shebang #');
    });

    test('a non-ASCII install path survives the round trip', () async {
      final Directory nonAscii = Directory('${root.path}/使用者/gbm')
        ..createSync(recursive: true);
      await UpdateInstaller(
        operatingSystem: 'windows',
        executablePath: '${nonAscii.path}/gbm_flutter.exe',
        exitProcess: (int code) => events.add('exit:$code'),
        start:
            (String exe, List<String> args, {String? workingDirectory}) async =>
                const DetachedStart.ok(),
      ).launchUpdater(
        staged: staged,
        scriptDir: scriptDir,
        processId: 999999,
        beforeExit: () async {},
      );

      expect(
        File('${scriptDir.path}/gbm-update.ps1').readAsStringSync(),
        contains(nonAscii.path),
      );
    });

    // The relaunched build must land back in its install directory rather
    // than in system temp, where the script itself now stands.
    test(
      'relaunches the new Windows build from the install directory',
      () async {
        await run(installerWith(startSucceeds: true, os: 'windows'));

        expect(
          File('${scriptDir.path}/gbm-update.ps1').readAsStringSync(),
          contains(r'Start-Process -WorkingDirectory $target'),
        );
      },
    );
  });

  // No Windows machine runs this suite, so this half is text only and the
  // manual pre-release pass is what actually covers it. Asserted anyway,
  // because release.yml compiles `windows/runner/` solely on tag -- nothing
  // else in CI would notice this drifting.
  group('the Windows script', () {
    String script({String target = r'C:\Program Files\gbm'}) =>
        buildWindowsUpdaterScript(
          pid: 4242,
          targetPath: target,
          stagedPath: r'C:\Temp\staged',
          relaunchCommand: 'Start-Process x',
          waitTimeout: const Duration(seconds: 30),
        );

    // Belt and braces behind the `workingDirectory` fix above. `Set-Location`
    // alone is NOT enough: it moves PowerShell's *provider* location while
    // the Win32 process directory -- the one holding the handle that blocks
    // the rename -- stays where the process was created. Only assigning
    // [System.Environment]::CurrentDirectory calls SetCurrentDirectory and
    // releases it.
    test('steps out of whatever directory it inherited', () {
      expect(script(), contains(r'Set-Location -LiteralPath $PSScriptRoot'));
      expect(
        script(),
        contains(r'[System.Environment]::CurrentDirectory = $PSScriptRoot'),
      );
    });

    // Same three arms the executed sh tests pin, asserted as text because no
    // Windows machine runs this suite. Every arm reached after the app has
    // exited must put a working build back -- a script that simply gives up
    // is what turned a failed rename into "the app closed and never came
    // back".
    test('puts a build back on every arm that runs after the app exits', () {
      final String s = script();

      expect(s, contains('function Restart-App'));
      expect(
        'Restart-App'.allMatches(s).length,
        4,
        reason: 'one definition plus the rename, success and rollback arms',
      );
      expect(s, contains('if (-not \$renamed) {'));
    });

    // Nothing in the app can report what the script did -- it runs after the
    // process has exited -- so the transcript is the only channel a failed
    // update has. Every exit goes through Stop-Updater so no arm can leave
    // without recording its code.
    test('records every arm it can end on', () {
      final String s = script();

      expect(s, contains("Join-Path \$PSScriptRoot '$kUpdateLogName'"));
      expect(s, contains('function Stop-Updater'));
      for (final int code in <int>[0, 2, 3, 4]) {
        expect(
          s,
          contains('Stop-Updater $code'),
          reason: 'exit $code must be recorded, not silent',
        );
      }
      expect(
        RegExp(r'^\s*exit \d', multiLine: true).hasMatch(s),
        isFalse,
        reason: 'a bare exit would skip the transcript',
      );
    });

    // With \$ErrorActionPreference = 'Stop', a rollback whose own Move-Item
    // throws would leave the catch block with no handler: the install gone
    // and the script dead.
    test('cannot be killed by its own rollback failing', () {
      expect(script(), contains('catch { }'));
    });

    test('never assigns PowerShell\'s read-only \$pid', () {
      // `$pid` is an automatic variable; assigning it fails at runtime, and
      // the failure would land after the app has already exited.
      expect(script(), contains(r'$parentPid = 4242'));
      expect(script(), isNot(contains(r'$pid =')));
    });

    test('aborts rather than swapping when the app outlives the deadline', () {
      expect(script(), contains(r'AddSeconds(30)'));
      expect(script(), contains('Stop-Updater 2'));
    });

    test('retries the rename against a lingering antivirus handle', () {
      expect(script(), contains(r'for ($i = 0; $i -lt 20; $i++)'));
      expect(script(), contains('Move-Item'));
    });

    test('restores the backup when the copy throws', () {
      final String text = script();
      final int copyAt = text.indexOf('Copy-Item');
      final int restoreAt = text.indexOf(r'Move-Item -LiteralPath $backup');
      expect(copyAt, greaterThan(0));
      expect(restoreAt, greaterThan(copyAt));
      expect(text, contains('Stop-Updater 4'));
    });

    test(
      'doubles an embedded quote instead of escaping it backslash-style',
      () {
        expect(
          script(target: r"C:\Users\o'brien\gbm"),
          contains(r"'C:\Users\o''brien\gbm'"),
        );
      },
    );

    test('passes paths as -LiteralPath so a bracket is not a wildcard', () {
      // PowerShell's -Path globs; `C:\gbm [1]` would match nothing and the
      // update would silently do nothing at all.
      expect(script(), isNot(contains('-Path \$target')));
      expect(script(), contains(r'-LiteralPath $target'));
    });
  });
}
