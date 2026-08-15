// Pure-Dart unit tests for workspace_tab.dart's data model and the two
// helper functions tab_row.dart is switched onto in this commit --
// defaultWorkspaceTabs() (the fixed History/Working Copy pair) and
// activeWorkspaceTabIndex() (the location -> active-tab lookup that
// replaces tab_row.dart's old `location.endsWith('/working-copy')` check).
// No widget pump needed: everything here is plain data/functions.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/workspace/widgets/workspace_tab.dart';
import 'package:gbm_flutter/routing/route_paths.dart';

const String _repoId = 'repo1';

void main() {
  group('defaultWorkspaceTabs', () {
    test('returns History before Working Copy, matching current tab order', () {
      final List<WorkspaceTab> tabs = defaultWorkspaceTabs(
        _repoId,
        pendingChangeCount: 0,
      );

      expect(tabs, hasLength(2));
      expect(tabs[0].kind, WorkspaceTabKind.history);
      expect(tabs[1].kind, WorkspaceTabKind.workingCopy);
    });

    test('History tab has the History label, route, and no badge', () {
      final List<WorkspaceTab> tabs = defaultWorkspaceTabs(
        _repoId,
        pendingChangeCount: 5,
      );
      final WorkspaceTab history = tabs[0];

      expect(history.label, 'History');
      expect(history.route, RoutePaths.historyFor(_repoId));
      expect(history.badgeCount, 0);
      expect(history.closable, isFalse);
    });

    test('Working Copy tab has the Working Copy label, route, and no badge '
        'when there are no pending changes', () {
      final List<WorkspaceTab> tabs = defaultWorkspaceTabs(
        _repoId,
        pendingChangeCount: 0,
      );
      final WorkspaceTab workingCopy = tabs[1];

      expect(workingCopy.label, 'Working Copy');
      expect(workingCopy.route, RoutePaths.workingCopyFor(_repoId));
      expect(workingCopy.badgeCount, 0);
      expect(workingCopy.closable, isFalse);
    });

    test(
      'Working Copy tab carries the pending change count as its badgeCount',
      () {
        final List<WorkspaceTab> tabs = defaultWorkspaceTabs(
          _repoId,
          pendingChangeCount: 3,
        );

        expect(tabs[1].badgeCount, 3);
        // History never picks up the count -- only Working Copy shows it.
        expect(tabs[0].badgeCount, 0);
      },
    );

    test('neither fixed tab is closable', () {
      final List<WorkspaceTab> tabs = defaultWorkspaceTabs(
        _repoId,
        pendingChangeCount: 7,
      );

      expect(tabs.every((WorkspaceTab tab) => !tab.closable), isTrue);
    });
  });

  group('activeWorkspaceTabIndex', () {
    late List<WorkspaceTab> tabs;

    setUp(() {
      tabs = defaultWorkspaceTabs(_repoId, pendingChangeCount: 0);
    });

    test('returns the History index when location is the History route', () {
      expect(activeWorkspaceTabIndex(tabs, RoutePaths.historyFor(_repoId)), 0);
    });

    test('returns the Working Copy index when location is the Working Copy '
        'route', () {
      expect(
        activeWorkspaceTabIndex(tabs, RoutePaths.workingCopyFor(_repoId)),
        1,
      );
    });

    test('falls back to index 0 (History) when location matches no tab route, '
        'mirroring the old !onWorkingCopy default', () {
      expect(activeWorkspaceTabIndex(tabs, '/repo/$_repoId/dialogs/merge'), 0);
    });
  });
}
