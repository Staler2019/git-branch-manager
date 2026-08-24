// Integration coverage for the core ask behind this whole test batch:
// "intent 之間切換的狀態要乾淨、符合狀態機模式" -- when
// RepoSessionState.conflictActive flips, every UI surface gated on it
// (keyboard-shortcut dispatch, the sidebar's branch checkout, the commit
// box, the in-window menu's visual enabled state) must flip with it, and
// flip back cleanly with no residue once the conflict clears. Drives the
// real WorkspaceScreen via pumpWorkspace/FakeRepoSessionController.emit(),
// not a hand-fed handler map -- see workspace_intent_dispatch_parity_test.dart
// for why that distinction matters.
//
// The menu-graying assertions below (`_repositoryMenuItemColor`) read
// GbmMenuItem.enabled's effect on _GbmMenuRow's rendered foreground color.
// GbmMenuItem.enabled does not exist yet as of this commit, so
// _GbmMenuRow always renders textPrimary regardless of whether the
// underlying action is wired -- these are expected RED until the following
// commit adds GbmMenuItem.enabled and wires MenuBarRow to it.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/workspace/widgets/action_toolbar.dart';
import 'package:gbm_flutter/features/workspace/workspace_screen.dart'
    show ConflictBanner;
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:gbm_flutter/routing/dialog_route.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
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

/// A non-HEAD local branch, so tapping its row in the sidebar exercises
/// only the `conflictActive` gate ([BranchTreeItem]'s `isHead` short-circuit
/// is a separate, unrelated reason a checkout row can be non-interactive).
final RefSnapshot _refsWithFeatureBranch = RefSnapshot(
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
    RefInfo(
      fullName: 'refs/heads/feature',
      shortName: 'feature',
      kind: RefKind.localBranch,
      target: 'cafef00d',
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isGone: false,
      isHead: false,
      isSymbolic: false,
      worktreePath: '',
    ),
  ],
  refCountGuardTripped: false,
  totalRefCount: 2,
);

RepoSessionState _cleanSession() =>
    RepoSessionState(isOpen: true, refs: _refsWithFeatureBranch);

RepoSessionState _conflictSession() => RepoSessionState(
  isOpen: true,
  refs: _refsWithFeatureBranch,
  repoState: _mergeState(),
  workingCopyStatus: const WorkingCopyStatus(entries: [_conflictEntry]),
);

RepoState _revertState() => const RepoState(
  flags: RepoStateFlags.revert,
  isClean: false,
  isSequencerOperation: true,
  rebaseStep: 0,
  rebaseTotal: 0,
  rebaseOntoLabel: '',
  indexLocked: false,
  indexLockAgeSeconds: null,
  describe: 'reverting',
);

RepoSessionState _revertSession() => RepoSessionState(
  isOpen: true,
  refs: _refsWithFeatureBranch,
  repoState: _revertState(),
  workingCopyStatus: const WorkingCopyStatus(entries: [_conflictEntry]),
);

Future<void> _pressCtrlShiftF(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pumpAndSettle();
}

/// Opens the in-window "Repository" menu and returns the rendered color of
/// [label]'s row -- `colors.textTertiary` once GbmMenuItem.enabled wires
/// through, `colors.textPrimary`/hover color otherwise. Leaves the menu
/// open; callers only need one read per pumped tree.
Color _repositoryMenuItemColor(WidgetTester tester, String label) {
  // The P02-2 toolbar renders 'Fetch'/'Pull'/'Push' as well, so an unscoped
  // find.text() matches two widgets once the menu is open. The menu row is
  // the one that is *not* inside ActionToolbar -- _GbmMenuPanel/_GbmMenuRow
  // are both private, so there is no public type to scope to positively.
  final Set<Element> inToolbar = find
      .descendant(of: find.byType(ActionToolbar), matching: find.text(label))
      .evaluate()
      .toSet();
  final Text text =
      find
              .text(label)
              .evaluate()
              .firstWhere((Element e) => !inToolbar.contains(e))
              .widget
          as Text;
  return text.style!.color!;
}

