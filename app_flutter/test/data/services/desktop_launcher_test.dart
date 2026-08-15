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
      expect(
        starter.args.last,
        <String>['-NoExit', '-Command', 'cd "C:\\dev\\repo"'],
      );
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
      expect(
        starter.args.single,
        <String>['--working-directory=/home/x/my repo; rm -rf /'],
        reason: 'arguments are passed as a list, never through a shell',
      );
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

    test('Windows passes an empty title before the URL', () async {
      final _RecordingStarter starter = _RecordingStarter(
        available: <String>{'cmd'},
      );
      final DesktopLauncher launcher = DesktopLauncher(
        start: starter.call,
        operatingSystem: 'windows',
      );

      await launcher.openUrl('https://example.com');
      expect(
        starter.args.single,
        <String>['/c', 'start', '', 'https://example.com'],
        reason: 'without the title argument, start consumes the URL as one',
      );
    });
  });
}
