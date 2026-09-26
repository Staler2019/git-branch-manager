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

  group('刪掉占用的本機分支之後，補 prune 先前被延後的 ref', () {
    // fetch 的 preview 說 origin/mine 已經 gone，但那時本機 mine 還占用著它，所以
    // 自動 prune 照裁定放過它。放過是一個**延後的決定**，不是終局：占用會消失（使用者
    // 刪掉那個本機分支），而 preview 不會再跑一次。
    void deferOriginMine(FakeRepoSessionController c) {
      c.debugRecordFetch(remoteName: 'origin');
      c.debugHandleEvent(_fetchFinished());
      c.debugHandleEvent(_previewReady('origin', <String>['origin/mine']));
    }

    // 本機 mine 被刪掉之後的 refs 快照。origin/mine 仍在磁碟上 -- 那就是使用者回報
    // 的「又以 remote 分支的樣子留在側邊欄」的那一列。
    RefSnapshot withoutLocalMine() => _snapshot(<RefInfo>[
      _remote('refs/remotes/origin/mine'),
      _remote('refs/remotes/origin/orphan'),
    ]);

    RefSnapshot withLocalMine() => _snapshot(<RefInfo>[
      _local('mine'),
      _remote('refs/remotes/origin/mine'),
      _remote('refs/remotes/origin/orphan'),
    ]);

    test('占用消失之後把它 prune 掉', () {
      final FakeRepoSessionController c = controller();
      deferOriginMine(c);
      expect(_prunes(c).length, 0, reason: '延後階段本身不該派工');

      c.publishRefs(withoutLocalMine());

      expect(_prunes(c).length, 1);
      expect(_prunes(c).single.args['remoteName'], 'origin');
      expect(_prunes(c).single.args['refs'], <String>[
        'refs/remotes/origin/mine',
      ]);
      // 背景做掉，所以失敗不會升 banner -- 走的是既有的 automatic 抑制路徑。
      expect(_prunes(c).single.args['automatic'], isTrue);
    });

    test('本機分支還在就不動它', () {
      // 對照組。沒有它，上一顆可能是因為亂 prune 而綠。
      final FakeRepoSessionController c = controller();
      deferOriginMine(c);

      c.publishRefs(withLocalMine());

      expect(_prunes(c).length, 0);
    });

    test('對話框來源的 preview 不會餵進延後表', () {
      // 沒有 fetch，所以這個 preview 不是自動的。gonePendingByRemote 無論來源都會被
      // 寫（現有行為，不動），但延後表不該被它填 -- 否則之後任何一次 refs 更新都會把
      // Prune 對話框正在列的 ref 刪掉，使用者的 Prune 按鈕就撞 not found。
      final FakeRepoSessionController c = controller();
      c.debugHandleEvent(_previewReady('origin', <String>['origin/mine']));
      expect(c.state.gonePendingRefs, <String>{'refs/remotes/origin/mine'});

      c.publishRefs(withoutLocalMine());

      expect(_prunes(c).length, 0);
    });

    test('只試一次', () {
      final FakeRepoSessionController c = controller();
      deferOriginMine(c);

      c.publishRefs(withoutLocalMine());
      c.publishRefs(withoutLocalMine());

      // 數而不是 any：第二次派工會對已經刪掉的 ref 再跑一次，拿到 not found。
      expect(_prunes(c).length, 1);
    });

    test('ref 已經不在 remoteBranches 裡就不送', () {
      // 別人（終端機、另一個 client）已經把它刪掉了。送過去只會拿到
      // 「remote-tracking branch not found」exit 1。
      final FakeRepoSessionController c = controller();
      deferOriginMine(c);

      c.publishRefs(
        _snapshot(<RefInfo>[_remote('refs/remotes/origin/orphan')]),
      );

      expect(_prunes(c).length, 0);
    });

    test('ref 又回到 remote 上就不送', () {
      final FakeRepoSessionController c = controller();
      deferOriginMine(c);
      // 較新的 preview 不再列它 -- withGonePendingFor 的空 entries 會把整片 slice
      // 移掉，這就是「它又回來了」的退場路徑。非 fetch 來源，所以不會重新延後。
      c.debugHandleEvent(_previewReady('origin', const <String>[]));
      expect(c.state.gonePendingRefs, isEmpty);

      // ref 仍在 remoteBranches 裡，所以「已經不在 remoteBranches」那一關過得去 --
      // 這一顆只能由「仍在 gonePendingByRemote 裡」擋下來。
      c.publishRefs(withoutLocalMine());

      expect(_prunes(c).length, 0);
    });

    test('中間一次無關的 refresh 不會讓延後項失效', () {
      // publishRefs 的頻率遠高於「使用者剛刪掉這個分支」：refreshHistory() 是
      // refreshRepoStatus() 的 Tier 1 成員，而 C++ 端 Session::onRefreshTimerFired()
      // 在每次 coalesced refresh 之後**無條件** emit GBM_EVENT_REFS_UPDATED，沒有
      // 「有沒有變」的閘門。所以「還被占用」是延後項在刪除之前的常態，不是可以把它
      // 逐出的理由 -- 逐出的話，fetch 與刪除之間按過一次 F5 就讓整個修正失效。
      //
      // 上面「本機分支還在就不動它」只有單次 observation，分不出「已逐出」與「留著
      // 還沒派工」：兩者在那一刻都是 0。
      final FakeRepoSessionController c = controller();
      deferOriginMine(c);

      c.publishRefs(withLocalMine());
      expect(_prunes(c).length, 0);

      c.publishRefs(withoutLocalMine());

      expect(_prunes(c).length, 1);
    });

    test('Prune 對話框開著時暫緩，關掉之後才派工', () {
      // 閘門 1 管的是「哪個 preview 可以餵延後表」；這一個管的是時機。sweep 的觸發
      // （publishRefs）是另一條獨立的路，所以對話框開著時它照樣會開火 -- 把使用者正
      // 要確認的那一列從底下抽掉，他們自己的 Prune 按鈕接著就撞 not found。
      final FakeRepoSessionController c = controller();
      deferOriginMine(c);
      c.beginPruneDialogPreview('origin');

      c.publishRefs(withoutLocalMine());
      expect(_prunes(c).length, 0, reason: '對話框正在列它');

      c.endPruneDialogPreview('origin');

      // 暫緩不消耗延後項，所以關窗時就做掉，而不是等到下一次 fetch。只斷言前半的話，
      // 「開過一次對話框就永久關掉 sweep」也會綠。
      expect(_prunes(c).length, 1);
    });

    test('關掉另一個 remote 的對話框不會開錯閘門', () {
      // 換上來的對話框可能在舊的 dispose 之前就宣告自己，所以帶著過期 remote 的
      // end 必須被忽略。
      final FakeRepoSessionController c = controller();
      deferOriginMine(c);
      c.beginPruneDialogPreview('origin');

      c.endPruneDialogPreview('upstream');
      c.publishRefs(withoutLocalMine());

      expect(_prunes(c).length, 0);
    });
  });
}
