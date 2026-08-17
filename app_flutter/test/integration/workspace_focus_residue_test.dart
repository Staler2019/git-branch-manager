// Integration coverage for the "intent A -> intent B 無殘留" item of the
// approved plan that workspace_tab_compare_test.dart didn't cover:
// editFilterBranches (Cmd/Ctrl+Shift+E) must reveal a hidden sidebar before
// focusing its filter field (mirroring fileSwitchRepository's own
// reveal-then-act comment in workspace_screen.dart), and viewToggleSidebar
// (Cmd/Ctrl+B) collapsing/re-expanding the sidebar must not leave stale
// focus behind -- re-expanding via the toggle alone (not editFilterBranches)
// must not silently refocus the filter field.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/sidebar/sidebar_panel.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

Future<void> _pressKeys(
  WidgetTester tester,
  List<LogicalKeyboardKey> modifiers,
  LogicalKeyboardKey key,
) async {
  for (final LogicalKeyboardKey modifier in modifiers) {
    await tester.sendKeyDownEvent(modifier);
  }
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  for (final LogicalKeyboardKey modifier in modifiers.reversed) {
    await tester.sendKeyUpEvent(modifier);
  }
  await tester.pumpAndSettle();
}

Future<void> _pressCtrlShiftE(WidgetTester tester) =>
    _pressKeys(tester, <LogicalKeyboardKey>[
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.shiftLeft,
    ], LogicalKeyboardKey.keyE);

Future<void> _pressCtrlB(WidgetTester tester) => _pressKeys(
  tester,
  <LogicalKeyboardKey>[LogicalKeyboardKey.controlLeft],
  LogicalKeyboardKey.keyB,
);

/// The single branch-filter [TextField] inside [SidebarPanel] -- see
/// workspace_interrupt_overlay_test.dart's header comment for why scoping to
/// a specific ancestor, not a bare `find.byType(TextField)`, is required
/// once more than one TextField can be mounted at once.
Finder _filterField() => find.descendant(
  of: find.byType(SidebarPanel),
  matching: find.byType(TextField),
);

bool _filterFieldHasFocus(WidgetTester tester) {
  final TextField field = tester.widget<TextField>(_filterField());
  return field.focusNode?.hasFocus ?? false;
}

void main() {
  group('sidebar filter focus residue', () {
    testWidgets(
      'editFilterBranches reveals a hidden sidebar and focuses its filter '
      'field',
      (tester) async {
        await pumpWorkspace(tester, identity: _identity);

        await _pressCtrlB(tester);
        expect(
          find.byType(SidebarPanel),
          findsNothing,
          reason:
              'Toggle sidebar must hide it before this test can prove '
              'editFilterBranches reveals it again.',
        );

        await _pressCtrlShiftE(tester);
        expect(
          find.byType(SidebarPanel),
          findsOneWidget,
          reason:
              'editFilterBranches must reveal the sidebar first -- '
              'there is nothing to focus otherwise.',
        );
        expect(
          _filterFieldHasFocus(tester),
          isTrue,
          reason:
              'editFilterBranches must focus the filter field once the '
              'sidebar revealing it is actually in the tree.',
        );
      },
    );

    testWidgets(
      'editFilterBranches focuses the filter field when the sidebar is '
      'already visible',
      (tester) async {
        await pumpWorkspace(tester, identity: _identity);

        expect(find.byType(SidebarPanel), findsOneWidget);
        expect(_filterFieldHasFocus(tester), isFalse);

        await _pressCtrlShiftE(tester);
        expect(_filterFieldHasFocus(tester), isTrue);
      },
    );

    testWidgets(
      'collapsing then re-expanding via viewToggleSidebar alone does not '
      'leave the filter field focused',
      (tester) async {
        await pumpWorkspace(tester, identity: _identity);

        await _pressCtrlShiftE(tester);
        expect(
          _filterFieldHasFocus(tester),
          isTrue,
          reason:
              'Sanity check: the field really was focused before the '
              'collapse/expand round trip.',
        );

        await _pressCtrlB(tester);
        expect(find.byType(SidebarPanel), findsNothing);

        await _pressCtrlB(tester);
        expect(find.byType(SidebarPanel), findsOneWidget);
        expect(
          _filterFieldHasFocus(tester),
          isFalse,
          reason:
              'viewToggleSidebar is not editFilterBranches -- '
              're-expanding the sidebar on its own must not silently '
              'refocus the filter field left over from a previous '
              'editFilterBranches call.',
        );
      },
    );
  });
}
