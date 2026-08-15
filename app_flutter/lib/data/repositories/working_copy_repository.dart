import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/working_copy_status.dart';
import 'repo_identity.dart';
import 'repo_session_repository.dart';

/// Working-copy status, selected out of [repoSessionProvider] so
/// `features/working_copy` widgets rebuild only when it actually changes --
/// see branch_repository.dart's doc comment for why this is a thin
/// `select()` rather than its own controller/session.
final ProviderFamily<WorkingCopyStatus, RepoIdentity>
repoWorkingCopyStatusProvider =
    Provider.family<WorkingCopyStatus, RepoIdentity>((ref, identity) {
      return ref.watch(
        repoSessionProvider(
          identity,
        ).select((state) => state.workingCopyStatus),
      );
    });

/// The most recent diff reply, selected the same way. `features/diff`
/// checks `reply.path`/`reply.staged` against what it asked for, since a
/// newer request for a different file can race an in-flight one.
final ProviderFamily<WorkingCopyDiffReply?, RepoIdentity> repoLastDiffProvider =
    Provider.family<WorkingCopyDiffReply?, RepoIdentity>((ref, identity) {
      return ref.watch(
        repoSessionProvider(identity).select((state) => state.lastDiff),
      );
    });

void refreshWorkingCopy(WidgetRef ref, RepoIdentity identity) {
  ref.read(repoSessionProvider(identity).notifier).refreshWorkingCopy();
}

void requestWorkingCopyDiff(
  WidgetRef ref,
  RepoIdentity identity,
  String path, {
  bool staged = false,
}) {
  ref
      .read(repoSessionProvider(identity).notifier)
      .requestDiff(path, staged: staged);
}

void stageFiles(WidgetRef ref, RepoIdentity identity, List<String> paths) {
  ref.read(repoSessionProvider(identity).notifier).stageFiles(paths);
}

void unstageFiles(WidgetRef ref, RepoIdentity identity, List<String> paths) {
  ref.read(repoSessionProvider(identity).notifier).unstageFiles(paths);
}

void commitChanges(
  WidgetRef ref,
  RepoIdentity identity,
  String message, {
  bool amend = false,
  bool signOff = false,
}) {
  ref
      .read(repoSessionProvider(identity).notifier)
      .commit(message, amend: amend, signOff: signOff);
}

void resolveConflict(
  WidgetRef ref,
  RepoIdentity identity,
  String path,
  ConflictResolution resolution, {
  bool oursBlobMissing = false,
  bool theirsBlobMissing = false,
  String resolvedContent = '',
}) {
  ref
      .read(repoSessionProvider(identity).notifier)
      .resolveConflict(
        path,
        resolution,
        oursBlobMissing: oursBlobMissing,
        theirsBlobMissing: theirsBlobMissing,
        resolvedContent: resolvedContent,
      );
}
