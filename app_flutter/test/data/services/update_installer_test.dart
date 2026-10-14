import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/prepared_update.dart';
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
    if (root.existsSync()) root.deleteSync(recursive: true);
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
    // to fail a real write rather than fake a stat. A parent that does not
    // exist does that for every user on every OS -- where a `chmod 555`
    // fixture is ignored by root and means nothing on Windows.
    test('blocks when the install directory cannot be written', () {
      final Directory install = Directory('${root.path}/gone/gbm');
      expect(install.parent.existsSync(), isFalse);

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

    // On Windows the release ships as an MSI, and only the copy Windows
    // Installer manages may update itself: msiexec is handed the folder the
    // installer recorded, so a copy anywhere else -- a portable zip from an
    // older release, or the installed folder copied elsewhere -- would have
    // the upgrade land on top of some *other* folder.
    group('on Windows', () {
      UpdateInstaller windowsInstaller(
        Directory install, {
        required String? registered,
      }) {
        return UpdateInstaller(
          operatingSystem: 'windows',
          executablePath: '${install.path}/gbm_flutter.exe',
          abi: Abi.windowsX64,
          homeDirectory: '${root.path}/home',
          readInstallLocation: () => registered,
        );
      }

      test('the installed copy may update itself', () {
        final Directory install = Directory('${root.path}/Programs/gbm')
          ..createSync(recursive: true);

        expect(
          windowsInstaller(
            install,
            registered: '${install.path.toUpperCase()}\\',
          ).selfInstallBlocker(),
          isNull,
          reason:
              'the installer records the folder with a trailing '
              'backslash, and Windows paths compare case-insensitively',
        );
      });

      test('a copy the installer never registered is sent to the page', () {
        final Directory install = Directory('${root.path}/Programs/gbm')
          ..createSync(recursive: true);

        final String? reason = windowsInstaller(
          install,
          registered: null,
        ).selfInstallBlocker();

        expect(reason, contains('installer'));
        expect(reason, contains('releases page'));
      });

      test('a copy of the installed folder elsewhere is sent there too', () {
        final Directory install = Directory('${root.path}/Desktop/gbm')
          ..createSync(recursive: true);

        final String? reason = windowsInstaller(
          install,
          registered: '${root.path}/Programs/gbm',
        ).selfInstallBlocker();

        expect(reason, contains('releases page'));
      });

      // Only Windows has an installer registration; the seam is never even
      // consulted elsewhere.
      test('is never asked on another platform', () {
        final Directory install = Directory('${root.path}/opt/gbm')
          ..createSync(recursive: true);
        bool asked = false;

        UpdateInstaller(
          operatingSystem: 'linux',
          executablePath: '${install.path}/gbm_flutter',
          abi: Abi.linuxX64,
          readInstallLocation: () {
            asked = true;
            return install.path;
          },
        ).selfInstallBlocker();

        expect(asked, isFalse);
      });
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

    /// A real file at [name] and the digest of what it holds, since
    /// [UpdateInstaller.stage] reads the bundle back before using it.
    File bundle(String name) =>
        File('${root.path}/$name')..writeAsStringSync('bundle');
    final String digest = sha256.convert(utf8.encode('bundle')).toString();

    // The bundle sits in a temp directory between download and install, for
    // as long as the user leaves it there. Unpacking a file that is no
    // longer the one verified would hand the updater whatever replaced it.
    for (final String os in <String>['linux', 'macos', 'windows']) {
      test('refuses a bundle changed since verification on $os', () async {
        final UpdateInstaller installer = UpdateInstaller(
          operatingSystem: os,
          run: recorder(),
        );

        await expectLater(
          installer.stage(bundle: bundle('x'), into: root, sha256: 'f' * 64),
          throwsA(
            isA<UpdateInstallException>().having(
              (UpdateInstallException e) => e.message,
              'message',
              contains('changed since it was verified'),
            ),
          ),
        );
        expect(ran, isEmpty, reason: 'nothing may be run on a stale bundle');
      });
    }

    test('refuses a bundle that has gone missing', () async {
      final UpdateInstaller installer = UpdateInstaller(
        operatingSystem: 'linux',
        run: recorder(),
      );

      await expectLater(
        installer.stage(
          bundle: File('${root.path}/swept'),
          into: root,
          sha256: digest,
        ),
        throwsA(isA<UpdateInstallException>()),
      );
      expect(ran, isEmpty);
    });

    test('descends the Linux tarball\'s single wrapper directory', () async {
      final UpdateInstaller installer = UpdateInstaller(
        operatingSystem: 'linux',
        run: recorder(
          onRun: (String exe, List<String> args) {
            // `tar xzf <bundle> -C <payload>` -- reproduce what release.yml's
            // `tar czf … "$name"` actually produces.
            Directory('${args.last}/git-branch-manager-0.31.0-linux-x86_64')
                .createSync(recursive: true);
          },
        ),
      );

      final PreparedUpdate staged = await installer.stage(
        bundle: bundle('x.tar.gz'),
        into: root,
        sha256: digest,
      );

      expect(ran.single.take(2), <String>['tar', 'xzf']);
      expect(
        (staged as PreparedDirectory).directory.path,
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

      final PreparedUpdate staged = await installer.stage(
        bundle: bundle('x.tar.gz'),
        into: root,
        sha256: digest,
      );

      expect((staged as PreparedDirectory).directory.path, endsWith('payload'));
    });

    // Windows Installer does the replacing, so there is nothing to unpack:
    // the verified package itself is what the updater hands to msiexec.
    test('hands the Windows installer package over unopened', () async {
      final UpdateInstaller installer = UpdateInstaller(
        operatingSystem: 'windows',
        run: recorder(),
      );
      final File msi = bundle('x.msi');

      final PreparedUpdate prepared = await installer.stage(
        bundle: msi,
        into: root,
        sha256: digest,
      );

      expect(prepared, PreparedInstallerPackage(package: msi, sha256: digest));
      expect(ran, isEmpty, reason: 'an MSI is never extracted');
    });

    test('mounts, dittos out of, and unmounts the macOS disk image', () async {
      final UpdateInstaller installer = UpdateInstaller(
        operatingSystem: 'macos',
        run: recorder(
          onRun: (String exe, List<String> args) {
            if (exe == 'hdiutil' && args.first == 'attach') {
              Directory('${root.path}/mnt/gbm_flutter.app')
                  .createSync(recursive: true);
            }
          },
        ),
      );

      await installer.stage(
        bundle: bundle('x.dmg'),
        into: root,
        sha256: digest,
      );

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
        () => installer.stage(bundle: bundle('x'), into: root, sha256: digest),
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
              Directory('${root.path}/mnt/gbm_flutter.app')
                  .createSync(recursive: true);
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
        await installer.stage(
          bundle: bundle('x.dmg'),
          into: root,
          sha256: digest,
        );

        expect(detachAttempts, greaterThan(1));
      },
    );
  });

  group('launchUpdater', () {
    late List<String> events;
    late List<String?> startedIn;
    late Directory staged;
    late PreparedInstallerPackage package;
    late Directory scriptDir;

    setUp(() {
      events = <String>[];
      startedIn = <String?>[];
      staged = Directory('${root.path}/staged')..createSync(recursive: true);
      package = PreparedInstallerPackage(
        package: File('${root.path}/download/x.msi'),
        sha256: 'ab' * 32,
      );
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
        readInstallLocation: () =>
            os == 'windows' ? '${root.path}/install' : null,
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

    /// The shape each platform's [UpdateInstaller.stage] really produces.
    PreparedUpdate preparedFor(String? os) =>
        os == 'windows' ? package : PreparedDirectory(staged);

    Future<String?> run(UpdateInstaller installer) => installer.launchUpdater(
      staged: preparedFor(installer.operatingSystem),
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
        staged: PreparedDirectory(staged),
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

      final String log = File('${scriptDir.path}/$kUpdateLogName')
          .readAsStringSync();
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

      final String log = File('${scriptDir.path}/$kUpdateLogName')
          .readAsStringSync();
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

    // Windows only ever updates through the installer now. A directory swap
    // reaching `launchUpdater` there would be a bug upstream, and the swap
    // script it would write is exactly what an installer-managed copy must
    // never get -- so it is refused here too, before anything is written.
    test('writes no swap script on Windows', () async {
      final List<String> started = <String>[];
      final String? reason =
          await UpdateInstaller(
            operatingSystem: 'windows',
            executablePath: '${root.path}/install/gbm_flutter.exe',
            readInstallLocation: () => '${root.path}/install',
            exitProcess: (int code) => events.add('exit:$code'),
            start:
                (String e, List<String> a, {String? workingDirectory}) async {
                  started.add(e);
                  return const DetachedStart.ok();
                },
          ).launchUpdater(
            staged: PreparedDirectory(staged),
            scriptDir: scriptDir,
            processId: 999999,
            beforeExit: () async => events.add('beforeExit'),
          );

      expect(reason, contains('installer'));
      expect(started, isEmpty);
      expect(events, isEmpty);
      expect(File('${scriptDir.path}/gbm-update.ps1').existsSync(), isFalse);
    });

    // The folder msiexec installs into is the one the installer recorded,
    // re-read at the last moment rather than trusted from the check.
    test('refuses when the installer registration has gone', () async {
      final String? reason =
          await UpdateInstaller(
            operatingSystem: 'windows',
            executablePath: '${root.path}/install/gbm_flutter.exe',
            readInstallLocation: () => null,
            exitProcess: (int code) => events.add('exit:$code'),
            start: (
              String e,
              List<String> a, {
              String? workingDirectory,
            }) async => const DetachedStart.ok(),
          ).launchUpdater(
            staged: package,
            scriptDir: scriptDir,
            processId: 999999,
            beforeExit: () async => events.add('beforeExit'),
          );

      expect(reason, contains('installer'));
      expect(events, isEmpty);
      expect(File('${scriptDir.path}/gbm-update.ps1').existsSync(), isFalse);
    });

    // msiexec installs into the recorded folder, so a registration naming a
    // folder other than the one running would upgrade that other folder.
    test('refuses when the registration names another folder', () async {
      final String? reason =
          await UpdateInstaller(
            operatingSystem: 'windows',
            executablePath: '${root.path}/install/gbm_flutter.exe',
            readInstallLocation: () => '${root.path}/elsewhere',
            exitProcess: (int code) => events.add('exit:$code'),
            start: (
              String e,
              List<String> a, {
              String? workingDirectory,
            }) async => const DetachedStart.ok(),
          ).launchUpdater(
            staged: package,
            scriptDir: scriptDir,
            processId: 999999,
            beforeExit: () async => events.add('beforeExit'),
          );

      expect(reason, contains('installer'));
      expect(events, isEmpty);
      expect(File('${scriptDir.path}/gbm-update.ps1').existsSync(), isFalse);
    });

    test('hands msiexec the recorded folder and the verified digest', () async {
      await run(installerWith(startSucceeds: true, os: 'windows'));

      final String script = File('${scriptDir.path}/gbm-update.ps1')
          .readAsStringSync();
      expect(script, contains("\$target = '${root.path}/install'"));
      expect(script, contains("\$package = '${root.path}/download/x.msi'"));
      expect(script, contains("\$expectedHash = '${'ab' * 32}'"));
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

      final String script = File('${scriptDir.path}/gbm-update.sh')
          .readAsStringSync();
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

      final String script = File('${scriptDir.path}/gbm-update.sh')
          .readAsStringSync();
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
        readInstallLocation: () => '${root.path}/install',
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
        staged: package,
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

      final Uint8List bytes = File('${scriptDir.path}/gbm-update.ps1')
          .readAsBytesSync();
      expect(bytes.take(3), <int>[0xEF, 0xBB, 0xBF]);
    });

    // `sh` has the opposite requirement: a BOM on the first line is a syntax
    // error, not a hint.
    test('writes the sh script without a BOM', () async {
      await run(installerWith(startSucceeds: true));

      final Uint8List bytes = File('${scriptDir.path}/gbm-update.sh')
          .readAsBytesSync();
      expect(bytes.first, 0x23, reason: 'must start with the shebang #');
    });

    test('a non-ASCII install path survives the round trip', () async {
      final Directory nonAscii = Directory('${root.path}/使用者/gbm')
        ..createSync(recursive: true);
      await UpdateInstaller(
        operatingSystem: 'windows',
        executablePath: '${nonAscii.path}/gbm_flutter.exe',
        readInstallLocation: () => nonAscii.path,
        exitProcess: (int code) => events.add('exit:$code'),
        start: (
          String exe,
          List<String> args, {
          String? workingDirectory,
        }) async => const DetachedStart.ok(),
      ).launchUpdater(
        staged: package,
        scriptDir: scriptDir,
        processId: 999999,
        beforeExit: () async {},
      );

      expect(
        File('${scriptDir.path}/gbm-update.ps1').readAsStringSync(),
        contains(nonAscii.path),
      );
    });

    // The executable's name is cut with the separators of the OS being
    // updated, not of the host running this code. On a real machine the two
    // are the same, which is why it went unseen: a Windows host handed a
    // POSIX-shaped path (every fixture in this file, and the golden's) cut
    // nothing at all and baked the whole path into `Join-Path $target '...'`.
    group('the executable name in the relaunch command', () {
      Future<String> scriptFor(String os, String exe) async {
        // Registered at wherever this executable resolves to, so the
        // installer-registration gate is out of the way of what is asserted.
        late final UpdateInstaller installer;
        installer = UpdateInstaller(
          operatingSystem: os,
          executablePath: exe,
          readInstallLocation: () => installer.installTarget().path,
          exitProcess: (int code) => events.add('exit:$code'),
          armWatchdog: (Duration after) async => true,
          start: (String e, List<String> a, {String? workingDirectory}) async =>
              const DetachedStart.ok(),
        );
        await installer.launchUpdater(
          staged: preparedFor(os),
          scriptDir: scriptDir,
          processId: 999999,
          beforeExit: () async {},
        );
        return File(
          '${scriptDir.path}/gbm-update.${os == 'windows' ? 'ps1' : 'sh'}',
        ).readAsStringSync();
      }

      for (final String exe in <String>[
        r'C:\Program Files\gbm\gbm_flutter.exe',
        '/opt/gbm/gbm_flutter.exe',
      ]) {
        test('is cut out of $exe for Windows, either separator', () async {
          expect(
            await scriptFor('windows', exe),
            contains(r"(Join-Path $target 'gbm_flutter.exe')"),
          );
        });
      }

      test('is cut out of a POSIX path for Linux', () async {
        expect(
          await scriptFor('linux', '/opt/gbm/gbm_flutter'),
          contains(r'"$TARGET/gbm_flutter" >/dev/null 2>&1 &'),
        );
      });

      // The counterpart that stops the lazy fix -- splitting on both
      // separators everywhere. A backslash is an ordinary character in a
      // POSIX file name, so cutting on it would relaunch the wrong binary.
      test('keeps a backslash inside a Linux file name', () async {
        expect(
          await scriptFor('linux', r'/opt/gbm/my\app'),
          contains(r'"$TARGET/my\app" >/dev/null 2>&1 &'),
        );
      });
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

  // The script runs after the app has exited, so nothing in the app can
  // report what it did; its arms are pinned here as text, `cq.yml`'s
  // `powershell-parse` job parses the golden, and the round's manual pass on
  // a real Windows machine is what executes it end to end.
  group('the Windows MSI script', () {
    const String digest =
        '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

    String script({
      String installFolder =
          r'C:\Users\jane\AppData\Local\Programs\Git Branch Manager',
      String packagePath =
          r'C:\Users\jane\AppData\Local\Temp\gbm-update-x\a.msi',
    }) => buildWindowsMsiUpdaterScript(
      pid: 4242,
      installFolder: installFolder,
      packagePath: packagePath,
      sha256: digest,
      relaunchCommand: 'Start-Process x',
      waitTimeout: const Duration(seconds: 30),
    );

    /// The text of the `if (...) {` block opening at [opening], up to its
    /// first closing brace at the same indent.
    String block(String text, String opening) {
      final int at = text.indexOf(opening);
      expect(at, greaterThanOrEqualTo(0), reason: 'no "$opening"');
      final int close = text.indexOf('\n}', at);
      return text.substring(at, close);
    }

    // `Set-Location` alone moves PowerShell's provider location while the
    // Win32 process directory stays where the process was created; only
    // assigning CurrentDirectory releases it.
    test('steps out of whatever directory it inherited', () {
      expect(script(), contains(r'Set-Location -LiteralPath $PSScriptRoot'));
      expect(
        script(),
        contains(r'[System.Environment]::CurrentDirectory = $PSScriptRoot'),
      );
    });

    test('never assigns PowerShell\'s read-only \$pid', () {
      expect(script(), contains(r'$parentPid = 4242'));
      expect(script(), isNot(contains(r'$pid =')));
    });

    // Timing out must leave everything untouched -- and nothing relaunched,
    // because the app is by definition still on screen.
    test('gives up without installing or relaunching at the deadline', () {
      final String s = script();
      final String wait = block(s, r'while (Get-Process -Id $parentPid');

      expect(s, contains('AddSeconds(30)'));
      expect(wait, contains('Stop-Updater 2'));
      expect(wait, isNot(contains('Restart-App')));
      expect(s.indexOf('Stop-Updater 2'), lessThan(s.indexOf('Get-FileHash')));
    });

    // The package waited in a temp directory for as long as the user left
    // the dialog open; it is checked again right before msiexec gets it.
    test('re-checks the package digest before msiexec is started', () {
      final String s = script();

      expect(s, contains("\$expectedHash = '$digest'"));
      expect(
        s,
        contains('Get-FileHash -LiteralPath \$package -Algorithm SHA256'),
      );
      expect(
        s.indexOf('Get-FileHash'),
        lessThan(s.indexOf(r'Start-Process -FilePath $msiexec')),
      );
    });

    test('a digest mismatch installs nothing and relaunches the old build', () {
      final String mismatch = block(
        script(),
        r'if ($actualHash -ne $expectedHash) {',
      );

      expect(mismatch, contains('Stop-Updater 6'));
      expect(mismatch, contains('Restart-App'));
      expect(mismatch, isNot(contains('Start-Process')));
    });

    // A bare `msiexec.exe` is resolved by searching, and the script stands
    // in the temp directory -- the same reason the updater itself starts
    // PowerShell by absolute path.
    test('starts msiexec by its absolute path', () {
      final String s = script();

      expect(
        s,
        contains(
          r"$msiexec = Join-Path $env:SystemRoot 'System32\msiexec.exe'",
        ),
      );
      expect(
        s,
        contains(r'Start-Process -FilePath $msiexec -ArgumentList $arguments'),
      );
    });

    test('runs a passive, logged install into the recorded folder', () {
      final String s = script();

      expect(
        s,
        contains(
          r"""$arguments = '/i "' + $package + '" /passive /norestart """
          r"""INSTALLFOLDER="' + $target + '" /l*v "' + $msiLog + '"'""",
        ),
      );
      expect(s, contains('-Wait -PassThru'));
    });

    test('only exit code 0 counts as installed', () {
      final String s = script();
      final String installed = block(s, r'if ($code -eq 0) {');

      expect(installed, contains('Restart-App'));
      expect(installed, contains('Stop-Updater 0'));
      expect(
        'Stop-Updater 0'.allMatches(s),
        hasLength(1),
        reason: 'no other arm may report success',
      );
    });

    // 3010/1641 mean files are queued for replacement at the next Windows
    // restart: relaunching now would start a mix of old and new DLLs.
    test('a reboot-required install exits 7 without relaunching', () {
      final String reboot = block(
        script(),
        r'if ($code -eq 3010 -or $code -eq 1641) {',
      );

      expect(reboot, contains('Stop-Updater 7'));
      expect(reboot, isNot(contains('Restart-App')));
    });

    test('a failed install exits 5 and relaunches the rolled-back build', () {
      final String s = script();
      final String tail = s.substring(s.lastIndexOf('Stop-Updater 7'));

      expect(tail, contains('Restart-App'));
      expect(tail, contains('Stop-Updater 5'));
    });

    test('records every arm it can end on', () {
      final String s = script();

      expect(s, contains("Join-Path \$PSScriptRoot '$kUpdateLogName'"));
      for (final int code in <int>[0, 2, 5, 6, 7]) {
        expect(s, contains('Stop-Updater $code'), reason: 'exit $code');
      }
      expect(
        RegExp(r'^\s*exit \d', multiLine: true).hasMatch(s),
        isFalse,
        reason: 'a bare exit would skip the transcript',
      );
    });

    // msiexec normalises a directory property to end in a backslash, and a
    // backslash right before the closing quote reads as an escaped quote to
    // anything parsing the command line the CommandLineToArgvW way.
    test('drops the recorded folder\'s trailing separator', () {
      expect(
        script(installFolder: r'C:\Programs\Git Branch Manager\'),
        contains(r"$target = 'C:\Programs\Git Branch Manager'"),
      );
    });

    // Every value baked into the script reaches PowerShell only as a
    // single-quoted literal, which interpolates nothing. Anything else --
    // a double-quoted string, a bare word -- would let a folder name run
    // code or add msiexec properties of its own.
    group('a hostile path', () {
      const List<String> hostile = <String>[
        r"C:\Users\o'brien\HOSTILE",
        r'C:\Users\$(calc)\HOSTILE',
        r'C:\Users\$env:TEMP\HOSTILE',
        r'C:\Users\back`tick\HOSTILE',
        r'C:\Users\a & b; c\HOSTILE',
        r'C:\Users\(paren)\HOSTILE',
        r'C:\Users\TRANSFORMS=x.mst HOSTILE',
        r'C:\Users\使用者 名\HOSTILE',
      ];

      String withoutLiterals(String text) =>
          text.replaceAll(RegExp(r"'(?:[^']|'')*'"), "''");

      for (final String path in hostile) {
        test('stays inside single quotes: $path', () {
          final String s = script(
            installFolder: path,
            packagePath: '$path\\x.msi',
          );

          expect(s, contains("'${path.replaceAll("'", "''")}'"));
          expect(
            withoutLiterals(s),
            isNot(contains('HOSTILE')),
            reason: 'the path appears outside a single-quoted literal',
          );
        });
      }

      // The text assertions above cannot see a syntax error; PowerShell's
      // own parser can, and every Windows host running this suite has it.
      test('parses cleanly in Windows PowerShell', () {
        final Directory dir = Directory.systemTemp.createTempSync('gbm-ps');
        addTearDown(() => dir.deleteSync(recursive: true));
        for (int i = 0; i < hostile.length; i++) {
          File('${dir.path}\\s$i.ps1').writeAsStringSync(
            '\uFEFF${script(installFolder: hostile[i], packagePath: '${hostile[i]}\\x.msi')}',
          );
        }
        final ProcessResult result = Process.runSync('powershell.exe', <String>[
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          r"$bad = 0; Get-ChildItem -LiteralPath '"
              '${dir.path}'
              r"' -Filter *.ps1 | ForEach-Object { $t = $null; $e = $null; "
              r'[void][System.Management.Automation.Language.Parser]::ParseFile('
              r'$_.FullName, [ref]$t, [ref]$e); if ($e.Count -gt 0) { '
              r'Write-Output "$($_.Name): $($e[0].Message)"; $bad++ } }; exit $bad',
        ]);

        expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      }, skip: !Platform.isWindows ? 'needs Windows PowerShell' : false);
    });
  });
}
