// 使用者回報：fetch 之後刪掉「remote 上已經被刪掉」的本機分支，那個分支又以 remote
// 分支的樣子留在側邊欄，F5 沒用，要再 fetch 一次才消失。
//
// 這一層跑真實的 WorkspaceScreen，因為 unit 層只證明 reducer 會派工，證不到使用者真的
// 看到那一列消失 -- 而「看到什麼」是整份回報的內容。三個狀態按順序走一遍：被占用而標記
// gone、占用消失後殘留成 remote-only 列（回報的症狀）、以及背景 prune 落地之後整列不見。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_tree_item.dart';

import '../support/fake_repo_session.dart';
import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

RefInfo _local(String shortName, {bool isHead = false}) => RefInfo(
  fullName: 'refs/heads/$shortName',
  shortName: shortName,
  kind: RefKind.localBranch,
  target: 'a' * 40,
  // 沒有 tracking config -- `git push origin HEAD` 的形狀，counterpart 由同名的
  // remote ref 解出來，這正是本輪要涵蓋的那一類分支。
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: isHead,
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
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'a' * 40,
  ),
  refs: refs,
  refCountGuardTripped: false,
  totalRefCount: refs.length,
);

/// 起始狀態：HEAD 是 main，另有一個本機 shipped 與它同名的 remote ref。
RefSnapshot _withShipped() => _snapshot(<RefInfo>[
  _local('main', isHead: true),
  _local('shipped'),
  _remote('refs/remotes/origin/main'),
  _remote('refs/remotes/origin/shipped'),
]);

/// 本機 shipped 被刪掉，但 remote-tracking ref 還在磁碟上。
RefSnapshot _withoutShipped() => _snapshot(<RefInfo>[
  _local('main', isHead: true),
  _remote('refs/remotes/origin/main'),
  _remote('refs/remotes/origin/shipped'),
]);

/// prune 真的做完之後。
RefSnapshot _pruned() => _snapshot(<RefInfo>[
  _local('main', isHead: true),
  _remote('refs/remotes/origin/main'),
]);

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

GbmEvent _pruneSucceeded() => GbmEvent(
  GbmEventType.operationFinished,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'succeeded': true,
      'error': null,
      'choices': <dynamic>[],
      'summary': 'Prune',
      'kind': 'prune-remote',
    }),
  ),
);

List<FakeCommand> _prunes(FakeRepoSessionController c) =>
    c.commandLog.where((FakeCommand cmd) => cmd.name == 'pruneRemote').toList();

BranchTreeItem _row(WidgetTester tester, String name) =>
    tester.widget<BranchTreeItem>(
      find.ancestor(of: find.text(name), matching: find.byType(BranchTreeItem)),
    );

void main() {
  testWidgets('刪掉占用的本機分支之後，殘留的 remote 列會被背景 prune 掉', (tester) async {
    final PumpedWorkspace w = await pumpWorkspace(
      tester,
      identity: _identity,
      initialState: RepoSessionState(isOpen: true, refs: _withShipped()),
    );

    // 1. fetch 的 preview 說 origin/shipped 已經 gone。本機 shipped 還占用它，所以
    //    照裁定不 prune，只標記 -- 使用者看到的是一列標記 gone 的本機分支。
    w.controller.debugRecordFetch(remoteName: 'origin');
    w.controller.debugHandleEvent(_fetchFinished());
    w.controller.debugHandleEvent(
      _previewReady('origin', <String>['origin/shipped']),
    );
    await tester.pumpAndSettle();

    expect(_row(tester, 'shipped').isGonePending, isTrue);
    expect(_prunes(w.controller).length, 0);

    // 2. 使用者刪掉本機 shipped。refs 重讀之後 origin/shipped 仍在磁碟上，所以側邊欄
    //    改畫一列 remote-only -- 這就是回報裡「又以 remote 分支的樣子留在那裡」。
    //    同一次 refs 更新要把補做的 prune 派出去。
    w.controller.publishRefs(_withoutShipped());
    await tester.pumpAndSettle();

    expect(
      _row(tester, 'shipped').ref.kind,
      RefKind.remoteBranch,
      reason: '本機列不見了，remote-only 列頂上來',
    );
    expect(_prunes(w.controller).length, 1);
    expect(_prunes(w.controller).single.args['refs'], <String>[
      'refs/remotes/origin/shipped',
    ]);

    // 3. prune 落地：成功的 outcome 清掉 gone 標記，refs 再更新一次就沒有這一列了。
    w.controller.debugHandleEvent(_pruneSucceeded());
    w.controller.publishRefs(_pruned());
    await tester.pumpAndSettle();

    expect(find.text('shipped'), findsNothing);
    // 不必第二次 fetch，這是整份回報的重點。
    expect(
      w.controller.commandLog
          .where((FakeCommand cmd) => cmd.name == 'fetchRemote')
          .length,
      0,
    );
    // 背景動作不打擾使用者（spec P10）。
    expect(w.controller.state.lastError, isNull);
  });
}
