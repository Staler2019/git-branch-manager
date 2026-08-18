// Verifies activeSequencerOperation() and SequencerOperationKind's
// capability matrix against the six flags RepoState can carry, plus the
// deliberate rebase > cherry-pick > revert > merge priority when more than
// one flag is set. The capability matrix (which of Abort/Skip/Continue is
// meaningful per kind) mirrors conflict_banner_test.dart's six cases, which
// are the app's existing behavioral spec for this.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_sequencer_operation.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';

RepoState _stateWithFlags(int flags) => RepoState(
  flags: flags,
  isClean: false,
  isSequencerOperation: false,
  rebaseStep: 0,
  rebaseTotal: 0,
  rebaseOntoLabel: '',
  indexLocked: false,
  indexLockAgeSeconds: null,
  describe: '',
);

void main() {
  group('activeSequencerOperation', () {
    test('returns null for a null RepoState', () {
      expect(activeSequencerOperation(null), isNull);
    });

    test(
      'returns null when no sequencer flag is set (clean or git apply --3way)',
      () {
        expect(activeSequencerOperation(_stateWithFlags(0)), isNull);
      },
    );

    test('merge flag -> merge', () {
      expect(
        activeSequencerOperation(_stateWithFlags(RepoStateFlags.merge)),
        SequencerOperationKind.merge,
      );
    });

    test('cherryPick flag -> cherryPick', () {
      expect(
        activeSequencerOperation(_stateWithFlags(RepoStateFlags.cherryPick)),
        SequencerOperationKind.cherryPick,
      );
    });

    test('revert flag -> revert', () {
      expect(
        activeSequencerOperation(_stateWithFlags(RepoStateFlags.revert)),
        SequencerOperationKind.revert,
      );
    });

    test('rebaseMerge flag -> rebase', () {
      expect(
        activeSequencerOperation(_stateWithFlags(RepoStateFlags.rebaseMerge)),
        SequencerOperationKind.rebase,
      );
    });

    test('rebaseApply flag -> rebase', () {
      expect(
        activeSequencerOperation(_stateWithFlags(RepoStateFlags.rebaseApply)),
        SequencerOperationKind.rebase,
      );
    });

    test('rebase + cherryPick both set (rebase using the merge backend leaves '
        'CHERRY_PICK_HEAD mid-step) -> rebase wins, not cherryPick', () {
      expect(
        activeSequencerOperation(
          _stateWithFlags(
            RepoStateFlags.rebaseMerge | RepoStateFlags.cherryPick,
          ),
        ),
        SequencerOperationKind.rebase,
      );
    });

    test('cherryPick + revert both set -> cherryPick wins over revert', () {
      expect(
        activeSequencerOperation(
          _stateWithFlags(RepoStateFlags.cherryPick | RepoStateFlags.revert),
        ),
        SequencerOperationKind.cherryPick,
      );
    });

    test('revert + merge both set -> revert wins over merge', () {
      expect(
        activeSequencerOperation(
          _stateWithFlags(RepoStateFlags.revert | RepoStateFlags.merge),
        ),
        SequencerOperationKind.revert,
      );
    });
  });

  group('SequencerOperationKind capability matrix', () {
    test('rebase: abort, skip, and continue all meaningful', () {
      expect(SequencerOperationKind.rebase.canAbort, isTrue);
      expect(SequencerOperationKind.rebase.canSkip, isTrue);
      expect(SequencerOperationKind.rebase.canContinue, isTrue);
    });

    test('cherryPick: abort, skip, and continue all meaningful', () {
      expect(SequencerOperationKind.cherryPick.canAbort, isTrue);
      expect(SequencerOperationKind.cherryPick.canSkip, isTrue);
      expect(SequencerOperationKind.cherryPick.canContinue, isTrue);
    });

    test('revert: abort, skip, and continue all disabled', () {
      expect(SequencerOperationKind.revert.canAbort, isFalse);
      expect(SequencerOperationKind.revert.canSkip, isFalse);
      expect(SequencerOperationKind.revert.canContinue, isFalse);
    });

    test('merge: abort only', () {
      expect(SequencerOperationKind.merge.canAbort, isTrue);
      expect(SequencerOperationKind.merge.canSkip, isFalse);
      expect(SequencerOperationKind.merge.canContinue, isFalse);
    });

    test('labels match the strings ConflictBanner/SequencerBanner render', () {
      expect(SequencerOperationKind.rebase.label, 'Rebase');
      expect(SequencerOperationKind.cherryPick.label, 'Cherry-pick');
      expect(SequencerOperationKind.revert.label, 'Revert');
      expect(SequencerOperationKind.merge.label, 'Merge');
    });

    test('gerunds match the strings _backgroundTasks/status_bar render', () {
      expect(SequencerOperationKind.rebase.gerund, 'Rebasing');
      expect(SequencerOperationKind.cherryPick.gerund, 'Cherry-picking');
      expect(SequencerOperationKind.revert.gerund, 'Reverting');
      expect(SequencerOperationKind.merge.gerund, 'Merging');
    });
  });
}
