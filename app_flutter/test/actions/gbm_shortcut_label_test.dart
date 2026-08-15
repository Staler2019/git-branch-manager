import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/actions/gbm_shortcuts.dart';

void main() {
  group('GbmKeyboardShortcut.displayLabel', () {
    test('spells modifiers out with + off macOS', () {
      const GbmKeyboardShortcut shortcut = GbmKeyboardShortcut(
        trigger: LogicalKeyboardKey.keyP,
        control: true,
        meta: false,
        shift: true,
      );
      expect(shortcut.displayLabel, 'Ctrl+Shift+P');
    });

    test('uses symbols with no separator on macOS', () {
      const GbmKeyboardShortcut shortcut = GbmKeyboardShortcut(
        trigger: LogicalKeyboardKey.keyP,
        control: false,
        meta: true,
        shift: true,
      );
      expect(shortcut.displayLabel, '⇧⌘P');
    });

    test('puts Command last, per the Apple HIG order', () {
      const GbmKeyboardShortcut shortcut = GbmKeyboardShortcut(
        trigger: LogicalKeyboardKey.keyK,
        control: false,
        meta: true,
        alt: true,
        shift: true,
      );
      expect(shortcut.displayLabel, '⌥⇧⌘K');
    });

    test('names keys whose keyLabel is unidiomatic', () {
      const GbmKeyboardShortcut comma = GbmKeyboardShortcut(
        trigger: LogicalKeyboardKey.comma,
        control: true,
        meta: false,
      );
      expect(comma.displayLabel, 'Ctrl+,');

      const GbmKeyboardShortcut enter = GbmKeyboardShortcut(
        trigger: LogicalKeyboardKey.enter,
        control: true,
        meta: false,
      );
      expect(enter.displayLabel, 'Ctrl+Enter');

      const GbmKeyboardShortcut tab = GbmKeyboardShortcut(
        trigger: LogicalKeyboardKey.tab,
        control: true,
        meta: false,
      );
      expect(tab.displayLabel, 'Ctrl+Tab');
    });

    test('every registered shortcut produces a non-empty label', () {
      for (final bool isMacOS in <bool>[true, false]) {
        final Map<GbmActionId, GbmKeyboardShortcut> shortcuts =
            gbmActionShortcuts(isMacOS);
        for (final MapEntry<GbmActionId, GbmKeyboardShortcut> entry
            in shortcuts.entries) {
          expect(
            entry.value.displayLabel,
            isNotEmpty,
            reason: '${entry.key} has no renderable shortcut label',
          );
          expect(
            entry.value.displayLabel,
            isNot(contains('?')),
            reason: '${entry.key} fell through to the unknown-key fallback',
          );
        }
      }
    });
  });
}
