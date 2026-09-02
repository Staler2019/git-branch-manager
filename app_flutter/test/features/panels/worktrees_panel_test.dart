// WorktreesPanel is spec page 19's reference instance -- the panel the
// other eleven are meant to be copied from ("只換欄位不換造型"). So this
// asserts the P19 PANELSPEC row for manage-worktrees specifically:
//
//   list:    worktree 名稱 + 分支 + 狀態
//   detail:  路徑、HEAD、待提交數、鎖定原因
//   toolbar: Add、Prune、Open、Remove
//
// 待提交數 used to be recorded here as unobtainable; it is obtainable now
// (WorktreeInfo.pendingChanges, fed by gbm_worktree_request_pending_counts)
// and simply not rendered until this panel's P19 rewrite. WorktreesPanel's
// class doc carries the struck note.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/worktree_info.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/worktrees_panel.dart';

import '../../support/fake_repo_session.dart';
import 'panel_test_support.dart';

const WorktreeInfo _main = WorktreeInfo(
  path: '/src/git-branch-manager',
  headOid: 'a1b2c3d',
  branch: 'main',
  isMain: true,
  isBare: false,
  isDetached: false,
  isLocked: false,
  lockReason: '',
  isPrunable: false,
  prunableReason: '',
  // A plain refresh leaves every count unmeasured; the panel asks for the
  // real numbers separately. The current worktree also has no
  // `worktrees/<name>/` admin directory, so git records no creation time
  // for it -- null here is the production value, not a fixture shortcut.
  pendingChanges: null,
  pendingCountState: WorktreePendingCountState.unmeasured,
  createdAt: null,
);

const WorktreeInfo _locked = WorktreeInfo(
  path: '/src/wt/gbm-lfs',
  headOid: '9d02f4e',
  branch: 'feature/lfs',
  isMain: false,
  isBare: false,
  isDetached: false,
  isLocked: true,
  lockReason: 'on the USB drive',
  isPrunable: false,
  prunableReason: '',
  pendingChanges: null,
  pendingCountState: WorktreePendingCountState.unmeasured,
  createdAt: null,
);

/// A worktree fixture whose count fields are the only thing a caller varies.
/// Everything else is held identical across a transition, which is
/// [TEST-fixture-cannot-disagree] shape 10: if the untouched halves are
/// rebuilt per call, an unrelated rebuild can answer the assertion.
WorktreeInfo _wt({
  String path = '/src/wt/gbm-lfs',
  String headOid = '9d02f4e',
  int? pendingChanges,
  WorktreePendingCountState pendingCountState =
      WorktreePendingCountState.unmeasured,
}) => WorktreeInfo(
  path: path,
  headOid: headOid,
  branch: 'feature/lfs',
  isMain: false,
  isBare: false,
  isDetached: false,
  isLocked: false,
  lockReason: '',
  isPrunable: false,
  prunableReason: '',
  pendingChanges: pendingChanges,
  pendingCountState: pendingCountState,
  createdAt: null,
);

int _requests(PumpedPanel pumped) => pumped.fake.commandLog
    .where((FakeCommand c) => c.name == 'requestWorktreePendingCounts')
    .length;

Future<PumpedPanel> _pump(
  WidgetTester tester, {
  List<WorktreeInfo> worktrees = const <WorktreeInfo>[_main, _locked],
}) => pumpPanel(
  tester,
  WorktreesPanel(identity: panelTestIdentity),
  state: RepoSessionState(isOpen: true, worktrees: worktrees),
);

