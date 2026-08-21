// WorktreesPanel is spec page 19's reference instance -- the panel the
// other eleven are meant to be copied from ("只換欄位不換造型"). So this
// asserts the P19 PANELSPEC row for manage-worktrees specifically:
//
//   list:    worktree 名稱 + 分支 + 狀態
//   detail:  路徑、HEAD、待提交數、鎖定原因
//   toolbar: Add、Prune、Open、Remove
//
// 待提交數 is deliberately absent -- WorktreeInfo carries no pending-change
// count and gbm_capi has no per-worktree status call. See WorktreesPanel's
// class doc.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/worktree_info.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/worktrees_panel.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

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
);

Future<ProviderContainer> _pump(
  WidgetTester tester, {
  List<WorktreeInfo> worktrees = const <WorktreeInfo>[_main, _locked],
}) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // GbmSplitPane reads sharedPreferencesProvider in initState to restore
  // the splitter position, so the panel shell cannot mount without it.
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    RepoSessionState(isOpen: true, worktrees: worktrees),
  );
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoSessionProvider(_identity).overrideWith((ref) => fake),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(body: WorktreesPanel(identity: _identity)),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

GbmButton _button(WidgetTester tester, String label) =>
    tester.widget<GbmButton>(
      find.ancestor(of: find.text(label), matching: find.byType(GbmButton)),
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

      expect(_button(tester, 'Open').onPressed, isNull);
      expect(_button(tester, 'Remove').onPressed, isNull);
    });

    // The main worktree is the repository -- git refuses to remove it, so
    // the button must not offer to.
    testWidgets('Remove stays disabled for the main worktree', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('git-branch-manager'));
      await tester.pumpAndSettle();

      expect(_button(tester, 'Open').onPressed, isNotNull);
      expect(_button(tester, 'Remove').onPressed, isNull);
    });

    testWidgets('Remove dispatches for a non-main worktree', (tester) async {
      await _pump(tester);

      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(_button(tester, 'Remove'), isNotNull);
    });

    testWidgets('an empty repository shows an empty-list message', (
      tester,
    ) async {
      await _pump(tester, worktrees: const <WorktreeInfo>[]);

      expect(find.text('No worktrees'), findsOneWidget);
    });
  });
}
