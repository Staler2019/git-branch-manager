import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

RefInfo _remoteBranch(String fullName) => RefInfo(
  fullName: fullName,
  shortName: fullName.substring('refs/remotes/'.length),
  kind: RefKind.remoteBranch,
  target: 'a' * 40,
  // Deliberately not derived from anything else: a remote branch has no
  // upstream of its own, and a fixture that computes one field from another
  // cannot falsify code that makes the same derivation.
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

RefSnapshot _snapshotOf(List<String> remoteFullNames) => RefSnapshot(
  head: RefSnapshot.empty.head,
  refs: remoteFullNames.map(_remoteBranch).toList(),
  refCountGuardTripped: false,
  totalRefCount: remoteFullNames.length,
);

GbmEvent _fetchFinished({
  required bool succeeded,
  bool? refsMoved,
  Map<String, dynamic>? error,
}) {
  return GbmEvent(
    GbmEventType.workingCopyOperationFinished,
    utf8.encode(
      jsonEncode(<String, dynamic>{
        'succeeded': succeeded,
        'error': error,
        'choices': <dynamic>[],
        'summary': 'Fetch',
        'kind': 'fetch',
        // Only a background fetch's outcome carries the key (JsonCodec.cpp).
        'refsMoved': ?refsMoved,
      }),
    ),
  );
}

/// Shaped as `capi::toJson(const GitError&)` sends it; `code` 5 is
/// `GitError::Code::Auth` (src/core/base/Error.h).
Map<String, dynamic> _authError() => <String, dynamic>{
  'code': 5,
  'codeName': 'Auth',
  'message': 'Git needs credentials',
  'detail': 'fatal: could not read Username',
  'argv': <String>['git', 'fetch', 'origin'],
  'exitCode': 128,
};

/// A completion event for something else on the same channel, with no kind.
GbmEvent _otherWorkingCopyFinished() {
  return GbmEvent(
    GbmEventType.workingCopyOperationFinished,
    utf8.encode(
      jsonEncode(<String, dynamic>{
        'succeeded': true,
        'error': null,
        'choices': <dynamic>[],
        'summary': 'Stage files',
      }),
    ),
  );
}

List<String> _previewedRemotes(FakeRepoSessionController c) => c.commandLog
    .where((cmd) => cmd.name == 'requestRemotePrunePreview')
    .map((cmd) => cmd.args['remoteName'] as String)
    .toList();

void main() {
  group('remotesToPreviewAfterFetch', () {
    test('a single-remote fetch previews only that remote', () {
      // Previewing every remote after `fetch origin` would fire network
      // round trips the user never asked for.
      expect(
        remotesToPreviewAfterFetch(
          'origin',
          _snapshotOf(<String>[
            'refs/remotes/origin/main',
            'refs/remotes/upstream/main',
          ]),
        ),
        <String>['origin'],
      );
    });

    test('previews the named remote even when the snapshot has no refs '
        'for it', () {
      // A remote that has never been fetched has no remote-tracking refs
      // yet, but the user just fetched it by name -- deriving from the
      // snapshot alone would silently skip it.
      expect(remotesToPreviewAfterFetch('origin', RefSnapshot.empty), <String>[
        'origin',
      ]);
    });

    test('an empty remote name means fetch --all: every remote', () {
      expect(
        remotesToPreviewAfterFetch(
          '',
          _snapshotOf(<String>[
            'refs/remotes/origin/main',
            'refs/remotes/origin/dev',
            'refs/remotes/upstream/main',
          ]),
        ),
        <String>['origin', 'upstream'],
      );
    });

    test('fetch --all with no remote branches previews nothing', () {
      expect(remotesToPreviewAfterFetch('', RefSnapshot.empty), isEmpty);
    });

    test(
      'a remote name is never recovered by splitting on the first slash',
      () {
        // refs/remotes/origin/feature/old split naively yields "refs".
        expect(
          remotesToPreviewAfterFetch(
            '',
            _snapshotOf(<String>['refs/remotes/origin/feature/old']),
          ),
          <String>['origin'],
        );
      },
    );
  });

  group('a completed fetch requests a prune preview', () {
    FakeRepoSessionController controller() {
      final FakeRepoSessionController c = FakeRepoSessionController(
        _identity,
        RepoSessionState(
          refs: _snapshotOf(<String>[
            'refs/remotes/origin/main',
            'refs/remotes/upstream/main',
          ]),
        ),
      );
      addTearDown(c.dispose);
      return c;
    }

    test('a successful single-remote fetch previews that remote', () {
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: 'origin');

      c.debugHandleEvent(_fetchFinished(succeeded: true));

      expect(_previewedRemotes(c), <String>['origin']);
    });

    test('a successful fetch --all previews every remote', () {
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: '');

      c.debugHandleEvent(_fetchFinished(succeeded: true));

      expect(_previewedRemotes(c), <String>['origin', 'upstream']);
    });

    test('a failed fetch previews nothing', () {
      // Nothing was brought in, so nothing can have become gone -- and the
      // failure may well be "no network", in which case the preview (which
      // also contacts the remote) would only fail again.
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: 'origin');

      c.debugHandleEvent(_fetchFinished(succeeded: false));

      expect(_previewedRemotes(c), isEmpty);
    });

    test('a failed fetch still pops the queue', () {
      // The queue tracks submissions, not successes. Skipping the pop would
      // make the *next* fetch consume this request and preview the wrong
      // remote.
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: 'origin');
      c.debugRecordFetch(remoteName: 'upstream');

      c.debugHandleEvent(_fetchFinished(succeeded: false));
      c.debugHandleEvent(_fetchFinished(succeeded: true));

      expect(_previewedRemotes(c), <String>['upstream']);
    });

    test('another operation completing in between changes nothing', () {
      // The reason this goes through PendingOperationTracker at all:
      // roughly thirty methods share this completion channel.
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: 'origin');

      c.debugHandleEvent(_otherWorkingCopyFinished());
      expect(_previewedRemotes(c), isEmpty);

      c.debugHandleEvent(_fetchFinished(succeeded: true));
      expect(_previewedRemotes(c), <String>['origin']);
    });

    test('a fetch outcome with no recorded request previews nothing', () {
      // Should not happen, but the reducer must not crash or guess.
      final FakeRepoSessionController c = controller();

      c.debugHandleEvent(_fetchFinished(succeeded: true));

      expect(_previewedRemotes(c), isEmpty);
    });
  });
  group('a background (auto) fetch', () {
    FakeRepoSessionController controller() {
      final FakeRepoSessionController c = FakeRepoSessionController(
        _identity,
        RepoSessionState(
          refs: _snapshotOf(<String>['refs/remotes/origin/main']),
        ),
      );
      addTearDown(c.dispose);
      return c;
    }

    test('that moved no ref previews nothing', () {
      // A quiet remote cannot have made anything gone, and each preview is a
      // network round trip -- every N minutes, per remote.
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: 'origin', background: true);

      c.debugHandleEvent(_fetchFinished(succeeded: true, refsMoved: false));

      expect(_previewedRemotes(c), isEmpty);
    });

    test('that moved a ref previews like a manual fetch', () {
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: 'origin', background: true);

      c.debugHandleEvent(_fetchFinished(succeeded: true, refsMoved: true));

      expect(_previewedRemotes(c), <String>['origin']);
    });

    test('that fails leaves lastError alone', () {
      // 背景作業失敗一律不彈窗: the failure reaches the log and the status
      // bar's error summary through its operation record, never the banner.
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: 'origin', background: true);

      c.debugHandleEvent(_fetchFinished(succeeded: false, error: _authError()));

      expect(c.state.lastError, isNull);
    });

    test('a manual fetch that fails still sets lastError', () {
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: 'origin');

      c.debugHandleEvent(_fetchFinished(succeeded: false, error: _authError()));

      expect(c.state.lastError?.codeName, 'Auth');
    });

    test('silences only its own outcome, not a manual fetch queued after '
        'it', () {
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: 'origin', background: true);
      c.debugRecordFetch(remoteName: 'origin');

      c.debugHandleEvent(_fetchFinished(succeeded: false, error: _authError()));
      expect(c.state.lastError, isNull);
      c.debugHandleEvent(_fetchFinished(succeeded: false, error: _authError()));
      expect(c.state.lastError?.codeName, 'Auth');
    });
  });
}
