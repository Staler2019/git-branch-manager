// The 並排 / unified switch's round trip through the real HistoryPage:
// tap the control that is actually on screen, and both the rendered diff and
// the persisted preference follow.
//
// `commit_detail_panel_test.dart` pumps CommitDetailPanelCore with the mode
// as a param and a callback, which proves the two renderers are wired to the
// right enum values but cannot prove anything about the provider -- a
// container that watched nothing, or wrote to the wrong notifier, would leave
// every one of those tests green. `diff_view_mode_repository_test.dart` proves
// the store round-trips but never renders anything. This file is the seam
// between them, and it is the only tier that fails if CommitDetailPanel
// forgets to call setMode.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/changed_file.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/diff_view_mode_repository.dart';
import 'package:gbm_flutter/data/repositories/history_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/diff/diff_page.dart';
import 'package:gbm_flutter/features/diff/side_by_side_diff_view.dart';
import 'package:gbm_flutter/features/history_graph/history_page.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/diff-view-mode-repo',
  gitDir: '/test/diff-view-mode-repo/.git',
);

const Signature _signature = Signature(
  name: 'Test Author',
  email: 'author@example.com',
  when: 0,
  tzOffsetMinutes: 0,
);

ChangedFile _file(String path) => ChangedFile(
  path: path,
  oldPath: path,
  kind: FileChangeKind.modified,
  oldMode: '100644',
  newMode: '100644',
  oldBlob: 'aaa',
  newBlob: 'bbb',
  similarity: 0,
  addedLines: 0,
  removedLines: 0,
);

/// One real hunk: ParsedDiff.empty renders 'No changes' in either mode, so it
/// could not tell the two renderers apart.
const ParsedDiff _diff = ParsedDiff(
  files: <DiffFile>[
    DiffFile(
      oldPath: 'a.dart',
      newPath: 'a.dart',
      kind: FileChangeKind.modified,
      oldMode: '100644',
      newMode: '100644',
      oldBlob: 'aaa',
      newBlob: 'bbb',
      binary: false,
      similarity: 0,
      addedLines: 1,
      removedLines: 1,
      displayPath: 'a.dart',
      hunks: <DiffHunk>[
        DiffHunk(
          oldStart: 1,
          oldCount: 1,
          newStart: 1,
          newCount: 1,
          heading: '',
          lines: <DiffLine>[
            DiffLine(
              kind: DiffLineKind.removed,
              oldLine: 1,
              newLine: 0,
              text: 'old',
            ),
            DiffLine(
              kind: DiffLineKind.added,
              oldLine: 0,
              newLine: 1,
              text: 'new',
            ),
          ],
        ),
      ],
    ),
  ],
  truncated: false,
  inputBytes: 0,
);

void main() {
  testWidgets('tapping the switch on a real HistoryPage swaps the renderer and '
      'persists the choice -- CommitDetailPanel really reaches the provider', (
    tester,
  ) async {
    final RepoSessionState state = RepoSessionState(
      isOpen: true,
      commitFiles: <ChangedFile>[_file('a.dart')],
      selectedCommitFileDiff: _diff,
      // Seeded so the panel resolves its commit immediately rather than
      // showing an indeterminate CircularProgressIndicator -- left
      // spinning, pumpAndSettle can only time out.
      commitMetaCache: const <String, CommitMeta>{
        'abc123': CommitMeta(
          oid: 'abc123',
          tree: 'tree123',
          parents: <String>[],
          author: _signature,
          committer: _signature,
          subject: 'Test commit',
          body: '',
          signedCommit: false,
        ),
      },
    );

    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
      initialState: state,
      overrides: <Override>[
        selectedCommitProvider(_identity).overrideWith((ref) => 'abc123'),
      ],
      historyBuilder: (context, state) => HistoryPage(identity: _identity),
    );
    final String repoId = Uri.encodeComponent(_identity.workDir);

    pumped.router.go(RoutePaths.historyFor(repoId));
    await tester.pumpAndSettle();

    // Selecting the file is what puts the panel on its diff face at all.
    pumped.container
            .read(selectedCommitFilePathProvider(_identity).notifier)
            .state =
        'a.dart';
    await tester.pumpAndSettle();

    // Default is unified, and it is the *rendered* default that matters
    // here -- the repository test already covers the stored one.
    expect(find.byType(DiffPage), findsOneWidget);
    expect(find.byType(SideBySideDiffView), findsNothing);

    // The real control on the real page, not the provider directly: a
    // container that never wired onDiffViewModeChanged would still pass a
    // provider-driven version of this test.
    await tester.tap(find.text('side by side'));
    await tester.pumpAndSettle();

    expect(find.byType(SideBySideDiffView), findsOneWidget);
    expect(find.byType(DiffPage), findsNothing);
    expect(
      pumped.container.read(diffViewModeProvider),
      DiffViewMode.sideBySide,
    );

    // And it reached the store, not just the in-memory notifier. This is
    // the half that a widget-local `setState` would fail.
    final SharedPreferences prefs = pumped.container.read(
      sharedPreferencesProvider,
    );
    expect(prefs.getString('diffViewMode'), 'sideBySide');

    // Back again, so the switch is not a one-way door.
    await tester.tap(find.text('unified'));
    await tester.pumpAndSettle();

    expect(find.byType(DiffPage), findsOneWidget);
    expect(find.byType(SideBySideDiffView), findsNothing);
    expect(prefs.getString('diffViewMode'), 'unified');
  });
}
