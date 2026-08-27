// The post-fetch automatic prune (使用者裁定：「delete 不要讓使用者知道
// prune，背景做掉」, scoped to 「僅限無本機分支者」).
//
// Driven through `debugHandleEvent`, which runs the *real* `_onEvent`, so
// these exercise the reducer rather than a stand-in for it. The discriminator
// under test is the one thing a preview reply does not carry: who asked for
// it. `prune_remote_branches_dialog.dart` requests previews too, and pruning
// off the back of that one would delete the refs out from under the list the
// user is looking at, then fail their own Prune button against refs that no
// longer exist.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

RefInfo _local(String shortName, {String upstream = ''}) => RefInfo(
  fullName: 'refs/heads/$shortName',
  shortName: shortName,
  kind: RefKind.localBranch,
  target: 'a' * 40,
  upstream: upstream,
  ahead: 0,
  behind: 0,
  // Never derived from `upstream`: %(upstream:track) is empty for a branch
  // exactly in sync, so a fixture computing one from the other cannot
  // falsify code that makes the same derivation.
  hasTrackingInfo: false,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

RefInfo _remote(String fullName) => RefInfo(
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

RefSnapshot _snapshot(List<RefInfo> refs) => RefSnapshot(
  head: RefSnapshot.empty.head,
  refs: refs,
  refCountGuardTripped: false,
  totalRefCount: refs.length,
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

GbmEvent _previewReady(String remote, List<String> shortRefs) => GbmEvent(
  GbmEventType.remotePrunePreviewReady,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'remote': remote,
      'refs': <dynamic>[
        for (final String ref in shortRefs) <String, dynamic>{'ref': ref},
      ],
    }),
  ),
);

GbmEvent _pruneFinished({required bool succeeded}) => GbmEvent(
  GbmEventType.operationFinished,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'succeeded': succeeded,
      'error': succeeded
          ? null
          : <String, dynamic>{
              'code': 1,
              'codeName': 'Unknown',
              'message': 'error: remote-tracking branch not found',
              'detail': '',
              'argv': <String>['branch', '--delete', '--remotes'],
              'exitCode': 1,
            },
      'choices': <dynamic>[],
      'summary': 'Prune',
      'kind': 'prune-remote',
    }),
  ),
);

List<FakeCommand> _prunes(FakeRepoSessionController c) =>
    c.commandLog.where((FakeCommand cmd) => cmd.name == 'pruneRemote').toList();

