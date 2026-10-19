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