void main() {
  group('WorktreesPanel (spec P19 reference instance)', () {
    testWidgets('the toolbar carries PANELSPEC\'s four actions', (
      tester,
    ) async {
      await _pump(tester);

      for (final String label in const <String>[
        'Add…',
        'Prune',
        'Open',
        'Remove',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('the list shows name, branch and status per row', (
      tester,
    ) async {
      await _pump(tester);

      // 名稱 (base name, not the full path -- the path is detail-column
      // content), 分支, 狀態.
      expect(find.text('git-branch-manager'), findsOneWidget);
      expect(find.text('main · main'), findsOneWidget);
      expect(find.text('gbm-lfs'), findsOneWidget);
      expect(find.text('feature/lfs · locked'), findsOneWidget);
    });

    testWidgets('the detail pane is empty until a row is selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Select a worktree to see its details'), findsOneWidget);
    });

    testWidgets('selecting a row shows path, HEAD and lock reason', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();

      expect(find.text('Path'), findsOneWidget);
      expect(find.text('/src/wt/gbm-lfs'), findsOneWidget);
      expect(find.text('HEAD'), findsOneWidget);
      expect(find.text('feature/lfs · 9d02f4e'), findsOneWidget);
      expect(find.text('Lock reason'), findsOneWidget);
      expect(find.text('on the USB drive'), findsOneWidget);
    });

    testWidgets('Open and Remove are disabled with nothing selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(panelButton(tester, 'Open').onPressed, isNull);
      expect(panelButton(tester, 'Remove').onPressed, isNull);
    });

    // The main worktree is the repository -- git refuses to remove it, so
    // the button must not offer to.
    testWidgets('Remove stays disabled for the main worktree', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('git-branch-manager'));
      await tester.pumpAndSettle();

      expect(panelButton(tester, 'Open').onPressed, isNotNull);
      expect(panelButton(tester, 'Remove').onPressed, isNull);
    });

    testWidgets('Remove dispatches for a non-main worktree', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(panelButton(tester, 'Remove'), isNotNull);
    });

    testWidgets('an empty repository shows an empty-list message', (
      tester,
    ) async {
      await _pump(tester, worktrees: const <WorktreeInfo>[]);

      expect(find.text('No worktrees'), findsOneWidget);
    });
  });

  // P19's PANELSPEC detail cell for this panel lists 待提交數, and it now has
  // a source: gbm_worktree_request_pending_counts(). The panel asks for it
  // itself, because the count is NOT part of refreshRepoStatus()'s sweep --
  // see [STATE-refresh-entry-point] and the controller's doc comment.
  //
  // Every test below counts dispatches rather than inspecting the cache.
  // [CULT-cache-documents-three-things] requires counting precisely because
  // "a cache that recomputed every time and answered correctly is
  // indistinguishable from a working one by its output" -- and here the
  // recomputation *is* the dispatch, so the dispatch count is the instrument.
  group('WorktreesPanel pending-change counts', () {
    testWidgets('mounting asks for the counts exactly once', (tester) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[_wt()],
      );

      expect(_requests(pumped), 1);
    });

    testWidgets('a republish of the same path@headOid does not re-ask', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[_wt()],
      );

      pumped.fake.emit(
        pumped.fake.state.copyWith(
          worktrees: <WorktreeInfo>[
            _wt(
              pendingChanges: 9,
              pendingCountState: WorktreePendingCountState.measured,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(_requests(pumped), 1);
    });

    // The loop case, on its own because it is the one that spins. A failed
    // measurement leaves no count, so a gate reading "some count is null"
    // re-asks forever -- every republish, every focus refresh, for as long
    // as the panel is open. The gate reads "some key was never asked".
    testWidgets('a failed measurement is an answer, and is not re-asked', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[_wt()],
      );

      for (int i = 0; i < 3; i++) {
        pumped.fake.emit(
          pumped.fake.state.copyWith(
            worktrees: <WorktreeInfo>[
              _wt(pendingCountState: WorktreePendingCountState.failed),
            ],
          ),
        );
        await tester.pumpAndSettle();
      }

      expect(_requests(pumped), 1);
    });

    // add / remove / prune all change a path, and a checkout changes the
    // oid, so a key that is genuinely new is exactly when the count can have
    // changed -- and exactly when one more request is owed.
    testWidgets('a worktree at a new path is asked for once', (tester) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[_wt()],
      );

      pumped.fake.emit(
        pumped.fake.state.copyWith(
          worktrees: <WorktreeInfo>[
            _wt(),
            _wt(path: '/src/wt/gbm-docs'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(_requests(pumped), 2);
    });

    // The other half of the key, and the half no other test here varies:
    // a checkout inside a worktree keeps its path and changes its oid, and
    // the count can change with it. Without this case a key of `path` alone
    // would be indistinguishable from `path@headOid`.
    testWidgets('a worktree moved to a new commit is asked about again', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[_wt()],
      );

      pumped.fake.emit(
        pumped.fake.state.copyWith(
          worktrees: <WorktreeInfo>[_wt(headOid: 'ff17a20')],
        ),
      );
      await tester.pumpAndSettle();

      expect(_requests(pumped), 2);
    });

    testWidgets('a measured count is shown in the detail column', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[
          _wt(
            pendingChanges: 9,
            pendingCountState: WorktreePendingCountState.measured,
          ),
        ],
      );
      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();

      expect(find.text('9 個未提交變更'), findsOneWidget);
      expect(_requests(pumped), 1);
    });

    // The symptom the cache exists to prevent, and the only test that can
    // see it: a plain refreshWorktrees() (the focus sweep runs one every
    // 2 seconds of alt-tabbing) republishes every worktree as `unmeasured`,
    // because measuring is a separate request. Without the cache the number
    // in front of the user blinks back to 「未量測」 on a timer.
    testWidgets('a measured count survives a republish that says unmeasured', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[
          _wt(
            pendingChanges: 9,
            pendingCountState: WorktreePendingCountState.measured,
          ),
        ],
      );
      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();

      pumped.fake.emit(
        pumped.fake.state.copyWith(worktrees: <WorktreeInfo>[_wt()]),
      );
      await tester.pumpAndSettle();

      expect(find.text('9 個未提交變更'), findsOneWidget);
    });
  });
}
