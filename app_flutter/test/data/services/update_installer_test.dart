import 'dart:ffi';
import 'dart:io';

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
    late Directory staged;
    late Directory scriptDir;

    setUp(() {
      events = <String>[];
      staged = Directory('${root.path}/staged')..createSync(recursive: true);
      scriptDir = Directory('${root.path}/script')..createSync(recursive: true);
    });

    UpdateInstaller installerWith({
      required bool startSucceeds,
      String os = 'linux',
    }) {
      return UpdateInstaller(
        operatingSystem: os,
        executablePath: '${root.path}/install/gbm_flutter',
        exitProcess: (int code) => events.add('exit:$code'),
        start:
            (String exe, List<String> args, {String? workingDirectory}) async {
              events.add('start:$exe');
              return startSucceeds;
            },
      );
    }

    Future<String?> run(UpdateInstaller installer) => installer.launchUpdater(
      staged: staged,
      scriptDir: scriptDir,
      processId: 999999,
      beforeExit: () async => events.add('beforeExit'),
    );

    // The ordering is the safety property. Closing the FFI sessions first
    // means a hang there leaves the app alive with no script running --
    // recoverable -- instead of a detached swap racing a live process.
    test('closes down, starts the script, and only then exits', () async {
      final String? reason = await run(installerWith(startSucceeds: true));

      expect(reason, isNull);
      expect(events, <String>['beforeExit', 'start:sh', 'exit:0']);
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

      final List<String> written = scriptDir
          .listSync()
          .map((e) => e.path)
          .toList();
      expect(written, hasLength(1));
      expect(written.single, endsWith('.sh'));
      expect(
        written.single,
        isNot(startsWith('${root.path}/install')),
        reason: 'a script inside the target would be moved aside mid-run',
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
              true,
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
      await run(installerWith(startSucceeds: true, os: 'windows'));

      expect(events.first, 'beforeExit');
      expect(events, contains('start:powershell'));
      expect(File('${scriptDir.path}/gbm-update.ps1').existsSync(), isTrue);
    });
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

    test('never assigns PowerShell\'s read-only \$pid', () {
      // `$pid` is an automatic variable; assigning it fails at runtime, and
      // the failure would land after the app has already exited.
      expect(script(), contains(r'$parentPid = 4242'));
      expect(script(), isNot(contains(r'$pid =')));
    });

    test('aborts rather than swapping when the app outlives the deadline', () {
      expect(script(), contains(r'AddSeconds(30)'));
      expect(script(), contains('exit 2'));
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
      expect(text, contains('exit 4'));
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
