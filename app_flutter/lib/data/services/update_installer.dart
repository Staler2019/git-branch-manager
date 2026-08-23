import 'dart:ffi';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/release_asset.dart';
import 'desktop_launcher.dart';

/// The outcome of a process run to completion.
class ProcessRunResult {
  const ProcessRunResult(this.exitCode, this.stderr);

  final int exitCode;
  final String stderr;

  bool get ok => exitCode == 0;
}

/// Runs a process **to completion** and reports how it went.
///
/// Deliberately a second seam alongside [ProcessStarter] rather than a
/// widening of it: that one starts a process *detached* and can only report
/// whether the executable was found, which is the right contract for
/// launching the updater script and the wrong one for everything else here.
/// Extraction has to be able to fail loudly -- an update that quits the app
/// and only then discovers the archive was corrupt has no way to say so.
typedef ProcessRunner =
    Future<ProcessRunResult> Function(
      String executable,
      List<String> arguments,
    );

/// Raised when an update cannot be prepared. Carries a message meant for the
/// update dialog, in the same spirit as `UpdateCheckException`.
class UpdateInstallException implements Exception {
  const UpdateInstallException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Replaces the running application with a freshly downloaded build.
///
/// **A process cannot overwrite its own running executable** -- Windows
/// refuses outright, and on Unix replacing a bundle underneath a live process
/// is merely undefined rather than impossible. So the swap is done by a small
/// script written to the system temp directory (never into the directory
/// being replaced), started detached, and left to run once this process has
/// exited.
///
/// The script's shape is the same on all three platforms:
///
/// 1. wait for this process to exit -- and **abort if it never does**, since
///    swapping underneath a live app leaves two instances over a
///    half-replaced install;
/// 2. rename the current install to `<name>.gbm-old` -- a rename, never a
///    delete, because that copy *is* the rollback;
/// 3. copy the staged build into the vacated path;
/// 4. on failure, undo the rename and relaunch the old build, so the user is
///    never left without a working application.
///
/// Extraction deliberately happens **before** the app quits ([stage]), not
/// inside the script: an archive that will not open is then an error the
/// running app can still report, rather than a broken install discovered when
/// there is nothing left to report it with.
class UpdateInstaller {
  const UpdateInstaller({
    ProcessStarter? start,
    ProcessRunner? run,
    void Function(int code)? exitProcess,
    this.operatingSystem,
    this.executablePath,
    this.abi,
  }) : _start = start ?? _startDetached,
       _run = run ?? _runToCompletion,
       _exitProcess = exitProcess ?? _realExit;

  final ProcessStarter _start;
  final ProcessRunner _run;

  /// Injected for the same reason as the two above, and more urgently: the
  /// default really does end the process, so a test that reached this
  /// through an un-substituted seam would take the test runner down with it
  /// rather than fail.
  final void Function(int code) _exitProcess;

  /// Overridden in tests; null means [Platform.operatingSystem].
  final String? operatingSystem;

  /// Overridden in tests; null means [Platform.resolvedExecutable].
  final String? executablePath;

  /// Overridden in tests; null means [Abi.current].
  final Abi? abi;

