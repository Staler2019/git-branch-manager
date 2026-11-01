// A range that renamed a file lists it once, under its new name. Selecting it
// has to ask for the diff with the old name too, or git sees only the new
// half and the pane draws the whole file as added; and the row says it moved.
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
import 'package:gbm_flutter/widgets/file_change_glyph.dart';
import 'package:gbm_flutter/widgets/gbm_diff_header_bar.dart';
import 'package:gbm_flutter/widgets/gbm_row.dart';
import 'package:gbm_flutter/widgets/lucide_icon.dart';
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

final List<DiffFile> _files = <DiffFile>[
  _file('moved.dart', oldPath: 'origin.dart', kind: FileChangeKind.renamed),
  _file('edited.dart'),
  _file('gone.dart', kind: FileChangeKind.deleted),
];

Future<FakeRepoSessionController> _pump(
  WidgetTester tester, {
  bool againstWorkingCopy = false,
}) async {
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
          files: _files,
        ),
      },
      compareFileDiffResults: <String, CompareFileDiffResult>{
        CompareFileDiffResult.key(
          'main',
          'feature',
          true,
          'moved.dart',
        ): CompareFileDiffResult(
          left: 'main',
          right: 'feature',
          threeDot: true,
          path: 'moved.dart',
          diff: ParsedDiff(
            files: <DiffFile>[_files.first],
            truncated: false,
            inputBytes: 0,
          ),
        ),
      },
      compareWithWorkingCopyResults: <String, CompareWithWorkingCopyResult>{
        CompareWithWorkingCopyResult.key('main'): CompareWithWorkingCopyResult(
          ref: 'main',
          diff: ParsedDiff(files: _files, truncated: false, inputBytes: 0),
        ),
      },
    ),
  );
  final CompareTabsNotifier tabs = CompareTabsNotifier();
  tabs.open(
    left: 'main',
    right: againstWorkingCopy ? null : 'feature',
    threeDot: true,
  );
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

  String? glyphIn(WidgetTester tester, String name) {
    final Finder glyph = find.descendant(
      of: find.ancestor(of: find.text(name), matching: find.byType(GbmRow)),
      matching: find.byType(FileChangeGlyph),
    );
    expect(glyph, findsOneWidget, reason: name);
    final Finder icon = find.descendant(
      of: glyph,
      matching: find.byType(LucideIcon),
    );
    return icon.evaluate().isEmpty
        ? null
        : tester.widget<LucideIcon>(icon).name;
  }

  for (final bool againstWorkingCopy in <bool>[false, true]) {
    final String side = againstWorkingCopy ? 'the working copy' : 'a ref';
    testWidgets('a compare against $side draws each file kind in front of '
        'its name', (tester) async {
      await _pump(tester, againstWorkingCopy: againstWorkingCopy);

      expect(glyphIn(tester, 'moved.dart'), 'arrow-right');
      expect(glyphIn(tester, 'gone.dart'), 'minus');
      expect(glyphIn(tester, 'edited.dart'), isNull);
    });
  }

  // Spec: docs/claude-design-demo/rename-diff-display-spec.html, 畫面 2 --
  // 「Compare 還沒選檔時不畫標頭 ok」.
  for (final bool againstWorkingCopy in <bool>[false, true]) {
    final String side = againstWorkingCopy ? 'the working copy' : 'a ref';
    testWidgets('a compare against $side heads the selected file\'s diff '
        'with both of a rename\'s paths, and nothing before a pick', (
      tester,
    ) async {
      await _pump(tester, againstWorkingCopy: againstWorkingCopy);
      expect(find.byType(GbmDiffHeaderBar), findsNothing);

      await tester.tap(find.text('moved.dart'));
      await tester.pump();

      expect(
        tester.widget<GbmDiffHeaderBar>(find.byType(GbmDiffHeaderBar)).text,
        'origin.dart → moved.dart',
      );
    });
  }
}
