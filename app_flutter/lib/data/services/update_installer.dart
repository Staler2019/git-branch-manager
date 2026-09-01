import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

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
/// 1. step out of whatever directory it inherited -- on Windows, standing in
///    the install directory is by itself enough to make step 2 impossible;
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
/// Windows is the live risk: its release artifact is a **flat** zip
/// (`release.yml`'s `Compress-Archive .../Release/*`), so extracting it
/// straight into Downloads puts `gbm_flutter.exe` directly there and makes
/// Downloads the install directory -- which the updater would then rename to
/// `Downloads.gbm-old` wholesale. macOS cannot reach this, because the
/// target is the `.app` bundle itself, and the Linux tarball carries its own
/// wrapper directory.
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
typedef DetachedProcessStarter =
    Future<DetachedStart> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
    });

/// Arms a deadline after which the process exits whatever else is happening.
/// Returns whether it was armed.
typedef UpdateWatchdog = Future<bool> Function(Duration after);

/// The watchdog, running on its own isolate -- which is the entire point.
///
/// [Future.timeout] cannot bound synchronous work on the isolate that is
/// doing it: the `Timer` it arms needs the very event loop the blocking call
/// is holding. Measured on this repository's Dart 3.12.2: `.timeout(100ms)`
/// around a future whose body synchronously sleeps three seconds reports
/// `completed after 3009ms` and never fires. `closeNativeSession()` is
/// exactly that shape -- a synchronous FFI `gbm_session_close` whose C++
/// destructor blocks in `operations_->drain()` until the operation worker
/// goes idle -- so the deadline has to be enforced from somewhere the main
/// isolate cannot stall. A spawned isolate has its own event loop on its own
/// OS thread, and `exit()` from it terminates the whole VM (measured: the
/// process ended with the watchdog's code while the main isolate was 30
/// seconds into a synchronous sleep).
///
/// `sleep` rather than a `Timer` so nothing depends on this isolate having a
/// live event-loop reason to stay alive.
void updateWatchdogEntryPoint(int milliseconds) {
  sleep(Duration(milliseconds: milliseconds));
  exit(0);
}

class UpdateInstaller {
  const UpdateInstaller({
    DetachedProcessStarter? start,
    ProcessRunner? run,
    UpdateWatchdog? armWatchdog,
    void Function(int code)? exitProcess,
    this.operatingSystem,
    this.executablePath,
    this.abi,
    this.homeDirectory,
    this.systemRoot,
    this.sessionCloseDeadline = kSessionCloseDeadline,
    this.watchdogDeadline = kUpdateWatchdogDeadline,
  }) : _start = start ?? _startDetached,
       _run = run ?? _runToCompletion,
       _armWatchdog = armWatchdog ?? _spawnWatchdog,
       _exitProcess = exitProcess ?? _realExit;

  final DetachedProcessStarter _start;
  final ProcessRunner _run;
  final UpdateWatchdog _armWatchdog;

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

  static Future<DetachedStart> _startDetached(
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
      return const DetachedStart.ok();
    } on ProcessException catch (e) {
      // Kept rather than collapsed to a bool: "The system cannot find the
      // file specified" and "Access is denied" send the user to completely
      // different places, and the old bool sent them to neither.
      return DetachedStart.failed(e.message);
    } on Object catch (e) {
      return DetachedStart.failed('$e');
    }
  }

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
    final Directory target = installTarget();
    // macOS runs a quarantined app from a read-only random mount point until
    // it is moved to /Applications. Replacing that is meaningless -- the copy
    // the user keeps is somewhere else, or nowhere.
    if (target.path.contains('/AppTranslocation/')) {
      return 'This app is running from a temporary location. Move it to your '
          'Applications folder first, then check again.';
    }
    // Not the reported failure -- that install was in a folder of its own --
    // but the same flat Windows zip makes this one plausible, and its blast
    // radius is the user's whole Downloads folder rather than a failed
    // update.
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

    final String body = isWindows
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
          );

    final UpdateLog log = UpdateLog(scriptDir);
    log.write('os=$_os');
    log.write('target=${target.path}');
    log.write('staged=${staged.path}');
    log.write('script=${script.path}');

    // UTF-8 with a BOM on Windows, without one everywhere else, and the
    // asymmetry is not cosmetic. `powershell.exe` -- Windows PowerShell 5.1,
    // which is what `-File` resolves to on a stock machine -- reads a
    // BOM-less .ps1 as ANSI rather than UTF-8. All three paths are baked
    // into the script as literals, so a user name in Chinese is enough to
    // mojibake every one of them and leave the rename and the copy pointing
    // nowhere: the same silent exit 3 an inherited working directory
    // produced. `sh` has the opposite requirement -- a BOM on the first line
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

# Both lines, not just the first. `Set-Location` moves PowerShell's provider
# location while the Win32 process directory -- the one holding the handle
# that blocks renaming it -- stays where the process was created. Only
# assigning CurrentDirectory calls SetCurrentDirectory and releases it.
Set-Location -LiteralPath \$PSScriptRoot
[System.Environment]::CurrentDirectory = \$PSScriptRoot

# Beside the script, appended to: the app truncated it when this install
# began and has already written everything that happened before the handover
# (see UpdateLog). Truncating here would delete exactly the half that says
# why the app never got this far. Failures to write are swallowed -- losing
# the log must never be what fails the update.
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

# Everything past the wait runs with the app already gone, so every arm has
# to put a working build back -- including the ones that change nothing.
# Wrapped in its own try: with ErrorActionPreference = 'Stop' a relaunch of
# something that is not there would otherwise take the script down before it
# could set an exit code.
function Restart-App {
  try { $relaunchCommand } catch { }
}

\$parentPid = $pid
\$target = ${_psQuote(targetPath)}
\$staged = ${_psQuote(stagedPath)}
\$backup = ${_psQuote('$targetPath.gbm-old')}

Write-Log "target=\$target"
Write-Log "staged=\$staged"

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

# Antivirus and Explorer routinely keep a handle open for a moment after the
# process itself has gone, so the rename is retried rather than trusted.
\$renamed = \$false
\$lastError = 'no attempt was made'
for (\$i = 0; \$i -lt 20; \$i++) {
  try {
    if (Test-Path -LiteralPath \$backup) {
      Remove-Item -LiteralPath \$backup -Recurse -Force
    }
    Move-Item -LiteralPath \$target -Destination \$backup -Force
    \$renamed = \$true
    break
  } catch {
    # Kept, not just slept on: all twenty retries used to swallow this, so
    # exit 3 named the step that failed and nothing about why -- and a
    # sharing violation, an access denial and a missing path each send the
    # user somewhere different.
    \$lastError = "\$_"
    Start-Sleep -Milliseconds 500
  }
}
if (-not \$renamed) {
  Write-Log "could not rename the install aside; nothing was changed: \$lastError"
  Restart-App
  Stop-Updater 3
}

try {
  Copy-Item -LiteralPath \$staged -Destination \$target -Recurse -Force
  Remove-Item -LiteralPath \$staged -Recurse -Force -ErrorAction SilentlyContinue
  Restart-App
  Stop-Updater 0
} catch {
  Write-Log "the copy failed: \$_"

  # The restore is itself guarded: an unhandled throw here would end the
  # script with the install gone and nothing running.
  try {
    Remove-Item -LiteralPath \$target -Recurse -Force -ErrorAction SilentlyContinue
    Move-Item -LiteralPath \$backup -Destination \$target -Force
  } catch { }
  Restart-App
  Stop-Updater 4
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
