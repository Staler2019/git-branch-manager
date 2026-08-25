import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/actions/gbm_shortcuts.dart';

void main() {
  group('gbmActionShortcuts', () {
    // branchRenameCurrentBranch is F2, the MENUS table's only binding with
    // no Ctrl/Cmd at all, so it is excluded from the "every shortcut carries
    // the platform modifier" invariant below rather than weakening it for
    // everything else. Its own modifiers are asserted separately at the end
    // of this group.
    const Set<GbmActionId> bareKeyActions = <GbmActionId>{
      GbmActionId.branchRenameCurrentBranch,
      // Bare F5. Refresh is F5 on every desktop Git client, and this round
      // gave it a binding because deleting TopBar removed the only Refresh
      // affordance in the window.
      GbmActionId.viewRefresh,
    };

    test('macOS shortcuts has exactly 40 entries, and every one but the '
        'bare-key group uses meta=true, control=false', () {
      final shortcuts = gbmActionShortcuts(true);
      expect(shortcuts.length, 40);
      shortcuts.forEach((id, shortcut) {
        if (bareKeyActions.contains(id)) return;
        expect(
          shortcut.meta,
          isTrue,
          reason: '$id: macOS should use meta=true',
        );
        expect(
          shortcut.control,
          isFalse,
          reason: '$id: macOS should use control=false',
        );
      });
    });

    test('non-macOS shortcuts has exactly 40 entries, and every one but the '
        'bare-key group uses meta=false, control=true', () {
      final shortcuts = gbmActionShortcuts(false);
      expect(shortcuts.length, 40);
      for (final MapEntry<GbmActionId, GbmKeyboardShortcut> entry
          in shortcuts.entries) {
        if (bareKeyActions.contains(entry.key)) continue;
        final GbmKeyboardShortcut shortcut = entry.value;
        expect(
          shortcut.meta,
          isFalse,
          reason: 'non-macOS should use meta=false',
        );
        expect(
          shortcut.control,
          isTrue,
          reason: 'non-macOS should use control=true',
        );
      }
    });

    test('no two shortcuts produce equal keyboard combinations on macOS', () {
      final shortcuts = gbmActionShortcuts(true);

      // Convert all to a comparable key. Two rules for what belongs in this
      // tuple, both learned the hard way:
      //
      // Every modifier, including ones nothing uses yet. `alt` was left out
      // while no shortcut set it, so the test could not tell Ctrl/Cmd+Shift+A
      // from Ctrl/Cmd+Alt+A; the moment the first alt binding landed
      // (repositoryStageAll) it reported a collision that does not exist.
      //
      // The key itself, not `trigger.keyLabel`. keyLabel is a display string:
      // today it does separate Digit 1 ("1") from Numpad 1 ("Numpad 1"), so
      // no two bindings currently collapse onto one label -- but that is
      // Flutter's presentation choice, not an identity guarantee, and identity
      // is what this test needs.
      final comparableKeys = shortcuts.values.map((s) {
        return (s.trigger, s.shift, s.alt, s.meta, s.control);
      }).toList();

      final uniqueKeys = comparableKeys.toSet();
      expect(
        uniqueKeys.length,
        comparableKeys.length,
        reason: 'No two shortcuts should have identical key combinations',
      );
    });

    // The non-macOS map got no duplicate check at all until now. That was
    // safe only by coincidence: `_makeShortcut()` differs between the two
    // platforms solely in which of meta/control it sets, so the two maps are
    // structurally identical and a collision on one shows on the other. The
    // first binding written as `isMacOS ? keyX : keyY` breaks that coincidence
    // and leaves this map unwatched -- the same way `alt` was unwatched for as
    // long as no shortcut used it.
    test(
      'no two shortcuts produce equal keyboard combinations on non-macOS',
      () {
        final shortcuts = gbmActionShortcuts(false);

        // Same comparable key as the macOS test above; its comment explains
        // why every modifier is in the tuple and why this is the key itself.
        final comparableKeys = shortcuts.values.map((s) {
          return (s.trigger, s.shift, s.alt, s.meta, s.control);
        }).toList();

        final uniqueKeys = comparableKeys.toSet();
        expect(
          uniqueKeys.length,
          comparableKeys.length,
          reason: 'No two shortcuts should have identical key combinations',
        );
      },
    );

    // Was 'editFindInFiles is absent' -- it recorded the #75-1 gap rather
    // than a requirement, and that gap is closed. REVISIONS assigns
    // Ctrl/Cmd+Shift+H.
    test('repositoryFetch has shift+F and editFindInFiles has shift+H', () {
      final shortcuts = gbmActionShortcuts(false);

      expect(shortcuts.containsKey(GbmActionId.repositoryFetch), isTrue);
      final repoFetch = shortcuts[GbmActionId.repositoryFetch]!;
      expect(repoFetch.trigger, LogicalKeyboardKey.keyF);
      expect(repoFetch.shift, isTrue);

      final findInFiles = shortcuts[GbmActionId.editFindInFiles];
      expect(findInFiles, isNotNull);
      expect(findInFiles!.trigger, LogicalKeyboardKey.keyH);
      expect(findInFiles.shift, isTrue);
      expect(findInFiles.alt, isFalse);
    });

    // Was 'branchStashChanges is absent' -- same story as above (#75-2).
    // REVISIONS assigns Ctrl/Cmd+Shift+S, which repositoryStageAll used to
    // occupy; Stage all moved to Ctrl/Cmd+Alt+A to free it.
    test(
      'viewFileListAsTree has shift+T and branchStashChanges has shift+S',
      () {
        final shortcuts = gbmActionShortcuts(false);

        expect(shortcuts.containsKey(GbmActionId.viewFileListAsTree), isTrue);
        final asTree = shortcuts[GbmActionId.viewFileListAsTree]!;
        expect(asTree.trigger, LogicalKeyboardKey.keyT);
        expect(asTree.shift, isTrue);

        final stash = shortcuts[GbmActionId.branchStashChanges];
        expect(stash, isNotNull);
        expect(stash!.trigger, LogicalKeyboardKey.keyS);
        expect(stash.shift, isTrue);
        expect(stash.alt, isFalse);

        // The other half of the swap: asserted here so a future edit cannot
        // quietly put Stage all back on Shift+S and take the stash binding
        // away again.
        final stageAll = shortcuts[GbmActionId.repositoryStageAll]!;
        expect(stageAll.trigger, LogicalKeyboardKey.keyA);
        expect(stageAll.alt, isTrue);
        expect(stageAll.shift, isFalse);

        // REVISIONS' Ctrl/Cmd+Alt+S for stage-selected-lines (#75-3). The spec
        // also writes Ctrl/Cmd+Shift+Enter for the same action on P03-5 and in
        // SCOPES row 7; that reading survives as a diff-area-scoped binding,
        // not as this global one.
        final stageLines = shortcuts[GbmActionId.repositoryStageSelectedLines]!;
        expect(stageLines.trigger, LogicalKeyboardKey.keyS);
        expect(stageLines.alt, isTrue);
        expect(stageLines.shift, isFalse);
      },
    );

    test('fileExit is absent from shortcuts entirely', () {
      final shortcutsMacOS = gbmActionShortcuts(true);
      final shortcutsNonMacOS = gbmActionShortcuts(false);

      expect(shortcutsMacOS.containsKey(GbmActionId.fileExit), isFalse);
      expect(shortcutsNonMacOS.containsKey(GbmActionId.fileExit), isFalse);
    });

    test('branchRenameCurrentBranch is bound to F2, per spec DIALOGS\' Rename '
        'branch entry (from 05-B -> Rename…) and CTX 05-B\'s own "Rename…" '
        'key column', () {
      final shortcuts = gbmActionShortcuts(false);
      final GbmKeyboardShortcut rename =
          shortcuts[GbmActionId.branchRenameCurrentBranch]!;
      expect(rename.trigger, LogicalKeyboardKey.f2);
    });

    test('F2 carries no Ctrl/Cmd on either platform -- the one bare-key '
        'binding in the MENUS table', () {
      for (final bool isMacOS in <bool>[true, false]) {
        final GbmKeyboardShortcut rename = gbmActionShortcuts(
          isMacOS,
        )[GbmActionId.branchRenameCurrentBranch]!;
        expect(rename.control, isFalse, reason: 'isMacOS=$isMacOS');
        expect(rename.meta, isFalse, reason: 'isMacOS=$isMacOS');
        expect(rename.shift, isFalse, reason: 'isMacOS=$isMacOS');
        expect(rename.alt, isFalse, reason: 'isMacOS=$isMacOS');
        // The shortcuts dialog derives its text from these fields, so a
        // stray modifier would show up as "Ctrl+F2" there too.
        expect(rename.displayLabel, 'F2', reason: 'isMacOS=$isMacOS');
      }
    });
  });

  group('editSelectAll (spec page 13 REVISIONS)', () {
    test('is bound to the plain Ctrl/Cmd+A, with no shift', () {
      for (final bool isMacOS in <bool>[true, false]) {
        final GbmKeyboardShortcut? shortcut = gbmActionShortcuts(
          isMacOS,
        )[GbmActionId.editSelectAll];
        expect(shortcut, isNotNull, reason: 'isMacOS=$isMacOS');
        expect(shortcut!.trigger, LogicalKeyboardKey.keyA);
        expect(shortcut.shift, isFalse);
        expect(shortcut.meta, isMacOS);
        expect(shortcut.control, !isMacOS);
      }
    });

    test('does not collide with repositoryAmendLastCommit, which is the '
        'shift variant of the same key', () {
      for (final bool isMacOS in <bool>[true, false]) {
        final Map<GbmActionId, GbmKeyboardShortcut> shortcuts =
            gbmActionShortcuts(isMacOS);
        final GbmKeyboardShortcut amend =
            shortcuts[GbmActionId.repositoryAmendLastCommit]!;
        expect(amend.trigger, LogicalKeyboardKey.keyA);
        expect(amend.shift, isTrue);
      }
    });
  });
}
