import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../actions/gbm_action_availability.dart';
import '../../actions/gbm_action_id.dart';
import '../../data/models/ref_snapshot.dart';
import '../../data/models/remote_info.dart';
import '../../data/models/stash_entry.dart';
import '../../data/repositories/branch_repository.dart';
import '../../data/repositories/compare_tabs_repository.dart';
import '../../data/repositories/panel_tabs_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../actions/gbm_selection_gesture.dart';
import '../../data/models/list_selection.dart';
import '../../data/repositories/branch_filter_repository.dart';
import '../../data/repositories/branch_selection_repository.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_menu.dart';
import '../../widgets/prompt_text_dialog.dart';
import '../repo_switcher/repo_switcher_popover.dart';
import 'branch_tree_builder.dart';
import 'gone_marking.dart';
import 'widgets/branch_folder_menu_items.dart';
import 'widgets/branch_tree_item.dart';
import 'widgets/multi_branch_menu_items.dart';
import 'widgets/stash_menu_items.dart';
import 'branch_filter.dart';

/// Local branches for the open repository, with checkout-on-tap, plus
/// create/rename/delete and the multi-select "gone" bulk-delete flow (see
/// docs/FEATURES.md's "Branch sync hygiene" entry). The Dart analog of
/// `SidebarPanel`/`RefTreeModel` (src/app/views/SidebarPanel.cpp,
/// src/app/models/RefTreeModel.cpp). Tags/stashes/worktrees still have
/// their own manage-* dialogs (see workspace_screen.dart's "⋯" menu) rather
/// than a sidebar tree -- but branches do not: local and remote-only
/// branches are merged into one tree via `branch_tree_builder.dart`'s
/// `mergeLocalAndRemoteBranches`, matching Flutter Desktop Spec page 02
/// items 4/12 ("Local 與 remote 不再分兩段，同一條分支只出現一次"). This
/// used to say "local branches only... unlike the Qt original" -- that was
/// the pre-merge state; the Qt original's single-tree design is what this
/// now (re)implements.
class SidebarPanel extends ConsumerStatefulWidget {
  const SidebarPanel({
    super.key,
    required this.identity,
    this.filterFocusNode,
    this.switcherController,
  });

  final RepoIdentity identity;

  /// Lets `WorkspaceScreen`'s `fileSwitchRepository` handler (Cmd/Ctrl+R)
  /// open the repository popover hanging off the button at the top of this
  /// panel -- see [RepoSwitcherController].
  final RepoSwitcherController? switcherController;

  /// Focused by `WorkspaceScreen`'s `editFilterBranches` action handler
  /// (Cmd/Ctrl+Shift+E) to jump the caret into the filter field below. Owned
  /// by the caller, not this widget, since the shortcut is registered above
  /// this widget in the tree -- mirrors `GbmSplitPaneController`'s
  /// attach/external-trigger rationale in split_pane.dart, but a plain
  /// `FocusNode` is enough here since "focus this field" needs no state of
  /// its own beyond what `Focus`/`TextField` already track.
  final FocusNode? filterFocusNode;

  @override
  ConsumerState<SidebarPanel> createState() => _SidebarPanelState();
}

class _SidebarPanelState extends ConsumerState<SidebarPanel> {
  /// Reads through to [branchSelectionProvider] -- the selection lives in a
  /// provider, not here, so `WorkspaceScreen` and the row that was
  /// right-clicked can both see it. Ticking a checkbox and Ctrl/Cmd-clicking
  /// a row write the same value; see the provider's doc comment.
  ListSelection<String> get _selection =>
      ref.read(branchSelectionProvider(widget.identity));

  StateController<ListSelection<String>> get _selectionController =>
      ref.read(branchSelectionProvider(widget.identity).notifier);
  final Set<String> _expandedFolders = <String>{};
  final TextEditingController _filterController = TextEditingController();

  /// P02-14's one filter box. The value lives in
  /// [branchFilterQueryProvider], not here, because the History graph
  /// converges on it -- see that provider's doc comment. `build()` watches it
  /// explicitly so this stays a plain read.
  String get _filterQuery =>
      ref.read(branchFilterQueryProvider(widget.identity));

  set _filterQuery(String value) =>
      ref.read(branchFilterQueryProvider(widget.identity).notifier).state =
          value;

  @override
  void initState() {
    super.initState();
    // The sidebar is hideable, so this State can be rebuilt while the query
    // is still set. Seeding the controller is what makes the box show the
    // filter that is actually in force rather than looking empty.
    _filterController.text = ref.read(
      branchFilterQueryProvider(widget.identity),
    );
  }

  @override
  void dispose() {
    _filterController.dispose();
    _treeFocus.dispose();
    super.dispose();
  }

  /// The branch tree's own focus node, so `MULTIKEYS`' keyboard half is
  /// scoped to the tree rather than the whole sidebar -- the filter
  /// `TextField` above it must keep Ctrl/Cmd+A as "select all text".
  final FocusNode _treeFocus = FocusNode(debugLabel: 'SidebarBranchTree');

  /// `MULTIKEYS`' Ctrl/Cmd+A over the rows as currently rendered, so a
  /// filtered tree selects what the user can actually see.
  void _selectAllBranches() {
    final List<String> all = _selectableBranchNames();
    if (all.isEmpty) return;
    _treeFocus.requestFocus();
    _selectionController.state = _selection.selectAll(all);
  }

  /// `MULTIKEYS`' Esc: collapse to the anchor rather than clearing, so the
  /// row the user started from stays selected.
  void _collapseSelection() =>
      _selectionController.state = _selection.collapseToAnchor();

  /// `MULTIKEYS`' Shift+↑/↓. The edge that moves is the one *opposite* the
  /// anchor, which is what makes Shift+↑ after Shift+↓ shrink the range
  /// back instead of growing it the other way.
  void _extendBranchSelection(int delta) {
    final List<String> all = _selectableBranchNames();
    final ListSelection<String> current = _selection;
    final String? anchor = current.anchor;
    if (all.isEmpty || anchor == null) return;
    final int anchorIndex = all.indexOf(anchor);
    if (anchorIndex < 0) return;
    final List<int> indices = <int>[
      for (final String name in current.items)
        if (all.contains(name)) all.indexOf(name),
    ]..sort();
    if (indices.isEmpty) return;
    final int movingEdge = indices.first == anchorIndex
        ? indices.last
        : indices.first;
    final int next = (movingEdge + delta).clamp(0, all.length - 1);
    _selectionController.state = current.range(all[next], all);
  }

  bool _isBulkSelectable(RefInfo branch) => !branch.isHead;

  /// Whether right-clicking [branch] should open `MULTIBRANCHMENU` rather
  /// than the per-row 05-B menu: it must be a bulk-selectable local row that
  /// is *already* part of a selection of more than one.
  bool _isInMultiSelection(RefInfo branch, {required bool isRemoteOnly}) =>
      !isRemoteOnly &&
      _isBulkSelectable(branch) &&
      _selection.length > 1 &&
      _selection.items.contains(branch.shortName);

