import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/prepared_update.dart';
import '../models/release_asset.dart';
import 'desktop_launcher.dart';
import 'install_location_registry.dart';
import 'update_watchdog.dart';

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
typedef ProcessRunner = Future<ProcessRunResult> Function(
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
/// On macOS and Linux the script swaps directories itself:
///
/// 1. step out of whatever directory it inherited;
/// 2. wait for this process to exit -- and **abort if it never does**, since
///    swapping underneath a live app leaves two instances over a
///    half-replaced install;
/// 3. rename the current install to `<name>.gbm-old` -- a rename, never a
///    delete, because that copy *is* the rollback;
/// 4. copy the staged build into the vacated path;
/// 5. on any failure past the wait, put a working build back -- undoing the
///    rename where one happened -- so the user is never left without an
///    application.
///
/// On Windows steps 3-5 belong to Windows Installer: the release is an MSI,
/// and the script hands it to msiexec, which replaces the files and rolls a
/// failure back inside one transaction ([buildWindowsMsiUpdaterScript]).
/// Steps 1 and 2 are the same -- on Windows, standing in the install
/// directory is by itself enough to make the install fail.
///
/// Extraction deliberately happens **before** the app quits ([stage]), not
/// inside the script: an archive that will not open is then an error the
/// running app can still report, rather than a broken install discovered when
/// there is nothing left to report it with.
/// Prefix of the system-temp directory one update downloads into.
///
/// Shared between the code that creates it (`UpdateController`) and the
/// sweep below, because a sweep matching a prefix nobody writes any more
/// would silently stop cleaning up.
const String kUpdateDownloadDirPrefix = 'gbm-update-';

/// Folders a user keeps other things in, which an install must therefore
/// never *be*.
///
/// Guards the directory swap, which renames the whole install directory
/// aside. It was written for the flat Windows zip earlier releases shipped
/// -- extracted straight into Downloads, that made Downloads the install
/// directory -- and Windows no longer takes the swap at all (it updates
/// through the installer, see [UpdateInstaller.selfInstallBlocker]). It
/// stays for Linux, where a tarball's wrapper can still be unpacked
/// somewhere shared; macOS cannot reach it, because the target is the `.app`
/// bundle itself.
const List<String> kSharedUserFolders = <String>[
  'Desktop',
  'Documents',
  'Downloads',
  'Music',
  'OneDrive',
  'Pictures',
  'Public',
  'Videos',
];

/// Whether [targetPath] is a folder that must not be replaced wholesale: a
/// filesystem or drive root, the home directory itself, or one of
/// [kSharedUserFolders] directly inside it.
///
/// Pure and separator-agnostic -- it splits on both, and compares case
/// insensitively -- rather than going through `Directory.parent`, which
/// follows the *host's* path rules and would make a `C:\...` fixture
/// meaningless on the macOS and Linux machines this is tested on.
///
/// Answers false when [homePath] is null. An environment with no home
/// variable is not evidence that anything is wrong, and a guard that fired
/// on missing information would block installs it knows nothing about.
bool isSharedUserFolder(String targetPath, String? homePath) {
  final List<String> target = _pathSegments(targetPath);
  // Nothing above it, so "rename it aside" would mean the whole volume.
  if (target.isEmpty || (target.length == 1 && target.single.endsWith(':'))) {
    return true;
  }
  if (homePath == null) {
    return false;
  }
  final List<String> home = _pathSegments(homePath);
  if (home.isEmpty) {
    return false;
  }
  if (_sameSegments(target, home)) {
    return true;
  }
  // A *direct* child only: `D:\Backup\Downloads` is somebody's own folder
  // that happens to share a name.
  if (target.length != home.length + 1) {
    return false;
  }
  if (!_sameSegments(target.sublist(0, home.length), home)) {
    return false;
  }
  final String name = target.last.toLowerCase();
  return kSharedUserFolders.any((String f) => f.toLowerCase() == name);
}

List<String> _pathSegments(String path) => path
    .split(RegExp(r'[/\\]+'))
    .where((String segment) => segment.isNotEmpty)
    .toList();

bool _sameSegments(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (int i = 0; i < a.length; i++) {
    if (a[i].toLowerCase() != b[i].toLowerCase()) {
      return false;
    }
  }
  return true;
}

/// Name of the transcript both halves of the handover write beside the
/// updater script.
///
/// The script runs after the process has exited, so nothing in the app can
/// report what it did. Without a file on disk a failed update is entirely
/// undiagnosable -- the position the Windows report left this feature in.
const String kUpdateLogName = 'gbm-update.log';

/// Where that transcript ends up.
///
/// Composed here, next to the generator, so the script and the sentence that
/// tells the user where to look cannot drift apart. It resolves to the
/// script's own directory because `UpdateController.install` passes
/// `Directory.systemTemp` as `scriptDir` -- the script writes the log beside
/// itself.
String updateLogPath() =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}$kUpdateLogName';

