// Spec page 19 樣板規則 5: 「例外狀態用面板內 banner」.
//
// The rule is about *where an exception state is told to the user*: inside
// the panel that has it, not thrown over the app as a transient SnackBar or
// a modal the user has to dismiss before they can look at the thing that
// went wrong.
//
// Two halves, because neither alone is the claim:
//
//  - a **source-level** sweep, which is the only form that covers all twelve
//    panels at once and catches the violation that has not been written yet;
//  - a **behavioural** check on the panels that actually have an exception
//    state, which is what proves the source sweep is guarding something real
//    rather than passing vacuously.
//
// **Input dialogs are not exception states and rule 5 does not forbid
// them.** Add remote…, New branch… and Create stash… all open a dialog, and
// must keep doing so: the user asked for one, nothing has gone wrong, and
// there is nowhere in a 78px definition list to type a name. A test that
// failed on those would be enforcing a rule the spec does not contain.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/lfs_state.dart';
import 'package:gbm_flutter/data/models/worktree_info.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/bisect_panel.dart';
import 'package:gbm_flutter/features/panels/gbm_panel_tab_shell.dart';
import 'package:gbm_flutter/features/panels/lfs_panel.dart';
import 'package:gbm_flutter/features/panels/worktrees_panel.dart';

import 'panel_test_support.dart';

const WorktreeInfo _prunable = WorktreeInfo(
  path: '/src/wt/gone',
  headOid: '9d02f4e',
  branch: 'feature/gone',
  isMain: false,
  isBare: false,
  isDetached: false,
  isLocked: false,
  lockReason: '',
  isPrunable: true,
  prunableReason: 'gitdir file points to non-existent location',
  isPrimary: false,
  pendingChanges: null,
  pendingCountState: WorktreePendingCountState.unmeasured,
  createdAt: null,
);

/// Asserts the exception state currently on screen is told *inside* the
/// panel and by no other means.
void _expectToldInPanel(WidgetTester tester, Finder message) {
  expect(message, findsWidgets, reason: 'the state has to be stated at all');
  expect(
    find.descendant(of: find.byType(GbmPanelTabShell), matching: message),
    findsWidgets,
    reason: 'rule 5: 例外狀態用面板內 banner -- inside the panel',
  );
  expect(find.byType(SnackBar), findsNothing, reason: 'not a SnackBar');
  expect(find.byType(Dialog), findsNothing, reason: 'not a modal');
  expect(find.byType(AlertDialog), findsNothing, reason: 'not a modal');
}

void main() {
  group('P19 rule 5: exception states are told inside the panel', () {
    test('no panel reaches for a SnackBar', () {
      final List<String> offenders = <String>[];
      // `recursive: true` because the point of a source sweep is the panel
      // nobody has written yet, and there is no rule saying it must be a
      // file directly in this directory rather than in a subdirectory of it.
      for (final FileSystemEntity f in Directory(
        'lib/features/panels',
      ).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final String src = f.readAsStringSync();
        if (src.contains('SnackBar') || src.contains('ScaffoldMessenger')) {
          offenders.add(f.path);
        }
      }

      // A source sweep rather than a widget test because the claim is about
      // all twelve panels *and the thirteenth nobody has written yet* --
      // there is no state to pump for a violation that does not exist. Same
      // form as `test/platform/window_title_test.dart`, which asserts a
      // plist as source text for the same reason.
      expect(
        offenders,
        isEmpty,
        reason:
            'rule 5 sends an exception state to an in-panel banner. A '
            'SnackBar is dismissed before it is read and covers the panel '
            'that has the problem; ScaffoldMessenger is how one is raised.',
      );
    });

    testWidgets('lfs: a missing git-lfs is stated in the panel', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        LfsPanel(identity: panelTestIdentity),
        state: const RepoSessionState(
          isOpen: true,
          lfsInstallation: LfsInstallation(available: false, version: ''),
        ),
      );

      _expectToldInPanel(
        tester,
        find.text('Git LFS is not installed for this repository'),
      );
    });

    testWidgets('worktrees: a path that is gone is stated in the panel', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        WorktreesPanel(identity: panelTestIdentity),
        state: const RepoSessionState(
          isOpen: true,
          worktrees: <WorktreeInfo>[_prunable],
        ),
      );

      _expectToldInPanel(tester, find.textContaining('路徑'));
    });

    testWidgets('bisect: no bisect running is stated in the panel', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        BisectPanel(identity: panelTestIdentity),
        state: const RepoSessionState(isOpen: true),
      );

      _expectToldInPanel(tester, find.text('No bisect in progress'));
    });
  });
}
