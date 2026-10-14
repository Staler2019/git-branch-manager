import 'dart:async';
import 'dart:io';

/// The outcome of trying to start a detached process, with the reason it
/// did not start.
///
/// A third seam alongside `ProcessStarter` and `ProcessRunner` rather than a
/// widening of either, for the reason `ProcessRunner`'s own doc comment
/// gives: `ProcessStarter` answers a bare bool and that bool is what drives
/// `DesktopLauncher`'s terminal fallback chains, while this one has to carry
/// the `ProcessException` message across -- which is the single most useful
/// string there is when an update fails to hand over, and which the bool
/// threw away.
class DetachedStart {
  const DetachedStart({required this.started, this.error});

  const DetachedStart.ok() : started = true, error = null;

  const DetachedStart.failed(String this.error) : started = false;

  final bool started;

  /// Null exactly when [started]; the platform's own message otherwise.
  final String? error;
}

/// Starts a process detached and says why it could not be started.
typedef DetachedProcessStarter = Future<DetachedStart> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
});

/// Starts [executable] so that it outlives this process.
///
/// On macOS and Linux that is `ProcessStartMode.detached`. **On Windows it
/// is not, because there it does not work**: `Process.start` returns a pid
/// and reports success, and the child never runs a single instruction --
/// measured with `powershell.exe -File` and `cmd.exe /c`, from `dart run`,
/// from an AOT executable and from a process WMI created outside any job,
/// with the parent alive for ten seconds after the start. It is the whole of
/// the earlier Windows report: a `gbm-update.ps1` in temp, no
/// `gbm-update.log` beside it, and the app still on screen. The script had
/// been written and never ran; nothing in the app could tell. It is
/// console programs that fail: `charmap.exe`, `wt.exe` and `explorer.exe`,
/// started the same way, run. Every Windows start goes through the relay
/// anyway, so no caller has to know which kind it is starting.
///
/// So on Windows PowerShell ([windowsRelayShell]) is started normally, and
/// asked to start [executable] through `Start-Process`
/// ([windowsRelayArguments]): that child belongs to no console and no pipe
/// of this process, and survives its exit. The relay is waited for, which
/// turns "reported started" into "started": a nonzero exit, with
/// PowerShell's own message, is a failed start. [window] is ignored
/// elsewhere.
Future<DetachedStart> startDetachedProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  RelayWindow window = RelayWindow.hidden,
}) async {
  try {
    if (!Platform.isWindows) {
      await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        mode: ProcessStartMode.detached,
      );
      return const DetachedStart.ok();
    }
    if (arguments.any((String a) => a.contains('"'))) {
      return const DetachedStart.failed(
        'an argument contains a double quote, which the relay cannot carry',
      );
    }
    final ProcessResult relay = await Process.run(
      windowsRelayShell(),
      windowsRelayArguments(
        executable,
        arguments,
        workingDirectory: workingDirectory ?? Directory.systemTemp.path,
        window: window,
      ),
      workingDirectory: workingDirectory,
    ).timeout(_kRelayDeadline);
    if (relay.exitCode != 0) {
      final String why = '${relay.stderr}'.trim();
      return DetachedStart.failed(
        why.isEmpty ? 'the relay exited with ${relay.exitCode}' : why,
      );
    }
    return const DetachedStart.ok();
  } on ProcessException catch (e) {
    // Kept rather than collapsed to a bool: "The system cannot find the
    // file specified" and "Access is denied" send the user to completely
    // different places, and the old bool sent them to neither.
    return DetachedStart.failed(e.message);
  } on TimeoutException {
    return DetachedStart.failed(
      'the relay did not finish within ${_kRelayDeadline.inSeconds}s',
    );
  } on Object catch (e) {
    return DetachedStart.failed('$e');
  }
}

/// Generous, because a cold PowerShell start on a busy machine takes
/// seconds; short of the watchdog, because nothing has been closed yet and
/// the app is still the user's to use if this gives up.
const Duration _kRelayDeadline = Duration(seconds: 15);

/// The relay's own command line: PowerShell asked to `Start-Process`
/// [executable] with [arguments] in [workingDirectory]. With no arguments
/// the parameter is left out -- `Start-Process` refuses an empty one, and a
/// URL or document handed to it on its own (opened by its association) has
/// none.
///
/// `Start-Process -ArgumentList` joins an array with spaces and quotes
/// nothing, so the arguments travel as **one** string, and that string, like
/// every other value, reaches PowerShell as a single-quoted literal, which
/// interpolates nothing. Inside it an argument is double-quoted only when it
/// is empty or holds a space or tab -- what `Process.start` itself does --
/// because a quoted switch is not a switch to every program: `cmd.exe`
/// given `"/c"` runs nothing (measured). A Windows path cannot contain `"`,
/// and [startDetachedProcess] refuses any argument that does. Backslashes
/// that end a quoted argument are doubled, also as `Process.start` does:
/// otherwise the last one escapes the closing quote and every argument after
/// it is swallowed into this one.
///
/// `-WorkingDirectory` is resolved as a wildcard pattern -- there is no
/// literal form -- so a repository under `br[1]` started nothing until the
/// path went through `[WildcardPattern]::Escape` (measured).
List<String> windowsRelayArguments(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  RelayWindow window = RelayWindow.hidden,
}) {
  final String joined = arguments.map(_relayQuote).join(' ');
  final String style = switch (window) {
    RelayWindow.hidden => 'Hidden',
    RelayWindow.normal => 'Normal',
  };
  return <String>[
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    'Start-Process -WindowStyle $style '
        '-FilePath ${psQuote(executable)} '
        '-WorkingDirectory '
        '([WildcardPattern]::Escape(${psQuote(workingDirectory)}))'
        '${arguments.isEmpty ? '' : ' -ArgumentList ${psQuote(joined)}'}',
  ];
}

String _relayQuote(String a) {
  if (a.isNotEmpty && !a.contains(RegExp(r'[ \t]'))) return a;
  final String body = a.replaceAllMapped(
    RegExp(r'\\+$'),
    (Match m) => '${m[0]}${m[0]}',
  );
  return '"$body"';
}

/// How the relayed program's window starts: hidden for the updater's own
/// script, normal for a terminal, browser or document the user asked for.
enum RelayWindow { hidden, normal }

/// The relay itself: Windows PowerShell by absolute path, because a bare
/// name is resolved by walking `PATH`, and a mangled `PATH` would take out
/// every start this app makes on Windows for a file that is always in the
/// same place.
String windowsRelayShell({String? systemRoot}) {
  final String root = systemRoot ?? Platform.environment['SystemRoot'] ?? '';
  return root.isEmpty
      ? 'powershell.exe'
      : '$root\\System32\\WindowsPowerShell\\v1.0\\powershell.exe';
}

/// PowerShell's single-quoted strings escape a quote by doubling it and
/// interpolate nothing -- which is also what keeps a literal `$` in a path.
String psQuote(String value) => "'${value.replaceAll("'", "''")}'";
