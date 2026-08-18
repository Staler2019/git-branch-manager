// Verifies ManageRemotesDialogContent's Add/Remove wiring reaches the
// real repoSessionProvider seam -- Phase 3 of the project-gaps plan:
// `git remote add`/`remove` now exist end-to-end (core -> capi -> FFI ->
// this dialog), closing the gap CLAUDE.md's "Known gaps" section used to
// document ("no entry point exists").
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/remote_info.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/manage_remotes/manage_remotes_dialog.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

import '../../../support/fake_repo_session.dart';

final RepoIdentity _testIdentity = RepoIdentity.forWorkDir('/test/repo');

const RemoteInfo _origin = RemoteInfo(
  name: 'origin',
  fetchUrl: 'https://example.com/repo.git',
  pushUrl: 'https://example.com/repo.git',
);

Future<FakeRepoSessionController> _pump(
  WidgetTester tester, {
  RepoSessionState initialState = const RepoSessionState(),
}) async {
  final FakeRepoSessionController fake = FakeRepoSessionController(
    _testIdentity,
    initialState,
  );

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      repoSessionProvider(_testIdentity).overrideWith((ref) => fake),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: ManageRemotesDialogContent(identity: _testIdentity),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return fake;
}

void main() {
  group('ManageRemotesDialogContent', () {
    testWidgets('Add remote… with both fields filled reaches addRemote', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(tester);

      await tester.tap(find.text('Add remote…'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'upstream',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'URL'),
        'git@example.com:upstream/repo.git',
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = fake.commandLog.singleWhere(
        (c) => c.name == 'addRemote',
      );
      expect(cmd.args['name'], 'upstream');
      expect(cmd.args['url'], 'git@example.com:upstream/repo.git');
    });

    testWidgets('Cancel does not reach addRemote', (tester) async {
      final FakeRepoSessionController fake = await _pump(tester);

      await tester.tap(find.text('Add remote…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'upstream',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(fake.commandLog.any((c) => c.name == 'addRemote'), isFalse);
    });

    testWidgets('Add with an empty URL does not reach addRemote (both fields '
        'required)', (tester) async {
      final FakeRepoSessionController fake = await _pump(tester);

      await tester.tap(find.text('Add remote…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'upstream',
      );
      // URL left empty.
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(fake.commandLog.any((c) => c.name == 'addRemote'), isFalse);
      // The dialog stays open on invalid input rather than silently
      // closing -- the Add button is still there to retry.
      expect(find.text('Add'), findsOneWidget);
    });

    testWidgets('Remove reaches removeRemote with that remote\'s name', (
      tester,
    ) async {
      final FakeRepoSessionController fake = await _pump(
        tester,
        initialState: const RepoSessionState(remotes: <RemoteInfo>[_origin]),
      );

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = fake.commandLog.singleWhere(
        (c) => c.name == 'removeRemote',
      );
      expect(cmd.args['name'], 'origin');
    });
  });
}
