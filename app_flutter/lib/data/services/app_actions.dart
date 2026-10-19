import 'dart:io';

import '../models/app_action.dart';
import '../models/external_app_entry.dart';
import 'desktop_launcher.dart';

/// No terminal emulator could be started; [DesktopLauncher.openTerminal]
/// tried its whole fallback chain.
final class TerminalLaunchException implements Exception {
  const TerminalLaunchException();
}

/// [DesktopLauncher.openExternalApp] reported a failure; [message] is its
/// detail (stderr's last line, or why the command was refused).
final class ExternalAppLaunchException implements Exception {
  const ExternalAppLaunchException(this.message);

  final String message;
}

/// Repository → Open in terminal, and the worktree panel's main segment.
///
/// Not cancellable: a terminal either starts or it does not.
AppAction<void> openTerminalAction(DesktopLauncher launcher, String path) =>
    AppAction<void>(
      name: 'openTerminal',
      cancellable: false,
      body: (_) async {
        if (!await launcher.openTerminal(path)) {
          throw const TerminalLaunchException();
        }
      },
      describeSuccess: (_) => 'Opened a terminal in $path',
      describeFailure: (_) => 'No terminal emulator was found',
      describeCancelled: () => 'Cancelled opening a terminal in $path',
    );

/// One entry of the worktree panel's ▾ list.
///
/// Not cancellable: cancelling could only stop the launcher's 5 s wait for an
/// early failure, never the app it already started, so reporting that as
/// Cancelled would be the lie security review F8 forbids.
AppAction<void> openExternalAppAction(
  DesktopLauncher launcher,
  ExternalAppEntry app,
  String path,
) => AppAction<void>(
  name: 'openExternalApp',
  cancellable: false,
  body: (_) async {
    switch (await launcher.openExternalApp(app, path)) {
      case ExternalAppStarted():
        return;
      case ExternalAppLaunchFailed(:final String message):
        throw ExternalAppLaunchException(message);
    }
  },
  describeSuccess: (_) => 'Opened $path with "${app.label}"',
  describeFailure: (Exception error) => switch (error) {
    ExternalAppLaunchException(:final String message) =>
      'Could not run "${app.label}": $message',
    _ => 'Could not run "${app.label}": $error',
  },
  describeCancelled: () => 'Cancelled opening $path with "${app.label}"',
);

/// [export] failed; [message] is why.
final class FileExportException implements Exception {
  const FileExportException(this.message);

  final String message;
}

/// History's 05-K "Open file at this revision" / "Save this revision as…".
///
/// [export] writes [path] to [destPath] and resolves to null on success or
/// to the reason it failed -- a closure, so this file depends on no session
/// type. Not cancellable: the capi request cannot be withdrawn.
AppAction<void> exportFileAtRevisionAction({
  required String path,
  required String destPath,
  required Future<String?> Function() export,
}) => AppAction<void>(
  name: 'exportFileAtRevision',
  cancellable: false,
  body: (_) async {
    final String? failure = await export();
    if (failure != null) throw FileExportException(failure);
  },
  describeSuccess: (_) => 'Exported $path to $destPath',
  describeFailure: (Exception error) => switch (error) {
    FileExportException(:final String message) =>
      'Could not export $path: $message',
    _ => 'Could not export $path: $error',
  },
  describeCancelled: () => 'Cancelled exporting $path',
);

/// The log drawer's Save as… (spec page 10 `LOGRULES` export row).
///
/// Writes [text] into [documentsDirectory] as `gbm-log-<local time>.txt` and
/// resolves to the file's path. Colons are illegal in Windows filenames, so
/// the ISO timestamp is flattened. Not cancellable: one small write.
AppAction<String> saveOperationLogAction({
  required Future<Directory> Function() documentsDirectory,
  required String text,
  DateTime Function() now = DateTime.now,
}) => AppAction<String>(
  name: 'saveOperationLog',
  cancellable: false,
  body: (_) async {
    final Directory dir = await documentsDirectory();
    final String stamp = now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final File file = File('${dir.path}/gbm-log-$stamp.txt');
    await file.writeAsString(text);
    return file.path;
  },
  describeSuccess: (String path) => 'Saved the log to $path',
  describeFailure: (Exception error) => switch (error) {
    FileSystemException(:final String message) =>
      'Could not save the log: $message',
    _ => 'Could not save the log: $error',
  },
  describeCancelled: () => 'Cancelled saving the log',
);
