import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/working_copy_status.dart';
import 'repo_identity.dart';
import 'working_copy_draft_repository.dart';
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

/// Every diff currently fetched for the selected file, keyed by
/// [workingCopyDiffKey] -- selected the same way.
///
/// Not "the last diff": the Working Copy view asks for the unstaged and the
/// staged side of one file at once and paints both, so a single slot always
/// hid one of them behind whichever reply happened to land second.
final ProviderFamily<Map<String, WorkingCopyDiffReply>, RepoIdentity>
repoWorkingCopyDiffsProvider =
    Provider.family<Map<String, WorkingCopyDiffReply>, RepoIdentity>((
      ref,
      identity,
    ) {
      return ref.watch(
        repoSessionProvider(identity).select((state) => state.workingCopyDiffs),
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

/// Joins a summary and a description into the one string git stores.
///
/// Blank line between them, and nothing at all when the body is empty --
/// `git log --format=%s` reads the first line and `%b` everything after the
/// blank, so a missing blank makes the whole message the subject.
String composeCommitMessage(String summary, String description) {
  final String subject = summary.trim();
  final String body = description.trim();
  return body.isEmpty ? subject : '$subject\n\n$body';
}

/// Submits the current draft as a commit.
///
/// **The one place a commit is made from.** The message box's buttons and
/// `GbmActionId.repositoryCommit`/`repositoryAmendLastCommit` both come
/// through here, reading the draft out of [workingCopyDraftProvider] rather
/// than out of a `TextEditingController` -- which is why the shell can
/// submit at all without reaching into the view.
///
/// Returns false and does nothing when there is no subject: git rejects an
/// empty message, and a button that fires an operation destined to fail is
/// worse than one that does not fire.
bool submitCommit(WidgetRef ref, RepoIdentity identity, {bool amend = false}) {
  final WorkingCopyDraft draft = ref.read(workingCopyDraftProvider(identity));
  final String message = composeCommitMessage(draft.summary, draft.description);
  if (message.isEmpty) return false;
  commitChanges(ref, identity, message, amend: amend);
  return true;
}

/// Enters amend mode and asks for HEAD's message.
///
/// **The one place amend mode starts from**, for the same reason
/// [submitCommit] is the one place a commit is made from: the message box's
/// `Amend…` button and `GbmActionId.repositoryAmendLastCommit` both come
/// through here.
///
/// Asks explicitly rather than reading `commitMetaCache` and hoping. That
/// cache is filled by History's viewport scrolling past a commit, so in a
/// session that never opened History it is empty and the box would come up
/// blank -- which reads as "the commit had no message".
void beginAmendMode(WidgetRef ref, RepoIdentity identity) {
  ref.read(workingCopyDraftProvider(identity).notifier).beginAmend();
  final String head = ref.read(repoSessionProvider(identity)).refs.head.target;
  if (head.isEmpty) return;
  ref.read(repoSessionProvider(identity).notifier).requestCommitMeta(<String>[
    head,
  ]);
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
