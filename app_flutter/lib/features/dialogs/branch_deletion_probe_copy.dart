import '../../data/models/branch_deletion_probe.dart';
import '../../data/models/git_error.dart';
import '../../data/models/ref_snapshot.dart';

/// The per-branch line the delete dialogs draw from one
/// [BranchDeletionProbe] -- the batch rows and the Delete Blocked list read
/// it, so the count and its wording cannot disagree between them.
///
/// Wording ruled 2026-10-21 (G1, A6): the count is against the branch's
/// upstream, named in its short form (`origin/x`); a branch with no
/// upstream, or a gone one, is not counted and says it cannot be confirmed.
String branchDeletionProbeText(BranchDeletionProbe probe) => switch (probe) {
  ProbeCounted(unsyncedCount: 0) => '已完整同步',
  ProbeCounted(:final int unsyncedCount, :final String upstream) =>
    '$unsyncedCount 個 commit 尚未同步到 ${shortUpstreamName(upstream)}',
  ProbeNoReference() => '沒有 upstream（或已 gone），無法確認是否已同步',
  ProbeNotFound() => '已經不存在',
};

/// Drawn instead of any count when the read failed; a dialog showing it
/// never enables its delete button.
String branchDeletionProbeFailedText(GitError error) =>
    '無法確認尚未同步的 commit：${error.message}';
