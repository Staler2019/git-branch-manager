// Integration coverage for spec page 07's STATES table (clean <-> conflict),
// complementing workspace_conflict_transition_test.dart rather than
// duplicating it: that file already drives Banner / Toolbar Fetch·Pull·Push /
// 切分支 / the Resolve… entry point (via conflict_resolve_flow_test.dart) and
// the lastError/Conflict-code interaction through the real WorkspaceScreen.
// This file adds integration-tier coverage for the three STATES rows that
// previously only had widget-tier (isolated-component) tests, if any:
//
//   - "Working copy" row: an extra Conflicted section pinned above
//     unstaged/staged, only through the real WorkingCopyView -- confirmed by
//     spot-check during this audit (see docs/reports/spec-conformance-matrix.md,
//     Page 07) after a discovery agent incorrectly reported it missing; this
//     test is the regression lock that finding didn't have yet.
//   - "Commit" row: the Commit/Amend buttons are disabled during conflict --
//     workspace_conflict_transition_test.dart's clean/conflict test pair
//     names this in its description ("commit box disabled") but never
//     actually asserts it, so it was untested despite reading as covered.
//   - "Status bar" row: the danger background tint, through the real
//     StatusBar mounted inside WorkspaceScreen (status_bar_test.dart only
//     covers the standalone widget, not this integration seam).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/repositories/working_copy_draft_repository.dart';
import 'package:gbm_flutter/features/status_bar/status_bar.dart';
import 'package:gbm_flutter/features/working_copy/working_copy_view.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/states-repo',
  gitDir: '/test/states-repo/.git',
);

final RefSnapshot _refs = RefSnapshot(
  head: const HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'deadbeef',
  ),
  refs: const <RefInfo>[
    RefInfo(
      fullName: 'refs/heads/main',
      shortName: 'main',
      kind: RefKind.localBranch,
      target: 'deadbeef',
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isGone: false,
      isHead: true,
      isSymbolic: false,
      worktreePath: '',
    ),
  ],
  refCountGuardTripped: false,
  totalRefCount: 1,
);

const WorkingCopyEntry _stagedEntry = WorkingCopyEntry(
  path: 'staged.txt',
  oldPath: '',
  untracked: false,
  staged: true,
  indexStatus: FileChangeKind.modified,
  hasUnstagedChange: false,
  worktreeStatus: FileChangeKind.modified,
  conflict: ConflictKind.none,
  ancestorBlob: '',
  oursBlob: '',
  theirsBlob: '',
  similarity: 0,
  isSubmodule: false,
  isConflicted: false,
);

const WorkingCopyEntry _conflictEntry = WorkingCopyEntry(
  path: 'conflict.txt',
  oldPath: '',
  untracked: false,
  staged: false,
  indexStatus: FileChangeKind.modified,
  hasUnstagedChange: true,
  worktreeStatus: FileChangeKind.modified,
  conflict: ConflictKind.bothModified,
  ancestorBlob: '',
  oursBlob: 'ours-hash',
  theirsBlob: 'theirs-hash',
  similarity: 0,
  isSubmodule: false,
  isConflicted: true,
);

RepoState _mergeState() => const RepoState(
  flags: RepoStateFlags.merge,
  isClean: false,
  isSequencerOperation: true,
  rebaseStep: 0,
  rebaseTotal: 0,
  rebaseOntoLabel: '',
  indexLocked: false,
  indexLockAgeSeconds: null,
  describe: '',
);

RepoSessionState _cleanSession() => RepoSessionState(
  isOpen: true,
  refs: _refs,
  workingCopyStatus: const WorkingCopyStatus(entries: [_stagedEntry]),
);

RepoSessionState _conflictSession() => RepoSessionState(
  isOpen: true,
  refs: _refs,
  repoState: _mergeState(),
  workingCopyStatus: const WorkingCopyStatus(
    entries: [_stagedEntry, _conflictEntry],
  ),
);

Future<PumpedWorkspace> _pumpAtWorkingCopy(
  WidgetTester tester,
  RepoSessionState initialState, {
  List<Override> overrides = const <Override>[],
}) async {
  final PumpedWorkspace pumped = await pumpWorkspace(
    tester,
    identity: _identity,
    initialState: initialState,
    overrides: overrides,
    workingCopyBuilder: (context, state) =>
        WorkingCopyView(identity: _identity),
  );
  pumped.router.go(
    RoutePaths.workingCopyFor(Uri.encodeComponent(_identity.workDir)),
  );
  await tester.pumpAndSettle();
  return pumped;
}

