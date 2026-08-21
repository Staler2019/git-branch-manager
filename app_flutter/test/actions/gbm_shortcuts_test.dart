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
    };

    test('macOS shortcuts has exactly 37 entries, and every one but the '
        'bare-key group uses meta=true, control=false', () {
      final shortcuts = gbmActionShortcuts(true);
      expect(shortcuts.length, 37);
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

    test('non-macOS shortcuts has exactly 37 entries, and every one but the '
        'bare-key group uses meta=false, control=true', () {
      final shortcuts = gbmActionShortcuts(false);
      expect(shortcuts.length, 37);
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

      // Convert all to a comparable key
      final comparableKeys = shortcuts.values.map((s) {
        return (s.trigger.keyLabel, s.shift, s.meta, s.control);
      }).toList();

      final uniqueKeys = comparableKeys.toSet();
      expect(
        uniqueKeys.length,
        comparableKeys.length,
        reason: 'No two shortcuts should have identical key combinations',
      );
    });

    test('repositoryFetch has shift+F, editFindInFiles is absent', () {
      final shortcuts = gbmActionShortcuts(false);

      // repositoryFetch should exist and have keyF with shift
      expect(shortcuts.containsKey(GbmActionId.repositoryFetch), isTrue);
      final repoFetch = shortcuts[GbmActionId.repositoryFetch]!;
      expect(repoFetch.trigger, LogicalKeyboardKey.keyF);
      expect(repoFetch.shift, isTrue);

      // editFindInFiles should not exist in the map
      expect(shortcuts.containsKey(GbmActionId.editFindInFiles), isFalse);
    });

    test('viewFileListAsTree has shift+T, branchStashChanges is absent', () {
      final shortcuts = gbmActionShortcuts(false);

      // viewFileListAsTree should exist and have keyT with shift
      expect(shortcuts.containsKey(GbmActionId.viewFileListAsTree), isTrue);
      final viewTree = shortcuts[GbmActionId.viewFileListAsTree]!;
      expect(viewTree.trigger, LogicalKeyboardKey.keyT);
      expect(viewTree.shift, isTrue);

      // branchStashChanges should not exist in the map
      expect(shortcuts.containsKey(GbmActionId.branchStashChanges), isFalse);
    });

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
