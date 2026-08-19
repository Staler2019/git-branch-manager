// RepoSessionState.operationLog's cap used to be a hardcoded module constant
// (_kMaxOperationLogEntries = 500) whose doc comment incorrectly claimed to
// mirror OperationRunner.cpp's kMaxUndoEntries -- that C++ constant is 200
// and guards an entirely different list (undoJournal_, the one Undo Last
// reads), so the two numbers were never actually the same thing. The cap now
// comes from AppPreferences.logMemoryLimit (spec page 10 LOGRULES: "上限寫在
// Preferences，不隱藏"), read once into RepoSessionController.
// maxOperationLogEntries when a session opens (see repoSessionProvider's
// factory). This mirrors repo_session_commit_meta_cache_test.dart's pattern
// for the analogous commitMetaCache cap, testing the pure
// RepoSessionState.withOperationRecord eviction logic directly rather than
// going through a live FFI session.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

OperationRecord _record(int whenEpochMs) => OperationRecord(
  whenEpochMs: whenEpochMs,
  repoDir: '/repo',
  argv: const <String>['git', 'status'],
  commandLine: 'git status',
  exitCode: 0,
  durationMs: 1,
  stderrText: '',
  cancelled: false,
  timedOut: false,
);

void main() {
  group('RepoSessionState.withOperationRecord', () {
    test('appends to an empty log', () {
      const state = RepoSessionState(isOpen: true);
      final RepoSessionState next = state.withOperationRecord(
        _record(1),
        maxEntries: 5,
      );
      expect(next.operationLog.length, 1);
      expect(next.operationLog.single.whenEpochMs, 1);
    });

    test('does not evict anything while under maxEntries', () {
      RepoSessionState state = const RepoSessionState(isOpen: true);
      for (int i = 0; i < 5; i++) {
        state = state.withOperationRecord(_record(i), maxEntries: 5);
      }
      expect(state.operationLog.length, 5);
      expect(state.operationLog.first.whenEpochMs, 0);
    });

    test('evicts the oldest entry (newest-last, sublist from the tail) once '
        'over maxEntries -- the cap must come from the caller-supplied '
        'maxEntries, not a hardcoded constant', () {
      RepoSessionState state = const RepoSessionState(isOpen: true);
      // Feed one over a small explicit cap, one event at a time -- the
      // same way a real session accumulates operationLogRecord events.
      const int maxEntries = 5;
      for (int i = 0; i < maxEntries + 1; i++) {
        state = state.withOperationRecord(_record(i), maxEntries: maxEntries);
      }

      expect(
        state.operationLog.length,
        maxEntries,
        reason: 'the log must stay bounded at the supplied maxEntries',
      );
      expect(
        state.operationLog.map((r) => r.whenEpochMs),
        <int>[1, 2, 3, 4, 5],
        reason:
            'the oldest entry (whenEpochMs 0) must be evicted, and the '
            'rest must stay in newest-last order',
      );
    });

    test('a larger maxEntries (as Preferences -> logMemoryLimit allows up to '
        '2000 by default) keeps proportionally more history', () {
      RepoSessionState state = const RepoSessionState(isOpen: true);
      const int maxEntries = 2000;
      for (int i = 0; i < 2001; i++) {
        state = state.withOperationRecord(_record(i), maxEntries: maxEntries);
      }
      expect(state.operationLog.length, maxEntries);
      expect(state.operationLog.first.whenEpochMs, 1);
      expect(state.operationLog.last.whenEpochMs, 2000);
    });
  });
}
