import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/recents_repository.dart';

/// Where a launch starts: the newest repository, or the welcome screen.
sealed class StartupTarget {
  const StartupTarget();
}

final class OpenRecent extends StartupTarget {
  const OpenRecent(this.workDir);

  final String workDir;

  @override
  bool operator ==(Object other) =>
      other is OpenRecent && other.workDir == workDir;

  @override
  int get hashCode => workDir.hashCode;
}

final class Welcome extends StartupTarget {
  const Welcome({this.skipped});

  /// The repository not reopened because the last launch ended while opening it.
  final String? skipped;

  @override
  bool operator ==(Object other) =>
      other is Welcome && other.skipped == skipped;

  @override
  int get hashCode => skipped.hashCode;
}

/// A [marker] left set means the last launch ended while opening that repository, so this one
/// does not reopen anything; it names the marker's repository even if the list has lost it.
StartupTarget decideStartupTarget({
  required String? marker,
  required List<RecentRepoEntry> recents,
}) {
  if (marker != null) return Welcome(skipped: marker);
  if (recents.isEmpty) return const Welcome();
  return OpenRecent(recents.first.workDir);
}

/// `bootstrapApp` overrides this with its decision. The default -- every test that never runs
/// bootstrap -- is the rule from before the marker existed: the newest repository, if any.
final Provider<StartupTarget> startupTargetProvider = Provider<StartupTarget>(
  (ref) => decideStartupTarget(
    marker: null,
    recents: ref.read(recentsRepositoryProvider).read(),
  ),
);
