// Presses an action's real keyboard binding on the host platform.
//
// The device tier runs on macOS, Windows and Linux, and a test that writes
// `metaLeft` by hand presses Cmd on all three -- on Windows that is the
// Windows key, the shortcut never fires, and the test fails on an assertion
// far from the keypress. Reading `gbmActionShortcuts` keeps the key table in
// one place.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/actions/gbm_shortcuts.dart';

/// Holds [id]'s modifiers, taps its trigger, and releases them in reverse.
///
/// `Platform.isMacOS`, not `defaultTargetPlatform`, because that is what
/// `WorkspaceScreen` hands `WorkspaceActionShortcuts` when it binds the keys.
Future<void> pressActionShortcut(WidgetTester tester, GbmActionId id) async {
  final GbmKeyboardShortcut? shortcut = gbmActionShortcuts(
    Platform.isMacOS,
  )[id];
  if (shortcut == null) {
    throw StateError('$id has no keyboard shortcut on this platform');
  }
  final List<LogicalKeyboardKey> modifiers = <LogicalKeyboardKey>[
    if (shortcut.meta) LogicalKeyboardKey.metaLeft,
    if (shortcut.control) LogicalKeyboardKey.controlLeft,
    if (shortcut.shift) LogicalKeyboardKey.shiftLeft,
    if (shortcut.alt) LogicalKeyboardKey.altLeft,
  ];
  final List<LogicalKeyboardKey> held = <LogicalKeyboardKey>[];
  try {
    for (final LogicalKeyboardKey key in modifiers) {
      await tester.sendKeyDownEvent(key);
      held.add(key);
    }
    await tester.sendKeyEvent(shortcut.trigger);
  } finally {
    for (final LogicalKeyboardKey key in held.reversed) {
      await tester.sendKeyUpEvent(key);
    }
  }
}
