import 'package:flutter/foundation.dart';

import '../../../routing/route_paths.dart';

/// The kind of content a [WorkspaceTab] renders. [history] and
/// [workingCopy] are the two fixed tabs tab_row.dart has always shown;
/// [compare] is declared now, ahead of need, purely so the M6 commit that
/// actually adds Compare tabs (multiple, closable, each carrying its own ref
/// pair) doesn't have to touch this enum -- this commit never constructs a
/// [WorkspaceTab] with [compare].
enum WorkspaceTabKind { history, workingCopy, compare }

/// One entry in the workspace tab strip. Immutable so a new tab list is
/// always a fresh `copyWith`-free rebuild rather than an in-place mutation
/// (docs/ARCHITECTURE.md invariant 2, which CLAUDE.md notes applies to the
/// Flutter layer too) -- this matters once Compare tabs can be opened and
/// closed and the list itself becomes session state.
///
/// [route] is the full path tab_row.dart's GoRouter navigates to on tap,
/// and doubles as the key [activeWorkspaceTabIndex] matches the current
/// location against to decide which tab is active.
@immutable
class WorkspaceTab {
  const WorkspaceTab({
    required this.kind,
    required this.label,
    required this.route,
    this.closable = false,
    this.badgeCount = 0,
  });

  final WorkspaceTabKind kind;
  final String label;
  final String route;

  /// Fixed tabs (History, Working Copy) are never closable. Only the
  /// future Compare tabs will set this true.
  final bool closable;
  final int badgeCount;
}

/// The two tabs tab_row.dart has always rendered, in the same History-then-
/// Working-Copy order as before. No Compare tab is ever included here --
/// that only starts once a later M6 commit adds the "open a Compare tab"
/// action.
List<WorkspaceTab> defaultWorkspaceTabs(
  String repoId, {
  required int pendingChangeCount,
}) {
  return <WorkspaceTab>[
    WorkspaceTab(
      kind: WorkspaceTabKind.history,
      label: 'History',
      route: RoutePaths.historyFor(repoId),
    ),
    WorkspaceTab(
      kind: WorkspaceTabKind.workingCopy,
      label: 'Working Copy',
      route: RoutePaths.workingCopyFor(repoId),
      badgeCount: pendingChangeCount,
    ),
  ];
}

/// Finds which [tabs] entry matches the current GoRouter [location].
///
/// For the two fixed tabs, [location] (`GoRouterState.uri.toString()`) is
/// always exactly one tab's [WorkspaceTab.route] -- there's no extra path
/// segment to strip -- so a plain equality match is safe. When nothing
/// matches (e.g. a dialog route is pushed on top), this falls back to index
/// 0 (History), the same default the old `!onWorkingCopy` check produced.
int activeWorkspaceTabIndex(List<WorkspaceTab> tabs, String location) {
  final int index = tabs.indexWhere(
    (WorkspaceTab tab) => tab.route == location,
  );
  return index == -1 ? 0 : index;
}