  String get _os => operatingSystem ?? Platform.operatingSystem;
  String get _exe => executablePath ?? Platform.resolvedExecutable;
  Abi get _abi => abi ?? Abi.current();

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
      return false;
    }
  }

  static Future<ProcessRunResult> _runToCompletion(
    String executable,
    List<String> arguments,
  ) async {
    try {
      final ProcessResult result = await Process.run(executable, arguments);
      return ProcessRunResult(result.exitCode, '${result.stderr}');
    } on ProcessException catch (e) {
      return ProcessRunResult(-1, e.message);
    }
  }

  /// The directory this update would replace.
  ///
  /// On macOS that is the `.app` bundle itself -- `resolvedExecutable` points
  /// at `<bundle>/Contents/MacOS/<name>`, three levels down. Elsewhere the
  /// executable sits directly in the install directory.
  Directory installTarget() {
    final File exe = File(_exe);
    if (_os == 'macos') {
      // MacOS -> Contents -> <name>.app
      return Directory(exe.parent.parent.parent.path);
    }
    return exe.parent;
  }

  /// Why this machine cannot replace its own installation, or null if it can.
  ///
  /// Asked at *check* time, not after a download: an install that was never
  /// going to work should present itself as "open the releases page" from the
  /// start rather than as a failure two minutes in. This is the single source
  /// of truth for the answer -- the dialog's Install button and the install
  /// path both read it, so the two cannot disagree about writability.
  String? selfInstallBlocker() {
    if (assetSuffixForAbi(_abi) == null) {
      return 'No build is published for this platform ($_abi). '
          'Download from the releases page instead.';
    }
    final Directory target = installTarget();
    // macOS runs a quarantined app from a read-only random mount point until
    // it is moved to /Applications. Replacing that is meaningless -- the copy
    // the user keeps is somewhere else, or nowhere.
    if (target.path.contains('/AppTranslocation/')) {
      return 'This app is running from a temporary location. Move it to your '
          'Applications folder first, then check again.';
    }
    if (!_isWritable(target.parent)) {
      return 'The install directory (${target.parent.path}) is not writable '
          'by this user. Download from the releases page instead.';
    }
    return null;
  }

  /// Probes by actually writing, not by reading a permission bit: the
  /// effective answer depends on ACLs, mount flags and (on macOS) sandbox
  /// policy, none of which a mode check sees.
  static bool _isWritable(Directory dir) {
    try {
      final File probe = File(
        '${dir.path}${Platform.pathSeparator}.gbm-write-probe',
      );
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  /// Unpacks [bundle] into [into] and returns the directory to swap into
  /// place -- shaped exactly like [installTarget], so the script's job is a
  /// plain directory-for-directory replacement on every platform.
  ///
  /// The three release artifacts unpack differently (`release.yml`'s Package
  /// steps): the DMG mounts with the `.app` at its volume root, the Windows
  /// zip is flat with no wrapper directory, and the Linux tarball has exactly
  /// one wrapper directory that has to be descended through.
  Future<Directory> stage({
    required File bundle,
    required Directory into,
  }) async {
    final Directory payload = Directory(
      '${into.path}${Platform.pathSeparator}payload',
    )..createSync(recursive: true);

    switch (_os) {
      case 'macos':
        return _stageDmg(bundle: bundle, into: into, payload: payload);
      case 'windows':
        // Windows 10+ ships bsdtar as `tar`, which reads zip archives.
        await _extract('tar', <String>['-xf', bundle.path, '-C', payload.path]);
        return payload;
      default:
        await _extract('tar', <String>['xzf', bundle.path, '-C', payload.path]);
        return _descendWrapper(payload);
    }
  }

  Future<void> _extract(String executable, List<String> arguments) async {
    final ProcessRunResult result = await _run(executable, arguments);
    if (!result.ok) {
      throw UpdateInstallException(
        'Unpacking the download failed: ${result.stderr.trim()}',
      );
    }
  }

  /// The Linux tarball wraps everything in one
  /// `git-branch-manager-<version>-linux-x86_64/` directory. Swapping that
  /// wrapper into place would nest the whole install one level deeper.
  Directory _descendWrapper(Directory payload) {
    final List<FileSystemEntity> entries = payload.listSync();
    if (entries.length == 1 && entries.single is Directory) {
      return entries.single as Directory;
    }
    return payload;
  }

  Future<Directory> _stageDmg({
    required File bundle,
    required Directory into,
    required Directory payload,
  }) async {
    final String mount = '${into.path}${Platform.pathSeparator}mnt';
    await _extract('hdiutil', <String>[
      'attach',
      '-nobrowse',
      '-readonly',
      '-mountpoint',
      mount,
      bundle.path,
    ]);
    try {
      final Iterable<Directory> bundles = Directory(mount)
          .listSync()
          .whereType<Directory>()
          .where((Directory d) => d.path.endsWith('.app'));
      if (bundles.isEmpty) {
        throw const UpdateInstallException(
          'The downloaded disk image contains no application bundle.',
        );
      }
      // `ditto` rather than `cp`: it is Apple's own bundle copier and
      // preserves the extended attributes and symlink layout a `.app`
      // depends on.
      await _extract('ditto', <String>[bundles.first.path, payload.path]);
      return payload;
    } finally {
      await _detach(mount);
    }
  }

  /// `hdiutil detach` intermittently reports "resource busy" even with
  /// `-nobrowse`, as indexing or a stat lags behind. A leaked mount is not a
  /// failed install, so this retries and then gives up silently rather than
  /// failing an update that has otherwise succeeded.
  Future<void> _detach(String mount) async {
    for (int attempt = 0; attempt < 3; attempt++) {
      final ProcessRunResult result = await _run('hdiutil', <String>[
        'detach',
        mount,
      ]);
      if (result.ok) return;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
  }

  /// Writes the updater script, runs [beforeExit], starts the script
  /// detached, and only then exits the process.
  ///
  /// The ordering is deliberate and is what the tests pin. [beforeExit] is
  /// where the app closes its FFI sessions; running it first means a hang
  /// there leaves the app alive with no script running -- recoverable --
  /// rather than a detached swap racing a live process. And the exit is not
  /// reached at all if the script failed to start, so a machine with no
  /// usable shell keeps both its working install and its running app.
  ///
  /// Returns a reason string if the update could not be launched. On success
  /// it does not return: the process is gone.
  Future<String?> launchUpdater({
    required Directory staged,
    required Directory scriptDir,
    required Future<void> Function() beforeExit,
    int? processId,
  }) async {
    final Directory target = installTarget();
    final bool isWindows = _os == 'windows';
    final File script = File(
      '${scriptDir.path}${Platform.pathSeparator}'
      'gbm-update.${isWindows ? 'ps1' : 'sh'}',
    );

    script.writeAsStringSync(
      isWindows
          ? buildWindowsUpdaterScript(
              pid: processId ?? pid,
              targetPath: target.path,
              stagedPath: staged.path,
              relaunchCommand: _windowsRelaunch(),
            )
          : buildUnixUpdaterScript(
              pid: processId ?? pid,
              targetPath: target.path,
              stagedPath: staged.path,
              copyCommand: _os == 'macos' ? 'ditto' : 'cp -a',
              relaunchCommand: _unixRelaunch(),
            ),
    );

    await beforeExit();

    final bool started = isWindows
        ? await _start('powershell', <String>[
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            script.path,
          ])
        : await _start('sh', <String>[script.path]);

    if (!started) {
      return 'The updater could not be started. Your current version is '
          'untouched; install the new version from the releases page.';
    }

    _exitProcess(0);
    return null;
  }

  static void _realExit(int code) => exit(code);

  /// `open` hands the relaunch to Finder, which is what actually registers a
  /// `.app` as running -- executing the inner binary directly gives a process
  /// with no Dock entry and no menu bar.
  String _unixRelaunch() {
    if (_os == 'macos') return 'open "\$TARGET"';
    return '"\$TARGET/${_executableName()}" >/dev/null 2>&1 &';
  }

  String _windowsRelaunch() =>
      r'Start-Process -FilePath (Join-Path $target '
      "'${_executableName()}')";

  String _executableName() => _exe.split(Platform.pathSeparator).last;
}

/// The `sh` updater, as a pure function of its inputs.
///
/// Pure, and taking [relaunchCommand] as a parameter, so the real script can
/// be *executed* against throwaway directories in a test rather than merely
/// having its text asserted -- see `update_installer_script_test.dart`. The
/// swap, the rollback and the still-running abort are control flow, and
/// control flow is not provable by string comparison.
///
/// Exit codes: 0 swapped, 2 the app never exited (nothing changed), 3 could
/// not rename the old install (nothing changed), 4 the copy failed and the
/// old install was restored.
String buildUnixUpdaterScript({
  required int pid,
  required String targetPath,
  required String stagedPath,
  required String copyCommand,
  required String relaunchCommand,
  Duration waitTimeout = const Duration(seconds: 60),
}) {
  // Polled every 200ms rather than one sleep for the whole budget, so the
  // common case -- the app is already gone -- costs nothing.
  final int attempts = (waitTimeout.inMilliseconds / 200).ceil();
  return '''
#!/bin/sh
# Generated by git-branch-manager. Replaces the installation this script's
# parent process was running from, once that process has exited.
set -u

PID=$pid
TARGET=${_shQuote(targetPath)}
STAGED=${_shQuote(stagedPath)}
BACKUP=${_shQuote('$targetPath.gbm-old')}
ATTEMPTS=$attempts

# Timing out must leave everything untouched. Falling through while the app
# is still running would put two instances over a half-replaced install.
i=0
while kill -0 "\$PID" 2>/dev/null; do
  i=\$((i + 1))
  if [ "\$i" -ge "\$ATTEMPTS" ]; then
    exit 2
  fi
  sleep 0.2
done

rm -rf "\$BACKUP"
mv "\$TARGET" "\$BACKUP" || exit 3

if $copyCommand "\$STAGED" "\$TARGET"; then
  rm -rf "\$STAGED"
  $relaunchCommand
  exit 0
fi

# The rename above is the only reason this is recoverable.
rm -rf "\$TARGET"
mv "\$BACKUP" "\$TARGET"
$relaunchCommand
exit 4
''';
}

/// The PowerShell updater, same control flow as [buildUnixUpdaterScript].
///
/// Cannot be executed by this project's test suite -- there is no Windows
/// machine in CI (`ci.yml`'s Flutter job is ubuntu-only and `windows/runner/`
/// is compiled solely by `release.yml` on tag), so this half is text-asserted
/// and covered for real only by the manual pre-release pass.
String buildWindowsUpdaterScript({
  required int pid,
  required String targetPath,
  required String stagedPath,
  required String relaunchCommand,
  Duration waitTimeout = const Duration(seconds: 60),
}) {
  // NOTE: `$pid` is an automatic read-only variable in PowerShell, so the
  // parameter below cannot be named that -- it would fail at assignment.
  return '''
# Generated by git-branch-manager. Replaces the installation this script's
# parent process was running from, once that process has exited.
\$ErrorActionPreference = 'Stop'

\$parentPid = $pid
\$target = ${_psQuote(targetPath)}
\$staged = ${_psQuote(stagedPath)}
\$backup = ${_psQuote('$targetPath.gbm-old')}

# Polled rather than Wait-Process, whose timeout surfaces as an error record
# rather than a distinguishable exception type.
\$deadline = (Get-Date).AddSeconds(${waitTimeout.inSeconds})
while (Get-Process -Id \$parentPid -ErrorAction SilentlyContinue) {
  if ((Get-Date) -gt \$deadline) { exit 2 }
  Start-Sleep -Milliseconds 200
}

# Antivirus and Explorer routinely keep a handle open for a moment after the
# process itself has gone, so the rename is retried rather than trusted.
\$renamed = \$false
for (\$i = 0; \$i -lt 20; \$i++) {
  try {
    if (Test-Path -LiteralPath \$backup) {
      Remove-Item -LiteralPath \$backup -Recurse -Force
    }
    Move-Item -LiteralPath \$target -Destination \$backup -Force
    \$renamed = \$true
    break
  } catch {
    Start-Sleep -Milliseconds 500
  }
}
if (-not \$renamed) { exit 3 }

try {
  Copy-Item -LiteralPath \$staged -Destination \$target -Recurse -Force
  Remove-Item -LiteralPath \$staged -Recurse -Force -ErrorAction SilentlyContinue
  $relaunchCommand
  exit 0
} catch {
  Remove-Item -LiteralPath \$target -Recurse -Force -ErrorAction SilentlyContinue
  Move-Item -LiteralPath \$backup -Destination \$target -Force
  $relaunchCommand
  exit 4
}
''';
}

/// Wraps [value] in single quotes for `sh`, ending and reopening the quote
/// around any embedded one. Install paths routinely contain spaces and a home
/// directory can contain an apostrophe; without this the script is a syntax
/// error at best and a wrong-path delete at worst.
String _shQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// PowerShell's single-quoted strings escape a quote by doubling it and
/// interpolate nothing -- which is also what keeps a literal `$` in a path.
String _psQuote(String value) => "'${value.replaceAll("'", "''")}'";

/// Overridden in tests with an installer built from recording seams, exactly
/// as `desktopLauncherProvider` is.
final Provider<UpdateInstaller> updateInstallerProvider =
    Provider<UpdateInstaller>((Ref ref) => const UpdateInstaller());
