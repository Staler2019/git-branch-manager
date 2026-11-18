// WorktreesPanel's failure states (read-failure-states-spec.html). The
// worktree list is a refreshed list (R class): a failed refresh keeps the
// list it had and says so in the panel banner, with Open log -- and that
// banner replaces the gone-paths one (「兩則 banner 同時出現時，只顯示失敗那一則」).
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/worktree_info.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/worktrees_panel.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';
import 'package:gbm_flutter/widgets/gbm_open_log_button.dart';

import 'panel_test_support.dart';

const GitError _listError = GitError(
  code: 2,
  codeName: 'CommandFailed',
  message: 'fatal: not a git repository',
  detail: '',
  argv: <String>['git', 'worktree', 'list', '--porcelain'],
  exitCode: 128,
);

WorktreeInfo _worktree(String path, {bool prunable = false}) => WorktreeInfo(
  path: path,
  headOid: 'a1b2c3d',
  branch: 'main',
  isMain: !prunable,
  isBare: false,
  isDetached: false,
  isLocked: false,
  lockReason: '',
  isPrunable: prunable,
  prunableReason: prunable ? 'gitdir file points to non-existent location' : '',
  isPrimary: !prunable,
  pendingChanges: null,
  pendingCountState: WorktreePendingCountState.unmeasured,
  createdAt: null,
);

void main() {
  // (w1)
  testWidgets('a failed list refresh keeps the rows and shows the banner', (
    tester,
  ) async {
    final PumpedPanel pumped = await pumpPanel(
      tester,
      WorktreesPanel(identity: panelTestIdentity),
      state: RepoSessionState(
        isOpen: true,
        worktrees: <WorktreeInfo>[_worktree('/src/git-branch-manager')],
      ),
    );
    expect(find.byType(GbmWarningBanner), findsNothing);

    pumped.fake.emit(pumped.fake.state.copyWith(worktreesError: _listError));
    await tester.pumpAndSettle();

    expect(find.textContaining('git-branch-manager'), findsWidgets);
    expect(find.text('無法載入 worktree 清單。${_listError.message}'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GbmWarningBanner),
        matching: find.byType(GbmOpenLogButton),
      ),
      findsOneWidget,
    );
  });

  // (w2) O2: with gone paths too, the failure banner is the only one.
  testWidgets('the failure banner replaces the gone-paths banner', (
    tester,
  ) async {
    final PumpedPanel pumped = await pumpPanel(
      tester,
      WorktreesPanel(identity: panelTestIdentity),
      state: RepoSessionState(
        isOpen: true,
        worktrees: <WorktreeInfo>[
          _worktree('/src/git-branch-manager'),
          _worktree('/src/wt/gone', prunable: true),
        ],
      ),
    );
    expect(find.byType(GbmWarningBanner), findsOneWidget);
    expect(find.textContaining('無法載入'), findsNothing);

    pumped.fake.emit(pumped.fake.state.copyWith(worktreesError: _listError));
    await tester.pumpAndSettle();

    expect(find.byType(GbmWarningBanner), findsOneWidget);
    expect(find.text('無法載入 worktree 清單。${_listError.message}'), findsOneWidget);
  });
}
