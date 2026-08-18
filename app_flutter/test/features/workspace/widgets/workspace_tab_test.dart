// Pure-Dart unit tests for workspace_tab.dart's data model and its three
// helper functions -- defaultWorkspaceTabs() (the fixed History/Working
// Copy pair), activeWorkspaceTabIndex() (the location -> active-tab
// lookup), and nextWorkspaceTabRoute() (View > Next tab / Ctrl+Tab's
// wrap-around route lookup, backing workspace_screen.dart's
// GbmActionId.viewNextTab handler). No widget pump needed: everything here
// is plain data/functions.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/compare_tabs_repository.dart';
import 'package:gbm_flutter/features/workspace/widgets/tab_row.dart';
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

  group('nextWorkspaceTabRoute', () {
    test('from History, returns Working Copy\'s route', () {
      final List<WorkspaceTab> tabs = defaultWorkspaceTabs(
        _repoId,
        pendingChangeCount: 0,
      );

      expect(
        nextWorkspaceTabRoute(tabs, RoutePaths.historyFor(_repoId)),
        RoutePaths.workingCopyFor(_repoId),
      );
    });

    test('from the last tab, wraps back around to the first tab\'s route', () {
      final List<WorkspaceTab> tabs = defaultWorkspaceTabs(
        _repoId,
        pendingChangeCount: 0,
      );

      expect(
        nextWorkspaceTabRoute(tabs, RoutePaths.workingCopyFor(_repoId)),
        RoutePaths.historyFor(_repoId),
      );
    });

    test('cycles through an open Compare tab between Working Copy and the '
        'wrap back to History', () {
      final CompareTabSpec compareSpec = const CompareTabSpec(
        id: 'tab1',
        left: 'HEAD',
      );
      final List<WorkspaceTab> tabs = <WorkspaceTab>[
        ...defaultWorkspaceTabs(_repoId, pendingChangeCount: 0),
        compareWorkspaceTab(compareSpec, _repoId),
      ];

      expect(
        nextWorkspaceTabRoute(tabs, RoutePaths.workingCopyFor(_repoId)),
        RoutePaths.compareFor(_repoId, 'tab1'),
      );
      expect(
        nextWorkspaceTabRoute(tabs, RoutePaths.compareFor(_repoId, 'tab1')),
        RoutePaths.historyFor(_repoId),
      );
    });

    test('when location matches no tab route, falls back to index 0 first '
        '(mirroring activeWorkspaceTabIndex) and advances to Working Copy', () {
      final List<WorkspaceTab> tabs = defaultWorkspaceTabs(
        _repoId,
        pendingChangeCount: 0,
      );

      expect(
        nextWorkspaceTabRoute(tabs, '/repo/$_repoId/dialogs/merge'),
        RoutePaths.workingCopyFor(_repoId),
      );
    });

    test('with only one tab, returns that same tab\'s route', () {
      final List<WorkspaceTab> tabs = <WorkspaceTab>[
        WorkspaceTab(
          kind: WorkspaceTabKind.history,
          label: 'History',
          route: RoutePaths.historyFor(_repoId),
        ),
      ];

      expect(
        nextWorkspaceTabRoute(tabs, RoutePaths.historyFor(_repoId)),
        RoutePaths.historyFor(_repoId),
      );
    });
  });
}
