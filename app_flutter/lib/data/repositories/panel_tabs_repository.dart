import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'repo_identity.dart';

/// The twelve advanced management panels spec page 14's `IAMAP` routes to
/// tabs rather than dialogs: "大型管理面板（12）… → 分頁（與 History /
/// Working copy / Compare 同一條分頁列）", because "有工具列 + 清單 + 明細的
/// 畫面不適合 modal：使用者需要邊看圖邊操作，且要能同時開兩個".
///
/// Deliberately excludes `clean-untracked`, which sits in the Tools menu's
/// `Rewrite history` submenu alongside two of these but belongs to `IAMAP`'s
/// *other* group ("中型表單 / 確認框（8）… → Dialog"). Menu adjacency is not
/// carrier assignment.
enum GbmPanelKind {
  manageStashes,
  manageWorktrees,
  manageRemotes,
  manageSubmodules,
  manageLfs,
  patches,
  interactiveRebase,
  bisect,
  reflog,
  blame,
  fileHistory,
  lineHistory;

  /// The tab-strip label. Sentence case per spec page 14 ("所有標籤一律
  /// sentence case"), and worded as the panel's own name rather than the
  /// menu item that opened it -- a tab says what it *is*, where a menu item
  /// says what it does.
  String get label => switch (this) {
    GbmPanelKind.manageStashes => 'Stashes',
    GbmPanelKind.manageWorktrees => 'Worktrees',
    GbmPanelKind.manageRemotes => 'Remotes',
    GbmPanelKind.manageSubmodules => 'Submodules',
    GbmPanelKind.manageLfs => 'Large files (LFS)',
    GbmPanelKind.patches => 'Patches',
    GbmPanelKind.interactiveRebase => 'Interactive rebase',
    GbmPanelKind.bisect => 'Bisect',
    GbmPanelKind.reflog => 'Reflog',
    GbmPanelKind.blame => 'Blame',
    GbmPanelKind.fileHistory => 'File history',
    GbmPanelKind.lineHistory => 'Line history',
  };

  /// Stable slug used inside the tab id, so a tab id is human-readable in a
  /// route (`/repo/<id>/panel/worktrees-0`) the way `compare-0` already is.
  String get slug => switch (this) {
    GbmPanelKind.manageStashes => 'stashes',
    GbmPanelKind.manageWorktrees => 'worktrees',
    GbmPanelKind.manageRemotes => 'remotes',
    GbmPanelKind.manageSubmodules => 'submodules',
    GbmPanelKind.manageLfs => 'lfs',
    GbmPanelKind.patches => 'patches',
    GbmPanelKind.interactiveRebase => 'interactive-rebase',
    GbmPanelKind.bisect => 'bisect',
    GbmPanelKind.reflog => 'reflog',
    GbmPanelKind.blame => 'blame',
    GbmPanelKind.fileHistory => 'file-history',
    GbmPanelKind.lineHistory => 'line-history',
  };

  /// Whether this panel's dialog has been ported to the tab carrier yet.
  ///
  /// Spec page 14 assigns all twelve to tabs, but they are being moved one
  /// commit at a time (progress tracked on issue #76). Until a panel is
  /// ported, its entry point must keep opening the **existing dialog** --
  /// routing it to an unbuilt tab would trade a working screen for a
  /// placeholder, which is a regression dressed up as conformance.
  ///
  /// Flip this as each panel lands; it is the single switch that decides
  /// which carrier every entry point uses.
  bool get isPortedToTab =>
      this == GbmPanelKind.manageWorktrees ||
      this == GbmPanelKind.manageStashes ||
      this == GbmPanelKind.manageRemotes ||
      this == GbmPanelKind.manageSubmodules ||
      this == GbmPanelKind.manageLfs ||
      this == GbmPanelKind.reflog ||
      this == GbmPanelKind.bisect ||
      this == GbmPanelKind.blame ||
      this == GbmPanelKind.fileHistory ||
      this == GbmPanelKind.lineHistory;

  /// Whether this panel is *about* a particular file, in which case two
  /// tabs of the same kind for two different paths are two different tabs.
  /// The nine repository-wide panels are singletons: asking for Worktrees
  /// twice means "show me Worktrees", not "give me a second copy".
  bool get isPerSubject =>
      this == GbmPanelKind.blame ||
      this == GbmPanelKind.fileHistory ||
      this == GbmPanelKind.lineHistory;
}

/// One open management-panel tab. Immutable, like [CompareTabSpec] and
/// `WorkspaceTab` -- a new list is always a fresh rebuild, never an in-place
/// mutation (docs/ARCHITECTURE.md invariant 2, which applies to the Flutter
/// layer too).
@immutable
class PanelTabSpec {
  const PanelTabSpec({required this.id, required this.kind, this.subject});

  final String id;
  final GbmPanelKind kind;

  /// The file path a per-subject panel ([GbmPanelKind.isPerSubject]) is
  /// about; null for the nine repository-wide panels.
  final String? subject;

  /// What the tab strip shows. A per-subject panel appends the file's base
  /// name, so two Blame tabs are told apart without reading the route.
  String get label {
    if (subject == null || subject!.isEmpty) return kind.label;
    final String base = subject!.split('/').last;
    return '${kind.label}: $base';
  }
}

/// Every management-panel tab currently open for one repository.
///
/// Pure UI state, not FFI-backed (unlike `RepoSessionState`), so it lives in
/// its own small family provider rather than growing that class -- the same
/// arrangement `compareTabsProvider` already uses, and this deliberately
/// mirrors it rather than inventing a second tab mechanism.
class PanelTabsNotifier extends StateNotifier<List<PanelTabSpec>> {
  PanelTabsNotifier() : super(const <PanelTabSpec>[]);

  int _nextId = 0;

  /// Opens [kind] (optionally about [subject]) and returns the tab id the
  /// caller navigates to via `RoutePaths.panelFor(repoId, id)`.
  ///
  /// Re-opening an already-open panel **focuses it instead of duplicating
  /// it**: the returned id is the existing tab's. Without this, choosing
  /// Tools > Worktrees twice would stack two identical tabs, which is the
  /// behaviour spec calls out as wrong for dialogs ("同一功能不留兩條路")
  /// and would be no better on a tab strip. Compare tabs differ on purpose
  /// -- two Compare tabs hold two genuinely different ref pairs.
  String open(GbmPanelKind kind, {String? subject}) {
    final String? normalized = kind.isPerSubject ? subject : null;
    for (final PanelTabSpec tab in state) {
      if (tab.kind == kind && tab.subject == normalized) return tab.id;
    }
    final String id = '${kind.slug}-${_nextId++}';
    state = <PanelTabSpec>[
      ...state,
      PanelTabSpec(id: id, kind: kind, subject: normalized),
    ];
    return id;
  }

  void close(String id) {
    state = state.where((PanelTabSpec tab) => tab.id != id).toList();
  }
}

final StateNotifierProviderFamily<
  PanelTabsNotifier,
  List<PanelTabSpec>,
  RepoIdentity
>
panelTabsProvider =
    StateNotifierProvider.family<
      PanelTabsNotifier,
      List<PanelTabSpec>,
      RepoIdentity
    >((ref, identity) => PanelTabsNotifier());
