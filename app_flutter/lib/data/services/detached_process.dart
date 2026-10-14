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

/// Starts the updater so that it outlives this process.
///
/// On macOS and Linux that is `ProcessStartMode.detached`. **On Windows it
/// is not, because there it does not work**: `Process.start` returns a pid
/// and reports success, and the child never runs a single instruction --
/// measured with `powershell.exe -File` and `cmd.exe /c`, from `dart run`,
/// from an AOT executable and from a process WMI created outside any job,
/// with the parent alive for ten seconds after the start. It is the whole of
/// the earlier Windows report: a `gbm-update.ps1` in temp, no
/// `gbm-update.log` beside it, and the app still on screen. The script had
/// been written and never ran; nothing in the app could tell.
///
/// So on Windows the same shell is started normally, and asked to start the
/// real one through `Start-Process` ([windowsRelayArguments]): that child
/// belongs to no console and no pipe of this process, and survives its exit.
/// The relay is waited for, which turns "reported started" into "started":
/// a nonzero exit, with PowerShell's own message, is a failed start.
Future<DetachedStart> startDetachedProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
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
    final ProcessResult relay = await Process.run(
      executable,
      windowsRelayArguments(
        executable,
        arguments,
        workingDirectory: workingDirectory ?? Directory.systemTemp.path,
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

/// The relay's own command line: [executable] asked to `Start-Process`
/// itself with [arguments], hidden, in [workingDirectory].
///
/// `Start-Process -ArgumentList` joins an array with spaces and quotes
/// nothing, so the arguments travel as **one** string with each one
/// double-quoted (a Windows path cannot contain `"`), and that string, like
/// every other value, reaches PowerShell as a single-quoted literal, which
/// interpolates nothing.
List<String> windowsRelayArguments(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
}) {
  final String joined = arguments.map((String a) => '"$a"').join(' ');
  return <String>[
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    'Start-Process -WindowStyle Hidden '
        '-FilePath ${psQuote(executable)} '
        '-WorkingDirectory ${psQuote(workingDirectory)} '
        '-ArgumentList ${psQuote(joined)}',
  ];
}

/// PowerShell's single-quoted strings escape a quote by doubling it and
/// interpolate nothing -- which is also what keeps a literal `$` in a path.
String psQuote(String value) => "'${value.replaceAll("'", "''")}'";
