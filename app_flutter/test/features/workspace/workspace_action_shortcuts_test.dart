import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/features/workspace/widgets/workspace_action_shortcuts.dart';

void main() {
  group('WorkspaceActionShortcuts', () {
    testWidgets('fires handler on shortcut press (non-macOS)', (tester) async {
      int callCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceActionShortcuts(
              isMacOS: false,
              handlers: {
                GbmActionId.viewToggleSidebar: () => callCount++,
              },
              child: const SizedBox(),
            ),
          ),
        ),
      );

      // Ctrl+B on Windows/Linux
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(callCount, 1);
    });

    testWidgets('uses Cmd instead of Ctrl on macOS', (tester) async {
      int callCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceActionShortcuts(
              isMacOS: true,
              handlers: {
                GbmActionId.viewToggleSidebar: () => callCount++,
              },
              child: const SizedBox(),
            ),
          ),
        ),
      );

      // Cmd+B on macOS should work
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pumpAndSettle();

      expect(callCount, 1);
    });

    testWidgets('does not fire when wrong modifier is used on macOS',
        (tester) async {
      int callCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceActionShortcuts(
              isMacOS: true,
              handlers: {
                GbmActionId.viewToggleSidebar: () => callCount++,
              },
              child: const SizedBox(),
            ),
          ),
        ),
      );

      // Ctrl+B should NOT work on macOS when configured for Cmd
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(callCount, 0);
    });

    testWidgets('null handler does not throw', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceActionShortcuts(
              isMacOS: false,
              handlers: {
                GbmActionId.viewToggleSidebar: null,
              },
              child: const SizedBox(),
            ),
          ),
        ),
      );

      // Should not throw even though handler is null
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Test passes if no exception was thrown
      expect(true, true);
    });

    testWidgets('absent id in handler map does not throw', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceActionShortcuts(
              isMacOS: false,
              handlers: {}, // No handlers at all
              child: const SizedBox(),
            ),
          ),
        ),
      );

      // Should not throw even though no handlers are registered
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      // Test passes if no exception was thrown
      expect(true, true);
    });

    testWidgets('fires handler with shift modifier', (tester) async {
      int callCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WorkspaceActionShortcuts(
              isMacOS: false,
              handlers: {
                GbmActionId.branchNewBranch: () => callCount++,
              },
              child: const SizedBox(),
            ),
          ),
        ),
      );

      // Ctrl+Shift+B
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(callCount, 1);
    });
  });
}
