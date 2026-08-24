// Device-tier E2E (Phase 4): open a real repository, view History, switch
// branch -- against the real gbm_capi.dylib/.so and a real temp git repo,
// not FakeRepoSessionController. Complements test/integration/'s widget-tier
// coverage rather than duplicating it (see CLAUDE.md's "Testing tiers").
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/features/log_drawer/log_drawer.dart';
import 'package:gbm_flutter/features/sidebar/sidebar_panel.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repoPath;

  setUp(() {
    repoPath = createTempGitRepo();
    // A second branch to switch to, one commit ahead of main.
    runGit(repoPath, <String>['checkout', '-b', 'feature']);
    runGit(repoPath, <String>['commit', '--allow-empty', '-m', 'Feature work']);
    runGit(repoPath, <String>['checkout', 'main']);
  });

  tearDown(() => deleteTempGitRepo(repoPath));

  testWidgets(
    'open repo -> History shows the initial commit -> switch branch via '
    'sidebar updates HEAD',
    (tester) async {
      await pumpRealAppOn(tester, repoPath);

      // History (the cold-start landing view) renders the seeded commit.
      expect(find.text('Initial commit'), findsOneWidget);

      // Status bar reflects the branch git itself reports as HEAD.
      final String initialBranch = runGit(repoPath, <String>[
        'branch',
        '--show-current',
      ]).stdout.toString().trim();
      expect(initialBranch, 'main');
      expect(find.text('main'), findsWidgets);

      // Switch branch: double-click the "feature" row in the sidebar's
      // branch tree. A single click only selects it (P13 MULTIKEYS 單擊);
      // checkout is the second click (BRANCH_STATES 「點兩下即 checkout」).
      // "feature" also renders as a ref-chip badge on the History row that
      // carries it, so this must be scoped to the sidebar specifically.
      final Finder featureRow = find.descendant(
        of: find.byType(SidebarPanel),
        matching: find.text('feature'),
      );
      expect(
        featureRow,
        findsOneWidget,
        reason: 'sidebar should list the feature branch created in setUp',
      );
      await tester.tap(featureRow);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(featureRow);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final String branchAfterSwitch = runGit(repoPath, <String>[
        'branch',
        '--show-current',
      ]).stdout.toString().trim();
      expect(
        branchAfterSwitch,
        'feature',
        reason:
            'double-clicking the branch row should have run a real '
            'checkout',
      );
      expect(find.text('feature'), findsWidgets);

      // LOGRULES 記什麼 asks for 「應用層事件（開啟 repo、切分支、prune 掉
      // 哪些 ref）」 in the same log as the git invocations. This tier is the
      // only one that can see the first of those: `_open()` emits it after
      // the FFI handle is genuinely allocated, and
      // FakeRepoSessionController's bindings return nullptr from
      // sessionOpen() by design, so no widget-tier test reaches that line.
      //
      // Read off the drawer's data rather than its rendered rows. The list
      // is `reverse: true` with a builder, so the *oldest* entry -- which is
      // exactly the one this is here to check -- is scrolled out of the
      // viewport by the git records that follow it, and `find.text` only
      // sees what was built. Matching on a prefix also sidesteps macOS
      // canonicalising the temp path (/var/... vs /private/var/...), which
      // is not what this test is about.
      final LogDrawer drawer = tester.widget<LogDrawer>(find.byType(LogDrawer));
      final List<String> appEvents = drawer.records
          .whereType<AppLogEntry>()
          .map((AppLogEntry e) => e.message)
          .toList(growable: false);

      expect(
        appEvents,
        contains(startsWith('Opened repository ')),
        reason: 'the log should record 「開啟 repo」, not only git commands',
      );
      expect(appEvents, contains('Checked out feature'));
    },
  );
}
