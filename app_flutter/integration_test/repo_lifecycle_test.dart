// Device-tier E2E (Phase 4): open a real repository, view History, switch
// branch -- against the real gbm_capi.dylib/.so and a real temp git repo,
// not FakeRepoSessionController. Complements test/integration/'s widget-tier
// coverage rather than duplicating it (see CLAUDE.md's "Testing tiers").
import 'package:flutter_test/flutter_test.dart';
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

      // Switch branch: tap the "feature" row in the sidebar's branch tree.
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
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final String branchAfterSwitch = runGit(repoPath, <String>[
        'branch',
        '--show-current',
      ]).stdout.toString().trim();
      expect(
        branchAfterSwitch,
        'feature',
        reason: 'tapping the branch row should have run a real checkout',
      );
      expect(find.text('feature'), findsWidgets);
    },
  );
}
