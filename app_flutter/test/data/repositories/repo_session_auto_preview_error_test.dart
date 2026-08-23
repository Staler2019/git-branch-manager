// The post-fetch prune preview is a background task: spec page 10 puts it in
// the "低優先度背景作業，失敗不彈窗" class. But the capi reports its failures
// on GBM_EVENT_ERROR_OCCURRED, which lands in RepoSessionState.lastError,
// which workspace_screen.dart renders as a GbmWarningBanner -- so without a
// suppression rule every fetch on an HTTPS remote with no cached credential
// would flash an error banner the user cannot act on.
// (Session::requestRemotePrunePreview has no askpass wiring: it passes a bare
// CancellationToken and no askpassDir.)
//
// A preview the *user* asked for, from the Prune dialog, must still surface.
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

GbmEvent _fetchFinished() => GbmEvent(
  GbmEventType.workingCopyOperationFinished,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'succeeded': true,
      'error': null,
      'choices': <dynamic>[],
      'summary': 'Fetch',
      'kind': 'fetch',
    }),
  ),
);

/// The exact argv shape `RemoteStore::prunePreview` builds
/// (RemoteOps.cpp: {"remote", "prune", remoteName, "--dry-run"}), wrapped in
/// the global flags `GitCommand` prepends.
GbmEvent _prunePreviewError(String remote) => GbmEvent(
  GbmEventType.errorOccurred,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'code': 5,
      'codeName': 'AuthFailed',
      'message': 'could not read Username for https://example.com',
      'detail': '',
      'argv': <String>[
        'git',
        '--no-optional-locks',
        '-C',
        '/test/repo',
        'remote',
        'prune',
        remote,
        '--dry-run',
      ],
      'exitCode': 128,
    }),
  ),
);

GbmEvent _unrelatedError() => GbmEvent(
  GbmEventType.errorOccurred,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'code': 5,
      'codeName': 'AuthFailed',
      'message': 'push rejected',
      'detail': '',
      'argv': <String>['git', '-C', '/test/repo', 'push', 'origin', 'main'],
      'exitCode': 1,
    }),
  ),
);

GbmEvent _prunePreviewReady(String remote) => GbmEvent(
  GbmEventType.remotePrunePreviewReady,
  utf8.encode(
    jsonEncode(<String, dynamic>{'remote': remote, 'refs': <dynamic>[]}),
  ),
);

void main() {
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

  /// Arranges "a post-fetch preview for [remote] is in flight".
  void fetchAndAwaitPreview(FakeRepoSessionController c, String remote) {
    c.debugRecordFetch(remoteName: remote);
    c.debugHandleEvent(_fetchFinished());
  }

  group('an automatic prune preview fails quietly', () {
    test('its failure does not become a banner', () {
      final FakeRepoSessionController c = controller();
      fetchAndAwaitPreview(c, 'origin');

      c.debugHandleEvent(_prunePreviewError('origin'));

      expect(c.state.lastError, isNull);
    });

    test('an already-shown error is not cleared either', () {
      // Suppression means "do not write", not "write null" -- an unrelated
      // failure the user still needs to see must survive.
      final FakeRepoSessionController c = controller();
      c.debugHandleEvent(_unrelatedError());
      expect(c.state.lastError, isNotNull);

      fetchAndAwaitPreview(c, 'origin');
      c.debugHandleEvent(_prunePreviewError('origin'));

      expect(c.state.lastError?.message, 'push rejected');
    });

    test('fetch --all suppresses each remote it previewed', () {
      final FakeRepoSessionController c = controller();
      fetchAndAwaitPreview(c, '');

      c.debugHandleEvent(_prunePreviewError('origin'));
      c.debugHandleEvent(_prunePreviewError('upstream'));

      expect(c.state.lastError, isNull);
    });
  });

  group('a user-initiated prune preview still surfaces', () {
    test('with no automatic preview in flight', () {
      final FakeRepoSessionController c = controller();

      c.debugHandleEvent(_prunePreviewError('origin'));

      expect(c.state.lastError?.codeName, 'AuthFailed');
    });

    test('for a different remote than the one being previewed', () {
      // Matching must be per remote, not "any prune preview is in flight" --
      // otherwise opening the Prune dialog for upstream during a post-fetch
      // preview of origin would swallow the dialog's own failure.
      final FakeRepoSessionController c = controller();
      fetchAndAwaitPreview(c, 'origin');

      c.debugHandleEvent(_prunePreviewError('upstream'));

      expect(c.state.lastError?.codeName, 'AuthFailed');
    });

    test('after the automatic preview has already replied', () {
      // The in-flight marker is consumed by the reply, so a later failure
      // for the same remote is the dialog's, not the fetch's.
      final FakeRepoSessionController c = controller();
      fetchAndAwaitPreview(c, 'origin');
      c.debugHandleEvent(_prunePreviewReady('origin'));

      c.debugHandleEvent(_prunePreviewError('origin'));

      expect(c.state.lastError?.codeName, 'AuthFailed');
    });

    test('a second failure for the same remote surfaces', () {
      // One in-flight request suppresses exactly one failure.
      final FakeRepoSessionController c = controller();
      fetchAndAwaitPreview(c, 'origin');

      c.debugHandleEvent(_prunePreviewError('origin'));
      expect(c.state.lastError, isNull);

      c.debugHandleEvent(_prunePreviewError('origin'));
      expect(c.state.lastError?.codeName, 'AuthFailed');
    });
  });

  group('unrelated errors are untouched', () {
    test('a failed push surfaces even while a preview is in flight', () {
      final FakeRepoSessionController c = controller();
      fetchAndAwaitPreview(c, 'origin');

      c.debugHandleEvent(_unrelatedError());

      expect(c.state.lastError?.message, 'push rejected');
    });
  });
}
