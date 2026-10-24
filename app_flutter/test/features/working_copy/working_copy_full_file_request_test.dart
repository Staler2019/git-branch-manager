// The full-context diff is asked for only while the full-file view is on,
// beside the -U3 one and under the same path per side; and switching the
// view on asks for the file already selected, without waiting for a click.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/app_preferences_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/repositories/working_copy_repository.dart'
    as wc;
import 'package:gbm_flutter/features/working_copy/working_copy_view.dart';

import '../../support/fake_repo_session.dart';
import '../../support/pump_app.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

/// Modified in the index and again in the work tree, so both sides exist.
const WorkingCopyEntry _bothSides = WorkingCopyEntry(
  path: 'lib/a.dart',
  oldPath: '',
  untracked: false,
  staged: true,
  indexStatus: FileChangeKind.modified,
  hasUnstagedChange: true,
  worktreeStatus: FileChangeKind.modified,
  unstagedAdded: 1,
  unstagedRemoved: 0,
  stagedAdded: 1,
  stagedRemoved: 0,
  conflict: ConflictKind.none,
  ancestorBlob: '',
  oursBlob: '',
  theirsBlob: '',
  similarity: 0,
  isSubmodule: false,
  isConflicted: false,
);

void main() {
  Future<(FakeRepoSessionController, ProviderContainer)> pump(
    WidgetTester tester,
  ) async {
    final FakeRepoSessionController fake = FakeRepoSessionController(
      _identity,
      const RepoSessionState(),
    );
    final ProviderContainer container = await pumpGbmWidget(
      tester,
      child: SizedBox(
        width: 800,
        height: 600,
        child: WorkingCopyView(identity: _identity),
      ),
      overrides: [
        repoSessionProvider(_identity).overrideWith((ref) => fake),
        wc
            .repoWorkingCopyStatusProvider(_identity)
            .overrideWithValue(
              const WorkingCopyStatus(entries: <WorkingCopyEntry>[_bothSides]),
            ),
        wc
            .repoWorkingCopyDiffsProvider(_identity)
            .overrideWithValue(const <String, WorkingCopyDiffReply>{}),
      ],
    );
    return (fake, container);
  }

  Future<void> setFullFile(ProviderContainer container, bool on) => container
      .read(appPreferencesProvider.notifier)
      .update((AppPreferences p) => p.copyWith(fullFileViewEnabled: on));

  /// `staged:path` of every [name] request, in order.
  List<String> requests(FakeRepoSessionController fake, String name) =>
      <String>[
        for (final FakeCommand c in fake.commandLog)
          if (c.name == name) '${c.args['staged']}:${c.args['path']}',
      ];

  testWidgets('off: selecting a file asks for the -U3 diffs only', (
    WidgetTester tester,
  ) async {
    final (FakeRepoSessionController fake, _) = await pump(tester);
    await tester.tap(find.text('lib/a.dart').first);
    await tester.pump();

    expect(requests(fake, 'requestDiff'), hasLength(2));
    expect(requests(fake, 'requestFullDiff'), isEmpty);
  });

  testWidgets('on: selecting a file asks for both sides\' full diffs too', (
    WidgetTester tester,
  ) async {
    final (FakeRepoSessionController fake, ProviderContainer container) =
        await pump(tester);
    await setFullFile(container, true);
    await tester.pump();
    await tester.tap(find.text('lib/a.dart').first);
    await tester.pump();

    expect(requests(fake, 'requestFullDiff'), <String>[
      'false:lib/a.dart',
      'true:lib/a.dart',
    ]);
  });

  testWidgets('switching it on asks for the selected file at once, and '
      'switching it off asks for nothing', (WidgetTester tester) async {
    final (FakeRepoSessionController fake, ProviderContainer container) =
        await pump(tester);
    await tester.tap(find.text('lib/a.dart').first);
    await tester.pump();
    expect(requests(fake, 'requestFullDiff'), isEmpty);

    await setFullFile(container, true);
    await tester.pump();
    expect(requests(fake, 'requestFullDiff'), <String>[
      'false:lib/a.dart',
      'true:lib/a.dart',
    ]);

    await setFullFile(container, false);
    await tester.pump();
    expect(requests(fake, 'requestFullDiff'), hasLength(2));
  });
}