/// The update transcript, written by **both** halves of the handover.
///
/// The app owns truncation and the scripts only ever append. It was the
/// other way round for one release -- each script opened the log with a
/// truncating write and the app wrote nothing at all -- which meant the
/// entire app-side half of the handover was undiagnosable: unpacking,
/// closing the repository sessions and starting the updater could each fail
/// with not one byte written anywhere, because the only writer was a script
/// that had not been started yet. That is precisely the window the Windows
/// report landed in: a `gbm-update.ps1` sitting in system temp, no
/// `gbm-update.log` beside it, and the app still on screen. A diagnostic
/// channel only the far side of a handover writes is no channel at all.
///
/// Never throws, on any method. Losing the transcript must never be what
/// fails an update.
class UpdateLog {
  const UpdateLog(this.directory);

  /// Always the directory the updater script is written into, so
  /// `$PSScriptRoot`, `$(dirname "$0")` and [updateLogPath] cannot name
  /// three different files.
  final Directory directory;

  File get file =>
      File('${directory.path}${Platform.pathSeparator}$kUpdateLogName');

  /// Starts a fresh transcript for one install attempt.
  ///
  /// Truncating here rather than in the scripts keeps the original reason
  /// for truncating at all -- a transcript accumulating every update ever
  /// run would bury the one being asked about -- while moving it to the
  /// first thing that happens, so nothing written afterwards is lost.
  void begin(String header) => _put(header, append: false);

  /// Appends one timestamped line.
  void write(String message) => _put(message, append: true);

  /// Flushed on every line, because the next thing this process does on the
  /// happy path is `exit(0)`, which runs no finalizers and flushes nothing.
  void _put(String message, {required bool append}) {
    try {
      file.writeAsStringSync(
        '${_stamp()} $message\n',
        mode: append ? FileMode.append : FileMode.write,
        flush: true,
      );
    } on Object {
      // A read-only temp directory, a full disk, a path that has gone away.
      // All three are the user's to resolve and none is worth failing an
      // update over.
    }
  }

  /// Second precision, matching `Get-Date -Format s` and `date
  /// '+%Y-%m-%dT%H:%M:%S'` so the app's lines and the script's lines below
  /// them read as one column.
  static String _stamp() => DateTime.now().toIso8601String().split('.').first;
}

/// Suffix the updater script renames the outgoing install to.
const String kPreviousInstallSuffix = '.gbm-old';

/// How old a `gbm-update-*` directory must be before the sweep takes it.
///
/// A second instance of the app may be downloading right now into a
/// directory that is indistinguishable by name from a leftover, so age is
/// the only thing separating "abandoned" from "in use". The cost is that
/// the directory from the update that just completed survives until the
/// launch after next -- system temp on macOS and Linux is purged anyway,
/// and on Windows, where it is not, one extra launch is a cheap price for
/// never deleting a transfer in progress.
const Duration kUpdateLeftoverMinAge = Duration(hours: 1);

/// How long the handover waits for the repository sessions to close before
/// giving up on them and exiting anyway.
///
/// User-ratified: 「子行程應該有 timeout，壞掉記 log」. The accepted cost is a
/// `git` child still holding `.git/index.lock`, which the new build reports
/// as "Another Git process appears to be running" -- recoverable, and
/// visible. A dialog stuck on "Installing…" with no buttons, which is what
/// an unbounded wait produced, is neither.
const Duration kSessionCloseDeadline = Duration(seconds: 10);

/// When the watchdog isolate ends the process regardless of what the main
/// isolate is doing.
///
/// **The three deadlines are nested and the order is load-bearing**:
/// [kSessionCloseDeadline] (10s) < this (20s) < the updater script's own
/// `waitTimeout` (60s). Push this past the script's and the script gives up
/// first -- `exit 2`, nothing changed -- and the app then dies anyway, so
/// the user gets a window that closed *and* no update, which is worse than
/// the bug being fixed.
const Duration kUpdateWatchdogDeadline = Duration(seconds: 20);

/// The outcome of trying to start a detached process, with the reason it
/// did not start.
///
/// A third seam alongside [ProcessStarter] and [ProcessRunner] rather than a
/// widening of either, for the reason [ProcessRunner]'s own doc comment
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
Future<DetachedStart> startUpdaterProcess(
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
        '-FilePath ${_psQuote(executable)} '
        '-WorkingDirectory ${_psQuote(workingDirectory)} '
        '-ArgumentList ${_psQuote(joined)}',
  ];
}

/// Arms a deadline after which the process exits whatever else is happening.
/// Returns whether it was armed.
typedef UpdateWatchdog = Future<bool> Function(Duration after);

