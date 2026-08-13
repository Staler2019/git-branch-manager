import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/actions/gbm_shortcuts.dart';

void main() {
  group('gbmActionShortcuts', () {
    test(
      'macOS shortcuts has exactly 34 entries with meta=true, control=false',
      () {
        final shortcuts = gbmActionShortcuts(true);
        expect(shortcuts.length, 34);
        for (final shortcut in shortcuts.values) {
          expect(shortcut.meta, isTrue, reason: 'macOS should use meta=true');
          expect(
            shortcut.control,
            isFalse,
            reason: 'macOS should use control=false',
          );
        }
      },
    );

    test(
      'non-macOS shortcuts has exactly 34 entries with meta=false, control=true',
      () {
        final shortcuts = gbmActionShortcuts(false);
        expect(shortcuts.length, 34);
        for (final shortcut in shortcuts.values) {
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
      },
    );

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
  });
}
