// Verifies isActionEnabled() against spec page 07's STATES table (Clean vs
// Conflict availability) plus the two non-P7 gates it also owns as the
// single source of truth: branchRenameCurrentBranch (detached HEAD) and
// repositoryStageAll (no unstaged files). See gbm_action_availability.dart's
// doc comment for why these two are included despite not being spec P7
// conflict-gates.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_availability.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

RepoState _sequencerState() => const RepoState(
  flags: RepoStateFlags.merge,
  isClean: false,
  isSequencerOperation: true,
  rebaseStep: 0,
  rebaseTotal: 0,
  rebaseOntoLabel: '',
  indexLocked: false,
  indexLockAgeSeconds: null,
  describe: '',
);

WorkingCopyEntry _entry({bool unstaged = false, bool conflicted = false}) =>
    WorkingCopyEntry(
      path: 'lib/main.dart',
      oldPath: '',
      untracked: false,
      staged: false,
      indexStatus: FileChangeKind.modified,
      hasUnstagedChange: unstaged,
      worktreeStatus: FileChangeKind.modified,
      conflict: conflicted ? ConflictKind.bothModified : ConflictKind.none,
      ancestorBlob: '',
      oursBlob: '',
      theirsBlob: '',
      similarity: 0,
      isSubmodule: false,
      isConflicted: conflicted,
    );

void main() {
  group('isActionEnabled -- spec page 07 conflict gate', () {
    const clean = RepoSessionState();
    final conflict = RepoSessionState(
      repoState: _sequencerState(),
      workingCopyStatus: WorkingCopyStatus(entries: [_entry(conflicted: true)]),
    );

    // Every id spec page 07's STATES table says is disabled mid-conflict.
    const gatedIds = <GbmActionId>[
      GbmActionId.repositoryFetch,
      GbmActionId.repositoryPull,
      GbmActionId.repositoryPush,
      GbmActionId.remoteFetchAllRemotes,
      GbmActionId.repositoryCommit,
      GbmActionId.repositoryAmendLastCommit,
      GbmActionId.branchNewBranch,
      GbmActionId.branchCheckout,
      GbmActionId.branchMergeIntoCurrent,
      GbmActionId.branchRebaseOnto,
      GbmActionId.branchStashChanges,
      GbmActionId.branchDeleteBranch,
    ];

    for (final id in gatedIds) {
      test('$id: enabled when clean, disabled mid-conflict', () {
        expect(isActionEnabled(id, clean), isTrue);
        expect(isActionEnabled(id, conflict), isFalse);
      });
    }

    test(
      'conflictActive is true for the clean/conflict fixtures used above',
      () {
        expect(clean.conflictActive, isFalse);
        expect(conflict.conflictActive, isTrue);
      },
    );
  });

  group('isActionEnabled -- branchRenameCurrentBranch', () {
    test(
      'disabled on a detached HEAD (empty branch name), even when clean',
      () {
        const detached = RepoSessionState(refs: RefSnapshot.empty);
        expect(detached.refs.head.branchName, isEmpty);
        expect(
          isActionEnabled(GbmActionId.branchRenameCurrentBranch, detached),
          isFalse,
        );
      },
    );

    test('enabled with a real branch name and no conflict', () {
      const onBranch = RepoSessionState(
        refs: RefSnapshot(
          head: HeadInfo(
            kind: HeadKind.branch,
            branchName: 'main',
            fullRef: 'refs/heads/main',
            target: 'deadbeef',
          ),
          refs: <RefInfo>[],
          refCountGuardTripped: false,
          totalRefCount: 0,
        ),
      );
      expect(
        isActionEnabled(GbmActionId.branchRenameCurrentBranch, onBranch),
        isTrue,
      );
    });

    test('disabled with a real branch name but mid-conflict', () {
      final onBranchConflict = RepoSessionState(
        repoState: _sequencerState(),
        workingCopyStatus: WorkingCopyStatus(
          entries: [_entry(conflicted: true)],
        ),
        refs: const RefSnapshot(
          head: HeadInfo(
            kind: HeadKind.branch,
            branchName: 'main',
            fullRef: 'refs/heads/main',
            target: 'deadbeef',
          ),
          refs: <RefInfo>[],
          refCountGuardTripped: false,
          totalRefCount: 0,
        ),
      );
      expect(
        isActionEnabled(
          GbmActionId.branchRenameCurrentBranch,
          onBranchConflict,
        ),
        isFalse,
      );
    });
  });

  group('isActionEnabled -- repositoryStageAll', () {
    test('disabled when there are no unstaged files', () {
      const noUnstaged = RepoSessionState();
      expect(
        isActionEnabled(GbmActionId.repositoryStageAll, noUnstaged),
        isFalse,
      );
    });

    test(
      'enabled when there is at least one unstaged file, even mid-conflict',
      () {
        // Not a P7 rule interaction, just documenting that stageAll's gate is
        // independent of conflictActive -- unlike the twelve ids above.
        final hasUnstaged = RepoSessionState(
          repoState: _sequencerState(),
          workingCopyStatus: WorkingCopyStatus(
            entries: [_entry(unstaged: true), _entry(conflicted: true)],
          ),
        );
        expect(
          isActionEnabled(GbmActionId.repositoryStageAll, hasUnstaged),
          isTrue,
        );
      },
    );
  });

  group('isActionEnabled -- ids outside the state-gated set', () {
    test('always true regardless of state (not this policy\'s concern)', () {
      const clean = RepoSessionState();
      final conflict = RepoSessionState(
        repoState: _sequencerState(),
        workingCopyStatus: WorkingCopyStatus(
          entries: [_entry(conflicted: true)],
        ),
      );
      // viewToggleSidebar and the not-yet-implemented ids are gated (or
      // not) elsewhere -- this policy only owns state-dependent gates.
      for (final id in <GbmActionId>[
        GbmActionId.viewToggleSidebar,
        GbmActionId.fileNewRepository,
        GbmActionId.helpAbout,
      ]) {
        expect(isActionEnabled(id, clean), isTrue);
        expect(isActionEnabled(id, conflict), isTrue);
      }
    });
  });
}
