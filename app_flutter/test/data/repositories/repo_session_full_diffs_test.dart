import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

// The full-file view's second diff (gbm_working_copy_full_diff): stored apart
// from the -U3 diffs under the same key, invalidated by the same fingerprint,
// and refetched at most once per (path, side, fingerprint) when it disagrees
// with the -U3 diff (feat/wc-full-file-view plan, step 2).

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

GbmEvent _event(int type, String path, {required bool staged}) => GbmEvent(
  type,
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

GbmEvent _fullReady(String path, {required bool staged}) =>
    _event(GbmEventType.workingCopyFullDiffReady, path, staged: staged);

GbmEvent _excerptReady(String path, {required bool staged}) =>
    _event(GbmEventType.workingCopyDiffReady, path, staged: staged);

WorkingCopyStatus _status({required int unstagedAdded}) =>
    WorkingCopyStatus.fromJson(<String, dynamic>{
      'entries': <dynamic>[
        <String, dynamic>{
          'path': 'a.dart',
          'oldPath': '',
          'untracked': false,
          'staged': true,
          'indexStatus': 1,
          'hasUnstagedChange': true,
          'worktreeStatus': 1,
          'unstagedAdded': unstagedAdded,
          'unstagedRemoved': 0,
          'stagedAdded': 1,
          'stagedRemoved': 0,
          'conflict': 0,
          'ancestorBlob': '',
          'oursBlob': '',
          'theirsBlob': '',
          'similarity': 0,
          'isSubmodule': false,
          'isConflicted': false,
          'untrackedSize': 0,
          'untrackedMtimeTicks': 0,
        },
      ],
      'lineCountsUnavailable': false,
    });

FakeRepoSessionController _controller() =>
    FakeRepoSessionController(_identity, const RepoSessionState(isOpen: true));

int _count(FakeRepoSessionController c, String name) =>
    c.commandLog.where((FakeCommand cmd) => cmd.name == name).length;

void main() {
  test('the event id matches gbm_capi.h', () {
    expect(GbmEventType.workingCopyFullDiffReady, 41);
  });

  group('workingCopyFullDiffs', () {
    test('a full-diff reply lands under the -U3 key, in its own map', () {
      final FakeRepoSessionController c = _controller();
      c.debugHandleEvent(_fullReady('a.dart', staged: true));

      final String key = workingCopyDiffKey('a.dart', staged: true);
      expect(c.state.workingCopyFullDiffs.keys, <String>[key]);
      expect(c.state.workingCopyFullDiffs[key]!.staged, isTrue);
      expect(
        c.state.workingCopyDiffs,
        isEmpty,
        reason:
            'a full diff must never stand in for the -U3 diff staging reads',
      );
    });

    test('a -U3 reply never lands in the full map', () {
      final FakeRepoSessionController c = _controller();
      c.debugHandleEvent(_excerptReady('a.dart', staged: false));
      expect(c.state.workingCopyFullDiffs, isEmpty);
      expect(c.state.workingCopyDiffs, hasLength(1));
    });

    test('is bounded like the -U3 map, dropping the least recently '
        'answered', () {
      final FakeRepoSessionController c = _controller();
      for (int i = 0; i <= kMaxCachedWorkingCopyDiffs; i++) {
        c.debugHandleEvent(_fullReady('f$i.dart', staged: false));
      }
      expect(
        c.state.workingCopyFullDiffs,
        hasLength(kMaxCachedWorkingCopyDiffs),
      );
      expect(
        c.state.workingCopyFullDiffs.containsKey(
          workingCopyDiffKey('f0.dart', staged: false),
        ),
        isFalse,
      );
    });

    test('a status publish that changes the fingerprint drops it, one that '
        'does not keeps it', () {
      final FakeRepoSessionController c = _controller();
      c.publishWorkingCopyStatus(_status(unstagedAdded: 1));
      c.debugHandleEvent(_fullReady('a.dart', staged: false));
      c.debugHandleEvent(_fullReady('a.dart', staged: true));

      c.publishWorkingCopyStatus(_status(unstagedAdded: 1));
      expect(c.state.workingCopyFullDiffs, hasLength(2));

      c.publishWorkingCopyStatus(_status(unstagedAdded: 2));
      expect(c.state.workingCopyFullDiffs.keys, <String>[
        workingCopyDiffKey('a.dart', staged: true),
      ], reason: 'only the unstaged side\'s fingerprint moved');
    });
  });

  group('refetchDisagreeingDiffs', () {
    test('refetches both diffs of that side once, then not again for the '
        'same fingerprint', () {
      final FakeRepoSessionController c = _controller();
      c.publishWorkingCopyStatus(_status(unstagedAdded: 1));

      expect(c.refetchDisagreeingDiffs('a.dart', staged: false), isTrue);
      expect(_count(c, 'requestDiff'), 1);
      expect(_count(c, 'requestFullDiff'), 1);

      expect(c.refetchDisagreeingDiffs('a.dart', staged: false), isFalse);
      expect(_count(c, 'requestDiff'), 1);
      expect(_count(c, 'requestFullDiff'), 1);
    });

    test('a new fingerprint allows exactly one more refetch', () {
      final FakeRepoSessionController c = _controller();
      c.publishWorkingCopyStatus(_status(unstagedAdded: 1));
      c.refetchDisagreeingDiffs('a.dart', staged: false);

      c.publishWorkingCopyStatus(_status(unstagedAdded: 2));
      expect(c.refetchDisagreeingDiffs('a.dart', staged: false), isTrue);
      expect(c.refetchDisagreeingDiffs('a.dart', staged: false), isFalse);
      expect(_count(c, 'requestDiff'), 2);
      expect(_count(c, 'requestFullDiff'), 2);
    });

    test('the two sides of one path are budgeted separately', () {
      final FakeRepoSessionController c = _controller();
      c.publishWorkingCopyStatus(_status(unstagedAdded: 1));
      expect(c.refetchDisagreeingDiffs('a.dart', staged: false), isTrue);
      expect(c.refetchDisagreeingDiffs('a.dart', staged: true), isTrue);
      final List<Object?> sides = <Object?>[
        for (final FakeCommand cmd in c.commandLog)
          if (cmd.name == 'requestFullDiff') cmd.args['staged'],
      ];
      expect(sides, <Object?>[false, true]);
    });
  });
}
