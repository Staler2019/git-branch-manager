// 使用者裁定：worktree 的 prune 跟遠端分支的 prune 一樣「背景做掉，使用者不
// 需要知道」——本輪原本把「路徑失效」當成一個要畫給使用者看、還要配一個徽章顏
// 色的狀態，那個前提被推翻了。
//
// 對照 `repo_session_auto_prune_test.dart`（遠端那一半），這裡是同一條規則
// [REF-fetch-auto-prunes] 套到 worktree 上。兩邊的形狀刻意對齊，差別只在
// worktree 沒有「preview」這一步：`git worktree list --porcelain` 已經直接
// 說了哪一筆 prunable，所以觸發點是 worktree 清單本身的發佈。
//
// **迴圈安全是這支檔案的重點。** prune 之後 git 會再發一次 worktrees 更新，
// 而一個 prune 不掉的項目（鎖住的、或 prune 失敗的）在新的快照裡仍然 prunable
// ——「只要看到 prunable 就 prune」會就地變成無窮迴圈。閘門因此是「這個 path
// 這個 session 內還沒被試過」，不是「這個 path 現在還 prunable」，跟
// worktrees 面板的 `path@headOid` 快取把 `failed` 也寫進去是同一個教訓。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/worktree_info.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

WorktreeInfo _wt(
  String path, {
  bool prunable = false,
  bool locked = false,
  bool primary = false,
}) => WorktreeInfo(
  path: path,
  headOid: '9d02f4e',
  branch: 'feature/x',
  isMain: false,
  isBare: false,
  isDetached: false,
  isLocked: locked,
  lockReason: locked ? 'on a usb stick' : '',
  isPrunable: prunable,
  prunableReason: prunable ? 'gitdir file points to non-existent location' : '',
  isPrimary: primary,
  pendingChanges: null,
  pendingCountState: WorktreePendingCountState.unmeasured,
  createdAt: null,
);

/// An outcome carrying no `kind`, which is what a worktree prune's really
/// looks like — `PendingOperationKind` has no arm for it, so attribution is
/// unavailable and the suppressor has to match on `argv`.
GbmEvent _pruneFailed() => GbmEvent(
  GbmEventType.operationFinished,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'succeeded': false,
      'error': <String, dynamic>{
        'code': 1,
        'codeName': 'Unknown',
        'message': 'fatal: could not remove .git/worktrees/gone',
        'detail': '',
        'argv': <String>['worktree', 'prune', '--verbose'],
        'exitCode': 1,
      },
      'choices': <dynamic>[],
      'summary': 'Prune worktrees',
      'kind': '',
    }),
  ),
);

int _prunes(FakeRepoSessionController c) => c.commandLog
    .where((FakeCommand cmd) => cmd.name == 'pruneWorktrees')
    .length;

void main() {
  FakeRepoSessionController controller() {
    final FakeRepoSessionController c = FakeRepoSessionController(
      _identity,
      const RepoSessionState(isOpen: true),
    );
    addTearDown(c.dispose);
    return c;
  }

  group('a prunable worktree is pruned in the background', () {
    test('publishing one prunable worktree prunes exactly once', () {
      final FakeRepoSessionController c = controller();
      c.publishWorktrees(<WorktreeInfo>[
        _wt('/src/wt/here', primary: true),
        _wt('/src/wt/gone', prunable: true),
      ]);

      // Counted, not `.any` ([TEST-count-dont-any]): the whole hazard here is
      // dispatching the same prune more than once.
      expect(_prunes(c), 1);
    });

    test('a healthy worktree list prunes nothing', () {
      final FakeRepoSessionController c = controller();
      c.publishWorktrees(<WorktreeInfo>[_wt('/src/wt/here', primary: true)]);
      expect(_prunes(c), 0);
    });

    // The loop. git re-publishes the worktree list after a prune, and a
    // locked-or-failed entry is still prunable in that new snapshot.
    test('re-publishing the same prunable path does not prune again', () {
      final FakeRepoSessionController c = controller();
      final List<WorktreeInfo> list = <WorktreeInfo>[
        _wt('/src/wt/gone', prunable: true),
      ];
      c.publishWorktrees(list);
      c.publishWorktrees(list);
      c.publishWorktrees(list);
      expect(_prunes(c), 1, reason: 'the gate is per path, not per snapshot');
    });

    test('a genuinely new prunable path is pruned', () {
      final FakeRepoSessionController c = controller();
      c.publishWorktrees(<WorktreeInfo>[_wt('/src/wt/gone', prunable: true)]);
      c.publishWorktrees(<WorktreeInfo>[
        _wt('/src/wt/gone', prunable: true),
        _wt('/src/wt/alsogone', prunable: true),
      ]);
      expect(_prunes(c), 2);
    });

    // git itself refuses to prune a locked worktree, so asking would be a
    // command that cannot succeed. Locking is also the user saying 「keep
    // this」 about a path that is only *temporarily* absent — an unmounted
    // volume is the case the whole 建立於 caveat list is written in the
    // spirit of.
    test('a locked worktree is never pruned, however prunable it looks', () {
      final FakeRepoSessionController c = controller();
      c.publishWorktrees(<WorktreeInfo>[
        _wt('/src/wt/usb', prunable: true, locked: true),
      ]);
      expect(_prunes(c), 0);
    });

    test('the list is still published when nothing is pruned', () {
      final FakeRepoSessionController c = controller();
      c.publishWorktrees(<WorktreeInfo>[_wt('/src/wt/here', primary: true)]);
      expect(c.state.worktrees.single.path, '/src/wt/here');
    });
  });

  group('a background prune failing does not interrupt the user', () {
    test('its error is kept out of lastError', () {
      final FakeRepoSessionController c = controller();
      c.publishWorktrees(<WorktreeInfo>[_wt('/src/wt/gone', prunable: true)]);
      c.debugHandleEvent(_pruneFailed());

      expect(
        c.state.lastError,
        isNull,
        reason:
            'nobody asked for this prune, so nothing about it belongs in the '
            'banner workspace_screen renders from lastError (spec page 10)',
      );
    });

    test('a second failure with nothing in flight does surface', () {
      final FakeRepoSessionController c = controller();
      // No auto-prune was ever dispatched, so this one can only be the user's
      // own `Prune` button, and they are owed the reason it failed.
      c.debugHandleEvent(_pruneFailed());
      expect(c.state.lastError, isNotNull);
    });
  });
}
