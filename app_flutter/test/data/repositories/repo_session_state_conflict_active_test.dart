import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/repo_state.dart' as model;
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

void main() {
  group('RepoSessionState.conflictActive', () {
    test(
      'returns false when in clean state (no sequencer, no conflicted files)',
      () {
        final state = RepoSessionState(
          isOpen: true,
          repoState: null,
          workingCopyStatus: WorkingCopyStatus.empty,
        );
        expect(state.conflictActive, false);
      },
    );

    test(
      'returns true when repoState.isSequencerOperation is true but conflicted list is empty',
      () {
        final repoState = model.RepoState(
          flags: 0,
          isClean: false,
          isSequencerOperation: true,
          rebaseStep: 0,
          rebaseTotal: 0,
          rebaseOntoLabel: '',
          indexLocked: false,
          indexLockAgeSeconds: null,
          describe: '',
        );
        final state = RepoSessionState(
          isOpen: true,
          repoState: repoState,
          workingCopyStatus: WorkingCopyStatus.empty,
        );
        expect(state.conflictActive, true);
      },
    );

    test(
      'returns true when repoState is null or isSequencerOperation is false but conflicted list is non-empty',
      () {
        // Test with null repoState
        const conflictedEntry = WorkingCopyEntry(
          path: 'file.txt',
          oldPath: '',
          untracked: false,
          staged: false,
          indexStatus: FileChangeKind.modified,
          hasUnstagedChange: false,
          worktreeStatus: FileChangeKind.modified,
          conflict: ConflictKind.bothModified,
          ancestorBlob: 'abc123',
          oursBlob: 'def456',
          theirsBlob: 'ghi789',
          similarity: 100,
          isSubmodule: false,
          isConflicted: true,
        );

        final status = WorkingCopyStatus(
          entries: <WorkingCopyEntry>[conflictedEntry],
        );

        final state = RepoSessionState(
          isOpen: true,
          repoState: null,
          workingCopyStatus: status,
        );
        expect(state.conflictActive, true);
      },
    );

    test(
      'returns true when both repoState.isSequencerOperation and conflicted list are true',
      () {
        final repoState = model.RepoState(
          flags: 0,
          isClean: false,
          isSequencerOperation: true,
          rebaseStep: 0,
          rebaseTotal: 0,
          rebaseOntoLabel: '',
          indexLocked: false,
          indexLockAgeSeconds: null,
          describe: '',
        );

        const conflictedEntry = WorkingCopyEntry(
          path: 'file.txt',
          oldPath: '',
          untracked: false,
          staged: false,
          indexStatus: FileChangeKind.modified,
          hasUnstagedChange: false,
          worktreeStatus: FileChangeKind.modified,
          conflict: ConflictKind.bothModified,
          ancestorBlob: 'abc123',
          oursBlob: 'def456',
          theirsBlob: 'ghi789',
          similarity: 100,
          isSubmodule: false,
          isConflicted: true,
        );

        final status = WorkingCopyStatus(
          entries: <WorkingCopyEntry>[conflictedEntry],
        );

        final state = RepoSessionState(
          isOpen: true,
          repoState: repoState,
          workingCopyStatus: status,
        );
        expect(state.conflictActive, true);
      },
    );

    test(
      'returns true when repoState.isSequencerOperation is false but conflicted list is non-empty',
      () {
        final repoState = model.RepoState(
          flags: 0,
          isClean: false,
          isSequencerOperation: false,
          rebaseStep: 0,
          rebaseTotal: 0,
          rebaseOntoLabel: '',
          indexLocked: false,
          indexLockAgeSeconds: null,
          describe: '',
        );

        const conflictedEntry = WorkingCopyEntry(
          path: 'file.txt',
          oldPath: '',
          untracked: false,
          staged: false,
          indexStatus: FileChangeKind.modified,
          hasUnstagedChange: false,
          worktreeStatus: FileChangeKind.modified,
          conflict: ConflictKind.bothModified,
          ancestorBlob: 'abc123',
          oursBlob: 'def456',
          theirsBlob: 'ghi789',
          similarity: 100,
          isSubmodule: false,
          isConflicted: true,
        );

        final status = WorkingCopyStatus(
          entries: <WorkingCopyEntry>[conflictedEntry],
        );

        final state = RepoSessionState(
          isOpen: true,
          repoState: repoState,
          workingCopyStatus: status,
        );
        expect(state.conflictActive, true);
      },
    );

    test('returns false when both repoState.isSequencerOperation is false and '
        'conflicted list is empty', () {
      final repoState = model.RepoState(
        flags: 0,
        isClean: false,
        isSequencerOperation: false,
        rebaseStep: 0,
        rebaseTotal: 0,
        rebaseOntoLabel: '',
        indexLocked: false,
        indexLockAgeSeconds: null,
        describe: '',
      );
      final state = RepoSessionState(
        isOpen: true,
        repoState: repoState,
        workingCopyStatus: WorkingCopyStatus.empty,
      );
      expect(state.conflictActive, false);
    });
  });
}