class UpdateInstaller {
  const UpdateInstaller({
    DetachedProcessStarter? start,
    ProcessRunner? run,
    UpdateWatchdog? armWatchdog,
    void Function(int code)? exitProcess,
    InstallLocationReader? readInstallLocation,
    this.operatingSystem,
    this.executablePath,
    this.abi,
    this.homeDirectory,
    this.systemRoot,
    this.sessionCloseDeadline = kSessionCloseDeadline,
    this.watchdogDeadline = kUpdateWatchdogDeadline,
  }) : _start = start ?? startUpdaterProcess,
       _run = run ?? _runToCompletion,
       _armWatchdog = armWatchdog ?? _spawnWatchdog,
       _exitProcess = exitProcess ?? _realExit,
       _readInstallLocation =
           readInstallLocation ?? readInstallLocationFromRegistry;

  final DetachedProcessStarter _start;
  final ProcessRunner _run;
  final UpdateWatchdog _armWatchdog;

  /// Injected for the same reason as the two above, and more urgently: the
  /// default really does end the process, so a test that reached this
  /// through an un-substituted seam would take the test runner down with it
  /// rather than fail.
  final void Function(int code) _exitProcess;

  /// Injected so no test reads the registry of the machine running it.
  /// Consulted on Windows only.
  final InstallLocationReader _readInstallLocation;

  /// Overridden in tests; null means [Platform.operatingSystem].
  final String? operatingSystem;

  /// Overridden in tests; null means [Platform.resolvedExecutable].
  final String? executablePath;

  /// Overridden in tests; null means [Abi.current].
  final Abi? abi;

  /// Overridden in tests; null means the platform's own home variable.
  final String? homeDirectory;

  /// Overridden in tests; null means `%SystemRoot%`. Only read on Windows,
  /// where it locates the stock `powershell.exe` by absolute path.
  final String? systemRoot;

  /// Overridden in tests so a wedged `beforeExit` can be exercised in
  /// milliseconds rather than in [kSessionCloseDeadline].
  final Duration sessionCloseDeadline;

  /// Overridden in tests, for the same reason as [sessionCloseDeadline].
  final Duration watchdogDeadline;

  String get _os => operatingSystem ?? Platform.operatingSystem;
  String get _exe => executablePath ?? Platform.resolvedExecutable;
  Abi get _abi => abi ?? Abi.current();

  String? get _home =>
      homeDirectory ??
      Platform.environment[_os == 'windows' ? 'USERPROFILE' : 'HOME'];