  /// [gonePendingRefs] is threaded in rather than read from the session
  /// here so this stays a pure predicate over one row -- a branch whose
  /// upstream the dry-run preview reports as gone belongs in the bulk-delete
  /// selection exactly as much as one git already reports `[gone]` for.
  ///
  /// `RefKind` is not widened: a remote-only row is not a local branch and
  /// "delete gone branches" deletes local branches. [isEffectivelyGone]
  /// would return true for one, so the `!branch.isHead` /
  /// `worktreePath.isEmpty` guards are joined by [_isBulkSelectable]'s own
  /// kind check at every call site.
  bool _isGoneAndBulkSelectable(RefInfo branch, Set<String> gonePendingRefs) =>
      isEffectivelyGone(branch, gonePendingRefs) &&
      branch.kind == RefKind.localBranch &&
      !branch.isHead &&
      branch.worktreePath.isEmpty;

  /// Set while a prune is scheduled but has not run yet, so a burst of
  /// rebuilds between the frame and its callback schedules exactly one.
  bool _prunePending = false;

  /// The selection with names that no longer exist dropped, or null when
  /// every selected name is still live -- the early return that keeps this
  /// from writing an equal value on every build and rebuilding forever.
  ///
  /// [names] is the *short* names of the merged local + remote-only list, the
  /// same keys the selection itself uses.
  ListSelection<String>? _prunedSelection(Set<String> names) {
    final ListSelection<String> current = _selection;
    final List<String> survivors = <String>[
      for (final String name in current.items)
        if (names.contains(name)) name,
    ];
    if (survivors.length == current.length) return null;
    final String? anchor = current.anchor;
    return ListSelection<String>(
      items: survivors,
      anchor: survivors.isEmpty
          ? null
          : (anchor != null && names.contains(anchor)
                ? anchor
                : survivors.last),
    );
  }

  Set<String> _liveBranchNames() {
    final RefSnapshot refs = ref.read(repoRefsProvider(widget.identity));
    return mergeLocalAndRemoteBranches(
      refs.localBranches,
      refs.remoteBranches,
    ).map((RefInfo b) => b.shortName).toSet();
  }