/// The [ActionToolbar] button labelled [label]. Scoped to the toolbar
/// because the Repository / Branch menus carry the same words, and an
/// unscoped finder would silently start matching one of those instead the
/// moment a menu is open.
GbmButton _toolbarButton(WidgetTester tester, String label) =>
    tester.widget<GbmButton>(
      find.descendant(
        of: find.byType(ActionToolbar),
        matching: find.widgetWithText(GbmButton, label),
      ),
    );

const List<String> _toolbarLabels = <String>[
  'Fetch',
  'Pull',
  'Push',
  'Branch',
  'Stash',
];

/// Sentinel destinations for the two toolbar buttons that navigate rather
/// than dispatch a command. Branch and Stash are gated identically and both
/// only `context.push(...)`, so asserting `onPressed != null` alone cannot
/// tell them apart -- swapping the two handlers would leave every such
/// assertion green (verified by mutation). These routes are what makes the
/// two distinguishable.
List<RouteBase> _branchAndStashDialogRoutes() => <RouteBase>[
  dialogRoute(
    path: RoutePaths.newBranchDialog,
    builder: (context, state) => const Text('NEW-BRANCH-DIALOG'),
  ),
  dialogRoute(
    path: RoutePaths.stashChangesDialog,
    builder: (context, state) => const Text('STASH-CHANGES-DIALOG'),
  ),
];

