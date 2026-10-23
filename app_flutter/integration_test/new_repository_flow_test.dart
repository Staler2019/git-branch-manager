// Device-tier E2E: New repository against the real gbm_capi library. The
// widget tier fakes `repoInit`, and dart:ffi cannot check a C function's
// arity, so only a real call proves `gbm_repo_init(path, initial_branch)`
// receives the branch the dialog sends (N-D3, N-D6).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/features/welcome/welcome_screen.dart';
import 'package:gbm_flutter/features/workspace/widgets/workspace_action_shortcuts.dart';
import 'package:gbm_flutter/features/workspace/workspace_screen.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory parent;

  setUp(() => parent = Directory.systemTemp.createTempSync('gbm_e2e_new_'));
  tearDown(() => deleteTempGitRepo(parent.path));

  Future<void> create(
    WidgetTester tester, {
    required String name,
    required String branch,
  }) async {
    // File → New repository…: on macOS a system-menu item, which a test
    // cannot click; this is the handler its `onSelected` is.
    tester
        .widget<WorkspaceActionShortcuts>(find.byType(WorkspaceActionShortcuts))
        .handlers[GbmActionId.fileNewRepository]!();
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('new-repo-name-field')), name);
    await tester.enterText(
      find.byKey(const Key('new-repo-location-field')),
      parent.path,
    );
    await tester.enterText(
      find.byKey(const Key('new-repo-branch-field')),
      branch,
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(GbmButton, 'Create repository'));
    await tester.pump();
  }

  testWidgets('Create inits the repository on the chosen branch and opens it', (
    tester,
  ) async {
    // From the welcome screen: the router mounts the workspace before it
    // disposes the welcome screen, and each has a PlatformMenuBarHost.
    await pumpRealAppWithNoRepo(tester);
    await create(tester, name: 'fresh', branch: 'trunk');
    final String fresh = '${parent.path}/fresh';
    await pumpUntil(
      tester,
      () => tester
          .widgetList<WorkspaceScreen>(find.byType(WorkspaceScreen))
          .any((WorkspaceScreen w) => w.identity.workDir == fresh),
    );

    final String head = File('$fresh/.git/HEAD').readAsStringSync().trim();
    expect(head, 'ref: refs/heads/trunk');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('an invalid branch leaves nothing on disk and opens nothing', (
    tester,
  ) async {
    await pumpRealAppWithNoRepo(tester);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    await create(tester, name: 'refused', branch: 'a..b');
    await tester.pumpAndSettle();

    expect(Directory('${parent.path}/refused').existsSync(), isFalse);
    expect(find.byType(WorkspaceScreen), findsNothing);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });
}