  /// Drops selected names that no longer exist (a branch was deleted or
  /// renamed under the selection).
  ///
  /// **The write is deferred to after the frame, and must stay that way.**
  /// This is called from `build()`, and `_selectionController.state = ...`
  /// reaches Riverpod's `_debugCanModifyProviders`, which throws
  /// `Tried to modify a provider while the widget tree was building`. That
  /// throw is `assert`-guarded, so a release build strips it and lets the
  /// write land mid-build instead -- the inconsistent-state risk the message
  /// describes. Both halves are wrong; only the debug half is loud.
  ///
  /// Deferring rather than moving the whole thing to a `ref.listen` on
  /// `repoRefsProvider` is deliberate. A listener covers *changes* only, and
  /// `branchSelectionProvider` is not autoDispose, so a selection outlives
  /// the repository it was made in and can already be stale at the first
  /// build -- with no change event to hang a prune on. Deferring keeps one
  /// path for all three entry cases (mount, refs change, identity change),
  /// because `build()` always sees the current pair. Same trap, opposite
  /// resolution, as `WorkspaceScreen._syncHistoryFilter`, which needed a
  /// post-frame arm *alongside* its listener for exactly this reason.
  ///
  /// The callback recomputes from the then-current refs rather than from
  /// [branches]: refs can change again between this frame and the callback,
  /// and a captured list would write a stale answer.
  void _pruneSelection(List<RefInfo> branches) {
    if (_prunePending) return;
    final Set<String> names = branches.map((b) => b.shortName).toSet();
    if (_prunedSelection(names) == null) return;

    _prunePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prunePending = false;
      if (!mounted) return;
      final ListSelection<String>? next = _prunedSelection(_liveBranchNames());
      if (next == null) return;
      _selectionController.state = next;
    });
  }

  Future<void> _createBranch() async {
    final String? name = await promptText(
      context,
      title: 'New Branch',
      label: 'Branch name',
    );
    if (name == null || !mounted) return;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .createBranch(name: name);
  }

  Future<void> _createBranchFrom(RefInfo branch) async {
    final String? name = await promptText(
      context,
      title: 'New Branch from ${branch.shortName}',
      label: 'Branch name',
    );
    if (name == null || !mounted) return;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .createBranch(name: name, startPoint: branch.shortName);
  }

  void _openMergeDialog() {
    context.push(
      RoutePaths.mergeDialogFor(Uri.encodeComponent(widget.identity.workDir)),
    );
  }

  /// 05-B's "Rename branch". Unlike the Branch menu and F2, this names the
  /// clicked branch rather than letting the dialog fall back to HEAD.
  void _renameBranch(RefInfo branch) {
    context.push(
      RoutePaths.renameBranchDialogFor(
        Uri.encodeComponent(widget.identity.workDir),
        branch: branch.shortName,
      ),
    );
  }

  /// Ctrl/Cmd-click and Shift-click on a branch row. A plain click is
  /// deliberately not routed here -- see [BranchTreeItem.onSelect].
  ///
  /// A Shift range is measured over [_selectableBranchNames], the rows as
  /// rendered (filter applied, HEAD and remote-only rows excluded), so the
  /// range never quietly picks up a branch the user cannot see or act on.
  void _onBranchSelect(String name, SelectionGesture gesture) {
    // Focus first: a row's InkWell is focusable for traversal but a tap does
    // not request focus, and without focus inside the tree the keyboard half
    // of MULTIKEYS (Shift+↑/↓, Ctrl/Cmd+A, Esc) never reaches
    // [_BranchSelectionShortcuts].
    _treeFocus.requestFocus();
    final List<String> all = _selectableBranchNames();
    final ListSelection<String> current = _selection;
    _selectionController.state = switch (gesture) {
      SelectionGesture.single => current.single(name),
      SelectionGesture.toggle => current.toggle(name),
      SelectionGesture.range => current.range(name, all),
    };
  }

  /// The first *result* row in rendered order, or null when the filter
  /// matched nothing. Written during `build` because rendered order is the
  /// tree's, and the tree sorts its children -- recomputing it in the key
  /// handler would mean a second copy of that ordering.
  ///
  /// Deliberately not `_selectableBranchNames().first`: that list is in ref
  /// order, so it would name whichever branch git happened to list first
  /// rather than the row directly under the filter box.
  String? _firstResultName;

  /// P02-14 rule 8. Also the clear button's action, so the two cannot drift.
  void _clearFilter() {
    _filterController.clear();
    _filterQuery = '';
  }

  /// P02-14 rule 9: 「↓ 直接跳進第一個結果」.
  ///
  /// Selects rather than merely focusing, so ↑/↓ and Shift+↑/↓ continue from
  /// there -- the point of the key is to hand the keyboard over to the
  /// results. A no-op when nothing matched; the pinned current branch (rule
  /// 7) is not a result and is skipped, since landing on it would select
  /// something the query excluded.
  void _enterFirstResult() {
    final String? first = _firstResultName;
    if (first == null) return;
    _onBranchSelect(first, SelectionGesture.single);
  }

  /// The first selectable leaf in render order, skipping remote-only rows --
  /// `BranchTreeItem` draws those with `selected: false`, so selecting one
  /// would look like the key did nothing.
  String? _firstLeafName(List<BranchTreeNode> nodes) {
    for (final BranchTreeNode node in nodes) {
      if (node is BranchTreeLeaf) {
        if (node.ref.kind != RefKind.remoteBranch) return node.ref.shortName;
      } else if (node is BranchTreeFolder) {
        final String? nested = _firstLeafName(node.children);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  /// The rows a range can span: the merged tree as currently filtered,
  /// minus HEAD and remote-only rows (neither is bulk-selectable).
  List<String> _selectableBranchNames() {
    final RefSnapshot refs = ref.read(repoRefsProvider(widget.identity));
    final List<RefInfo> visible = filterBranches(
      mergeLocalAndRemoteBranches(refs.localBranches, refs.remoteBranches),
      _filterQuery,
    );
    return <String>[
      for (final RefInfo b in visible)
        if (_isBulkSelectable(b) && b.kind != RefKind.remoteBranch) b.shortName,
    ];
  }

  /// Spec page 13's `MULTIBRANCHMENU`, opened by right-clicking any row
  /// while more than one branch is selected. Right-clicking a row that is
  /// *not* in the selection collapses to it first and gets the ordinary
  /// 05-B menu instead -- see [_onBranchContextMenu].
  List<GbmMenuItem> _multiBranchMenuItems(RepoSessionState session) {
    final List<String> names = _selection.items;
    return multiBranchMenuItems(
      count: names.length,
      conflictActive: !isActionEnabled(GbmActionId.branchDeleteBranch, session),
      onCopyNames: () =>
          Clipboard.setData(ClipboardData(text: names.join('\n'))),
      onFetch: _fetchSelectedBranches,
      onPush: _pushSelectedBranches,
      fetchBlockedReason: _fetchBlockedReason(),
      pushBlockedReason: _pushBlockedReason(),
      onCompare: names.length == 2 ? _compareSelectedBranches : null,
      onDelete: _deleteSelected,
    );
  }

  /// The selected branches that still exist in the ref snapshot, as
  /// [RefInfo] rather than bare names -- Fetch and Push both need each
  /// branch's `upstream` to work out which remote it belongs to.
  List<RefInfo> _selectedBranchRefs() {
    final RefSnapshot refs = ref.read(repoRefsProvider(widget.identity));
    final Set<String> names = _selection.items.toSet();
    return <RefInfo>[
      for (final RefInfo b in refs.localBranches)
        if (names.contains(b.shortName)) b,
    ];
  }

  /// Groups [branches] by the remote their upstream lives on.
  ///
  /// `RefInfo.upstream` is the **full** ref name (`%(upstream)`, e.g.
  /// `refs/remotes/origin/main`), so the remote comes from
  /// [remoteBranchParts] -- never from splitting on the first slash, which
  /// yields `"refs"` and is the live bug #74 records in
  /// `delete_branch_dialog.dart`. `upstream.isEmpty` is the "no upstream"
  /// test, **not** `hasTrackingInfo`: the latter mirrors
  /// `%(upstream:track)`, which is an empty string for a branch exactly in
  /// sync with its upstream (the Tier 0c trap).
  Map<String, List<RefInfo>> _groupByUpstreamRemote(List<RefInfo> branches) {
    final Map<String, List<RefInfo>> byRemote = <String, List<RefInfo>>{};
    for (final RefInfo b in branches) {
      if (b.upstream.isEmpty) continue;
      final (String remote, String _) = remoteBranchParts(b.upstream);
      if (remote.isEmpty) continue;
      byRemote.putIfAbsent(remote, () => <RefInfo>[]).add(b);
    }
    return byRemote;
  }

  /// MULTIBRANCHMENU's `Fetch N branches`.
  ///
  /// Spec page 13 says nothing about which remote a multi-branch fetch
  /// targets, so the rule here is the only one that needs no guessing: a
  /// branch is fetched through the remote its own upstream names. One
  /// `gbm_remote_fetch` call per distinct remote, each carrying that
  /// remote's refspecs -- `gbm_capi.h` rejects a non-empty `refs` with an
  /// empty `remoteName`, so a single batched call is not available, and a
  /// selection spanning two remotes is genuinely two fetches.
  ///
  /// A branch with no upstream has no remote-tracking ref to update and is
  /// skipped; when *none* of the selection has one, the menu row is
  /// disabled with [_fetchBlockedReason] rather than silently doing nothing.
  void _fetchSelectedBranches() {
    final Map<String, List<RefInfo>> byRemote = _groupByUpstreamRemote(
      _selectedBranchRefs(),
    );
    final RepoSessionController session = ref.read(
      repoSessionProvider(widget.identity).notifier,
    );
    byRemote.forEach((String remote, List<RefInfo> branches) {
      session.fetchRemote(
        remoteName: remote,
        refs: <String>[
          for (final RefInfo b in branches) remoteBranchParts(b.upstream).$2,
        ],
      );
    });
  }

  /// MULTIBRANCHMENU's `Push N branches`.
  ///
  /// Published branches go to the remote their upstream names, one
  /// `gbm_push` per remote -- and because `gbm_push` now takes a branch
  /// list, that is one `git push <remote> a b c` per remote rather than one
  /// per branch, which is what keeps a same-remote batch a single
  /// background task (spec page 10).
  ///
  /// Unpublished branches (spec's `local` badge state, "還沒 push 過…Push
  /// 後 badge 自動消失") are the case Push exists for, but they name no
  /// remote. They are pushed to the repository's sole remote with
  /// `--set-upstream` when there is exactly one; with several remotes there
  /// is nothing to infer from, so they are excluded and the row explains
  /// that via [_pushBlockedReason]. They are also kept in their own call
  /// rather than folded into a same-remote published group: `push -u` would
  /// otherwise repoint a branch that tracks a differently-named upstream.
  void _pushSelectedBranches() {
    final List<RefInfo> selected = _selectedBranchRefs();
    final Map<String, List<RefInfo>> byRemote = _groupByUpstreamRemote(
      selected,
    );
    final List<RefInfo> unpublished = <RefInfo>[
      for (final RefInfo b in selected)
        if (b.upstream.isEmpty) b,
    ];
    final RepoSessionController session = ref.read(
      repoSessionProvider(widget.identity).notifier,
    );
    byRemote.forEach((String remote, List<RefInfo> branches) {
      session.pushChanges(
        remoteName: remote,
        branches: <String>[for (final RefInfo b in branches) b.shortName],
      );
    });
    final String? sole = _soleRemoteName();
    if (unpublished.isNotEmpty && sole != null) {
      session.pushChanges(
        remoteName: sole,
        branches: <String>[for (final RefInfo b in unpublished) b.shortName],
        setUpstream: true,
      );
    }
  }

  /// The repository's only remote, or null when it has none or several.
  String? _soleRemoteName() {
    final List<RemoteInfo> remotes = ref
        .read(repoSessionProvider(widget.identity))
        .remotes;
    return remotes.length == 1 ? remotes.single.name : null;
  }

  /// Why `Fetch N branches` is off, or null when it is available.
  String? _fetchBlockedReason() =>
      _groupByUpstreamRemote(_selectedBranchRefs()).isEmpty
      ? 'None of the selected branches has an upstream to fetch from'
      : null;

  /// Why `Push N branches` is off, or null when it is available. See
  /// [_pushSelectedBranches] for why an unpublished branch needs a sole
  /// remote.
  String? _pushBlockedReason() {
    final List<RefInfo> selected = _selectedBranchRefs();
    final bool anyPublished = _groupByUpstreamRemote(selected).isNotEmpty;
    final bool anyUnpublished = selected.any((RefInfo b) => b.upstream.isEmpty);
    if (anyUnpublished && _soleRemoteName() == null) {
      return anyPublished
          ? 'Some selected branches have no upstream, and this repository '
                'has no single remote to push them to'
          : 'The selected branches have no upstream, and this repository '
                'has no single remote to push them to';
    }
    return anyPublished || anyUnpublished ? null : 'Nothing to push';
  }

  /// COMPARES 1: 「同時選兩個分支 → 右鍵 Compare」. Both sides are known, so
  /// unlike 05-B's single-branch "Compare with…" this fills the tab
  /// outright instead of leaving the right to the ref picker.
  void _compareSelectedBranches() {
    final List<String> names = _selection.items;
    if (names.length != 2) return;
    final String repoId = Uri.encodeComponent(widget.identity.workDir);
    final String tabId = ref
        .read(compareTabsProvider(widget.identity).notifier)
        .open(left: names.first, right: names.last);
    context.go(RoutePaths.compareFor(repoId, tabId));
  }

  void _deleteSingle(RefInfo branch) {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .deleteBranch(names: <String>[branch.shortName]);
  }

  void _applyStash(StashEntry stash) {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .applyStash(stash.index);
  }

  void _popStash(StashEntry stash) {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .applyStash(stash.index, pop: true);
  }

  Future<void> _createBranchFromStash(StashEntry stash) async {
    final String? name = await promptText(
      context,
      title: 'New Branch from Stash',
      label: 'Branch name',
    );
    if (name == null || !mounted) return;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .branchFromStash(stash.index, name);
  }

  /// 05-H "View diff" -- opens the Stashes panel with this stash selected.
  ///
  /// Was the manage-stashes *dialog* until Tier 6c moved that panel to a tab
  /// (spec page 14 `IAMAP`). `context.go`, not `push`: a panel is a tab
  /// beside History/Working Copy and replaces the shell's child. The stash
  /// index rides in the query rather than the tab id, so asking twice for
  /// two different stashes focuses one tab instead of opening two.
  void _viewStashDiff(StashEntry stash) {
    final String repoId = Uri.encodeComponent(widget.identity.workDir);
    final String tabId = ref
        .read(panelTabsProvider(widget.identity).notifier)
        .open(GbmPanelKind.manageStashes);
    context.go(
      RoutePaths.panelFor(
        repoId,
        tabId,
        query: <String, String>{'select': '${stash.index}'},
      ),
    );
  }

  // Uses the stash's own commit oid as the Compare tab's left ref -- a
  // stash entry is a real commit (`git stash` creates one even though it
  // never gets a branch), so this is the same `left: <ref string>`
  // mechanism repositoryCompare already uses, not a new capability.
  void _compareStash(StashEntry stash) {
    final String repoId = Uri.encodeComponent(widget.identity.workDir);
    final String tabId = ref
        .read(compareTabsProvider(widget.identity).notifier)
        .open(left: stash.oid);
    context.go(RoutePaths.compareFor(repoId, tabId));
  }

  void _dropStash(StashEntry stash) {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .dropStash(stash.index);
  }

  void _checkoutTagDetached(RefInfo tag) {
    checkoutBranch(ref, widget.identity, tag.shortName, detach: true);
  }

  void _pushTag(RefInfo tag, RemoteInfo remote) {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .pushTag(remote.name, name: tag.shortName);
  }

  // Same `left: <ref string>` mechanism as _compareStash -- a tag name is
  // already a valid ref on its own.
  void _compareTag(RefInfo tag) {
    final String repoId = Uri.encodeComponent(widget.identity.workDir);
    final String tabId = ref
        .read(compareTabsProvider(widget.identity).notifier)
        .open(left: tag.shortName);
    context.go(RoutePaths.compareFor(repoId, tabId));
  }

  // 05-B "Compare with…" -- same `left: <ref string>` mechanism as
  // _compareTag and _compareStash. A branch name is already a valid ref, so
  // no per-branch compare dialog is needed; the Compare page's own picker
  // chooses the right-hand side.
  void _compareRef(String refName) {
    final String repoId = Uri.encodeComponent(widget.identity.workDir);
    final String tabId = ref
        .read(compareTabsProvider(widget.identity).notifier)
        .open(left: refName);
    context.go(RoutePaths.compareFor(repoId, tabId));
  }

  // 05-B "Rebase current onto here" -- the repository-level rebase dialog,
  // pre-selected on this branch, rather than a second per-branch dialog
  // that would duplicate its stash-first handling and commit-count preview.
  void _rebaseOntoBranch(RefInfo branch) {
    final String repoId = Uri.encodeComponent(widget.identity.workDir);
    context.push(
      RoutePaths.rebaseOntoDialogFor(repoId, target: branch.shortName),
    );
  }

  void _deleteTag(RefInfo tag) {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .deleteTag(tag.shortName);
  }

  List<RefInfo> _collectFolderLeafRefs(List<BranchTreeNode> nodes) {
    final List<RefInfo> refs = <RefInfo>[];
    for (final BranchTreeNode node in nodes) {
      if (node is BranchTreeLeaf) {
        refs.add(node.ref);
      } else if (node is BranchTreeFolder) {
        refs.addAll(_collectFolderLeafRefs(node.children));
      }
    }
    return refs;
  }

  /// Full paths, not display names -- `_expandedFolders` is keyed the way
  /// `buildBranchTree` reads it (see [BranchTreeFolder.folderPath]).
  Set<String> _collectFolderPaths(List<BranchTreeNode> nodes) {
    final Set<String> names = <String>{};
    for (final BranchTreeNode node in nodes) {
      if (node is BranchTreeFolder) {
        names.add(node.folderPath);
        names.addAll(_collectFolderPaths(node.children));
      }
    }
    return names;
  }

  // "Expand all" opens this folder and every nested subfolder beneath it,
  // not just this one level -- "Collapse all" only needs to close this
  // one, since a closed ancestor already hides its descendants regardless
  // of their own recorded expand state.
  void _toggleFolderExpand(BranchTreeFolder folder) {
    setState(() {
      if (_expandedFolders.contains(folder.folderPath)) {
        _expandedFolders.remove(folder.folderPath);
      } else {
        _expandedFolders
          ..add(folder.folderPath)
          ..addAll(_collectFolderPaths(folder.children));
      }
    });
  }

  // Reuses deleteBranch's existing safe-delete default (force: false,
  // i.e. plain `git branch -d`) rather than a new "is this merged" capi
  // capability: git itself refuses any branch here that isn't merged, and
  // that refusal already surfaces through the existing delete-branch-
  // recovery flow (checkoutChoices/deleteBranchChoices), the same path a
  // single unmerged branch delete goes through today. Excludes HEAD and
  // any branch checked out in a linked worktree, matching
  // _isGoneAndBulkSelectable's exclusions for the same reason -- deleting
  // either would fail loudly or move the current session's HEAD.
  void _deleteMergedInFolder(BranchTreeFolder folder) {
    final List<String> names = _collectFolderLeafRefs(folder.children)
        .where(
          (RefInfo ref) =>
              ref.kind == RefKind.localBranch &&
              !ref.isHead &&
              ref.worktreePath.isEmpty,
        )
        .map((RefInfo ref) => ref.shortName)
        .toList(growable: false);
    if (names.isEmpty) return;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .deleteBranch(names: names);
  }

  // Only offered when every leaf ref in the folder resolves to the same
  // remote (see fetchableRefsInFolder's doc comment) -- there's no "default
  // remote" to fall back to for a folder mixing refs from more than one,
  // unlike a repository-level fetch.
  void _fetchFolder(BranchTreeFolder folder) {
    final (String remote, List<String> branches)? fetchable =
        fetchableRefsInFolder(_collectFolderLeafRefs(folder.children));
    if (fetchable == null) return;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .fetchRemote(remoteName: fetchable.$1, refs: fetchable.$2);
  }

  void _openFolderContextMenu(
    BuildContext context,
    TapDownDetails details,
    BranchTreeFolder folder,
  ) {
    final (String, List<String>)? fetchable = fetchableRefsInFolder(
      _collectFolderLeafRefs(folder.children),
    );
    showGbmContextMenu(
      context,
      details.globalPosition,
      branchFolderMenuItems(
        isExpanded: folder.isExpanded,
        onToggleExpand: () => _toggleFolderExpand(folder),
        onCopyPrefix: () =>
            Clipboard.setData(ClipboardData(text: '${folder.folderPath}/')),
        onDeleteMerged: () => _deleteMergedInFolder(folder),
        onFetchFolder: fetchable == null ? null : () => _fetchFolder(folder),
      ),
    );
  }

  void _openStashContextMenu(
    BuildContext context,
    TapDownDetails details,
    StashEntry stash,
    bool conflictActive,
  ) {
    showGbmContextMenu(
      context,
      details.globalPosition,
      stashMenuItems(
        onApply: conflictActive ? null : () => _applyStash(stash),
        onPop: conflictActive ? null : () => _popStash(stash),
        onCreateBranch: conflictActive
            ? null
            : () => _createBranchFromStash(stash),
        onViewDiff: () => _viewStashDiff(stash),
        onCompare: () => _compareStash(stash),
        onDrop: () => _dropStash(stash),
      ),
    );
  }

  /// Spec page 13 requires a batch delete to be confirmed item by item
  /// (「逐項列出名稱與未 push 的 commit 數」), not fired straight off the
  /// action bar as this used to do.
  void _deleteSelected() {
    final List<String> names = _selection.items;
    if (names.isEmpty) return;
    final String repoId = Uri.encodeComponent(widget.identity.workDir);
    context.push(RoutePaths.deleteBranchesDialogFor(repoId, names: names));
  }

  /// 05-C "Checkout as new local…" / double-tap on a remote-only row --
  /// [remoteRef.fullName] is an unambiguous git ref
  /// (`refs/remotes/origin/...`), unlike its already-prefix-stripped
  /// `shortName`, so it's used as the checkout target; the stripped
  /// `shortName` becomes the new local branch's name.
  void _checkoutRemoteAsNewLocal(RefInfo remoteRef) {
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .checkout(
          target: remoteRef.fullName,
          createBranch: true,
          newBranchName: remoteRef.shortName,
        );
  }

  /// 05-C "Prune this ref" -- removes just this one remote-tracking ref
  /// locally (`git branch --delete --remotes`), independent of whether the
  /// branch is still live on the actual remote.
  void _pruneRemoteRef(RefInfo remoteRef) {
    final (String remoteName, String _) = remoteBranchParts(remoteRef.fullName);
    ref.read(repoSessionProvider(widget.identity).notifier).pruneRemote(
      remoteName,
      <String>[remoteRef.fullName],
    );
  }

  /// 05-C "Prune this ref" for a *gone* row -- [goneRef] is the local
  /// branch itself (`refs/heads/...`), so the ref to prune is its vanished
  /// upstream (`goneRef.upstream`, e.g. `refs/remotes/origin/feature`), not
  /// [goneRef.fullName]. This clears the stale remote-tracking ref and
  /// leaves the local branch untouched -- see BRANCH_STATES's note: "真正
  /// 移除 remote-tracking ref 要執行 Prune".
  void _pruneGoneUpstream(RefInfo goneRef) {
    final (String remoteName, String _) = remoteBranchParts(goneRef.upstream);
    ref.read(repoSessionProvider(widget.identity).notifier).pruneRemote(
      remoteName,
      <String>[goneRef.upstream],
    );
  }

  /// 05-C "Fetch this branch" -- a remote-only row's own ref is already an
  /// unambiguous single remote + branch (unlike 05-J's folder-wide fetch,
  /// which needs fetchableRefsInFolder()'s "single remote across every
  /// leaf" check), so this always fetches exactly the one branch.
  void _fetchRemoteRef(RefInfo remoteRef) {
    final (String remoteName, String branch) = remoteBranchParts(
      remoteRef.fullName,
    );
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .fetchRemote(remoteName: remoteName, refs: <String>[branch]);
  }

  /// 05-C "Delete on remote…" -- opens the existing dialog
  /// (`deleteRemoteBranchDialogFor`), previously unreachable from any UI.
  void _openDeleteRemoteBranchDialog(RefInfo remoteRef) {
    final (String remoteName, String _) = remoteBranchParts(remoteRef.fullName);
    context.push(
      RoutePaths.deleteRemoteBranchDialogFor(
        Uri.encodeComponent(widget.identity.workDir),
        remote: remoteName,
        branch: remoteRef.shortName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final RefSnapshot refs = ref.watch(repoRefsProvider(widget.identity));
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final ListSelection<String> selection = ref.watch(
      branchSelectionProvider(widget.identity),
    );
    // Subscribes this widget to the filter box; the `_filterQuery` getter
    // below is a plain read, so without this line typing would change the
    // provider and nothing would repaint.
    ref.watch(branchFilterQueryProvider(widget.identity));
    final GbmColors colors = context.gbmColors;
    final List<RefInfo> branches = mergeLocalAndRemoteBranches(
      refs.localBranches,
      refs.remoteBranches,
    );
    _pruneSelection(branches);

    // Compute filtered branches first, since we need it for both the enable
    // check AND the selection source of the "select all gone" button.
    // This ensures the button only selects branches that are currently
    // visible on screen, respecting the active filter.
    final List<RefInfo> filteredBranches = filterBranches(
      branches,
      _filterQuery,
    );
    final Set<String> gonePendingRefs = session.gonePendingRefs;
    final bool anyGoneSelectable = filteredBranches.any(
      (RefInfo b) => _isGoneAndBulkSelectable(b, gonePendingRefs),
    );
    // Spec page 02 stage 1: 「在區塊標題右邊顯示待清理數量」. Counted over
    // the unfiltered merged list -- how many refs are waiting to be pruned
    // is a fact about the repository, not about what the filter box happens
    // to be showing.
    final int pendingCleanup = gonePendingCount(branches, gonePendingRefs);
    // P02-14 rule 7: 「目前分支永遠置頂顯示，即使不符合條件也不會被濾掉」.
    //
    // Read as "regardless of the query", not "restructure the sidebar
    // permanently": with no query the tree is exactly what buildBranchTree
    // produced, folders and all. A filter is the only state in which the
    // current branch can vanish, and the sidebar must always be able to
    // answer "where am I".
    //
    // The pin *replaces* the tree row rather than joining it -- rendering
    // both would show `main` twice whenever it does match. `filterBranches`
    // itself is left alone: it is a pure name-matching rule and has no
    // business knowing which ref is HEAD, which is also why the hit count
    // below still counts only genuine matches.
    final bool isFiltering = _filterQuery.trim().isNotEmpty;
    final RefInfo? pinnedHead = isFiltering
        ? branches.where((RefInfo b) => b.isHead).firstOrNull
        : null;
    final List<BranchTreeNode> branchTree = buildBranchTree(
      pinnedHead == null
          ? filteredBranches
          : filteredBranches
                .where((RefInfo b) => !b.isHead)
                .toList(growable: false),
      _expandedFolders,
      // P02-14 rule 4. Read-only: the user's own set is never written to
      // here, so clearing the query restores exactly what they had.
      expandAll: isFiltering,
    );
    _firstResultName = _firstLeafName(branchTree);
    final List<RefInfo> filteredTags = filterBranches(refs.tags, _filterQuery);
    // Stashes go through the same rule as branches and tags: P02-14 is one
    // box over three sections, so a query that finds a branch by its
    // initials must find a stash the same way.
    final List<StashEntry> filteredStashes = _filterQuery.trim().isEmpty
        ? session.stashes
        : session.stashes
              .where((s) => matchesBranchFilter(s.message, _filterQuery))
              .toList(growable: false);

    // P02-14 rule 6: 「右側顯示 命中/總數」. One ratio across all three
    // sections, matching the one box that produced it -- a per-section
    // breakdown would be three numbers for a control that does not
    // distinguish them.
    //
    // `filteredBranches`, not the rendered rows: rule 7 puts the current
    // branch on screen whether or not it matched, and counting what is drawn
    // would quietly redefine 命中 as "visible".
    final int filterHits =
        filteredBranches.length + filteredTags.length + filteredStashes.length;
    final int filterTotal =
        branches.length + refs.tags.length + session.stashes.length;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfacePanel,
        border: Border(right: BorderSide(color: colors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Spec page 02 item 15: the repository button sits at the very top
          // of the sidebar, above the three per-repo sections -- the
          // repository *list* itself lives in the popover it opens, not in
          // this panel ("repository 清單已移出，改用 15 的切換彈窗").
          RepoSwitcherButton(
            currentWorkDir: widget.identity.workDir,
            controller: widget.switcherController,
          ),
          // BRANCHES section header
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GbmSpacing.space3,
              GbmSpacing.space3,
              GbmSpacing.space1,
              GbmSpacing.space1,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'BRANCHES',
                    style: TextStyle(
                      fontSize: GbmTypography.textXs,
                      fontWeight: GbmTypography.weightSemibold,
                      color: colors.textTertiary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                if (pendingCleanup > 0)
                  Padding(
                    padding: const EdgeInsets.only(right: GbmSpacing.space1),
                    child: Tooltip(
                      message:
                          'Remote branches that no longer exist upstream. '
                          'Remote → Prune remote branches removes them.',
                      child: Text(
                        '$pendingCleanup to clean up',
                        style: TextStyle(
                          fontSize: GbmTypography.textXs,
                          color: colors.warning,
                        ),
                      ),
                    ),
                  ),
                Tooltip(
                  message: 'Select all branches with a gone upstream',
                  child: IconButton(
                    icon: Icon(
                      Icons.playlist_add_check,
                      size: 16,
                      color: anyGoneSelectable
                          ? colors.textSecondary
                          : colors.textTertiary,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: anyGoneSelectable
                        ? () => _selectionController.state =
                              const ListSelection<String>().selectAll(<String>[
                                for (final RefInfo b in filteredBranches)
                                  if (_isGoneAndBulkSelectable(
                                    b,
                                    gonePendingRefs,
                                  ))
                                    b.shortName,
                              ])
                        : null,
                  ),
                ),
                Tooltip(
                  message: 'New branch…',
                  child: IconButton(
                    icon: Icon(
                      Icons.add,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    onPressed: _createBranch,
                  ),
                ),
              ],
            ),
          ),
          // Filter field -- Cmd/Ctrl+Shift+E (editFilterBranches) focuses
          // this via widget.filterFocusNode. Matches branches, tags and
          // stashes through matchesBranchFilter (see branch_filter.dart).
          Padding(
            padding: const EdgeInsets.fromLTRB(
              GbmSpacing.space3,
              0,
              GbmSpacing.space3,
              GbmSpacing.space2,
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: SizedBox(
                    height: 28,
                    // P02-14 rules 8 and 9. Placed here rather than on the
                    // panel: this is the innermost `Shortcuts` above the
                    // field, so it resolves Esc and ↓ before the app-level
                    // `DefaultTextEditingShortcuts` gets them -- and it is
                    // scoped to the field, so the tree's own Esc (MULTIKEYS'
                    // collapse) is untouched. Same focus-scope reasoning as
                    // Ctrl/Cmd+A being bound to the tree only.
                    child: CallbackShortcuts(
                      bindings: <ShortcutActivator, VoidCallback>{
                        const SingleActivator(LogicalKeyboardKey.escape):
                            _clearFilter,
                        const SingleActivator(LogicalKeyboardKey.arrowDown):
                            _enterFirstResult,
                      },
                      child: TextField(
                        controller: _filterController,
                        focusNode: widget.filterFocusNode,
                        style: TextStyle(
                          fontSize: GbmTypography.textSm,
                          color: colors.textPrimary,
                        ),
                        onChanged: (value) => _filterQuery = value,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Filter branches',
                          hintStyle: TextStyle(
                            fontSize: GbmTypography.textSm,
                            color: colors.textTertiary,
                          ),
                          prefixIcon: Icon(
                            Icons.search,
                            size: 14,
                            color: colors.textTertiary,
                          ),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 28,
                            minHeight: 28,
                          ),
                          suffixIcon: _filterQuery.isEmpty
                              ? null
                              : IconButton(
                                  icon: Icon(
                                    Icons.close,
                                    size: 14,
                                    color: colors.textTertiary,
                                  ),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 28,
                                    minHeight: 28,
                                  ),
                                  onPressed: _clearFilter,
                                ),
                          contentPadding: const EdgeInsets.symmetric(
                            vertical: GbmSpacing.space1,
                          ),
                          filled: true,
                          fillColor: colors.surfaceSunken,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: colors.borderSubtle),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: colors.borderSubtle),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                            borderSide: BorderSide(color: colors.borderFocus),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Only while filtering: "6/6" on an untouched sidebar is
                // noise, and spec describes the count as part of the
                // filter's behaviour rather than as a permanent counter.
                if (isFiltering)
                  Padding(
                    padding: const EdgeInsets.only(left: GbmSpacing.space2),
                    child: Text(
                      '$filterHits/$filterTotal',
                      style: TextStyle(
                        fontSize: GbmTypography.textXs,
                        color: colors.textTertiary,
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Selection action bar
          if (selection.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: GbmSpacing.space3,
                vertical: GbmSpacing.space1,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${selection.length} selected',
                      style: TextStyle(
                        fontSize: GbmTypography.textXs,
                        color: colors.textSecondary,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  // Default TextButton padding plus its 64px minimum width
                  // put the pair at ~150px, which does not leave the count
                  // label anything at the sidebar's 180px minimum. The
                  // buttons stay full-width targets vertically; only the
                  // horizontal padding and the minimum are given up.
                  TextButton(
                    style: _compactActionStyle,
                    onPressed: () => _selectionController.state =
                        const ListSelection<String>(),
                    child: Text(
                      'Clear',
                      style: TextStyle(
                        fontSize: GbmTypography.textXs,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  TextButton(
                    style: _compactActionStyle,
                    onPressed: _deleteSelected,
                    child: Text(
                      'Delete',
                      style: TextStyle(
                        fontSize: GbmTypography.textXs,
                        color: colors.danger,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          // Branch tree list
          Expanded(
            child: branches.isEmpty
                ? Center(
                    child: Text(
                      'No branches',
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: GbmTypography.textSm,
                      ),
                    ),
                  )
                : _BranchSelectionShortcuts(
                    focusNode: _treeFocus,
                    onSelectAll: _selectAllBranches,
                    onCollapse: _collapseSelection,
                    onExtend: _extendBranchSelection,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          // Routed through the same _buildTreeNode as any
                          // other leaf, so the pinned row keeps checkout,
                          // selection and the 05-B menu rather than becoming
                          // a second, thinner rendering of a branch.
                          if (pinnedHead != null)
                            _buildTreeNode(
                              BranchTreeLeaf(ref: pinnedHead),
                              context,
                            ),
                          _buildTreeNodes(branchTree, context),
                          // Inside the scroll column rather than replacing
                          // it, because the pinned current branch (rule 7)
                          // lives here too -- a centred label swapped in for
                          // the whole tree took the pin down with it, in
                          // exactly the state where "where am I" is hardest
                          // to answer.
                          if (isFiltering &&
                              branchTree.isEmpty &&
                              filteredTags.isEmpty &&
                              filteredStashes.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(GbmSpacing.space3),
                              child: Text(
                                'No matches',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: colors.textTertiary,
                                  fontSize: GbmTypography.textSm,
                                ),
                              ),
                            ),
                          if (filteredTags.isNotEmpty) ...<Widget>[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                GbmSpacing.space3,
                                GbmSpacing.space2,
                                GbmSpacing.space1,
                                GbmSpacing.space1,
                              ),
                              child: Text(
                                'TAGS',
                                style: TextStyle(
                                  fontSize: GbmTypography.textXs,
                                  fontWeight: GbmTypography.weightSemibold,
                                  color: colors.textTertiary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            ...filteredTags.map((tag) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: GbmSpacing.space1,
                                ),
                                child: BranchTreeItem(
                                  ref: tag,
                                  onCheckout: () => _checkoutTagDetached(tag),
                                  onPushTag: session.remotes.length == 1
                                      ? () => _pushTag(
                                          tag,
                                          session.remotes.single,
                                        )
                                      : null,
                                  onCompareRef: () => _compareTag(tag),
                                  onDeleteTag: () => _deleteTag(tag),
                                  // Sourced from isActionEnabled(), not
                                  // session.conflictActive directly -- single
                                  // source of truth for checkout availability.
                                  conflictActive: !isActionEnabled(
                                    GbmActionId.branchCheckout,
                                    session,
                                  ),
                                ),
                              );
                            }),
                          ],
                          if (filteredStashes.isNotEmpty) ...<Widget>[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                GbmSpacing.space3,
                                GbmSpacing.space2,
                                GbmSpacing.space1,
                                GbmSpacing.space1,
                              ),
                              child: Text(
                                'STASH',
                                style: TextStyle(
                                  fontSize: GbmTypography.textXs,
                                  fontWeight: GbmTypography.weightSemibold,
                                  color: colors.textTertiary,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            ...filteredStashes.map((stash) {
                              return _buildStashRow(
                                stash,
                                colors,
                                // Sourced from isActionEnabled(), not
                                // session.conflictActive directly -- same
                                // pattern as every other conflict-sensitive
                                // gate in this file. branchStashChanges is
                                // the closest existing id (stash apply/pop
                                // mutate the working tree/index the same way
                                // creating a stash would).
                                !isActionEnabled(
                                  GbmActionId.branchStashChanges,
                                  session,
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTreeNodes(
    List<BranchTreeNode> nodes,
    BuildContext context, {
    int depth = 0,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: nodes
          .map((node) => _buildTreeNode(node, context, depth: depth))
          .toList(),
    );
  }

  Widget _buildTreeNode(
    BranchTreeNode node,
    BuildContext context, {
    int depth = 0,
  }) {
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    if (node is BranchTreeLeaf) {
      final bool isRemoteOnly = node.ref.kind == RefKind.remoteBranch;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space1),
        child: BranchTreeItem(
          ref: node.ref,
          onCheckout: isRemoteOnly
              ? () => _checkoutRemoteAsNewLocal(node.ref)
              : () => checkoutBranch(ref, widget.identity, node.ref.shortName),
          selected: isRemoteOnly
              ? false
              : _selection.items.contains(node.ref.shortName),
          // None of the local-branch-only actions below apply to a
          // remote-only leaf -- there is no local branch to select for bulk
          // delete, rename, branch-from, or merge.
          // Ticking the box is exactly a Ctrl/Cmd-click, so both go through
          // the same transition rather than growing a second selection set.
          onSelectedChanged: isRemoteOnly
              ? null
              : _isBulkSelectable(node.ref)
              ? (_) => _selectionController.state = _selection.toggle(
                  node.ref.shortName,
                )
              : null,
          onSelect: isRemoteOnly || !_isBulkSelectable(node.ref)
              ? null
              : (SelectionGesture gesture) =>
                    _onBranchSelect(node.ref.shortName, gesture),
          // Spec page 13's two right-click halves. Only a row that is
          // itself inside a >1 selection gets MULTIBRANCHMENU; every other
          // row collapses the selection onto itself first, so the 05-B menu
          // that opens can never act on branches scrolled out of view.
          multiSelectMenuBuilder:
              _isInMultiSelection(node.ref, isRemoteOnly: isRemoteOnly)
              ? () => _multiBranchMenuItems(session)
              : null,
          multiSelectMenuTitle: '${_selection.length} branches selected',
          onCollapseSelectionToThis:
              isRemoteOnly || !_isBulkSelectable(node.ref)
              ? null
              : () => _selectionController.state = _selection.single(
                  node.ref.shortName,
                ),
          onRename: isRemoteOnly ? null : () => _renameBranch(node.ref),
          onDelete: isRemoteOnly || node.ref.isHead
              ? null
              : () => _deleteSingle(node.ref),
          onNewBranchFromHere: isRemoteOnly
              ? null
              : () => _createBranchFrom(node.ref),
          onMerge: isRemoteOnly || node.ref.isHead ? null : _openMergeDialog,
          onPruneRef: isRemoteOnly
              ? () => _pruneRemoteRef(node.ref)
              // Effective gone, not `isGone`: a row marked from the dry-run
              // preview is exactly the row whose upstream Prune should
              // remove, and it is the only way that menu item is reachable
              // before a real prune has happened.
              : isEffectivelyGone(node.ref, session.gonePendingRefs) &&
                    node.ref.upstream.isNotEmpty
              ? () => _pruneGoneUpstream(node.ref)
              : null,
          onDeleteOnRemote: isRemoteOnly
              ? () => _openDeleteRemoteBranchDialog(node.ref)
              : null,
          onFetchRef: isRemoteOnly ? () => _fetchRemoteRef(node.ref) : null,
          // 05-B's two previously-missing items. Neither needed a new
          // dialog: Compare reuses the same open-a-tab-with-this-ref-on-the
          // -left mechanism _compareTag/_compareStash already use, and
          // Rebase reuses the repository-level dialog, now pre-fillable via
          // its `target` query parameter.
          onCompareRef: isRemoteOnly
              ? null
              : () => _compareRef(node.ref.shortName),
          onRebaseOntoHere: isRemoteOnly || node.ref.isHead
              ? null
              : () => _rebaseOntoBranch(node.ref),
          // Sourced from isActionEnabled(), not session.conflictActive
          // directly -- single source of truth for checkout availability.
          conflictActive: !isActionEnabled(GbmActionId.branchCheckout, session),
          isGonePending: isEffectivelyGone(node.ref, session.gonePendingRefs),
        ),
      );
    } else if (node is BranchTreeFolder) {
      return _buildFolderNode(node, context, depth: depth);
    }
    return const SizedBox.shrink();
  }

  // Single-level toggle -- the chevron and clicking the folder name both
  // use this, distinct from the context menu's "Expand all" (see
  // _toggleFolderExpand's doc comment for why that one recurses).
  void _toggleFolderExpandedSingleLevel(BranchTreeFolder folder) {
    setState(() {
      if (_expandedFolders.contains(folder.folderPath)) {
        _expandedFolders.remove(folder.folderPath);
      } else {
        _expandedFolders.add(folder.folderPath);
      }
    });
  }

  /// How many folder levels still get the 12px indent. The sidebar's own
  /// minimum is 180px (GbmLayout.sidebarMinWidth) and a leaf row already
  /// spends ~93px of that on a checkbox, an icon and the actions button, so
  /// an uncapped indent runs the branch name out of room after a handful of
  /// levels -- and a branch leaf renders its *full* slash-separated name
  /// anyway, so the indent is not the only thing expressing the hierarchy.
  /// Past this depth the rows stay flush; expansion state still shows where
  /// they sit.
  static const int _kMaxIndentedDepth = 3;

  /// Shared by the selection action bar's two TextButtons -- see the comment
  /// at their call site for why the defaults do not fit a 180px sidebar.
  static final ButtonStyle _compactActionStyle = TextButton.styleFrom(
    padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
    minimumSize: Size.zero,
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  );

  Widget _buildFolderNode(
    BranchTreeFolder folder,
    BuildContext context, {
    int depth = 0,
  }) {
    final colors = context.gbmColors;
    // From the node, not re-derived from _expandedFolders: buildBranchTree
    // already decided this, and while a filter is active it decides
    // `expandAll` -- a second reading of the set here would draw a closed
    // chevron over an open folder and, worse, gate the children on the
    // stale answer.
    final bool isExpanded = folder.isExpanded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        GestureDetector(
          onSecondaryTapDown: (TapDownDetails details) =>
              _openFolderContextMenu(context, details, folder),
          child: Container(
            height: GbmSpacing.rowHeightCompact,
            padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
            child: Row(
              children: <Widget>[
                IconButton(
                  icon: Icon(
                    isExpanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  onPressed: () => _toggleFolderExpandedSingleLevel(folder),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _toggleFolderExpandedSingleLevel(folder),
                    child: Text(
                      folder.folderName,
                      style: TextStyle(
                        fontSize: GbmTypography.textSm,
                        color: colors.textSecondary,
                      ),
                      // Without these the Text soft-wraps to a second line
                      // inside a fixed-height rowHeightCompact (26px)
                      // Container. That is a *cross-axis* overflow, which
                      // RenderFlex does not report -- so it never threw, it
                      // just silently painted over the neighbouring rows.
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: EdgeInsets.only(
              left: depth < _kMaxIndentedDepth ? GbmSpacing.space3 : 0,
            ),
            child: _buildTreeNodes(folder.children, context, depth: depth + 1),
          ),
      ],
    );
  }

  Widget _buildStashRow(
    StashEntry stash,
    GbmColors colors,
    bool conflictActive,
  ) {
    final now = DateTime.now();
    final stashTime = DateTime.fromMillisecondsSinceEpoch(stash.timestamp);
    final diff = now.difference(stashTime);

    String timeStr;
    if (diff.inMinutes < 1) {
      timeStr = 'just now';
    } else if (diff.inHours < 1) {
      timeStr = '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      timeStr = '${diff.inHours}h ago';
    } else {
      timeStr = '${diff.inDays}d ago';
    }

    return GestureDetector(
      onSecondaryTapDown: (TapDownDetails details) =>
          _openStashContextMenu(context, details, stash, conflictActive),
      child: Container(
        // No fixed height, unlike a branch row -- this row shows two lines
        // (message + relative time) rather than one, and rowHeightCompact
        // (26px) is too short for both at GbmTypography's textSm/textXs
        // sizes, overflowing the Column below by several pixels. Vertical
        // padding gives it breathing room instead of pinning a height that
        // would need recalibrating by hand every time either text style
        // changes.
        padding: const EdgeInsets.symmetric(
          horizontal: GbmSpacing.space2,
          vertical: GbmSpacing.space1,
        ),
        child: Row(
          children: <Widget>[
            const SizedBox(width: GbmSpacing.space2),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    stash.message,
                    style: TextStyle(
                      fontSize: GbmTypography.textSm,
                      color: colors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    timeStr,
                    style: TextStyle(
                      fontSize: GbmTypography.textXs,
                      color: colors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keyboard half of spec page 13's `MULTIKEYS`, scoped to the branch tree.
///
/// Deliberately **not** wrapped around the whole sidebar: the filter
/// `TextField` sits above this subtree, and a `Shortcuts` closer to a
/// focused editor than `DefaultTextEditingShortcuts` would take Ctrl/Cmd+A
/// away from "select all text". Same shape and same reasoning as
/// `commit_graph_view.dart`'s `_SelectionShortcuts`, including the
/// Shortcuts/Actions-above-Focus ordering: a key event dispatches to the
/// primary focus and then walks its *ancestors*, so a `Shortcuts` nested
/// inside the focused node would never see anything.
class _BranchSelectionShortcuts extends StatelessWidget {
  const _BranchSelectionShortcuts({
    required this.focusNode,
    required this.onSelectAll,
    required this.onCollapse,
    required this.onExtend,
    required this.child,
  });

  final FocusNode focusNode;
  final VoidCallback onSelectAll;
  final VoidCallback onCollapse;
  final ValueChanged<int> onExtend;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true):
            const GbmExtendSelectionIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
            const GbmExtendSelectionIntent(1),
        // Both modifiers registered rather than branching on platform: an
        // unheld modifier simply never matches.
        const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
            const GbmSelectAllIntent(),
        const SingleActivator(LogicalKeyboardKey.keyA, control: true):
            const GbmSelectAllIntent(),
        const SingleActivator(LogicalKeyboardKey.escape): const DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          GbmExtendSelectionIntent: CallbackAction<GbmExtendSelectionIntent>(
            onInvoke: (GbmExtendSelectionIntent intent) {
              onExtend(intent.delta);
              return null;
            },
          ),
          GbmSelectAllIntent: CallbackAction<GbmSelectAllIntent>(
            onInvoke: (GbmSelectAllIntent intent) {
              onSelectAll();
              return null;
            },
          ),
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (DismissIntent intent) {
              onCollapse();
              return null;
            },
          ),
        },
        child: Focus(focusNode: focusNode, child: child),
      ),
    );
  }
}
