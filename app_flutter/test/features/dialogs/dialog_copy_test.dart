// The dialogs' copy, held against the spec's per-element language rule.
//
// 使用者裁定：「現在都是中文的，那就改成中文」. The spec does not simply
// "use Chinese" -- counted from `DLGS` in `spec_logic.js`, it splits by
// element: dialog titles are English 26/0 and primary buttons 26/0, while
// field labels run 3/47 Chinese, options 40/81 and hints 0/13. So this file
// asserts *both* directions on every dialog it covers. A test that only
// looked for the Chinese would pass a dialog whose title had been
// translated too, which is the other way to get this wrong.
//
// The wording is transcribed from `DLGS` wherever the spec describes the
// same control, so most of these strings are quotations rather than
// translations. Where it does not -- merge's fast-forward-only radio, which
// is `--ff-only` and not the spec's plain `--ff` -- the copy is composed in
// the same voice and the divergence is recorded at the call site.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/cherry_pick/cherry_pick_dialog.dart';
import 'package:gbm_flutter/features/dialogs/merge/merge_dialog.dart';
import 'package:gbm_flutter/features/dialogs/stash_changes/stash_changes_dialog.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

const RepoIdentity _identity = RepoIdentity(
  workDir: '/tmp/repo',
  gitDir: '/tmp/repo/.git',
);

RefInfo _ref(String shortName) => RefInfo(
  fullName: 'refs/heads/$shortName',
  shortName: shortName,
  kind: RefKind.localBranch,
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

final RepoSessionState _state = RepoSessionState(
  isOpen: true,
  refs: RefSnapshot(
    head: const HeadInfo(
      kind: HeadKind.branch,
      branchName: 'main',
      fullRef: 'refs/heads/main',
      target: 'aaaa',
    ),
    refs: <RefInfo>[_ref('main'), _ref('feature/lane-allocator')],
    refCountGuardTripped: false,
    totalRefCount: 2,
  ),
);

Future<void> _pump(WidgetTester tester, Widget dialog) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final FakeRepoSessionController controller = FakeRepoSessionController(
    _identity,
    _state,
  );

  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(path: '/dialog', builder: (context, state) => dialog),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(prefs),
        repoSessionProvider(_identity).overrideWith((ref) => controller),
      ],
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  router.push('/dialog');
  await tester.pumpAndSettle();
}

/// Every label, option and hint the dialog draws, in one pass.
void _expectAll(List<String> texts) {
  for (final String text in texts) {
    expect(find.text(text), findsOneWidget, reason: 'missing copy: $text');
  }
}

void main() {
  group('Merge Branch', () {
    testWidgets('title and primary button stay English', (tester) async {
      await _pump(tester, const MergeDialogContent(identity: _identity));
      _expectAll(<String>['Merge Branch', 'Merge', 'Cancel']);
    });

    testWidgets('labels, options and hints are Chinese', (tester) async {
      await _pump(tester, const MergeDialogContent(identity: _identity));
      _expectAll(<String>[
        '合入 main',
        '來源分支',
        '只允許 fast-forward',
        'Merge commit（保留分支形狀）',
        'Squash 成一筆',
        'Commit 訊息（可留空）',
        '先 stash 未提交的變更',
      ]);
      expect(
        find.text('Branch to merge from'),
        findsNothing,
        reason: 'an English field label left behind is the miss',
      );
    });
  });

  group('Cherry-pick Commits', () {
    testWidgets('title and primary button stay English', (tester) async {
      await _pump(tester, const CherryPickDialogContent(identity: _identity));
      _expectAll(<String>['Cherry-pick Commits', 'Cherry-pick', 'Cancel']);
    });

    testWidgets('labels, options and hints are Chinese', (tester) async {
      await _pump(tester, const CherryPickDialogContent(identity: _identity));
      _expectAll(<String>[
        '套用這些 commit（依序）',
        '以空白或換行分隔，舊的在前',
        '不自動 commit（-n，套完停在工作區）',
        '先 stash 未提交的變更',
      ]);
    });
  });

  group('Stash Changes', () {
    testWidgets('title and primary button stay English', (tester) async {
      await _pump(tester, const StashChangesDialogContent(identity: _identity));
      _expectAll(<String>['Stash Changes', 'Stash', 'Cancel']);
    });

    testWidgets('labels, options and hints are Chinese', (tester) async {
      await _pump(tester, const StashChangesDialogContent(identity: _identity));
      _expectAll(<String>[
        '訊息',
        '空白時使用預設的 WIP on <branch>',
        '包含 untracked 檔案',
        '保留已 stage 的內容在工作區',
      ]);
      expect(
        find.text('Message (optional)'),
        findsNothing,
        reason: '「(optional)」 moved into the hint, it did not stay',
      );
    });
  });
}