void main() {
  // origin/orphan has no local branch; origin/mine is claimed by a local
  // branch that never set an upstream (`git push origin HEAD`), which is the
  // case the whole round is about.
  FakeRepoSessionController controller() {
    final FakeRepoSessionController c = FakeRepoSessionController(
      _identity,
      RepoSessionState(
        refs: _snapshot(<RefInfo>[
          _local('mine'),
          _remote('refs/remotes/origin/mine'),
          _remote('refs/remotes/origin/orphan'),
        ]),
      ),
    );
    addTearDown(c.dispose);
    return c;
  }

  group('a fetch-triggered preview prunes what no local branch claims', () {
    test('prunes exactly the unclaimed ref', () {
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: 'origin');
      c.debugHandleEvent(_fetchFinished());

      c.debugHandleEvent(_previewReady('origin', <String>['origin/orphan']));

      // Counted, not `any`: a double dispatch would run the same delete
      // twice and the second would fail with "not found".
      expect(_prunes(c).length, 1);
      expect(_prunes(c).single.args['remoteName'], 'origin');
      expect(_prunes(c).single.args['refs'], <String>[
        'refs/remotes/origin/orphan',
      ]);
      expect(_prunes(c).single.args['automatic'], isTrue);
    });

    test('leaves a ref whose local branch still exists', () {
      // 使用者裁定：「有本機分支的保留 cloud-off，因為使用者還能 repush」.
      // Deleting the tracking ref would throw away the only thing telling
      // them the branch used to be on the remote.
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: 'origin');
      c.debugHandleEvent(_fetchFinished());

      c.debugHandleEvent(_previewReady('origin', <String>['origin/mine']));

      expect(_prunes(c).length, 0);
      expect(c.state.gonePendingRefs, <String>{'refs/remotes/origin/mine'});
    });

    test('splits a mixed preview, keeping the claimed half marked', () {
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: 'origin');
      c.debugHandleEvent(_fetchFinished());

      c.debugHandleEvent(
        _previewReady('origin', <String>['origin/mine', 'origin/orphan']),
      );

      expect(_prunes(c).length, 1);
      expect(_prunes(c).single.args['refs'], <String>[
        'refs/remotes/origin/orphan',
      ]);
      // Both are still marked here: the pruned one is cleared by the
      // prune's own success path, not by dispatching it.
      expect(c.state.gonePendingRefs, <String>{
        'refs/remotes/origin/mine',
        'refs/remotes/origin/orphan',
      });
    });

    test('an empty preview prunes nothing', () {
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: 'origin');
      c.debugHandleEvent(_fetchFinished());

      c.debugHandleEvent(_previewReady('origin', const <String>[]));

      expect(_prunes(c).length, 0);
    });

    test('a second preview for the same remote is not automatic', () {
      // One fetch, one automatic preview. The marker is consumed by the
      // first reply, so a later dialog-initiated reply for the same remote
      // must not inherit it.
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: 'origin');
      c.debugHandleEvent(_fetchFinished());

      c.debugHandleEvent(_previewReady('origin', <String>['origin/orphan']));
      c.debugHandleEvent(_previewReady('origin', <String>['origin/orphan']));

      expect(_prunes(c).length, 1);
    });
  });

  group('a dialog-triggered preview prunes nothing', () {
    test('no fetch, no automatic prune', () {
      // prune_remote_branches_dialog.dart calls requestRemotePrunePreview on
      // mount. If this fired, it would delete the rows out from under the
      // list the user opened the dialog to look at.
      final FakeRepoSessionController c = controller();

      c.debugHandleEvent(_previewReady('origin', <String>['origin/orphan']));

      expect(_prunes(c).length, 0);
      expect(c.state.gonePendingRefs, <String>{'refs/remotes/origin/orphan'});
    });

    test('a preview for a remote nobody fetched is not automatic', () {
      // Per remote, not "any preview is in flight": fetching origin must not
      // arm an auto-prune for upstream.
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: 'origin');
      c.debugHandleEvent(_fetchFinished());

      c.debugHandleEvent(_previewReady('upstream', <String>['upstream/x']));

      expect(_prunes(c).length, 0);
    });
  });

  group('a failed automatic prune does not raise the banner', () {
    test('lastError stays null', () {
      // Spec page 10: a background task the user did not initiate must not
      // interrupt them. The failure is still in the operation log -- every
      // git invocation is recorded there with its exit code, which is where
      // this whole bug report came from.
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: 'origin');
      c.debugHandleEvent(_fetchFinished());
      c.debugHandleEvent(_previewReady('origin', <String>['origin/orphan']));

      c.debugHandleEvent(_pruneFinished(succeeded: false));

      expect(c.state.lastError, isNull);
    });

    test('a user-initiated prune failing still raises it', () {
      // The control. Without this, "lastError is null" could just as well
      // mean the outcome never reached the reducer.
      final FakeRepoSessionController c = controller();
      c.debugRecordPruneRemote(
        remoteName: 'origin',
        refs: <String>['origin/orphan'],
      );

      c.debugHandleEvent(_pruneFinished(succeeded: false));

      expect(c.state.lastError, isNotNull);
    });

    test('an unrelated error already on screen survives', () {
      // Suppression means "do not write", not "write null".
      final FakeRepoSessionController c = controller();
      c.debugRecordFetch(remoteName: 'origin');
      c.debugHandleEvent(_fetchFinished());
      c.debugHandleEvent(_previewReady('origin', <String>['origin/orphan']));
      c.emit(
        c.state.copyWith(
          lastError: const GitError(
            code: 1,
            codeName: 'Unknown',
            message: 'something the user was reading',
            detail: '',
            argv: <String>[],
            exitCode: 1,
          ),
        ),
      );

      c.debugHandleEvent(_pruneFinished(succeeded: false));

      expect(c.state.lastError?.message, 'something the user was reading');
    });
  });
}
