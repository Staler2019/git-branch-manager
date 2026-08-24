// Integration coverage for spec page 03 item 10: "同一個設定套用到 Working
// Copy 兩欄、History 的 Changed files、Compare 的 Files、以及 Conflict 視窗
//的檔案清單" -- the List/Tree display mode is ONE shared preference
// (fileListViewModeProvider), not four independent per-view toggles.
// Widget-tier tests (changed_files_panel_test.dart, working_copy_board's own
// tests, compare_page_test.dart, conflict_resolve_window_test.dart) each
// prove their own view reads the provider correctly in isolation, but none
// of them can prove the "same setting carries across a real navigation"
// half of the claim -- that needs the actual WorkspaceScreen + GoRouter
// stack, which is what this file adds.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/changed_file.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/file_list_view_mode_repository.dart';
import 'package:gbm_flutter/data/repositories/history_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/history_graph/history_page.dart';
import 'package:gbm_flutter/features/working_copy/working_copy_view.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/widgets/file_tree_folder_row.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/view-mode-repo',
  gitDir: '/test/view-mode-repo/.git',
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
  // 0/0 draws no badge, so these rows render exactly as they did before
  // spec P02-10's line counts existed -- this file is about something
  // else and should not start depending on them.
  addedLines: 0,
  removedLines: 0,
);

void main() {
  testWidgets(
    'setting Tree mode while on Working Copy carries over to History after '
    'navigating away and back -- the same fileListViewModeProvider, not a '
    'per-view copy',
    (tester) async {
      const Signature signature = Signature(
        name: 'Test Author',
        email: 'author@example.com',
        when: 0,
        tzOffsetMinutes: 0,
      );
      final RepoSessionState state = RepoSessionState(
        isOpen: true,
        commitFiles: <ChangedFile>[
          _file('a.dart'),
          _file('b/c.dart'),
          _file('b/d.dart'),
        ],
        // Seeded so CommitDetailPanel resolves 'abc123' immediately instead
        // of showing an indeterminate CircularProgressIndicator -- which,
        // left spinning, would make pumpWorkspace's own pumpAndSettle()
        // time out before this test ever gets to its own assertions.
        commitMetaCache: const <String, CommitMeta>{
          'abc123': CommitMeta(
            oid: 'abc123',
            tree: 'tree123',
            parents: <String>[],
            author: signature,
            committer: signature,
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
        workingCopyBuilder: (context, state) =>
            WorkingCopyView(identity: _identity),
        historyBuilder: (context, state) => HistoryPage(identity: _identity),
      );
      final String repoId = Uri.encodeComponent(_identity.workDir);

      // Start on Working Copy (list mode, the default) -- nothing to
      // assert yet beyond "it mounts", this just establishes the starting
      // point of the round trip.
      pumped.router.go(RoutePaths.workingCopyFor(repoId));
      await tester.pumpAndSettle();
      expect(find.byType(WorkingCopyView), findsOneWidget);

      // Flip the shared preference while still on Working Copy -- this is
      // what tapping any of the FileListModeToggleButton instances wired
      // into History/Compare/Conflict does under the hood; driving the
      // provider directly here is equivalent and avoids depending on
      // WorkingCopyBoard's own internal toggle affordance (or lack of one)
      // for a test that is really about propagation, not that button.
      await pumped.container
          .read(fileListViewModeProvider.notifier)
          .setMode(FileListViewMode.tree);
      await tester.pumpAndSettle();

      // Navigate to History -- a fresh route, not just a rebuild of the
      // same widget -- and confirm its Changed files panel already renders
      // in tree mode with no further action needed.
      pumped.router.go(RoutePaths.historyFor(repoId));
      await tester.pumpAndSettle();

      expect(find.byType(HistoryPage), findsOneWidget);
      // 'b' has two children (c.dart, d.dart) so it does not single-child
      // collapse -- see file_tree.dart's _collapseIfSingleChild.
      expect(find.byType(FileTreeFolderRow), findsOneWidget);
      expect(find.text('b'), findsOneWidget);
      expect(find.text('a.dart'), findsOneWidget);
    },
  );
}
