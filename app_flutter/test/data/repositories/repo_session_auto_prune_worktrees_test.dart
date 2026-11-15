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
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
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

/// A worktree prune's outcome as the library really sends it: through the
/// working-copy funnel, so on `workingCopyOperationFinished`, stamped
/// `prune-worktrees`. The controller pairs these with the prunes it
/// dispatched, in queue order, to tell its own background prune from the
/// user's.
GbmEvent _outcome({required bool succeeded, String kind = 'prune-worktrees'}) =>
    GbmEvent(
      GbmEventType.workingCopyOperationFinished,
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'succeeded': succeeded,
          'error': succeeded
              ? null
              : <String, dynamic>{
                  'code': 1,
                  'codeName': 'Unknown',
                  'message': 'fatal: could not remove .git/worktrees/gone',
                  'detail': '',
                  'argv': <String>['worktree', 'prune', '--verbose'],
                  'exitCode': 1,
                },
          'choices': <dynamic>[],
          'summary': 'Prune worktrees',
          'kind': kind,
        }),
      ),
    );

/// A real controller over an open fake session, so the real `pruneWorktrees`
/// body and its binding call run. Each prune answers the next value of
/// [pruneAnswers] (1 when empty), as `gbm_worktree_prune` would.
class _PruneBindings extends FakeGbmBindings {
  final List<int> pruneAnswers = <int>[];
  int pruneCalls = 0;
  Uint8List _staged = Uint8List(0);

  @override
  RepoStateJsonDart get repoStateJson => (Pointer<Void> session) {
    _staged = utf8.encode(
      jsonEncode(<String, dynamic>{
        'flags': 0,
        'isClean': true,
        'isSequencerOperation': false,
        'rebaseStep': 0,
        'rebaseTotal': 0,
        'rebaseOntoLabel': '',
        'indexLocked': false,
        'indexLockAgeSeconds': null,
        'preparedMessagePending': false,
        'describe': '',
      }),
    );
    return 0;
  };

  @override
  LastResultJsonLenDart get lastResultJsonLen =>
      () => _staged.length;

  @override
  LastResultJsonCopyDart get lastResultJsonCopy =>
      (Pointer<Uint8> out, int outLen) {
        out.asTypedList(outLen).setAll(0, _staged);
      };

  @override
  SessionOpenDart get sessionOpen =>
      (Pointer<Utf8> workDir, Pointer<Utf8> gitDir, Pointer<Utf8> commonDir) =>
          Pointer<Void>.fromAddress(1);

  @override
  SessionCloseDart get sessionClose => (Pointer<Void> session) {};

  @override
  RegisterCallbackDart get registerCallback =>
      (
        Pointer<Void> session,
        Pointer<NativeFunction<GbmEventCallbackNative>> callback,
        Pointer<Void> userData,
      ) => 1;

  @override
  HistoryRefreshDart get historyRefresh =>
      (Pointer<Void> session) => 1;

  @override
  WorkingCopyRefreshDart get workingCopyRefresh => (Pointer<Void> session) {};

  @override
  LocalIdentityRefreshDart get localIdentityRefresh =>
      (Pointer<Void> session) {};

  @override
  EffectiveIdentityRefreshDart get effectiveIdentityRefresh =>
      (Pointer<Void> session) {};

  @override
  WorktreePruneDart get worktreePrune => (Pointer<Void> session) {
    pruneCalls++;
    return pruneAnswers.isEmpty ? 1 : pruneAnswers.removeAt(0);
  };
}

class _NoopRecents extends FakeRecentsRepository {
  @override
  Future<void> recordOpen(String workDir) async {}
}

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
    late _PruneBindings bindings;
    late RepoSessionController c;

    setUp(() {
      bindings = _PruneBindings();
      c = RepoSessionController(bindings, _identity, _NoopRecents());
      addTearDown(c.dispose);
    });

    void autoPrune(String path) =>
        c.publishWorktrees(<WorktreeInfo>[_wt(path, prunable: true)]);

    test('its error is kept out of lastError', () {
      autoPrune('/src/wt/gone');
      expect(bindings.pruneCalls, 1);
      c.debugHandleEvent(_outcome(succeeded: false));

      expect(
        c.state.lastError,
        isNull,
        reason:
            'nobody asked for this prune, so nothing about it belongs in the '
            'banner workspace_screen renders from lastError (spec page 10)',
      );
    });

    test("a user's prune failing with nothing automatic queued surfaces", () {
      c.pruneWorktrees();
      c.debugHandleEvent(_outcome(succeeded: false));
      expect(c.state.lastError, isNotNull);
    });

    // A background prune that succeeded is accounted for too: otherwise it
    // stays "in flight" and swallows the user's next failure.
    test("an automatic prune's success does not hide the user's later "
        'failure', () {
      autoPrune('/src/wt/gone');
      c.debugHandleEvent(_outcome(succeeded: true));

      c.pruneWorktrees();
      c.debugHandleEvent(_outcome(succeeded: false));
      expect(c.state.lastError, isNotNull);
    });

    test('outcomes are paired with prunes in queue order', () {
      c.pruneWorktrees();
      autoPrune('/src/wt/gone');

      c.debugHandleEvent(_outcome(succeeded: false));
      final Object? users = c.state.lastError;
      expect(users, isNotNull, reason: "the first was the user's");

      // Suppression means "do not write": the user's error stays on screen.
      c.debugHandleEvent(_outcome(succeeded: false));
      expect(
        c.state.lastError,
        same(users),
        reason: 'the second was automatic',
      );
    });

    // An automatic prune that was never queued has no outcome coming; left
    // in the queue, it would be paired with the user's next prune and hide
    // its failure.
    test('an automatic prune that was not queued takes no outcome', () {
      bindings.pruneAnswers.add(0);
      autoPrune('/src/wt/gone');

      c.pruneWorktrees();
      c.debugHandleEvent(_outcome(succeeded: false));
      expect(c.state.lastError, isNotNull);
    });

    test('an outcome of another kind leaves the queue alone', () {
      autoPrune('/src/wt/gone');
      c.debugHandleEvent(_outcome(succeeded: false, kind: 'stage'));
      final Object? stage = c.state.lastError;
      expect(stage, isNotNull, reason: 'a stage failure surfaces');

      c.debugHandleEvent(_outcome(succeeded: false));
      expect(
        c.state.lastError,
        same(stage),
        reason: 'still the automatic prune',
      );
    });
  });
}