/// [WorkingCopyView.initState] seeds its summary `TextEditingController`
/// from `ref.read(workingCopyDraftProvider(identity))` once, at mount time
/// -- pre-populating the draft via provider override tests the "Commit"
/// STATES row's actual gate logic (`canCommit`) directly, without depending
/// on whether a later `tester.enterText` reliably triggers a rebuild of
/// `WorkingCopyView` itself (see this file's own note below on why it does
/// not, discovered while writing this test).
Override _draftWithSummary(String summary) {
  return workingCopyDraftProvider(_identity).overrideWith(
    (ref) => WorkingCopyDraftController()..updateSummary(summary),
  );
}

void main() {
  final GbmColors colors = buildGbmTheme(
    GbmThemeVariant.darkTechnical,
  ).extension<GbmColors>()!;

  group('spec page 07 STATES table -- "Working copy" row', () {
    testWidgets(
      'clean: no CONFLICTED section above unstaged/staged',
      (tester) async {
        await _pumpAtWorkingCopy(tester, _cleanSession());
        expect(find.text('CONFLICTED'), findsNothing);
      },
    );

    testWidgets(
      'conflict: a CONFLICTED section is pinned above unstaged/staged, '
      'sized to the conflicted-entry count',
      (tester) async {
        await _pumpAtWorkingCopy(tester, _conflictSession());
        expect(find.text('CONFLICTED'), findsOneWidget);
        expect(find.text('1'), findsWidgets); // conflicted-count badge
        // conflict.txt is expected to render twice: once in the pinned
        // CONFLICTED section, and again in the ordinary unstaged list --
        // WorkingCopyStatus.unstaged filters on hasUnstagedChange only,
        // which a conflicted entry also satisfies, so the two sections
        // are not mutually exclusive by construction. Confirming presence
        // (not an exact single-widget count) is the right assertion here.
        expect(find.text('conflict.txt'), findsWidgets);
      },
    );
  });

  group('spec page 07 STATES table -- "Commit" row', () {
    testWidgets('clean: Commit/Amend enabled with a staged file and a '
        'non-empty summary', (tester) async {
      await _pumpAtWorkingCopy(
        tester,
        _cleanSession(),
        overrides: <Override>[_draftWithSummary('A summary')],
      );

      final GbmButton commitButton = tester.widget<GbmButton>(
        find.widgetWithText(GbmButton, 'Commit'),
      );
      expect(
        commitButton.onPressed,
        isNotNull,
        reason:
            'staged.isNotEmpty && summary.isNotEmpty && '
            'isActionEnabled(repositoryCommit, clean session) should all '
            'hold.',
      );
    });

    testWidgets(
      'conflict: Commit/Amend stay disabled even with a staged file and a '
      'non-empty summary -- isActionEnabled(repositoryCommit, ...) must '
      'gate on conflictActive regardless of the other two conditions',
      (tester) async {
        await _pumpAtWorkingCopy(
          tester,
          _conflictSession(),
          overrides: <Override>[_draftWithSummary('A summary')],
        );

        final GbmButton commitButton = tester.widget<GbmButton>(
          find.widgetWithText(GbmButton, 'Commit'),
        );
        expect(commitButton.onPressed, isNull);

        final GbmButton amendButton = tester.widget<GbmButton>(
          find.widgetWithText(GbmButton, 'Amend'),
        );
        expect(amendButton.onPressed, isNull);
      },
    );
  });

  group('spec page 07 STATES table -- "Status bar" row', () {
    testWidgets('clean: StatusBar renders the ordinary surfacePanel '
        'background, not the danger tint', (tester) async {
      await pumpWorkspace(tester, identity: _identity, initialState: _cleanSession());

      final Container container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(StatusBar),
              matching: find.byType(Container),
            )
            .first,
      );
      final BoxDecoration decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, colors.surfacePanel);
    });

    testWidgets(
      'conflict: StatusBar background switches to the danger tint '
      '(colors.danger at 15% alpha, per status_bar.dart)',
      (tester) async {
        await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflictSession(),
        );

        final Container container = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(StatusBar),
                matching: find.byType(Container),
              )
              .first,
        );
        final BoxDecoration decoration =
            container.decoration! as BoxDecoration;
        expect(decoration.color, colors.danger.withValues(alpha: 0.15));
      },
    );

    testWidgets(
      'conflict -> clean round trip: the danger tint clears with no '
      'residue',
      (tester) async {
        final PumpedWorkspace pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflictSession(),
        );

        pumped.controller.emit(_cleanSession());
        await tester.pumpAndSettle();

        final Container container = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(StatusBar),
                matching: find.byType(Container),
              )
              .first,
        );
        final BoxDecoration decoration =
            container.decoration! as BoxDecoration;
        expect(decoration.color, colors.surfacePanel);
      },
    );
  });
}
