// The session's askpass answer: what was typed is what reaches git, from the
// Submit button and from Enter alike.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/credential/credential_dialog.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';

import '../../../support/fake_repo_session.dart';

const RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

Future<FakeRepoSessionController> _pump(WidgetTester tester) async {
  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    const RepoSessionState(isOpen: true, credentialPrompt: 'Password for x'),
  );
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: SizedBox.shrink()),
      ),
      GoRoute(
        path: '/dialog',
        builder: (context, state) =>
            const Scaffold(body: CredentialDialogContent(identity: _identity)),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        repoSessionProvider(_identity).overrideWith((Ref ref) => fake),
      ],
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: router,
      ),
    ),
  );
  router.push('/dialog');
  await tester.pumpAndSettle();
  return fake;
}

void main() {
  testWidgets('Enter submits what was typed, once, and closes', (tester) async {
    final FakeRepoSessionController fake = await _pump(tester);
    await tester.enterText(
      find.byKey(const Key('credential-secret-field')),
      's3',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    final List<FakeCommand> sent = fake.commandLog
        .where((FakeCommand c) => c.name == 'provideCredential')
        .toList();
    expect(sent, hasLength(1));
    expect(sent.single.args['secret'], 's3');
    expect(
      fake.commandLog.where((FakeCommand c) => c.name == 'cancelCredential'),
      isEmpty,
    );
    expect(find.byType(CredentialDialogContent), findsNothing);
  });
}
