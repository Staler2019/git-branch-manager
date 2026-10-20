import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/external_app_entry.dart';
import 'detached_process.dart';

/// Starts a detached OS process. Injected rather than calling
/// [Process.start] directly so the platform-specific candidate chains below
/// can be widget/unit-tested without actually spawning a terminal -- the
/// same testability rationale as `GbmBindings` being injected through
/// `gbmBindingsProvider` instead of opening the real `.so` at import time.
///
/// Returns `true` if the process started, `false` if the executable was not
/// found (which is what drives the fallback chains). Implementations must
/// not throw for a missing executable.
typedef ProcessStarter = Future<bool> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

/// Starts a process in normal mode and hands it back, so
/// [DesktopLauncher.openExternalApp] can watch its exit code and stderr --
/// which a detached start ([ProcessStarter]) cannot. Defaults to
/// [Process.start]; injected so tests drive a fake [Process].
typedef ProcessSpawner = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

/// What [DesktopLauncher.openExternalApp] decided.
sealed class ExternalAppLaunchResult {
  const ExternalAppLaunchResult();
}

final class ExternalAppStarted extends ExternalAppLaunchResult {
  const ExternalAppStarted();
}

final class ExternalAppLaunchFailed extends ExternalAppLaunchResult {
  const ExternalAppLaunchFailed(this.message);

  /// Shown verbatim after 「無法執行「<label>」：」.
  final String message;
}

