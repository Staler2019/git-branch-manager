import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

WorkingCopyDiffReply _reply(String path, {required bool staged}) =>
    WorkingCopyDiffReply(path: path, staged: staged, diff: ParsedDiff.empty);

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

/// One raw entry, differing from a real `WorkingCopyEntry.fromJson` payload
/// by whichever named field a test overrides -- per
/// [TEST-fixture-cannot-disagree], every status fixture in this file is
/// built through [WorkingCopyStatus.fromJson], never by hand-constructing a
/// [WorkingCopyEntry], so the same decode path production uses is what the
/// fingerprint function sees.
Map<String, dynamic> _entry({
  String path = 'a.dart',
  String oldPath = '',
  bool untracked = false,
  bool staged = false,
  int indexStatus = 0,
  bool hasUnstagedChange = false,
  int worktreeStatus = 0,
  int unstagedAdded = 0,
  int unstagedRemoved = 0,
  int stagedAdded = 0,
  int stagedRemoved = 0,
  int conflict = 0,
  String ancestorBlob = '',
  String oursBlob = '',
  String theirsBlob = '',
  int similarity = 0,
  bool isSubmodule = false,
  bool isConflicted = false,
  int untrackedSize = 0,
  int untrackedMtimeTicks = 0,
}) {
  return <String, dynamic>{
    'path': path,
    'oldPath': oldPath,
    'untracked': untracked,
    'staged': staged,
    'indexStatus': indexStatus,
    'hasUnstagedChange': hasUnstagedChange,
    'worktreeStatus': worktreeStatus,
    'unstagedAdded': unstagedAdded,
    'unstagedRemoved': unstagedRemoved,
    'stagedAdded': stagedAdded,
    'stagedRemoved': stagedRemoved,
    'conflict': conflict,
    'ancestorBlob': ancestorBlob,
    'oursBlob': oursBlob,
    'theirsBlob': theirsBlob,
    'similarity': similarity,
    'isSubmodule': isSubmodule,
    'isConflicted': isConflicted,
    'untrackedSize': untrackedSize,
    'untrackedMtimeTicks': untrackedMtimeTicks,
  };
}

WorkingCopyStatus _status(List<Map<String, dynamic>> entries) =>
    WorkingCopyStatus.fromJson(<String, dynamic>{'entries': entries});

GbmEvent _diffReadyEvent(String path, {required bool staged}) => GbmEvent(
  GbmEventType.workingCopyDiffReady,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'path': path,
      'staged': staged,
      'diff': <String, dynamic>{
        'files': <dynamic>[],
        'truncated': false,
        'inputBytes': 0,
      },
    }),
  ),
);

FakeRepoSessionController _controller() {
  final FakeRepoSessionController c = FakeRepoSessionController(
    _identity,
    const RepoSessionState(isOpen: true),
  );
  return c;
}