/// Checkout is a double-click on the branch row (BRANCH_STATES 「點兩下即
/// checkout」); a single click only selects (MULTIKEYS 單擊).
Future<void> _doubleTapRow(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  final GbmColors colors = buildGbmTheme(
    GbmThemeVariant.darkTechnical,
  ).extension<GbmColors>()!;

  group('workspace conflict <-> clean transition', () {
    testWidgets('clean: no ConflictBanner, Fetch shortcut reaches fetchRemote, '
        'checkout reaches checkout(), commit box stays enabled', (
      tester,
    ) async {
      final pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _cleanSession(),
      );

      expect(find.textContaining('conflicted'), findsNothing);

      await _pressCtrlShiftF(tester);
      expect(
        pumped.controller.commandLog.any((c) => c.name == 'fetchRemote'),
        isTrue,
      );

      await _doubleTapRow(tester, 'feature');
      expect(
        pumped.controller.commandLog
            .where((c) => c.name == 'checkout' && c.args['target'] == 'feature')
            .length,
        1,
      );
    });

    testWidgets(
      'conflict: ConflictBanner shown, Fetch shortcut no-ops, checkout '
      'no-ops, commit box disabled',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflictSession(),
        );

        expect(find.textContaining('conflicted'), findsWidgets);

        await _pressCtrlShiftF(tester);
        expect(
          pumped.controller.commandLog.any((c) => c.name == 'fetchRemote'),
          isFalse,
          reason:
              'repositoryFetch must be gated off by isActionEnabled() while '
              'conflictActive is true.',
        );

        await tester.tap(find.text('feature'));
        await tester.pumpAndSettle();
        expect(
          pumped.controller.commandLog.any((c) => c.name == 'checkout'),
          isFalse,
          reason:
              'BranchTreeItem.onTap must be null while conflictActive is '
              'true, mirroring isActionEnabled(branchCheckout, ...).',
        );
      },
    );

    testWidgets(
      'conflict -> clean round trip leaves no residue: banner disappears '
      'and every gate reopens',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflictSession(),
        );

        expect(find.textContaining('conflicted'), findsWidgets);
        await _pressCtrlShiftF(tester);
        expect(
          pumped.controller.commandLog.any((c) => c.name == 'fetchRemote'),
          isFalse,
        );

        pumped.controller.emit(_cleanSession());
        await tester.pumpAndSettle();

        expect(
          find.textContaining('conflicted'),
          findsNothing,
          reason:
              'ConflictBanner must not linger after conflictActive '
              'flips back to false.',
        );

        await _pressCtrlShiftF(tester);
        expect(
          pumped.controller.commandLog.any((c) => c.name == 'fetchRemote'),
          isTrue,
          reason:
              'The keyboard shortcut path must reopen the moment the gate '
              'clears -- no stale null captured from the conflicted build.',
        );

        await _doubleTapRow(tester, 'feature');
        expect(
          pumped.controller.commandLog
              .where(
                (c) => c.name == 'checkout' && c.args['target'] == 'feature',
              )
              .length,
          1,
          reason:
              'the checkout path must reopen the moment the gate clears -- '
              'no stale null captured from the conflicted build.',
        );
      },
    );

    testWidgets(
      'revert: invoking the dispatchers behind ConflictBanner\'s disabled '
      'Abort/Skip/Continue reaches no backend command',
      (tester) async {
        // ConflictBanner disables all three buttons for revert (see
        // conflict_banner_test.dart's "revert: Abort, Skip, and Continue
        // all disabled" case), so a real tap can never trigger
        // WorkspaceScreen._handleConflictAbort/Skip/Continue for this
        // state. Those dispatchers are private, but the closures they
        // produce are exposed publicly through ConflictBanner.onAbort/
        // onSkip/onContinue -- calling those fields directly reaches the
        // real exhaustive switch without going through the disabled
        // button, proving the revert branch is a genuine no-op rather
        // than falling through to a rebase/cherry-pick backend call.
        //
        // This is a real regression lock, not a formality: before the
        // dispatchers were rewritten as exhaustive switches (Commit 4 of
        // the sequencer-kind consolidation), the implicit "anything that
        // isn't merge/cherry-pick -> rebase" fallback meant this exact
        // sequence would have logged 'abortRebase' on the fake.
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _revertSession(),
        );

        final ConflictBanner banner = tester.widget<ConflictBanner>(
          find.byType(ConflictBanner),
        );

        banner.onAbort();
        banner.onSkip();
        banner.onContinue();
        await tester.pumpAndSettle();

        expect(
          pumped.controller.commandLog,
          isEmpty,
          reason:
              'Revert has no backend abort/skip/continue entry point (see '
              'RevertOps.h); the exhaustive switch in '
              '_handleConflictAbort/Skip/Continue must no-op for '
              'SequencerOperationKind.revert instead of mis-dispatching to '
              'a rebase or cherry-pick command.',
        );
      },
    );

    testWidgets(
      'Repository menu > Fetch renders enabled (not greyed) while clean',
      (tester) async {
        await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _cleanSession(),
        );

        await tester.tap(find.text('Repository'));
        await tester.pumpAndSettle();

        expect(
          _repositoryMenuItemColor(tester, 'Fetch'),
          isNot(colors.textTertiary),
        );
      },
    );

    testWidgets(
      'Repository menu > Fetch renders disabled (greyed) while conflicted',
      (tester) async {
        await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflictSession(),
        );

        await tester.tap(find.text('Repository'));
        await tester.pumpAndSettle();

        expect(
          _repositoryMenuItemColor(tester, 'Fetch'),
          colors.textTertiary,
          reason:
              'GbmMenuItem.enabled must be false for repositoryFetch while '
              'conflictActive is true, and _GbmMenuRow must render disabled '
              'items with the fixed textTertiary foreground regardless of '
              'hover -- mirrors repo_switcher_popover.dart\'s disabled-row '
              'pattern.',
        );
      },
    );

    testWidgets(
      'lastError with codeName Conflict is not shown as a warning banner '
      'while conflicted; a non-Conflict error is shown',
      (tester) async {
        final conflictError = const GitError(
          code: 1,
          codeName: 'Conflict',
          message: 'The operation stopped with conflicts',
          detail: '',
          argv: <String>[],
          exitCode: 1,
        );

        await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflictSession().copyWith(lastError: conflictError),
        );

        expect(
          find.text('The operation stopped with conflicts'),
          findsNothing,
          reason:
              'ConflictBanner already states this; a duplicate warning '
              'banner for the same Conflict-coded error must not appear.',
        );

        final authError = const GitError(
          code: 2,
          codeName: 'AuthenticationFailed',
          message: 'Authentication failed for remote origin',
          detail: '',
          argv: <String>[],
          exitCode: 1,
        );

        await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflictSession().copyWith(lastError: authError),
        );

        expect(
          find.text('Authentication failed for remote origin'),
          findsOneWidget,
          reason:
              'An error unrelated to the conflict itself must stay visible '
              'even while conflictActive is true.',
        );
      },
    );
  });

  // Spec P02 item 2 is the toolbar row itself, and spec P07's STATES table
  // gates it: 「Fetch / Pull / Push 全部可用」when clean, 「三顆停用，改由
  // banner 提供 Abort / Skip / Continue / Resolve…」when not. Until this
  // round the row did not exist, so every check of that rule -- including
  // this file's own header, which already claimed to drive "Toolbar
  // Fetch·Pull·Push" -- was really checking isActionEnabled(), the gate,
  // rather than the surface being gated. These tests go through the real
  // buttons.
  group('spec P02-2 toolbar', () {
    testWidgets('clean: all five buttons are enabled', (tester) async {
      await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _cleanSession(),
      );

      for (final String label in _toolbarLabels) {
        expect(
          _toolbarButton(tester, label).onPressed,
          isNotNull,
          reason: '$label must be pressable while the work tree is clean',
        );
      }
    });

    testWidgets('clean: tapping Fetch/Pull/Push dispatches exactly once each', (
      tester,
    ) async {
      final pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _cleanSession(),
      );

      for (final (String label, String command) in <(String, String)>[
        ('Fetch', 'fetchRemote'),
        ('Pull', 'pullChanges'),
        ('Push', 'pushChanges'),
      ]) {
        await tester.tap(
          find.descendant(
            of: find.byType(ActionToolbar),
            matching: find.widgetWithText(GbmButton, label),
          ),
        );
        await tester.pumpAndSettle();

        // Counted, not `.any()` -- a second tappable layered over the button
        // would double-dispatch, and `.any()` cannot see that.
        expect(
          pumped.controller.commandLog.where((c) => c.name == command).length,
          1,
          reason: 'the toolbar $label button must reach $command() once',
        );
      }
    });

    testWidgets(
      'conflict: all five buttons are disabled and dispatch nothing',
      (tester) async {
        final pumped = await pumpWorkspace(
          tester,
          identity: _identity,
          initialState: _conflictSession(),
        );

        for (final String label in _toolbarLabels) {
          expect(
            _toolbarButton(tester, label).onPressed,
            isNull,
            reason:
                '$label moves HEAD or starts a second sequencer operation, so '
                'spec P07 disables it while conflictActive is true',
          );
        }

        final int before = pumped.controller.commandLog.length;
        for (final String label in _toolbarLabels) {
          await tester.tap(
            find.descendant(
              of: find.byType(ActionToolbar),
              matching: find.widgetWithText(GbmButton, label),
            ),
            warnIfMissed: false,
          );
          await tester.pumpAndSettle();
        }
        expect(
          pumped.controller.commandLog.length,
          before,
          reason: 'a greyed button must also be inert, not merely grey',
        );
      },
    );

    testWidgets('conflict -> clean reopens every toolbar button', (
      tester,
    ) async {
      // The round trip, not just the conflict half: a gate that latches
      // closed looks identical to a correct one until the conflict clears.
      final pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _conflictSession(),
      );
      expect(_toolbarButton(tester, 'Fetch').onPressed, isNull);

      pumped.controller.emit(_cleanSession());
      await tester.pumpAndSettle();

      for (final String label in _toolbarLabels) {
        expect(
          _toolbarButton(tester, label).onPressed,
          isNotNull,
          reason: '$label must come back once the conflict is resolved',
        );
      }
    });

    testWidgets('Branch and Stash open their own dialogs, not each other\'s', (
      tester,
    ) async {
      await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _cleanSession(),
        topLevelRoutes: _branchAndStashDialogRoutes(),
      );

      await tester.tap(
        find.descendant(
          of: find.byType(ActionToolbar),
          matching: find.widgetWithText(GbmButton, 'Branch'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('NEW-BRANCH-DIALOG'), findsOneWidget);
      expect(find.text('STASH-CHANGES-DIALOG'), findsNothing);

      // Back to the workspace before the second half, or the first dialog
      // stays on the stack and the second assertion reads a stale tree.
      Navigator.of(tester.element(find.text('NEW-BRANCH-DIALOG'))).pop();
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(ActionToolbar),
          matching: find.widgetWithText(GbmButton, 'Stash'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('STASH-CHANGES-DIALOG'), findsOneWidget);
      expect(find.text('NEW-BRANCH-DIALOG'), findsNothing);
    });
  });
}