  /// Spawns [updateWatchdogEntryPoint]. Its failure is reported rather than
  /// thrown: a watchdog that could not be armed is a diagnostic loss, not a
  /// reason to abandon an update that is otherwise ready to hand over.
  static Future<bool> _spawnWatchdog(Duration after) async {
    try {
      await Isolate.spawn(updateWatchdogEntryPoint, after.inMilliseconds);
      return true;
    } on Object {
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

  /// Removes what a completed update left behind: the previous install kept
  /// for rollback, and abandoned download directories.
  ///
  /// Run shortly after launch, and only from the build that replaced the
  /// old one -- reaching this code at all is the proof the swap worked. The
  /// updater script keeps [kPreviousInstallSuffix] precisely so a failed
  /// copy can be undone; once the new build is running there is nothing
  /// left to undo, and the script's own `rm -rf` of the backup only happens
  /// at the *start* of the next update, which may never come.
  ///
  /// Never throws. Housekeeping must not be the reason the app fails to
  /// start, and every failure here is something the user can delete by hand.
  Future<void> sweepUpdateLeftovers({
    Directory? tempDir,
    DateTime Function()? now,
  }) async {
    _deleteQuietly(Directory('${installTarget().path}$kPreviousInstallSuffix'));

    final Directory temp = tempDir ?? Directory.systemTemp;
    final DateTime cutoff = (now ?? DateTime.now).call().subtract(
      kUpdateLeftoverMinAge,
    );
    final List<FileSystemEntity> entries;
    try {
      entries = temp.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final FileSystemEntity entry in entries) {
      // Directories only: a *file* carrying the prefix was not written by
      // this app's downloader, and deleting by name alone would reach past
      // what this sweep owns.
      if (entry is! Directory) continue;
      final String name = entry.path.split(Platform.pathSeparator).last;
      if (!name.startsWith(kUpdateDownloadDirPrefix)) continue;
      try {
        if (entry.statSync().modified.isAfter(cutoff)) continue;
      } on FileSystemException {
        continue;
      }
      _deleteQuietly(entry);
    }
  }

  static void _deleteQuietly(Directory dir) {
    try {
      if (dir.existsSync()) {
        dir.deleteSync(recursive: true);
      }
    } on FileSystemException {
      // Read-only, gone, or on a volume that has been unmounted. All three
      // are the user's to resolve, and none is worth a dialog on launch.
    }
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
    // Windows updates through the installer, which owns every check below
    // for itself; all this app has to establish is that the copy running is
    // the one the installer manages.
    if (_os == 'windows') {
      return _installerBlocker();
    }
    final Directory target = installTarget();
    // macOS runs a quarantined app from a read-only random mount point until
    // it is moved to /Applications. Replacing that is meaningless -- the copy
    // the user keeps is somewhere else, or nowhere.
    if (target.path.contains('/AppTranslocation/')) {
      return 'This app is running from a temporary location. Move it to your '
          'Applications folder first, then check again.';
    }
    // Its blast radius would be the user's whole Downloads folder rather
    // than a failed update.
    if (isSharedUserFolder(target.path, _home)) {
      return 'This app is installed directly in ${target.path}, alongside '
          'whatever else is in there. Updating replaces the whole folder, so '
          'it will not do that. Move the app into a folder of its own, or '
          'download from the releases page.';
    }
    if (!_isWritable(target.parent)) {
      return 'The install directory (${target.parent.path}) is not writable '
          'by this user. Download from the releases page instead.';
    }
    return null;
  }

  /// Why Windows Installer cannot update this copy, or null when it can.
  ///
  /// msiexec is handed the folder the installer recorded, so only the copy
  /// running from that folder may start it. Anything else -- a portable zip
  /// from an earlier release, the installed folder copied somewhere -- would
  /// have the upgrade land on some *other* folder while this one stayed as
  /// it was. Both are pointed at the installer instead.
  ///
  /// The mirror rule matters as much: a copy the installer *does* manage is
  /// registered with Windows Installer (the Apps list, upgrade detection,
  /// uninstall), and is never given the directory swap, which would leave
  /// all three describing files that are gone. [launchUpdater] refuses that
  /// shape on Windows outright.
  String? _installerBlocker() {
    final String? registered = _readInstallLocation();
    if (registered != null &&
        sameInstallLocation(registered, installTarget().path)) {
      return null;
    }
    return 'This copy was not installed with the installer, so it cannot '
        'update itself. Download the .msi from the releases page and install '
        'it once; later updates then install themselves.';
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

  /// Prepares [bundle] for the updater script, inside [into].
  ///
  /// The factory for [PreparedUpdate]: which shape comes back is decided by
  /// the operating system being updated, and every shape is something the
  /// script can apply without having to inspect the download itself. A
  /// [PreparedDirectory] is shaped exactly like [installTarget], so its
  /// script's job is a plain directory-for-directory replacement; a
  /// [PreparedInstallerPackage] goes to Windows Installer unopened.
  ///
  /// The three release artifacts are prepared differently (`release.yml`'s
  /// Package steps): the DMG mounts with the `.app` at its volume root, the
  /// Linux tarball has exactly one wrapper directory that has to be
  /// descended through, and the Windows `.msi` is not opened at all.
  ///
  /// [sha256] is the digest the bundle matched when it was downloaded. It is
  /// checked again here, before anything reads the bundle, because the file
  /// has been sitting in a temp directory since then -- for as long as the
  /// user left the dialog at "ready to install" -- and the sweep or anything
  /// else running as this user could have replaced or removed it.
  Future<PreparedUpdate> stage({
    required File bundle,
    required Directory into,
    required String sha256,
  }) async {
    await _verifyUnchanged(bundle, sha256);
    if (_os == 'windows') {
      return PreparedInstallerPackage(
        package: bundle,
        sha256: sha256.toLowerCase(),
      );
    }
    final Directory payload = Directory(
      '${into.path}${Platform.pathSeparator}payload',
    )..createSync(recursive: true);

    if (_os == 'macos') {
      return PreparedDirectory(
        await _stageDmg(bundle: bundle, into: into, payload: payload),
      );
    }
    await _extract('tar', <String>['xzf', bundle.path, '-C', payload.path]);
    return PreparedDirectory(_descendWrapper(payload));
  }

  static Future<void> _verifyUnchanged(File bundle, String expected) async {
    final String actual;
    try {
      actual = (await sha256.bind(bundle.openRead()).first).toString();
    } on FileSystemException catch (e) {
      throw UpdateInstallException(
        'The downloaded update is no longer where it was saved '
        '(${e.message}). Download it again.',
      );
    }
    if (actual != expected.toLowerCase()) {
      throw const UpdateInstallException(
        'The downloaded update has changed since it was verified, so it was '
        'not installed. Download it again.',
      );
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

  /// Writes the updater script, starts it detached, closes the app down
  /// under a deadline, and only then exits the process.
  ///
  /// **The order was the other way round for one release, and the rationale
  /// that defended it was wrong.** It ran [beforeExit] first, on the grounds
  /// that a hang there "leaves the app alive with no script running --
  /// recoverable -- rather than a detached swap racing a live process". Both
  /// halves fell over on a Windows report:
  ///
  /// * The swap does not race a live process. The script's first act after
  ///   its own `cd` is to poll for the parent's exit every 200ms against a
  ///   60s deadline, and its timeout arm changes nothing at all. Starting it
  ///   early is safe by construction; that was never the risk it was
  ///   defended against.
  /// * "Recoverable" was the part the user actually hit, and it is not.
  ///   [beforeExit] closes the FFI sessions, and `closeNativeSession()` is a
  ///   *synchronous* `gbm_session_close` whose C++ destructor blocks in
  ///   `operations_->drain()` until the operation worker goes idle -- which
  ///   an operation waiting on askpass never does. The reported symptom is
  ///   the dialog frozen on "Installing…", which by design renders no
  ///   buttons, so there is nothing to recover *with*.
  ///
  /// So: start the script first, and only then close down, under two
  /// deadlines that are both needed and neither of which subsumes the other.
  /// [sessionCloseDeadline] catches a [beforeExit] that is merely slow;
  /// [watchdogDeadline], enforced from another isolate, is the only thing
  /// that can catch one that has blocked this isolate outright -- see
  /// [updateWatchdogEntryPoint] for why a `Future.timeout` provably cannot.
  ///
  /// The exit is still not reached if the script failed to start, so a
  /// machine with no usable shell keeps both its working install and its
  /// running app -- and the watchdog is armed only past that point, which is
  /// what lets that path stay alive with no cancellation handshake.
  ///
  /// Every step is written to [UpdateLog] beside the script, because on the
  /// path this exists to fix there is no other channel: the app never gets
  /// to render an error and the script never gets to write a line.
  ///
  /// Returns a reason string if the update could not be launched. On success
  /// it does not return: the process is gone.
  Future<String?> launchUpdater({
    required PreparedUpdate staged,
    required Directory scriptDir,
    required Future<void> Function() beforeExit,
    int? processId,
  }) async {
    final bool isWindows = _os == 'windows';
    final _UpdaterPlan plan;
    switch (staged) {
      // Asked again here, where the script is actually written, rather than
      // trusting that every caller asked [selfInstallBlocker] first: the
      // registration can have changed since the check, and the folder handed
      // to msiexec is read from it.
      case PreparedInstallerPackage(:final File package, :final String sha256)
          when isWindows:
        final String? registered = _readInstallLocation();
        if (registered == null ||
            !sameInstallLocation(registered, installTarget().path)) {
          return _installerBlocker();
        }
        plan = _UpdaterPlan(
          target: registered,
          source: package.path,
          body: buildWindowsMsiUpdaterScript(
            pid: processId ?? pid,
            installFolder: registered,
            packagePath: package.path,
            sha256: sha256,
            relaunchCommand: _windowsRelaunch(),
          ),
        );
      case PreparedDirectory(:final Directory directory) when !isWindows:
        final Directory target = installTarget();
        plan = _UpdaterPlan(
          target: target.path,
          source: directory.path,
          body: buildUnixUpdaterScript(
            pid: processId ?? pid,
            targetPath: target.path,
            stagedPath: directory.path,
            copyCommand: _os == 'macos' ? 'ditto' : 'cp -a',
            relaunchCommand: _unixRelaunch(),
          ),
        );
      // A directory swap on Windows would leave an installer-managed copy's
      // registration describing files that are gone; an installer package
      // anywhere else has nothing to run it. Neither is reachable through
      // [stage], and neither gets a script.
      case PreparedDirectory() || PreparedInstallerPackage():
        return 'This update cannot be applied here: Windows updates only '
            'through the installer. Download the new version from the '
            'releases page.';
    }
    final File script = File(
      '${scriptDir.path}${Platform.pathSeparator}'
      'gbm-update.${isWindows ? 'ps1' : 'sh'}',
    );
    final String body = plan.body;

    final UpdateLog log = UpdateLog(scriptDir);
    log.write('os=$_os');
    log.write('target=${plan.target}');
    log.write('${isWindows ? 'package' : 'staged'}=${plan.source}');
    log.write('script=${script.path}');

    // UTF-8 with a BOM on Windows, without one everywhere else, and the
    // asymmetry is not cosmetic. `powershell.exe` -- Windows PowerShell 5.1,
    // which is what `-File` resolves to on a stock machine -- reads a
    // BOM-less .ps1 as ANSI rather than UTF-8. Every path is baked into the
    // script as a literal, so a user name in Chinese is enough to mojibake
    // them and leave msiexec pointed at nothing. `sh` has the opposite requirement -- a BOM on the first line
    // is a syntax error, not a hint.
    script.writeAsStringSync(isWindows ? '\uFEFF$body' : body);

    final DetachedStart outcome = await _startUpdater(script, scriptDir, log);
    if (!outcome.started) {
      // Nothing has been armed and nothing has been closed, so the app is
      // simply still here -- which is the right outcome for a machine with
      // no shell to run the swap with.
      return 'The updater could not be started (${outcome.error}). Your '
          'current version is untouched; install the new version from the '
          'releases page. ${log.file.path} has the details.';
    }
    log.write('updater started');

    // Armed before the close, never after: closing is the thing it exists to
    // survive. Only past a successful start, so the branch above can stay
    // alive without a cancellation handshake -- which it could not perform
    // anyway if the isolate were the thing that wedged.
    log.write(
      await _armWatchdog(watchdogDeadline)
          ? 'watchdog armed for ${_readable(watchdogDeadline)}'
          : 'the watchdog could not be armed',
    );

    log.write('closing repository sessions');
    try {
      await beforeExit().timeout(sessionCloseDeadline);
      log.write('sessions closed');
    } on TimeoutException {
      log.write(
        'the repository sessions did not close within '
        '${_readable(sessionCloseDeadline)}; exiting anyway',
      );
    } on Object catch (e) {
      // Swallowed for the same reason OpenRepoSessions.closeAll() swallows
      // its own: the process is on its way out and there is no surface left
      // to report on. Recorded, though -- that is what was missing.
      log.write('closing the repository sessions failed: $e');
    }

    log.write('exiting');
    _exitProcess(0);
    return null;
  }

  /// Whole seconds where the duration has them, milliseconds otherwise, so
  /// a deadline tuned below a second does not report itself as `0s`.
  static String _readable(Duration d) => d.inMilliseconds % 1000 == 0
      ? '${d.inSeconds}s'
      : '${d.inMilliseconds}ms';

  /// Tries each shell [_updaterShells] offers until one starts, recording
  /// every attempt.
  ///
  /// `workingDirectory` is load-bearing on Windows, not tidiness.
  /// `Process.start` inherits the parent's current directory when none is
  /// given, and an app launched by double-clicking its .exe has the install
  /// directory as its own -- so the detached updater stood inside the very
  /// folder it then tried to rename. Windows refuses to rename or delete any
  /// process's current directory (that handle carries no FILE_SHARE_DELETE),
  /// so `Move-Item` failed every retry and the script gave up having already
  /// closed the app and changed nothing. POSIX permits it, which is why only
  /// Windows broke. `scriptDir` is outside the target by construction -- the
  /// script is deliberately never written into the directory being replaced.
  Future<DetachedStart> _startUpdater(
    File script,
    Directory scriptDir,
    UpdateLog log,
  ) async {
    DetachedStart outcome = const DetachedStart.failed(
      'no shell candidate was tried',
    );
    for (final String shell in _updaterShells()) {
      final List<String> arguments = _updaterArguments(script);
      log.write('starting $shell ${arguments.join(' ')}');
      outcome = await _start(
        shell,
        arguments,
        workingDirectory: scriptDir.path,
      );
      if (outcome.started) return outcome;
      log.write('$shell did not start: ${outcome.error}');
    }
    return outcome;
  }

  /// The shells to try, in order.
  ///
  /// Windows leads with an absolute path rather than the bare name it used
  /// to use. A bare `powershell` is resolved by `CreateProcess` walking
  /// `PATH`, and a truncated or mangled `PATH` is a real condition on
  /// Windows -- one that would take out the only route this app has to
  /// update itself, for a file that is always in the same place. `pwsh.exe`
  /// last, because PowerShell 7 is not on a stock machine and the script is
  /// written for what `-File` resolves to when it is absent.
  List<String> _updaterShells() {
    if (_os != 'windows') return const <String>['sh'];
    final String? root = systemRoot ?? Platform.environment['SystemRoot'];
    return <String>[
      if (root != null && root.isNotEmpty)
        '$root\\System32\\WindowsPowerShell\\v1.0\\powershell.exe',
      'powershell.exe',
      'pwsh.exe',
    ];
  }

  List<String> _updaterArguments(File script) => _os == 'windows'
      ? <String>[
          '-NoProfile',
          '-ExecutionPolicy',
          'Bypass',
          '-File',
          script.path,
        ]
      : <String>[script.path];

  static void _realExit(int code) => exit(code);

  /// `open` hands the relaunch to Finder, which is what actually registers a
  /// `.app` as running -- executing the inner binary directly gives a process
  /// with no Dock entry and no menu bar.
  String _unixRelaunch() {
    if (_os == 'macos') return 'open "\$TARGET"';
    return '"\$TARGET/${_executableName()}" >/dev/null 2>&1 &';
  }

  /// `-WorkingDirectory` so the new build starts in its own install
  /// directory rather than in system temp, where this script is standing.
  String _windowsRelaunch() =>
      r'Start-Process -WorkingDirectory $target -FilePath (Join-Path $target '
      "'${_executableName()}')";

  /// Cut with the separators of the OS being updated, not of the host: the
  /// two coincide on a real machine, and diverge only where a test hands a
  /// foreign-shaped path to a foreign [operatingSystem]. Windows accepts both
  /// separators; a POSIX file name may contain a backslash.
  String _executableName() =>
      _exe.split(_os == 'windows' ? RegExp(r'[/\\]') : '/').last;
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
///
/// **Every code except 2 relaunches.** 2 is the one arm reached with the app
/// still on screen, where a second instance would be worse than nothing;
/// each of the others runs after the process has gone, so leaving without
/// starting something is what makes a failed update look like the app
/// vanishing.
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

# Out of whatever directory this was started in, before touching anything.
# Belt and braces behind launchUpdater's own `workingDirectory`: a script
# standing inside the directory it is about to move has no business doing so
# on any platform, and on Windows the equivalent is what broke the update.
cd "\$(dirname "\$0")" || exit 1

# Beside the script, appended to: the app truncated it when this install
# began and has already written everything that happened before the handover
# (see UpdateLog). Truncating here would delete exactly the half that says
# why the app never got this far. Failures to write are swallowed -- losing
# the log must never be what fails the update.
LOG="\$PWD/$kUpdateLogName"
log() {
  printf '%s %s\\n' "\$(date '+%Y-%m-%dT%H:%M:%S')" "\$*" >> "\$LOG" 2>/dev/null || true
}
finish() {
  log "exit \$1"
  exit "\$1"
}

PID=$pid
TARGET=${_shQuote(targetPath)}
STAGED=${_shQuote(stagedPath)}
BACKUP=${_shQuote('$targetPath.gbm-old')}
ATTEMPTS=$attempts

log "target=\$TARGET"
log "staged=\$STAGED"

# Timing out must leave everything untouched. Falling through while the app
# is still running would put two instances over a half-replaced install.
i=0
while kill -0 "\$PID" 2>/dev/null; do
  i=\$((i + 1))
  if [ "\$i" -ge "\$ATTEMPTS" ]; then
    log "the app was still running at the deadline; nothing was changed"
    finish 2
  fi
  sleep 0.2
done

# Everything past the wait runs with the app already gone, so every arm has
# to put a working build back -- including the ones that change nothing. A
# script that simply gave up is what turned a failed rename into "the app
# closed and never came back".
relaunch() {
  $relaunchCommand
}

rm -rf "\$BACKUP"
# stderr is kept because "could not rename" on its own names no cause. It
# only ever reaches a *message*: these strings are gettext-localised, so
# nothing branches on them.
if ! mv_error=\$(mv "\$TARGET" "\$BACKUP" 2>&1); then
  log "could not rename the install aside; nothing was changed: \$mv_error"
  relaunch
  finish 3
fi

if $copyCommand "\$STAGED" "\$TARGET"; then
  rm -rf "\$STAGED"
  relaunch
  finish 0
fi

# The rename above is the only reason this is recoverable.
log "the copy failed; restoring the old install"
rm -rf "\$TARGET"
mv "\$BACKUP" "\$TARGET"
relaunch
finish 4
''';
}

/// Name of msiexec's own verbose log, written beside the updater script.
const String kUpdateMsiLogName = 'gbm-update-msi.log';

/// The PowerShell updater for Windows: once this process has exited, hand
/// the verified package to Windows Installer and relaunch.
///
/// Windows Installer does what the Unix script does by hand -- replacing the
/// files, and putting the old ones back when that fails -- inside one
/// transaction, so this script only has to wait, re-check, run and report.
///
/// Every value is baked in as a single-quoted PowerShell literal, which
/// interpolates nothing, and msiexec's command line is concatenated from
/// those variables as **one** string: `Start-Process -ArgumentList` joins an
/// array with spaces and quotes nothing, so a folder name with a space in it
/// -- the default install folder has two -- would otherwise reach msiexec
/// as several arguments.
///
/// Exit codes:
///
/// | code | meaning                                              | relaunch |
/// |------|------------------------------------------------------|----------|
/// | 0    | installed                                            | yes      |
/// | 2    | the app never exited; nothing was changed            | no       |
/// | 5    | msiexec failed or would not start; it rolled back    | yes      |
/// | 6    | the package no longer matches its verified digest    | yes      |
/// | 7    | installed, but Windows must restart to finish        | no       |
///
/// 2 relaunches nothing because the app is still on screen. 7 relaunches
/// nothing because files are queued for replacement at the next restart, and
/// starting the app now would load a mix of old and new DLLs.
///
/// Not executed by this project's test suite -- see `update_installer_test`
/// for what is asserted as text, and `cq.yml`'s `powershell-parse` job for
/// the golden that is parsed.
String buildWindowsMsiUpdaterScript({
  required int pid,
  required String installFolder,
  required String packagePath,
  required String sha256,
  required String relaunchCommand,
  Duration waitTimeout = const Duration(seconds: 60),
}) {
  // msiexec normalises a directory property to end in a backslash, and a
  // backslash right before a closing quote is an escaped quote to anything
  // that parses a command line the CommandLineToArgvW way.
  final String target = installFolder.replaceAll(RegExp(r'[\\/]+$'), '');
  // NOTE: `$pid` is an automatic read-only variable in PowerShell, so the
  // parameter below cannot be named that -- it would fail at assignment.
  return '''
# Generated by git-branch-manager. Upgrades the installation the parent process of this
# script was running from with a Windows Installer package, once that
# process has exited.
\$ErrorActionPreference = 'Stop'

# Both lines, not just the first. `Set-Location` moves the PowerShell provider
# location while the Win32 process directory stays where the process was
# created. Only assigning CurrentDirectory calls SetCurrentDirectory.
Set-Location -LiteralPath \$PSScriptRoot
[System.Environment]::CurrentDirectory = \$PSScriptRoot

# Beside the script, appended to: the app truncated it when this install
# began and has already written everything that happened before the handover
# (see UpdateLog). Failures to write are swallowed -- losing the log must
# never be what fails the update.
\$log = Join-Path \$PSScriptRoot '$kUpdateLogName'
function Write-Log(\$message) {
  try {
    Add-Content -LiteralPath \$log -Value "\$(Get-Date -Format s) \$message"
  } catch { }
}
function Stop-Updater(\$code) {
  Write-Log "exit \$code"
  exit \$code
}

# Wrapped in its own try: with ErrorActionPreference = 'Stop' a relaunch of
# something that is not there would otherwise take the script down before it
# could set an exit code.
function Restart-App {
  try { $relaunchCommand } catch { }
}

\$parentPid = $pid
\$target = ${_psQuote(target)}
\$package = ${_psQuote(packagePath)}
\$expectedHash = ${_psQuote(sha256.toLowerCase())}
\$msiLog = Join-Path \$PSScriptRoot '$kUpdateMsiLogName'
# By absolute path: a bare name is resolved by searching, and this script
# stands in the temp directory.
\$msiexec = Join-Path \$env:SystemRoot 'System32\\msiexec.exe'

Write-Log "target=\$target"
Write-Log "package=\$package"

# Polled rather than Wait-Process, whose timeout surfaces as an error record
# rather than a distinguishable exception type.
\$deadline = (Get-Date).AddSeconds(${waitTimeout.inSeconds})
while (Get-Process -Id \$parentPid -ErrorAction SilentlyContinue) {
  if ((Get-Date) -gt \$deadline) {
    Write-Log 'the app was still running at the deadline; nothing was changed'
    Stop-Updater 2
  }
  Start-Sleep -Milliseconds 200
}

# The package waited in a temp directory for as long as the update dialog
# stayed open. Checked once more, right before Windows Installer reads it.
try {
  \$actualHash = (Get-FileHash -LiteralPath \$package -Algorithm SHA256).Hash.ToLowerInvariant()
} catch {
  \$actualHash = "unreadable: \$_"
}
if (\$actualHash -ne \$expectedHash) {
  Write-Log "the package no longer matches its verified SHA-256 (\$actualHash); nothing was installed"
  Restart-App
  Stop-Updater 6
}

\$arguments = '/i "' + \$package + '" /passive /norestart INSTALLFOLDER="' + \$target + '" /l*v "' + \$msiLog + '"'
Write-Log "running \$msiexec \$arguments"
try {
  \$process = Start-Process -FilePath \$msiexec -ArgumentList \$arguments -Wait -PassThru
  \$code = \$process.ExitCode
} catch {
  Write-Log "msiexec could not be started: \$_"
  Restart-App
  Stop-Updater 5
}
Write-Log "msiexec exited with \$code"

if (\$code -eq 0) {
  Remove-Item -LiteralPath \$package -Force -ErrorAction SilentlyContinue
  Restart-App
  Stop-Updater 0
}
if (\$code -eq 3010 -or \$code -eq 1641) {
  Write-Log 'installed; Windows must restart to finish, so the app is not relaunched'
  Stop-Updater 7
}

# Windows Installer rolls a failed install back by itself, so the build
# relaunched here is the one that was running before.
Write-Log "the install failed and was rolled back; see \$msiLog"
Restart-App
Stop-Updater 5
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

/// What [UpdateInstaller.launchUpdater] decided to run: the script body and
/// the two locations it names, for the transcript.
class _UpdaterPlan {
  const _UpdaterPlan({
    required this.target,
    required this.source,
    required this.body,
  });

  final String target;
  final String source;
  final String body;
}

/// Overridden in tests with an installer built from recording seams, exactly
/// as `desktopLauncherProvider` is.
final Provider<UpdateInstaller> updateInstallerProvider =
    Provider<UpdateInstaller>((Ref ref) => const UpdateInstaller());
