// The one place a commit is made from. Both the message box's buttons and
// GbmActionId.repositoryCommit/repositoryAmendLastCommit come through
// submitCommit(), so what it does with an empty or partial draft is what
// every entry point does.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/repositories/working_copy_draft_repository.dart';
import 'package:gbm_flutter/data/repositories/working_copy_repository.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

const RepoIdentity _identity = RepoIdentity(
  workDir: '/repo',
  gitDir: '/repo/.git',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('composeCommitMessage', () {
    test('a body is separated from the subject by a blank line', () {
      // `git log --format=%s` reads the first line and `%b` everything past
      // the blank one; without it the whole message becomes the subject.
      expect(composeCommitMessage('subject', 'body'), 'subject\n\nbody');
    });

    test('no body means no trailing blank lines', () {
      expect(composeCommitMessage('subject', ''), 'subject');
    });

    test('whitespace-only fields count as empty', () {
      expect(composeCommitMessage('  subject  ', '   '), 'subject');
      expect(composeCommitMessage('   ', ''), isEmpty);
    });
  });

  group('submitCommit', () {
    late FakeRepoSessionController controller;

    Future<ProviderContainer> pumped(
      WidgetTester tester, {
      required String summary,
      String description = '',
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      controller = FakeRepoSessionController(
        _identity,
        const RepoSessionState(isOpen: true),
      );
      late ProviderContainer container;
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
            repoSessionProvider(_identity).overrideWith((_) => controller),
          ],
          child: MaterialApp(
            home: Consumer(
              builder: (BuildContext context, WidgetRef ref, _) {
                container = ProviderScope.containerOf(context);
                return TextButton(
                  onPressed: () => submitCommit(ref, _identity),
                  child: const Text('go'),
                );
              },
            ),
          ),
        ),
      );
      final WorkingCopyDraftController draft = container.read(
        workingCopyDraftProvider(_identity).notifier,
      );
      draft.updateSummary(summary);
      draft.updateDescription(description);
      return container;
    }

    testWidgets('reads the draft, not a text controller', (
      WidgetTester tester,
    ) async {
      await pumped(tester, summary: 'fix: it', description: 'why');

      await tester.tap(find.text('go'));

      final Iterable<FakeCommand> commits = controller.commandLog.where(
        (FakeCommand c) => c.name == 'commit',
      );
      expect(commits.length, 1);
      expect(commits.single.args['message'], 'fix: it\n\nwhy');
    });

    testWidgets('an empty subject submits nothing at all', (
      WidgetTester tester,
    ) async {
      // git rejects an empty message; a button that fires an operation
      // destined to fail is worse than one that does not fire.
      await pumped(tester, summary: '   ');

      await tester.tap(find.text('go'));

      expect(
        controller.commandLog
            .where((FakeCommand c) => c.name == 'commit')
            .length,
        0,
      );
    });
  });
}
