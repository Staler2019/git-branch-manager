import 'external_app_entry.dart';

/// The worktree panel's ▾ list before the user has edited it: one file
/// manager per platform (open-with-apps-spec.html, ruling D4). `.` is the
/// worktree, because every entry runs with it as the working directory.
///
/// [operatingSystem] takes [Platform.operatingSystem]'s values, injected the
/// way `DesktopLauncher.operatingSystem` is so each branch is testable.
List<ExternalAppEntry> defaultExternalApps(String operatingSystem) {
  final (String label, String command) = switch (operatingSystem) {
    'macos' => ('Finder', 'open .'),
    'windows' => ('Explorer', 'explorer .'),
    _ => ('File manager', 'xdg-open .'),
  };
  return <ExternalAppEntry>[
    switch (ExternalAppEntry.create(
      label: label,
      command: command,
      newId: () => 'default-file-manager',
    )) {
      ExternalAppEntryAccepted(:final ExternalAppEntry entry) => entry,
      ExternalAppEntryRejected(:final String reason) => throw StateError(
        'default entry rejected: $reason',
      ),
    },
  ];
}
