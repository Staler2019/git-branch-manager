// A range that renamed a file lists it once, under its new name. Selecting it
// has to ask for the diff with the old name too, or git sees only the new
// half and the pane draws the whole file as added.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/compare_commit_entry.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/compare_tabs_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/compare/compare_page.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

DiffFile _file(String path, {String oldPath = '', FileChangeKind? kind}) =>
    DiffFile(
      oldPath: oldPath.isEmpty ? path : oldPath,
      newPath: path,
      kind: kind ?? FileChangeKind.modified,
      oldMode: '100644',
      newMode: '100644',
      oldBlob: 'aaa',
      newBlob: 'bbb',
      binary: false,
      similarity: kind == FileChangeKind.renamed ? 100 : 0,
      addedLines: 1,
      removedLines: 0,
      displayPath: path,
      hunks: const <DiffHunk>[],
    );

Future<FakeRepoSessionController> _pump(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'fileListViewMode': 'list',
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    RepoSessionState(
      compareResults: <String, CompareResult>{
        CompareResult.key('main', 'feature', true): CompareResult(
          left: 'main',
          right: 'feature',
          threeDot: true,
          mergeBase: 'abc123',
          commits: const <CompareCommitEntry>[],
          files: <DiffFile>[
            _file(
              'moved.dart',
              oldPath: 'origin.dart',
              kind: FileChangeKind.renamed,
            ),
            _file('edited.dart'),
          ],
        ),
      },
    ),
  );
  final CompareTabsNotifier tabs = CompareTabsNotifier();
  tabs.open(left: 'main', right: 'feature', threeDot: true);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoSessionProvider(_identity).overrideWith((ref) => fake),
      compareTabsProvider(_identity).overrideWith((ref) => tabs),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: ComparePage(identity: _identity, tabId: tabs.state.single.id),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

List<FakeCommand> _requests(FakeRepoSessionController fake) => fake.commandLog
    .where((FakeCommand c) => c.name == 'requestCompareFileDiff')
    .toList(growable: false);

void main() {
  testWidgets('selecting a renamed file asks for its diff with the old name', (
    tester,
  ) async {
    final FakeRepoSessionController fake = await _pump(tester);

    await tester.tap(find.text('moved.dart'));
    await tester.pump();

    final List<FakeCommand> requests = _requests(fake);
    expect(requests, hasLength(1));
    expect(requests.single.args['path'], 'moved.dart');
    expect(requests.single.args['oldPath'], 'origin.dart');
  });

  testWidgets('selecting a file that was not renamed sends no old name', (
    tester,
  ) async {
    final FakeRepoSessionController fake = await _pump(tester);

    await tester.tap(find.text('edited.dart'));
    await tester.pump();

    expect(_requests(fake).single.args['oldPath'], '');
  });
}
