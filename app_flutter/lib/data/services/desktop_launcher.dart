import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Starts a detached OS process. Injected rather than calling
/// [Process.start] directly so the platform-specific candidate chains below
/// can be widget/unit-tested without actually spawning a terminal -- the
/// same testability rationale as `GbmBindings` being injected through
/// `gbmBindingsProvider` instead of opening the real `.so` at import time.
///
/// Returns `true` if the process started, `false` if the executable was not
/// found (which is what drives the fallback chains). Implementations must
/// not throw for a missing executable.
typedef ProcessStarter =
    Future<bool> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

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
  const DesktopLauncher({ProcessStarter? start, this.operatingSystem})
    : _start = start ?? _startDetached;

  final ProcessStarter _start;

  /// Overridden in tests; null means [Platform.operatingSystem].
  final String? operatingSystem;

  String get _os => operatingSystem ?? Platform.operatingSystem;

  static Future<bool> _startDetached(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    try {
      await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        mode: ProcessStartMode.detached,
      );
      return true;
    } on ProcessException {
      // Executable not on PATH -- the caller falls through to the next
      // candidate in the chain.
      return false;
    }
  }

  /// The ordered candidate chain for [_os], per the spec's `TERMINALS` table.
  List<_TerminalCandidate> _terminalCandidates(String path) {
    switch (_os) {
      case 'windows':
        return <_TerminalCandidate>[
          _TerminalCandidate('wt.exe', <String>['-d', path]),
          _TerminalCandidate('powershell.exe', <String>[
            '-NoExit',
            '-Command',
            'cd "$path"',
          ]),
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

  /// Hands [url] to the OS default browser. Backs Help → Documentation and
  /// Help → Report an issue, whose URLs are compile-time constants (see
  /// `GbmUrls`), never user input.
  Future<bool> openUrl(String url) async {
    switch (_os) {
      case 'windows':
        // `start` is a cmd builtin, so it needs cmd itself as the
        // executable. The empty string is `start`'s title argument -- without
        // it, a quoted URL would be consumed as the window title.
        return _start('cmd', <String>['/c', 'start', '', url]);
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
}
