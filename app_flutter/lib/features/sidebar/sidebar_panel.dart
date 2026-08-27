import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../actions/gbm_action_availability.dart';
import '../../actions/gbm_action_id.dart';
import '../../data/models/ref_snapshot.dart';
import '../../data/models/stash_entry.dart';
import '../../data/repositories/branch_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../actions/gbm_selection_gesture.dart';
import '../../data/models/list_selection.dart';
import '../../data/repositories/branch_filter_repository.dart';
import '../../data/repositories/branch_selection_repository.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_menu.dart';
import '../repo_switcher/repo_switcher_popover.dart';
import 'branch_bulk_actions.dart';
import 'branch_row_actions.dart';
import 'branch_selection_rules.dart';
import 'branch_tree_builder.dart';
import 'gone_marking.dart';
import 'widgets/branch_folder_menu_items.dart';
import 'widgets/branch_folder_row.dart';
import 'widgets/branch_selection_action_bar.dart';
import 'widgets/branch_selection_shortcuts.dart';
import 'widgets/branches_section_header.dart';
import 'widgets/sidebar_filter_field.dart';
import 'widgets/branch_tree_item.dart';
import 'widgets/multi_branch_menu_items.dart';
import 'widgets/sidebar_stash_section.dart';
import 'widgets/sidebar_tag_section.dart';
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
  /// right-clicked can both see it. Every MULTIKEYS gesture -- plain,
  /// Ctrl/Cmd and Shift clicks, Ctrl/Cmd+A, Shift+↑/↓ -- writes the same
  /// value; see the provider's doc comment.
  ListSelection<String> get _selection =>
      ref.read(branchSelectionProvider(widget.identity));

  StateController<ListSelection<String>> get _selectionController =>
      ref.read(branchSelectionProvider(widget.identity).notifier);
  final Set<String> _expandedFolders = <String>{};

  /// The branch name the expanded set was last seeded for, so mount and every
  /// later checkout run through one path -- `null -> 'main'` is a change too.
  ///
  /// A `ref.listen` on [repoRefsProvider] would cover the checkout but not the
  /// mount: it never fires for the value already present when it registers,
  /// and refs are typically already loaded by the time this panel builds. Same
  /// trap, same resolution, as [_pruneSelection]'s doc comment describes.
  String? _seededExpansionForHead;
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
    final List<String> all = _selectableNamesInRenderOrder;
    if (all.isEmpty) return;
    _treeFocus.requestFocus();
    _selectionController.state = _selection.selectAll(all);
  }

  /// `MULTIKEYS`' Esc: collapse to the anchor rather than clearing, so the
  /// row the user started from stays selected.
  void _collapseSelection() =>
      _selectionController.state = _selection.collapseToAnchor();

  /// `MULTIKEYS`' Shift+↑/↓, over the rows as currently rendered.
  void _extendBranchSelection(int delta) {
    final ListSelection<String>? next = extendedSelection(
      _selection,
      _selectableNamesInRenderOrder,
      delta,
    );
    if (next == null) return;
    _selectionController.state = next;
  }

  /// Set while a prune is scheduled but has not run yet, so a burst of
  /// rebuilds between the frame and its callback schedules exactly one.
  bool _prunePending = false;

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
    if (prunedSelection(_selection, names) == null) return;

    _prunePending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _prunePending = false;
      if (!mounted) return;
      final ListSelection<String>? next = prunedSelection(
        _selection,
        liveBranchNames(ref.read(repoRefsProvider(widget.identity))),
      );
      if (next == null) return;
      _selectionController.state = next;
    });
  }

  /// Ctrl/Cmd-click and Shift-click on a branch row. A plain click is
  /// deliberately not routed here -- see [BranchTreeItem.onSelect].
  ///
  /// A Shift range is measured over [_selectableNamesInRenderOrder] -- the
  /// rows in the order they are actually painted -- so the range never
  /// quietly picks up a branch the user cannot see or act on.
  void _onBranchSelect(String name, SelectionGesture gesture) {
    // Focus first: a row's InkWell is focusable for traversal but a tap does
    // not request focus, and without focus inside the tree the keyboard half
    // of MULTIKEYS (Shift+↑/↓, Ctrl/Cmd+A, Esc) never reaches
    // [_BranchSelectionShortcuts].
    _treeFocus.requestFocus();
    final List<String> all = _selectableNamesInRenderOrder;
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
  /// Deliberately not [_selectableNamesInRenderOrder]`.first`. Both are now
  /// in paint order, but that list drops the rows a *selection* cannot use
  /// (HEAD, remote-only), while ↓ should land on whatever row sits directly
  /// under the filter box regardless of whether it can be bulk-selected.
  String? _firstResultName;

  /// The selectable rows **in the order they are painted**, written during
  /// `build` from the tree for the same reason [_firstResultName] is: the
  /// tree sorts folders before leaves and each group alphabetically, so
  /// rendered order is the tree's and rebuilding it inside a key handler
  /// would be a second copy of that ordering.
  ///
  /// This used to be derived on demand from the *ref* list, which is a
  /// different order entirely -- git's. Every Shift range and every
  /// Shift+arrow step was therefore measured over rows that are not the ones
  /// on screen: with branches alpha, beta, delta, gamma the sidebar paints
  /// them alphabetically, so Shift-clicking alpha then gamma has to take
  /// `delta` with it, and the ref-ordered list silently left it out.
  List<String> _selectableNamesInRenderOrder = const <String>[];

  /// Remote branches indexed by branch name, rebuilt at the top of every
  /// [build] from the same [RefSnapshot] the rows are built from.
  ///
  /// A field rather than a parameter only because `_buildBranchNode` is
  /// reached through the tree walk; it is written once per build and read
  /// within that build, exactly like [_selectableNamesInRenderOrder] above.
  RemoteBranchIndex _remoteIndex = RemoteBranchIndex.from(const <RefInfo>[]);

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

  /// Built per call, never stored -- same reasoning as [_bulk].
  BranchRowActions get _rowActions =>
      BranchRowActions(ref: ref, identity: widget.identity);

  /// Built per call, never stored: `BranchBulkActions` is a pure function of
  /// the selection, and a stored copy would be a second source of truth for
  /// it.
  BranchBulkActions get _bulk => BranchBulkActions(
    ref: ref,
    identity: widget.identity,
    selectedNames: _selection.items,
  );

  List<GbmMenuItem> _multiBranchMenuItems(RepoSessionState session) {
    final List<String> names = _selection.items;
    final BranchBulkActions bulk = _bulk;
    return multiBranchMenuItems(
      count: names.length,
      conflictActive: !isActionEnabled(GbmActionId.branchDeleteBranch, session),
      onCopyNames: () =>
          Clipboard.setData(ClipboardData(text: names.join('\n'))),
      onFetch: bulk.fetch,
      onPush: bulk.push,
      fetchBlockedReason: bulk.fetchBlockedReason(),
      pushBlockedReason: bulk.pushBlockedReason(),
      onCompare: names.length == 2 ? () => bulk.compare(context) : null,
      onDelete: () => _rowActions.deleteSelected(context, names),
    );
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
          ..addAll(collectFolderPaths(folder.children));
      }
    });
  }

  void _openFolderContextMenu(
    BuildContext context,
    TapDownDetails details,
    BranchTreeFolder folder,
  ) {
    final (String, List<String>)? fetchable = fetchableRefsInFolder(
      collectFolderLeafRefs(folder.children),
    );
    final BranchRowActions actions = _rowActions;
    showGbmContextMenu(
      context,
      details.globalPosition,
      branchFolderMenuItems(
        isExpanded: folder.isExpanded,
        // Expand/collapse stays here: it is this panel's setState.
        onToggleExpand: () => _toggleFolderExpand(folder),
        onCopyPrefix: () =>
            Clipboard.setData(ClipboardData(text: '${folder.folderPath}/')),
        onDeleteMerged: () => actions.deleteMergedInFolder(folder),
        onFetchFolder: fetchable == null
            ? null
            : () => actions.fetchFolder(folder),
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
    // Built once per build and read by every row below: gone marking, the
    // bulk-select set and the pending count all have to agree about which
    // remote ref a local branch corresponds to. Resolving per row instead
    // would be quadratic (measured: 14ms per pass at 500+500 branches).
    // It is a local, never part of any watched provider state.
    _remoteIndex = RemoteBranchIndex.from(refs.remoteBranches);
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
      (RefInfo b) => isGoneAndBulkSelectable(
        b,
        gonePendingRefs,
        remoteCounterpart: _remoteIndex.counterpartOf(b),
      ),
    );
    // Spec page 02 stage 1: 「在區塊標題右邊顯示待清理數量」. Counted over
    // the unfiltered merged list -- how many refs are waiting to be pruned
    // is a fact about the repository, not about what the filter box happens
    // to be showing.
    final int pendingCleanup = gonePendingCount(
      branches,
      gonePendingRefs,
      _remoteIndex.counterpartOf,
    );
    // 「Where am I」, with no sort pin to answer it: open the folders on the
    // way to the current branch, so its row is already on screen.
    //
    // Deliberately **not** deferred to a post-frame callback and deliberately
    // no `setState`: [_expandedFolders] is this State's own field rather than
    // a provider, so writing it here reaches none of the guards
    // [_pruneSelection] has to respect, and `buildBranchTree` a few lines
    // below reads it in this same build -- so the first frame is already
    // expanded, with no flash of a collapsed tree.
    //
    // Only ever `addAll`: 「不自動收合」 is what makes a checkout leave the
    // folder the user was in open, and a folder they collapsed themselves
    // stays collapsed until HEAD actually moves.
    final String headBranch = refs.head.branchName;
    if (headBranch != _seededExpansionForHead) {
      _seededExpansionForHead = headBranch;
      _expandedFolders.addAll(ancestorFolderPaths(headBranch));
    }

    // A query filters the current branch exactly like any other row.
    //
    // P02-14 rule 7 (「目前分支永遠置頂顯示，即使不符合條件也不會被濾掉」) and
    // BRANCH_STATES' 「不受 filter 影響」 both said otherwise, and both are a
    // **user-ratified deviation** now -- see docs/ledger.md. The panel used to
    // add HEAD back into the builder's input when the query dropped it, which
    // also resurrected its ancestor folders (a row cannot sit inside a folder
    // that is not drawn), so a filtered sidebar showed a folder with no
    // matching child in it purely to carry one exempt row.
    //
    // 「Where am I」 is answered by the expanded-to-HEAD default instead
    // (`ancestorFolderPaths` below), which a query overrides anyway: rule 4's
    // `expandAll` opens every folder while one is typed.
    final bool isFiltering = _filterQuery.trim().isNotEmpty;
    final List<BranchTreeNode> branchTree = buildBranchTree(
      filteredBranches,
      _expandedFolders,
      // P02-14 rule 4. Read-only: the user's own set is never written to
      // here, so clearing the query restores exactly what they had.
      expandAll: isFiltering,
    );
    _firstResultName = firstLeafName(branchTree);
    _selectableNamesInRenderOrder = selectableLeafNames(branchTree);
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
    // `filteredBranches`, not the rendered rows: the two agree today, but
    // 命中 means "matched the query", and reading it off what is drawn would
    // make the number a property of the tree rather than of the filter.
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
          BranchesSectionHeader(
            pendingCleanup: pendingCleanup,
            canSelectAllGone: anyGoneSelectable,
            onSelectAllGone: () => _selectionController.state =
                const ListSelection<String>().selectAll(<String>[
                  for (final RefInfo b in filteredBranches)
                    if (isGoneAndBulkSelectable(
                      b,
                      gonePendingRefs,
                      remoteCounterpart: _remoteIndex.counterpartOf(b),
                    ))
                      b.shortName,
                ]),
            onNewBranch: () => _rowActions.createBranch(context),
          ),
          SidebarFilterField(
            controller: _filterController,
            focusNode: widget.filterFocusNode,
            isFiltering: isFiltering,
            hasQuery: _filterQuery.isNotEmpty,
            hits: filterHits,
            total: filterTotal,
            onChanged: (String value) => _filterQuery = value,
            onClear: _clearFilter,
            onEnterFirstResult: _enterFirstResult,
          ),
          // Selection action bar
          if (selection.isNotEmpty)
            BranchSelectionActionBar(
              count: selection.length,
              onClear: () =>
                  _selectionController.state = const ListSelection<String>(),
              onDelete: () =>
                  _rowActions.deleteSelected(context, selection.items),
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
                : BranchSelectionShortcuts(
                    focusNode: _treeFocus,
                    onSelectAll: _selectAllBranches,
                    onCollapse: _collapseSelection,
                    onExtend: _extendBranchSelection,
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          // The current branch is one of these, with no
                          // special row of its own, so it goes through the
                          // same _buildTreeNode as any other leaf and keeps
                          // checkout, selection and the 05-B menu.
                          _buildTreeNodes(branchTree, context),
                          // Inside the scroll column rather than replacing
                          // it. `branchTree` and `filteredBranches` are both
                          // empty together now that rule 7's exemption is
                          // gone, so the two keyings agree again -- but this
                          // stays on the *matches*, because 「no matches」 is
                          // a fact about the query and reading it off the
                          // tree would make it a fact about the rendering.
                          // A centred label swapped in for the whole tree is
                          // what once took the exempt row down with it.
                          if (isFiltering &&
                              filteredBranches.isEmpty &&
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
                          SidebarTagSection(
                            identity: widget.identity,
                            tags: filteredTags,
                          ),
                          SidebarStashSection(
                            identity: widget.identity,
                            stashes: filteredStashes,
                          ),
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
      final BranchRowActions actions = _rowActions;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space1),
        child: BranchTreeItem(
          ref: node.ref,
          // P02 item 12: 「名稱中的斜線自動摺成資料夾」 -- the folder row above
          // prints the prefix, so the leaf prints only its last segment.
          //
          // Except once the indent stops. Past [_kMaxIndentedDepth] rows are
          // painted flush, and the full name is what that cap has always
          // leaned on to keep the hierarchy readable -- see its doc comment.
          // Shortening those rows too would leave them with neither indent
          // nor prefix.
          displayName: depth > _kMaxIndentedDepth
              ? node.ref.shortName
              : node.displayLabel,
          onCheckout: isRemoteOnly
              ? () => actions.checkoutRemoteAsNewLocal(node.ref)
              : () => checkoutBranch(ref, widget.identity, node.ref.shortName),
          selected: isRemoteOnly
              ? false
              : _selection.items.contains(node.ref.shortName),
          // None of the local-branch-only actions below apply to a
          // remote-only leaf -- there is no local branch to select for bulk
          // delete, rename, branch-from, or merge.
          onSelect: isRemoteOnly || !isBulkSelectable(node.ref)
              ? null
              : (SelectionGesture gesture) =>
                    _onBranchSelect(node.ref.shortName, gesture),
          // Spec page 13's two right-click halves. Only a row that is
          // itself inside a >1 selection gets MULTIBRANCHMENU; every other
          // row collapses the selection onto itself first, so the 05-B menu
          // that opens can never act on branches scrolled out of view.
          multiSelectMenuBuilder:
              isInMultiSelection(
                node.ref,
                isRemoteOnly: isRemoteOnly,
                selection: _selection,
              )
              ? () => _multiBranchMenuItems(session)
              : null,
          multiSelectMenuTitle: '${_selection.length} branches selected',
          onCollapseSelectionToThis: isRemoteOnly || !isBulkSelectable(node.ref)
              ? null
              : () => _selectionController.state = _selection.single(
                  node.ref.shortName,
                ),
          onRename: isRemoteOnly
              ? null
              : () => actions.renameBranch(context, node.ref),
          onDelete: isRemoteOnly || node.ref.isHead
              ? null
              : () => actions.deleteSingle(node.ref),
          onNewBranchFromHere: isRemoteOnly
              ? null
              : () => actions.createBranchFrom(context, node.ref),
          onMerge: isRemoteOnly || node.ref.isHead
              ? null
              : () => actions.openMergeDialog(context),
          onPruneRef: isRemoteOnly
              ? () => actions.pruneRemoteRef(node.ref)
              // Effective gone, not `isGone`: a row marked from the dry-run
              // preview is exactly the row whose upstream Prune should
              // remove, and it is the only way that menu item is reachable
              // before a real prune has happened.
              : isEffectivelyGone(
                      node.ref,
                      session.gonePendingRefs,
                      remoteCounterpart: _remoteIndex.counterpartOf(node.ref),
                    ) &&
                    node.ref.upstream.isNotEmpty
              ? () => actions.pruneGoneUpstream(node.ref)
              : null,
          onDeleteOnRemote: isRemoteOnly
              ? () => actions.openDeleteRemoteBranchDialog(context, node.ref)
              : null,
          onFetchRef: isRemoteOnly
              ? () => actions.fetchRemoteRef(node.ref)
              : null,
          // 05-B's two previously-missing items. Neither needed a new
          // dialog: Compare reuses the same open-a-tab-with-this-ref-on-the
          // -left mechanism _compareTag/_compareStash already use, and
          // Rebase reuses the repository-level dialog, now pre-fillable via
          // its `target` query parameter.
          onCompareRef: isRemoteOnly
              ? null
              : () => actions.compareRef(context, node.ref.shortName),
          onRebaseOntoHere: isRemoteOnly || node.ref.isHead
              ? null
              : () => actions.rebaseOnto(context, node.ref),
          // Sourced from isActionEnabled(), not session.conflictActive
          // directly -- single source of truth for checkout availability.
          conflictActive: !isActionEnabled(GbmActionId.branchCheckout, session),
          isGonePending: isEffectivelyGone(
            node.ref,
            session.gonePendingRefs,
            remoteCounterpart: _remoteIndex.counterpartOf(node.ref),
          ),
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
  /// minimum is 180px (GbmLayout.sidebarMinWidth) and a leaf row spends a
  /// fixed part of that on its icon, its gap, the tracking badge and the
  /// trailing actions slot before the name gets anything, so an uncapped
  /// indent runs the name out of room after a handful of levels. Past this
  /// depth the rows stay flush.
  ///
  /// The old wording justified the cap with "a branch leaf renders its
  /// *full* slash-separated name anyway, so the indent is not the only thing
  /// expressing the hierarchy". That stopped being true when leaves started
  /// printing only their last segment (P02 item 12), which is why
  /// [_buildTreeNode] hands the full name back to any row deeper than this:
  /// a row with neither indent nor prefix cannot be placed at all.
  static const int _kMaxIndentedDepth = 3;

  Widget _buildFolderNode(
    BranchTreeFolder folder,
    BuildContext context, {
    int depth = 0,
  }) {
    // From the node, not re-derived from _expandedFolders: buildBranchTree
    // already decided this, and while a filter is active it decides
    // `expandAll` -- a second reading of the set here would draw a closed
    // chevron over an open folder and, worse, gate the children on the
    // stale answer.
    final bool isExpanded = folder.isExpanded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        BranchFolderRow(
          folderName: folder.folderName,
          isExpanded: isExpanded,
          onToggle: () => _toggleFolderExpandedSingleLevel(folder),
          onSecondaryTapDown: (TapDownDetails details) =>
              _openFolderContextMenu(context, details, folder),
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
}
