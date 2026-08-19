// Verifies ComparePage's file list (both the ref-vs-ref and
// ref-vs-Working-Copy sides) actually reads the shared
// fileListViewModeProvider and renders through FileTreeFolderRow in tree
// mode -- spec page 03 item 10: the same List/Tree preference applies to
// Working Copy, History's Changed files, Compare's Files, and the Conflict
// window's file rail. _RefCompareFileList/_WorkingCopyFileList are private
// to compare_page.dart, so this drives them through the real ComparePage
// rather than importing them directly (mirrors
// manage_remotes_dialog_test.dart's FakeRepoSessionController pattern).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/compare_commit_entry.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/compare_tabs_repository.dart';
import 'package:gbm_flutter/data/repositories/file_list_view_mode_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/compare/compare_page.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/file_list_mode_toggle_button.dart';
import 'package:gbm_flutter/widgets/file_tree_folder_row.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

DiffFile _file(String path) => DiffFile(
  oldPath: path,
  newPath: path,
  kind: FileChangeKind.modified,
  oldMode: '100644',
  newMode: '100644',
  oldBlob: 'aaa',
  newBlob: 'bbb',
  binary: false,
  similarity: 0,
  addedLines: 1,
  removedLines: 0,
  displayPath: path,
  hunks: const <DiffHunk>[],
);

/// Pumps a ComparePage with [tab] already open and [viewMode] preset via
/// SharedPreferences (read once at container construction -- see
/// fileListViewModeRepositoryProvider), backed by [state]'s compare
/// results.
Future<void> _pump(
  WidgetTester tester, {
  required CompareTabSpec tab,
  required RepoSessionState state,
  required FileListViewMode viewMode,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'fileListViewMode': viewMode == FileListViewMode.tree ? 'tree' : 'list',
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    state,
  );
  final CompareTabsNotifier tabsNotifier = CompareTabsNotifier();
  tabsNotifier.open(left: tab.left, right: tab.right, threeDot: tab.threeDot);

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoSessionProvider(_identity).overrideWith((ref) => fake),
      compareTabsProvider(_identity).overrideWith((ref) => tabsNotifier),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: ComparePage(
            identity: _identity,
            tabId: tabsNotifier.state.single.id,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ComparePage file list -- ref vs ref', () {
    const String left = 'main';
    const String right = 'feature';
    final List<DiffFile> files = <DiffFile>[
      _file('a.dart'),
      _file('b/c.dart'),
      _file('b/d.dart'),
    ];
    final RepoSessionState stateWithResult = RepoSessionState(
      compareResults: <String, CompareResult>{
        CompareResult.key(left, right, true): CompareResult(
          left: left,
          right: right,
          threeDot: true,
          mergeBase: 'abc123',
          commits: const <CompareCommitEntry>[],
          files: files,
        ),
      },
    );

    testWidgets('shows the shared list/tree toggle button', (tester) async {
      await _pump(
        tester,
        tab: const CompareTabSpec(id: 'unused', left: left, right: right),
        state: stateWithResult,
        viewMode: FileListViewMode.list,
      );

      expect(find.byType(FileListModeToggleButton), findsOneWidget);
    });

    testWidgets('tree mode renders a FileTreeFolderRow for a multi-file '
        'folder', (tester) async {
      await _pump(
        tester,
        tab: const CompareTabSpec(id: 'unused', left: left, right: right),
        state: stateWithResult,
        viewMode: FileListViewMode.tree,
      );

      expect(find.byType(FileTreeFolderRow), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(find.text('a.dart'), findsOneWidget);
    });
  });

  group('ComparePage file list -- ref vs Working Copy', () {
    const String left = 'main';
    final List<DiffFile> files = <DiffFile>[
      _file('a.dart'),
      _file('b/c.dart'),
      _file('b/d.dart'),
    ];
    final RepoSessionState stateWithResult = RepoSessionState(
      compareWithWorkingCopyResults: <String, CompareWithWorkingCopyResult>{
        CompareWithWorkingCopyResult.key(left): CompareWithWorkingCopyResult(
          ref: left,
          diff: ParsedDiff(files: files, truncated: false, inputBytes: 0),
        ),
      },
    );

    testWidgets('shows the shared list/tree toggle button', (tester) async {
      await _pump(
        tester,
        tab: const CompareTabSpec(id: 'unused', left: left),
        state: stateWithResult,
        viewMode: FileListViewMode.list,
      );

      expect(find.byType(FileListModeToggleButton), findsOneWidget);
    });

    testWidgets('tree mode renders a FileTreeFolderRow for a multi-file '
        'folder', (tester) async {
      await _pump(
        tester,
        tab: const CompareTabSpec(id: 'unused', left: left),
        state: stateWithResult,
        viewMode: FileListViewMode.tree,
      );

      expect(find.byType(FileTreeFolderRow), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(find.text('a.dart'), findsOneWidget);
    });
  });
}
