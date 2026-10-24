// The full-context diff is asked for only while the full-file view is on,
// beside the -U3 one and under the same path per side; and switching the
// view on asks for the file already selected, without waiting for a click.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/app_preferences_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/repositories/working_copy_repository.dart'
    as wc;
import 'package:gbm_flutter/features/working_copy/working_copy_view.dart';

import '../../support/fake_repo_session.dart';
import '../../support/full_file_diffs.dart';
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
    WidgetTester tester, {
    Map<String, WorkingCopyDiffReply> diffs =
        const <String, WorkingCopyDiffReply>{},
    Map<String, WorkingCopyDiffReply> fullDiffs =
        const <String, WorkingCopyDiffReply>{},
  }) async {
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
        wc.repoWorkingCopyDiffsProvider(_identity).overrideWithValue(diffs),
        wc
            .repoWorkingCopyFullDiffsProvider(_identity)
            .overrideWithValue(fullDiffs),
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

  group('with the replies in', () {
    WorkingCopyDiffReply reply(DiffFile file) => WorkingCopyDiffReply(
      path: 'lib/a.dart',
      staged: false,
      diff: ParsedDiff(
        files: <DiffFile>[file],
        truncated: false,
        inputBytes: 0,
      ),
    );
    final String key = workingCopyDiffKey('lib/a.dart', staged: false);
    // Line 9 is the first after the first card's -U3 window (2-8): only a
    // fill row draws it, and it is near enough the top to be built.
    Finder filled() => find.text('L9', findRichText: true);

    // The real `refetchDisagreeingDiffs` runs on the fake: it is seen by the
    // pair of requests it sends.
    int unstagedFullRequests(FakeRepoSessionController fake) => requests(
      fake,
      'requestFullDiff',
    ).where((String r) => r == 'false:lib/a.dart').length;

    Future<FakeRepoSessionController> show(
      WidgetTester tester, {
      required Set<int> fullEdits,
      bool on = true,
    }) async {
      final (
        FakeRepoSessionController fake,
        ProviderContainer container,
      ) = await pump(
        tester,
        diffs: <String, WorkingCopyDiffReply>{
          key: reply(replacementsDiff(40, const <int>{5, 30}, context: 3)),
        },
        fullDiffs: <String, WorkingCopyDiffReply>{
          key: reply(replacementsDiff(40, fullEdits, context: kAllContext)),
        },
      );
      await setFullFile(container, on);
      await tester.pump();
      await tester.tap(find.text('lib/a.dart').first);
      await tester.pump();
      await tester.pump();
      return fake;
    }

    testWidgets('an agreeing full diff fills the pane and refetches nothing', (
      WidgetTester tester,
    ) async {
      final FakeRepoSessionController fake = await show(
        tester,
        fullEdits: const <int>{5, 30},
      );
      expect(filled(), findsOneWidget);
      expect(unstagedFullRequests(fake), 1, reason: 'the click only');
    });

    testWidgets('a disagreeing one asks for both diffs again, once per side '
        'that disagrees', (WidgetTester tester) async {
      final FakeRepoSessionController fake = await show(
        tester,
        fullEdits: const <int>{5, 31},
      );
      expect(filled(), findsNothing);
      // The click's request, then the refetch's -- which asks for the -U3
      // diff of that side again too, and for nothing on the staged side.
      expect(unstagedFullRequests(fake), 2);
      expect(
        requests(
          fake,
          'requestDiff',
        ).where((String r) => r == 'false:lib/a.dart'),
        hasLength(2),
      );
      expect(
        requests(
          fake,
          'requestFullDiff',
        ).where((String r) => r == 'true:lib/a.dart'),
        hasLength(1),
      );
    });

    // A full diff left in the session from before the view was switched off
    // is not the view's business any more: refetching it would spend git
    // invocations on a view nobody is looking at.
    testWidgets('off: a stale disagreeing full diff refetches nothing', (
      WidgetTester tester,
    ) async {
      final FakeRepoSessionController fake = await show(
        tester,
        fullEdits: const <int>{5, 31},
        on: false,
      );
      expect(unstagedFullRequests(fake), 0);
    });
  });
}
