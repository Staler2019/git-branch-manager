import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/services/desktop_launcher.dart';

/// Records every attempt and reports success only for executables in
/// [available], which is how the fallback chains are exercised without
/// spawning anything.
class _RecordingStarter {
  _RecordingStarter({required this.available});

  final Set<String> available;
  final List<String> attempted = <String>[];
  final List<List<String>> args = <List<String>>[];
  final List<String?> workingDirs = <String?>[];

  Future<bool> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    attempted.add(executable);
    args.add(arguments);
    workingDirs.add(workingDirectory);
    return available.contains(executable);
  }
}

void main() {
  group('openTerminal', () {
    test('Windows uses wt.exe with -d, per the spec TERMINALS table', () async {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{'wt.exe'},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'windows',
      );

      expect(await launcher.openTerminal(r'C:\dev\repo'), isTrue);
      expect(starter.attempted, <String>['wt.exe']);
      expect(starter.args.single, <String>['-d', r'C:\dev\repo']);
    });

    test('Windows falls back to powershell when wt.exe is missing', () async {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{'powershell.exe'},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'windows',
      );

      expect(await launcher.openTerminal(r'C:\dev\repo'), isTrue);
      expect(starter.attempted, <String>['wt.exe', 'powershell.exe']);
      expect(starter.args.last, <String>['-NoExit']);
      expect(starter.workingDirs.last, r'C:\dev\repo');
    });

    // `cd "$path"` was a double-quoted PowerShell string: a folder named
    // `$(calc)` was run, not entered. The directory now travels only as the
    // working directory.
    test('Windows never puts the path into a PowerShell command', () async {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{'powershell.exe'},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'windows',
      );

      await launcher.openTerminal(r'C:\dev\$(calc)');
      expect(starter.args.last, isNot(contains(contains('calc'))));
    });

    test('macOS opens Terminal.app', () async {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{'open'},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'macos',
      );

      expect(await launcher.openTerminal('/Users/x/repo'), isTrue);
      expect(starter.attempted, <String>['open']);
      expect(starter.args.single, <String>['-a', 'Terminal', '/Users/x/repo']);
    });

    test('Linux tries the spec chain in order', () async {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{'konsole'},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'linux',
      );

      expect(await launcher.openTerminal('/home/x/repo'), isTrue);
      expect(starter.attempted, <String>[
        'x-terminal-emulator',
        'gnome-terminal',
        'konsole',
      ]);
      expect(starter.args.last, <String>['--workdir', '/home/x/repo']);
    });

    test('returns false when every candidate is missing', () async {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'linux',
      );

      expect(await launcher.openTerminal('/home/x/repo'), isFalse);
      expect(starter.attempted, hasLength(4), reason: 'xterm is tried last');
    });

    test('every candidate also inherits the working directory', () async {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'linux',
      );

      await launcher.openTerminal('/home/x/repo');
      expect(
        starter.workingDirs,
        everyElement('/home/x/repo'),
        reason:
            'a terminal whose directory flag this build does not understand '
            'must still land in the repository, not the home directory',
      );
    });

    test('a path with spaces stays a single argument', () async {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{'x-terminal-emulator'},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'linux',
      );

      await launcher.openTerminal('/home/x/my repo; rm -rf /');
      expect(starter.args.single, <String>[
        '--working-directory=/home/x/my repo; rm -rf /',
      ], reason: 'arguments are passed as a list, never through a shell');
    });
  });

  group('openUrl', () {
    test('macOS uses open', () async {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{'open'},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'macos',
      );

      expect(await launcher.openUrl(GbmUrls.documentation), isTrue);
      expect(starter.args.single, <String>[GbmUrls.documentation]);
    });

    test('Linux uses xdg-open', () async {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{'xdg-open'},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'linux',
      );

      expect(await launcher.openUrl(GbmUrls.reportAnIssue), isTrue);
      expect(starter.attempted, <String>['xdg-open']);
    });

    // `cmd /c start` is a console program, and started detached on Windows
    // it never ran: Help's links and the update dialog's release page opened
    // nothing. The URL itself is handed over, opened by its association.
    test('Windows hands the URL itself over, with no cmd', () async {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{'https://example.com'},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'windows',
      );

      expect(await launcher.openUrl('https://example.com'), isTrue);
      expect(starter.attempted, <String>['https://example.com']);
      expect(starter.args.single, isEmpty);
    });
  });

  group('openFile (05-F "Open file")', () {
    test('macOS hands the path to open', () async {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{'open'},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'macos',
      );

      expect(await launcher.openFile('/dev/repo/lib/main.dart'), isTrue);
      expect(starter.attempted, <String>['open']);
      expect(starter.args.single, <String>['/dev/repo/lib/main.dart']);
    });

    test('Linux uses xdg-open', () async {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{'xdg-open'},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'linux',
      );

      expect(await launcher.openFile('/dev/repo/lib/main.dart'), isTrue);
      expect(starter.attempted, <String>['xdg-open']);
    });

    test('Windows hands the normalized path itself over, with no cmd', () {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{r'C:\dev\repo\lib\main.dart'},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'windows',
      );

      return launcher.openFile('C:/dev/repo/lib/main.dart').then((bool ok) {
        expect(ok, isTrue);
        expect(starter.attempted, <String>[r'C:\dev\repo\lib\main.dart']);
        expect(starter.args.single, isEmpty);
      });
    });

    // The real starter, not a recording: `cmd /c start` started detached
    // reported success for anything, including this, and ran nothing.
    test('Windows reports a file that is not there as not opened', () async {
      final Directory dir = Directory.systemTemp.createTempSync('gbm open ');
      addTearDown(() => dir.deleteSync(recursive: true));

      expect(
        await const DesktopLauncher().openFile('${dir.path}\\absent.txt'),
        isFalse,
      );
    }, skip: Platform.isWindows ? false : 'Windows only');

    test('returns false when the launcher executable is missing', () async {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'macos',
      );

      expect(await launcher.openFile('/dev/repo/lib/main.dart'), isFalse);
    });
  });

  group('openInFileManager (05-A/05-F "Show in file manager")', () {
    test('macOS reveals the item with -R rather than opening it', () async {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{'open'},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'macos',
      );

      expect(
        await launcher.openInFileManager('/dev/repo/lib/main.dart'),
        isTrue,
      );
      expect(starter.args.single, <String>['-R', '/dev/repo/lib/main.dart']);
    });

    test('Linux has no portable reveal, so it opens the path itself', () async {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{'xdg-open'},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'linux',
      );

      await launcher.openInFileManager('/dev/repo/lib/main.dart');
      expect(starter.args.single, <String>['/dev/repo/lib/main.dart']);
    });

    test(
      'Windows normalizes separators -- explorer /select, silently falls back '
      'to opening Documents when handed forward slashes',
      () async {
        final _RecordingStarter starter = _RecordingStarter(
          available: <String>{'explorer.exe'},
        );
        final DesktopLauncher launcher = DesktopLauncher(
          start: starter.call,
          operatingSystem: 'windows',
        );

        await launcher.openInFileManager('C:/dev/repo/lib/main.dart');
        expect(starter.args.single, <String>[
          '/select,',
          r'C:\dev\repo\lib\main.dart',
        ]);
      },
    );

    // Measured: explorer handed `"/select,C:\a b\f.txt"` -- one argument,
    // quoted whole because of the space -- opens Documents and selects
    // nothing. `/select, "C:\a b\f.txt"` selects the file, so the path is its
    // own argument and only it is quoted.
    test(
      'Windows passes the path as its own argument after /select,',
      () async {
        final _RecordingStarter starter = _RecordingStarter(
          available: <String>{'explorer.exe'},
        );
        final DesktopLauncher launcher = DesktopLauncher(
          start: starter.call,
          operatingSystem: 'windows',
        );

        await launcher.openInFileManager(r'C:\Users\Jane Doe\repo\a.txt');
        expect(starter.args.single, <String>[
          '/select,',
          r'C:\Users\Jane Doe\repo\a.txt',
        ]);
      },
    );
  });
}
