// Regression test for the menubar flicker the user reported as "每次捲動
// menubar 都會閃爍" while scrolling History.
//
// WorkspaceScreen.build() watches the *whole* RepoSessionState:
//
//     final RepoSessionState session = ref.watch(repoSessionProvider(identity));
//
// Scrolling the commit graph drives a metadata prefetch on every scroll
// tick (CommitGraphView._onScroll -> _requestVisibleMeta ->
// requestCommitMeta), each reply lands as a commitMetaReady event, and the
// controller republishes state via `copyWith(commitMetaCache: ...)`. That
// is a new RepoSessionState object, so the unfiltered `ref.watch` above
// rebuilds the entire shell -- MenuBarRow, PlatformMenuBarHost,
// ActionToolbar, TabRow and _buildActionHandlers() -- continuously, for the
// whole duration of a scroll. On macOS PlatformMenuBarHost rebuilds a real
// native PlatformMenuBar, which is what the user sees flickering.
//
// WorkspaceScreen reads ten session fields and `commitMetaCache` is not one
// of them, so none of that work can change anything on screen: it is pure
// waste on the hottest path in the app.
//
// Both directions are pinned, because "never rebuild" would satisfy the
// first assertion alone and break the app:
//   - a commitMetaCache-only publish must NOT rebuild the shell
//   - a repoState publish MUST rebuild it
//
// Rebuilds are observed without instrumenting lib/: WorkspaceScreen builds
// MenuBarRow with callbacks, so it cannot be const, so a rebuild of the
// parent necessarily constructs a new child widget instance. Comparing the
// instance by identity is therefore an exact rebuild probe.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/workspace/widgets/menu_bar_row.dart';

import '../support/pump_workspace.dart';

final CommitMeta _meta = CommitMeta(
  oid: 'a' * 40,
  tree: 'b' * 40,
  parents: <String>[],
  author: const Signature(
    name: 'Test',
    email: 'test@example.com',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  committer: const Signature(
    name: 'Test',
    email: 'test@example.com',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  subject: 'subject',
  body: '',
  signedCommit: false,
);

const RepoState _mergingState = RepoState(
  flags: RepoStateFlags.merge | RepoStateFlags.sequencer,
  isClean: false,
  isSequencerOperation: true,
  rebaseStep: 0,
  rebaseTotal: 0,
  rebaseOntoLabel: '',
  indexLocked: false,
  indexLockAgeSeconds: null,
  describe: 'merging',
);

void main() {
  final RepoIdentity identity = RepoIdentity(
    workDir: '/test/repo',
    gitDir: '/test/repo/.git',
  );

  testWidgets(
    'a commitMetaCache-only publish does not rebuild the workspace shell',
    (WidgetTester tester) async {
      final PumpedWorkspace pumped = await pumpWorkspace(
        tester,
        identity: identity,
      );
      await tester.pumpAndSettle();

      final MenuBarRow before = tester.widget<MenuBarRow>(
        find.byType(MenuBarRow),
      );

      // Exactly what _onEvent does for commitMetaReady.
      pumped.controller.emit(
        pumped.controller.state.withCommitMeta(<CommitMeta>[_meta]),
      );
      await tester.pump();

      final MenuBarRow after = tester.widget<MenuBarRow>(
        find.byType(MenuBarRow),
      );

      expect(
        identical(before, after),
        isTrue,
        reason:
            'WorkspaceScreen rebuilt for a commitMetaCache change it never '
            'reads. During a scroll this fires per metadata reply and '
            'rebuilds the whole menu bar -- the reported flicker.',
      );
    },
  );

  testWidgets('a repoState publish still rebuilds the workspace shell', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: identity,
    );
    await tester.pumpAndSettle();

    final MenuBarRow before = tester.widget<MenuBarRow>(
      find.byType(MenuBarRow),
    );

    pumped.controller.emit(
      pumped.controller.state.copyWith(repoState: _mergingState),
    );
    await tester.pump();

    final MenuBarRow after = tester.widget<MenuBarRow>(find.byType(MenuBarRow));

    expect(
      identical(before, after),
      isFalse,
      reason:
          'repoState gates twelve actions through isActionEnabled(); the '
          'shell must rebuild so the menu greys them out.',
    );
  });
}
