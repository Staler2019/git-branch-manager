import 'git_error.dart';

/// Mirrors `gbm::BranchDeletionProbe` (src/core/git/ops/BranchOps.h) as
/// serialized by `capi::toJson(const BranchDeletionProbe&)`: what deleting
/// one local branch would lose, read before the user confirms.
sealed class BranchDeletionProbe {
  const BranchDeletionProbe(this.name);

  factory BranchDeletionProbe.fromJson(Map<String, dynamic> json) {
    final String name = json['name'] as String;
    final String tipOid = json['tipOid'] as String;
    return switch (json['state'] as String) {
      'notFound' => ProbeNotFound(name),
      'noReference' => ProbeNoReference(name, tipOid: tipOid),
      'counted' => ProbeCounted(
        name,
        tipOid: tipOid,
        upstream: json['upstream'] as String,
        unsyncedCount: json['unsyncedCount'] as int,
      ),
      final String other => throw FormatException(
        'unknown branch deletion probe state: $other',
      ),
    };
  }

  final String name;
}

/// The branch no longer exists -- a retry after a partial delete drops it.
final class ProbeNotFound extends BranchDeletionProbe {
  const ProbeNotFound(super.name);
}

/// No upstream, or a gone one: nothing to count against (使用者裁示
/// 2026-10-21). The dialog shows a notice and deletes with `-D` at [tipOid].
final class ProbeNoReference extends BranchDeletionProbe {
  const ProbeNoReference(super.name, {required this.tipOid});

  final String tipOid;
}

/// [unsyncedCount] commits on the branch that [upstream] does not have,
/// counted at [tipOid]. Zero is safe for `-d`: git compares against the same
/// upstream.
final class ProbeCounted extends BranchDeletionProbe {
  const ProbeCounted(
    super.name, {
    required this.tipOid,
    required this.upstream,
    required this.unsyncedCount,
  });

  final String tipOid;

  /// Full ref, e.g. `refs/remotes/origin/feature`.
  final String upstream;
  final int unsyncedCount;
}

/// One `GBM_EVENT_BRANCH_DELETION_PROBE_READY` reply. A failed read carries
/// [error] and no probes: it is neither "nothing to warn about" nor "no
/// upstream", so a caller must not delete on it.
class BranchDeletionProbeReply {
  const BranchDeletionProbeReply({required this.probes, this.error});

  factory BranchDeletionProbeReply.fromJson(Map<String, dynamic> json) {
    final Object? error = json['error'];
    return BranchDeletionProbeReply(
      error: error is Map<String, dynamic> ? GitError.fromJson(error) : null,
      probes: List<BranchDeletionProbe>.unmodifiable(
        (json['probes'] as List<dynamic>).map(
          (Object? e) =>
              BranchDeletionProbe.fromJson(e as Map<String, dynamic>),
        ),
      ),
    );
  }

  final List<BranchDeletionProbe> probes;
  final GitError? error;
}

/// One branch of a `deleteBranch` call. A forced entry carries the tip the
/// user was warned about; core refuses it when the branch has moved
/// (`StaleBranchTip`) or when the tip is missing (`MissingBranchTip`).
class DeleteBranchEntry {
  const DeleteBranchEntry.plain(this.name) : force = false, expectedTipOid = '';

  const DeleteBranchEntry.forced(this.name, {required this.expectedTipOid})
    : force = true;

  final String name;
  final bool force;
  final String expectedTipOid;

  @override
  bool operator ==(Object other) =>
      other is DeleteBranchEntry &&
      other.name == name &&
      other.force == force &&
      other.expectedTipOid == expectedTipOid;

  @override
  int get hashCode => Object.hash(name, force, expectedTipOid);

  @override
  String toString() => force
      ? 'DeleteBranchEntry.forced($name, $expectedTipOid)'
      : 'DeleteBranchEntry.plain($name)';
}

/// The remote half of a local delete, as one
/// `git push <remoteName> --delete <names...>`, sent by the controller only
/// once the local delete it belongs to has succeeded. Sent alongside, a refused local delete would
/// still lose the remote branch, and its outcome would replace the local
/// one's recovery request.
class RemoteBranchDeletion {
  const RemoteBranchDeletion({required this.remoteName, required this.names});

  final String remoteName;
  final List<String> names;

  @override
  bool operator ==(Object other) =>
      other is RemoteBranchDeletion &&
      other.remoteName == remoteName &&
      _sameNames(other.names, names);

  @override
  int get hashCode => Object.hash(remoteName, Object.hashAll(names));

  @override
  String toString() => 'RemoteBranchDeletion($remoteName, $names)';
}

bool _sameNames(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