void main() {
  group('workingCopyDiffKey', () {
    test('separates the two sides of one path', () {
      expect(
        workingCopyDiffKey('lib/main.dart', staged: true),
        isNot(workingCopyDiffKey('lib/main.dart', staged: false)),
        reason:
            'a key without the side would make the two replies overwrite '
            'each other -- which is exactly what the single lastDiff slot '
            'did, and why one pane was always empty',
      );
    });

    test('separates two paths on the same side', () {
      expect(
        workingCopyDiffKey('a.dart', staged: false),
        isNot(workingCopyDiffKey('b.dart', staged: false)),
      );
    });
  });

  group('RepoSessionState.workingCopyDiffs', () {
    test('holds both sides of a file at once', () {
      const RepoSessionState empty = RepoSessionState();

      final RepoSessionState both = empty.copyWith(
        workingCopyDiffs: <String, WorkingCopyDiffReply>{
          workingCopyDiffKey('lib/main.dart', staged: false): _reply(
            'lib/main.dart',
            staged: false,
          ),
          workingCopyDiffKey('lib/main.dart', staged: true): _reply(
            'lib/main.dart',
            staged: true,
          ),
        },
      );

      expect(both.workingCopyDiffs.length, 2);
      expect(both.workingCopyDiffs.values.map((r) => r.staged).toSet(), <bool>{
        false,
        true,
      });
    });

    test('starts empty rather than null, so a reader never has to ask '
        'whether anything has been fetched yet', () {
      expect(const RepoSessionState().workingCopyDiffs, isEmpty);
    });
  });

  group('publishWorkingCopyStatus retention (fix/refresh-ui-first-tiering '
      'C2b)', () {
    // The plan's own worked mistake: the obvious condition is "the path is
    // still present", and it is wrong -- staging a hunk renumbers the
    // *other* side's hunks too, so a survived path can still carry a stale
    // reply. Every case below turns exactly one field the reducer must
    // read, never "is path in status".
    test('an unchanged status keeps both sides of the selected file', () {
      final FakeRepoSessionController c = _controller();
      final WorkingCopyStatus status = _status(<Map<String, dynamic>>[
        _entry(
          path: 'a.dart',
          hasUnstagedChange: true,
          staged: true,
          unstagedAdded: 3,
          stagedAdded: 2,
        ),
      ]);

      c.publishWorkingCopyStatus(status);
      c.debugHandleEvent(_diffReadyEvent('a.dart', staged: false));
      c.debugHandleEvent(_diffReadyEvent('a.dart', staged: true));
      expect(c.state.workingCopyDiffs.length, 2);

      c.publishWorkingCopyStatus(status);

      expect(c.state.workingCopyDiffs.length, 2);
    });

    test('changed numstat on both sides drops both cached replies', () {
      final FakeRepoSessionController c = _controller();
      c.publishWorkingCopyStatus(
        _status(<Map<String, dynamic>>[
          _entry(
            path: 'a.dart',
            hasUnstagedChange: true,
            staged: true,
            unstagedAdded: 3,
            stagedAdded: 2,
          ),
        ]),
      );
      c.debugHandleEvent(_diffReadyEvent('a.dart', staged: false));
      c.debugHandleEvent(_diffReadyEvent('a.dart', staged: true));

      c.publishWorkingCopyStatus(
        _status(<Map<String, dynamic>>[
          _entry(
            path: 'a.dart',
            hasUnstagedChange: true,
            staged: true,
            unstagedAdded: 1,
            stagedAdded: 5,
          ),
        ]),
      );

      expect(c.state.workingCopyDiffs, isEmpty);
    });

    test('a file that goes clean is dropped; a sibling file survives in '
        'the same publish', () {
      final FakeRepoSessionController c = _controller();
      c.publishWorkingCopyStatus(
        _status(<Map<String, dynamic>>[
          _entry(path: 'a.dart', hasUnstagedChange: true, unstagedAdded: 3),
          _entry(path: 'b.dart', hasUnstagedChange: true, unstagedAdded: 5),
        ]),
      );
      c.debugHandleEvent(_diffReadyEvent('a.dart', staged: false));
      c.debugHandleEvent(_diffReadyEvent('b.dart', staged: false));

      // a.dart went clean and dropped out of the status entirely.
      c.publishWorkingCopyStatus(
        _status(<Map<String, dynamic>>[
          _entry(path: 'b.dart', hasUnstagedChange: true, unstagedAdded: 5),
        ]),
      );

      expect(
        c.state.workingCopyDiffs.containsKey(
          workingCopyDiffKey('a.dart', staged: false),
        ),
        isFalse,
      );
      expect(
        c.state.workingCopyDiffs.containsKey(
          workingCopyDiffKey('b.dart', staged: false),
        ),
        isTrue,
      );
    });

    test('a half-staged rename drops only the side whose numstat changed', () {
      final FakeRepoSessionController c = _controller();
      Map<String, dynamic> unstagedSide() =>
          _entry(path: 'old.dart', hasUnstagedChange: true, unstagedAdded: 1);
      c.publishWorkingCopyStatus(
        _status(<Map<String, dynamic>>[
          unstagedSide(),
          _entry(
            path: 'new.dart',
            oldPath: 'old.dart',
            staged: true,
            stagedAdded: 4,
            similarity: 80,
          ),
        ]),
      );
      c.debugHandleEvent(_diffReadyEvent('old.dart', staged: false));
      c.debugHandleEvent(_diffReadyEvent('new.dart', staged: true));

      // Only the staged side's numstat changes; the unstaged side is byte
      // for byte the same entry as before.
      c.publishWorkingCopyStatus(
        _status(<Map<String, dynamic>>[
          unstagedSide(),
          _entry(
            path: 'new.dart',
            oldPath: 'old.dart',
            staged: true,
            stagedAdded: 9,
            similarity: 80,
          ),
        ]),
      );

      expect(
        c.state.workingCopyDiffs.containsKey(
          workingCopyDiffKey('old.dart', staged: false),
        ),
        isTrue,
        reason: 'the unstaged side did not change and must survive',
      );
      expect(
        c.state.workingCopyDiffs.containsKey(
          workingCopyDiffKey('new.dart', staged: true),
        ),
        isFalse,
        reason: 'the staged side\'s numstat changed and must be dropped',
      );
    });

    test('a conflicted file whose blob changed is dropped even though its '
        'numstat did not move', () {
      final FakeRepoSessionController c = _controller();
      c.publishWorkingCopyStatus(
        _status(<Map<String, dynamic>>[
          _entry(
            path: 'c.dart',
            hasUnstagedChange: true,
            isConflicted: true,
            conflict: 2,
            unstagedAdded: 4,
            oursBlob: 'aaa',
          ),
        ]),
      );
      c.debugHandleEvent(_diffReadyEvent('c.dart', staged: false));

      c.publishWorkingCopyStatus(
        _status(<Map<String, dynamic>>[
          _entry(
            path: 'c.dart',
            hasUnstagedChange: true,
            isConflicted: true,
            conflict: 2,
            unstagedAdded: 4,
            oursBlob: 'bbb',
          ),
        ]),
      );

      expect(c.state.workingCopyDiffs, isEmpty);
    });

    test('an untracked file edited in place -- same line count, changed '
        'mtime -- is dropped', () {
      final FakeRepoSessionController c = _controller();
      c.publishWorkingCopyStatus(
        _status(<Map<String, dynamic>>[
          _entry(
            path: 'u.txt',
            untracked: true,
            hasUnstagedChange: true,
            unstagedAdded: 2,
            untrackedSize: 9,
            untrackedMtimeTicks: 1000,
          ),
        ]),
      );
      c.debugHandleEvent(_diffReadyEvent('u.txt', staged: false));

      c.publishWorkingCopyStatus(
        _status(<Map<String, dynamic>>[
          _entry(
            path: 'u.txt',
            untracked: true,
            hasUnstagedChange: true,
            unstagedAdded: 2, // unchanged -- an in-place edit is not a diff
            untrackedSize: 9, // unchanged
            untrackedMtimeTicks: 2000, // the only thing that moved
          ),
        ]),
      );

      expect(
        c.state.workingCopyDiffs,
        isEmpty,
        reason:
            'unstagedAdded alone cannot see this edit -- only '
            'untrackedMtimeTicks can, per the C2a fields',
      );
    });

    test('an untracked file with both C2a fields at 0 is dropped '
        'unconditionally, even across an otherwise identical republish', () {
      final FakeRepoSessionController c = _controller();
      final WorkingCopyStatus status = _status(<Map<String, dynamic>>[
        _entry(
          path: 'z.bin',
          untracked: true,
          hasUnstagedChange: true,
          untrackedSize: 0,
          untrackedMtimeTicks: 0,
        ),
      ]);

      c.publishWorkingCopyStatus(status);
      c.debugHandleEvent(_diffReadyEvent('z.bin', staged: false));
      expect(c.state.workingCopyDiffs, isNotEmpty);

      c.publishWorkingCopyStatus(status);

      expect(
        c.state.workingCopyDiffs,
        isEmpty,
        reason:
            '0/0 means "not measured", never "unchanged" -- '
            '[GIT-zero-means-unmeasured]',
      );
    });

    test('keepDiffDuringRefresh: false reproduces the old wholesale clear', () {
      final FakeRepoSessionController c = _controller();
      c.refreshFlags = const RefreshFlags(keepDiffDuringRefresh: false);
      final WorkingCopyStatus status = _status(<Map<String, dynamic>>[
        _entry(path: 'a.dart', hasUnstagedChange: true, unstagedAdded: 3),
      ]);

      c.publishWorkingCopyStatus(status);
      c.debugHandleEvent(_diffReadyEvent('a.dart', staged: false));
      expect(c.state.workingCopyDiffs, isNotEmpty);

      c.publishWorkingCopyStatus(status);

      expect(c.state.workingCopyDiffs, isEmpty);
    });
  });

  group('workingCopyDiffReady eviction bound (C2b)', () {
    test('bounded to kMaxCachedWorkingCopyDiffs; a re-touched key survives '
        'eviction, an untouched one does not', () {
      final FakeRepoSessionController c = _controller();

      for (final String path in <String>['1', '2', '3', '4']) {
        c.debugHandleEvent(_diffReadyEvent('$path.txt', staged: false));
      }
      expect(c.state.workingCopyDiffs.length, kMaxCachedWorkingCopyDiffs);

      // Re-touch '1.txt' -- must move to the back of the eviction order.
      c.debugHandleEvent(_diffReadyEvent('1.txt', staged: false));
      // Two more distinct keys: the first (5) evicts '2.txt' (the oldest
      // never re-touched), the second (6) evicts '3.txt'.
      c.debugHandleEvent(_diffReadyEvent('5.txt', staged: false));
      c.debugHandleEvent(_diffReadyEvent('6.txt', staged: false));

      expect(c.state.workingCopyDiffs.length, kMaxCachedWorkingCopyDiffs);
      final Set<String> survivors = c.state.workingCopyDiffs.keys
          .map((String key) => key.split(':')[1])
          .toSet();
      expect(
        survivors,
        <String>{'1.txt', '4.txt', '5.txt', '6.txt'},
        reason:
            "'1.txt' was re-touched and survives; '2.txt' and '3.txt' "
            'were each touched once, early, and were evicted first',
      );
    });
  });
}