/// One candidate in a platform's fallback chain: the executable to try and
/// the arguments to pass it. A candidate may carry no directory flag of its
/// own (plain `xterm`), relying solely on the spawned process inheriting
/// `workingDirectory`.
class _TerminalCandidate {
  const _TerminalCandidate(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

/// Opens a terminal emulator in a repository's working directory, and hands
/// URLs to the OS default browser.
///
/// The terminal command tables are verbatim from spec page 02's `TERMINALS`
/// data (`wt.exe -d "{path}"` with a `powershell.exe` fallback on Windows,
/// `open -a Terminal "{path}"` on macOS, `x-terminal-emulator
/// --working-directory="{path}"` on Linux "依序試 gnome-terminal、konsole、
/// xterm"). Backs the Repository → Open in terminal menu item and the
/// "Open terminal here" entries in context menus 05-A / 05-F / 05-K.
///
/// Every candidate is also spawned with `workingDirectory` set, so a
/// terminal whose directory flag this build of it does not understand still
/// lands in the right place rather than in the user's home directory.
/// Arguments are passed as a list -- never interpolated into a shell string
/// -- so a repository path containing spaces, quotes or shell metacharacters
/// cannot turn into a command injection.
class DesktopLauncher {
  const DesktopLauncher({
    ProcessStarter? start,
    ProcessSpawner? spawn,
    this.operatingSystem,
    this.environment,
    this.exitWait = const Duration(seconds: 5),
  }) : _start = start ?? _startDetached,
       _spawn = spawn ?? Process.start;

  final ProcessStarter _start;
  final ProcessSpawner _spawn;

  /// Overridden in tests; null means [Platform.environment].
  final Map<String, String>? environment;

  /// How long [openExternalApp] waits for an exit code (ruling D3).
  final Duration exitWait;

  Map<String, String> get _env => environment ?? Platform.environment;

  /// Overridden in tests; null means [Platform.operatingSystem].
  final String? operatingSystem;

  String get _os => operatingSystem ?? Platform.operatingSystem;

  /// [startDetachedProcess], which on Windows relays through
  /// `Start-Process` because a console program started detached there never
  /// runs -- `cmd /c start` and the `powershell.exe` fallback both opened
  /// nothing. The window is shown: everything here is something the user
  /// asked to see. A missing executable is a failed start, which is what
  /// moves the caller to the next candidate in the chain.
  static Future<bool> _startDetached(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    final DetachedStart outcome = await startDetachedProcess(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      window: RelayWindow.normal,
    );
    return outcome.started;
  }

  /// The ordered candidate chain for [_os], per the spec's `TERMINALS` table.
  List<_TerminalCandidate> _terminalCandidates(String path) {
    switch (_os) {
      case 'windows':
        return <_TerminalCandidate>[
          _TerminalCandidate('wt.exe', <String>['-d', path]),
          // No `cd` command: a path inside a double-quoted PowerShell
          // string is interpolated, so a folder named `$(calc)` would be
          // run. The inherited workingDirectory is the directory.
          const _TerminalCandidate('powershell.exe', <String>['-NoExit']),
        ];
      case 'macos':
        return <_TerminalCandidate>[
          _TerminalCandidate('open', <String>['-a', 'Terminal', path]),
        ];
      default:
        return <_TerminalCandidate>[
          _TerminalCandidate('x-terminal-emulator', <String>[
            '--working-directory=$path',
          ]),
          _TerminalCandidate('gnome-terminal', <String>[
            '--working-directory=$path',
          ]),
          _TerminalCandidate('konsole', <String>['--workdir', path]),
          // No directory flag -- relies on the inherited workingDirectory.
          const _TerminalCandidate('xterm', <String>[]),
        ];
    }
  }

  /// Opens a terminal at [path], trying each candidate for the current
  /// platform in order. Returns `false` only if every candidate is missing,
  /// which callers surface as an operation-log line rather than a dialog
  /// (spec page 10: background failures do not open windows).
  Future<bool> openTerminal(String path) async {
    for (final _TerminalCandidate candidate in _terminalCandidates(path)) {
      final bool started = await _start(
        candidate.executable,
        candidate.arguments,
        workingDirectory: path,
      );
      if (started) return true;
    }
    return false;
  }

  /// Runs [app]'s command in the worktree at [path] -- the worktree panel's
  /// ▾ list (open-with-apps-spec.html). Never throws: every way it can go
  /// wrong is an [ExternalAppLaunchFailed] ~~the caller paints as a
  /// SnackBar~~ that `openExternalAppAction` turns into an error line in the
  /// Log through AppActionRunner (ruling R4; no toast, P10 #3).
  ///
  /// macOS/Linux, working directory [path]:
  /// `<shell> -lic '{ <command>\n} </dev/null >/dev/null' gbm <path>`.
  /// - The shell is `$SHELL` only when it is an absolute path to a POSIX
  ///   shell; `$1` means something else in fish, pwsh or tcsh (security
  ///   review F3). `/bin/sh` otherwise.
  /// - `-lic` (ruling D6): the login profile *and* `.zshrc`, so a PATH set
  ///   up for nvm or pyenv is there. A `.zshrc` that `exec`s tmux will keep
  ///   the command from running; that is the ruling's accepted cost.
  /// - [ExternalAppEntry.pathToken] becomes `"$1"`, and the path travels as
  ///   argument 1 -- never inside the script, so nothing in it is parsed.
  /// - stdin is closed at once, so a prompt in `.zshrc` reads EOF instead of
  ///   waiting; the command's own stdout goes to `/dev/null` in the script.
  /// - A non-zero exit within [exitWait] is a failure carrying stderr's last
  ///   line; zero, or still running, is started (ruling D3). After the
  ///   window stderr keeps being drained until the process ends, so the pipe
  ///   never fills, holding at most [_StderrTail.limit] characters. A child
  ///   still alive when this app quits gets SIGPIPE on its next stderr
  ///   write -- accepted: editor launchers fork and exit within the window.
  ///
  /// Windows: `%SystemRoot%\System32\cmd.exe /d /s /v:off /c <command>`
  /// through the detached relay, working directory [path] (F2). The path
  /// never enters the command -- [ExternalAppEntry.pathToken] becomes `.` --
  /// because cmd expands `%…%` *before* it parses quotes, so a directory
  /// named `x%CMDCMDLINE:~-1%&calc` would close the quotes and run calc. A
  /// UNC path is refused (cmd cannot use one as its working directory), and
  /// so is a command with `"`, which the relay refuses to carry
  /// ([startDetachedProcess]). The relay only waits for `Start-Process`, so
  /// cmd's own exit code is never seen: D3's failure report is POSIX-only.
  Future<ExternalAppLaunchResult> openExternalApp(
    ExternalAppEntry app,
    String path,
  ) async {
    if (_os == 'windows') return _openExternalAppWindows(app, path);
    if (!path.startsWith('/')) {
      return ExternalAppLaunchFailed('不是絕對路徑：$path');
    }
    final String script =
        '{ ${app.command.replaceAll(ExternalAppEntry.pathToken, r'"$1"')}\n'
        '} </dev/null >/dev/null';
    final Process process;
    try {
      process = await _spawn(_posixShell(), <String>[
        '-lic',
        script,
        'gbm',
        path,
      ], workingDirectory: path);
    } on ProcessException catch (e) {
      return ExternalAppLaunchFailed(e.message);
    }
    unawaited(process.stdin.close());
    unawaited(process.stdout.drain<void>());
    final _StderrTail tail = _StderrTail();
    final Completer<void> stderrDone = Completer<void>();
    process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(tail.add, onDone: stderrDone.complete, onError: (_) {});
    final int? code =
        await Future.wait<Object?>(<Future<Object?>>[
              process.exitCode,
              stderrDone.future,
            ])
            .then<int?>((List<Object?> r) => r.first as int?)
            .timeout(exitWait, onTimeout: () => null);
    if (code == null || code == 0) return const ExternalAppStarted();
    final String line = tail.lastLine;
    return ExternalAppLaunchFailed(line.isEmpty ? '結束碼 $code' : line);
  }

  static const Set<String> _posixShells = <String>{
    'sh',
    'bash',
    'zsh',
    'dash',
    'ksh',
    'mksh',
    'yash',
    'ash',
  };

  String _posixShell() {
    final String shell = _env['SHELL'] ?? '';
    if (!shell.startsWith('/')) return '/bin/sh';
    return _posixShells.contains(shell.split('/').last) ? shell : '/bin/sh';
  }

  Future<ExternalAppLaunchResult> _openExternalAppWindows(
    ExternalAppEntry app,
    String path,
  ) async {
    if (path.startsWith(r'\\')) {
      return ExternalAppLaunchFailed('不支援網路路徑（UNC）：$path');
    }
    if (!RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path)) {
      return ExternalAppLaunchFailed('不是絕對路徑：$path');
    }
    if (app.command.contains('"')) {
      return const ExternalAppLaunchFailed('Windows 上的指令不能含雙引號');
    }
    final String root = _env['SystemRoot'] ?? '';
    final String cmd = root.isEmpty ? 'cmd.exe' : '$root\\System32\\cmd.exe';
    final bool started = await _start(cmd, <String>[
      '/d',
      '/s',
      '/v:off',
      '/c',
      app.command.replaceAll(ExternalAppEntry.pathToken, '.'),
    ], workingDirectory: path);
    return started
        ? const ExternalAppStarted()
        : const ExternalAppLaunchFailed('無法啟動 cmd.exe');
  }

  /// Reveals [path] in the OS file manager. Backs the "Open in file manager"
  /// / "Show in file manager" entries in context menus 05-A and 05-F, which
  /// were previously bound to a no-op.
  ///
  /// Explorer's `/select,` and Finder's `-R` reveal the item *within* its
  /// parent folder, which is what "show in" means for a file; Linux has no
  /// portable reveal, so `xdg-open` opens the path itself.
  Future<bool> openInFileManager(String path) async {
    switch (_os) {
      case 'windows':
        // Two arguments, so only the path is ever quoted: explorer handed
        // `"/select,C:\a b\f.txt"` quoted whole opens Documents instead.
        return _start('explorer.exe', <String>['/select,', _windows(path)]);
      case 'macos':
        return _start('open', <String>['-R', path]);
      default:
        return _start('xdg-open', <String>[path]);
    }
  }

  /// Opens [path] with whatever application the OS has associated with it.
  /// Backs 05-F's "Open file".
  ///
  /// Deliberately separate from [openUrl] despite the identical per-platform
  /// command shape: that one takes a compile-time constant `https://` URL
  /// ([GbmUrls]) and this one takes a work-tree path, so only this one needs
  /// the Windows separator normalization below and only this one would be
  /// the place to add a "file does not exist" guard if one is ever wanted.
  Future<bool> openFile(String path) async {
    switch (_os) {
      case 'windows':
        // The path itself, opened by its association -- see openUrl.
        return _start(_windows(path), const <String>[]);
      case 'macos':
        return _start('open', <String>[path]);
      default:
        return _start('xdg-open', <String>[path]);
    }
  }

  /// Rewrites `/` to `\` for the Windows shell utilities that are picky
  /// about it. `explorer.exe /select,` in particular does not fail on a
  /// forward-slash path -- it silently ignores the selection and opens
  /// Documents instead, which reads as "the menu item is broken".
  ///
  /// Callers join a repository's work dir with a repo-relative path from
  /// git, which always uses `/`, so a Windows path reaching here is
  /// routinely mixed-separator.
  static String _windows(String path) => path.replaceAll('/', r'\');

  /// Hands [url] to the OS default browser. Backs Help → Documentation and
  /// Help → Report an issue, whose URLs are compile-time constants (see
  /// `GbmUrls`), never user input.
  Future<bool> openUrl(String url) async {
    switch (_os) {
      case 'windows':
        // Handed to `Start-Process` as the program to start, which opens it
        // with whatever is associated -- the default browser here. It used
        // to be `cmd /c start`, and cmd, a console program, never ran.
        return _start(url, const <String>[]);
      case 'macos':
        return _start('open', <String>[url]);
      default:
        return _start('xdg-open', <String>[url]);
    }
  }
}

/// Overridden in tests with a [DesktopLauncher] built from a recording
/// [ProcessStarter], so a widget test can assert which executable a menu
/// item would have spawned without spawning anything.
final Provider<DesktopLauncher> desktopLauncherProvider =
    Provider<DesktopLauncher>((ref) => const DesktopLauncher());

/// External destinations reachable from the Help menu (spec page 04's
/// `MENUS` table: Documentation, Report an issue). Constants rather than a
/// preference: both point at this project's own canonical locations, and
/// nothing in the spec makes them configurable.
abstract final class GbmUrls {
  static const String documentation =
      'https://github.com/staler2019/git-branch-manager#readme';
  static const String reportAnIssue =
      'https://github.com/staler2019/git-branch-manager/issues/new';

  /// The REST endpoint the update check reads. `/releases/latest` excludes
  /// drafts and pre-releases on GitHub's side, which is the whole
  /// pre-release policy -- there is no client-side filter to keep in step.
  static const String latestReleaseApi =
      'https://api.github.com/repos/Staler2019/git-branch-manager/releases/latest';

  /// Where the user is sent when self-installing is not possible (an
  /// unsupported CPU, an install directory this process cannot write).
  static const String releasesPage =
      'https://github.com/Staler2019/git-branch-manager/releases/latest';
}

/// The last line of a stream of stderr text, capped at [limit] characters
/// from its end, so a child that writes forever costs a bounded amount.
class _StderrTail {
  static const int limit = 512;

  String _pending = '';
  String _lastComplete = '';

  void add(String chunk) {
    final List<String> parts = (_pending + chunk).split('\n');
    _pending = _cap(parts.removeLast());
    for (final String part in parts.reversed) {
      final String line = part.replaceAll('\r', '').trim();
      if (line.isNotEmpty) {
        _lastComplete = _cap(line);
        break;
      }
    }
  }

  String get lastLine {
    final String pending = _pending.replaceAll('\r', '').trim();
    return pending.isNotEmpty ? pending : _lastComplete;
  }

  static String _cap(String s) =>
      s.length <= limit ? s : s.substring(s.length - limit);
}
