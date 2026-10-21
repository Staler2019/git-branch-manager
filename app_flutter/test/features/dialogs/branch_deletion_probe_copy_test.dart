import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/branch_deletion_probe.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/features/dialogs/branch_deletion_probe_copy.dart';

// Strings ruled 2026-10-21 (G1, A6): counted against the upstream, named by
// its short form; no upstream or a gone one is not counted at all.
void main() {
  test('a counted branch names its commits and the short upstream', () {
    expect(
      branchDeletionProbeText(
        const ProbeCounted(
          'x',
          tipOid: 't',
          upstream: 'refs/remotes/origin/feature/x',
          unsyncedCount: 3,
        ),
      ),
      '3 個 commit 尚未同步到 origin/feature/x',
    );
  });

  test('a counted branch with nothing unsynced says so', () {
    expect(
      branchDeletionProbeText(
        const ProbeCounted(
          'x',
          tipOid: 't',
          upstream: 'refs/remotes/origin/x',
          unsyncedCount: 0,
        ),
      ),
      '已完整同步',
    );
  });

  test('no upstream, or a gone one, cannot be confirmed', () {
    expect(
      branchDeletionProbeText(const ProbeNoReference('x', tipOid: 't')),
      '沒有 upstream（或已 gone），無法確認是否已同步',
    );
  });

  test('a branch that is gone says so', () {
    expect(branchDeletionProbeText(const ProbeNotFound('x')), '已經不存在');
  });

  test('a failed read carries git\'s message', () {
    expect(
      branchDeletionProbeFailedText(
        const GitError(
          code: 1,
          codeName: 'Unknown',
          message: 'boom',
          detail: '',
          argv: <String>[],
          exitCode: 1,
        ),
      ),
      '無法確認尚未同步的 commit：boom',
    );
  });
}
