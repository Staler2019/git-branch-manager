import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../actions/gbm_selection_gesture.dart';
import '../../data/models/commit_meta.dart';
import '../../data/models/graph_snapshot.dart';
import '../../data/models/list_selection.dart';
import '../../data/models/ref_snapshot.dart';
import '../../data/repositories/branch_repository.dart';
import '../../data/repositories/compare_tabs_repository.dart';
import '../../data/services/file_save_picker.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/prompt_text_dialog.dart';
import 'commit_search.dart';
import '../../data/repositories/graph_columns_repository.dart';
import 'widgets/commit_row.dart';
import 'widgets/commit_row_layout.dart';
import 'widgets/graph_ref_chips.dart';

/// The Fork-style commit graph, rendered from the real packed
/// `GraphSnapshot` buffer read over FFI (`gbm_graph_snapshot_rows`/`_oids`/
/// `_parents`, see data/models/graph_snapshot.dart). The Dart analog of
/// `CommitListModel` + `GraphColumnDelegate` (src/app/models/
/// CommitListModel.cpp, GraphColumnDelegate.cpp).
///
/// A [ConsumerStatefulWidget], not stateless, because it owns a
/// [ScrollController]: author/subject metadata is fetched in batches for
/// whichever rows are actually visible (see [CommitMeta] and
/// `history_repository.dart`'s `commitMetaProvider`/`requestCommitMeta`),
/// so this needs to know the current scroll offset and viewport height to
/// compute that range -- a plain `ListView.builder` with no controller has
/// no way to ask "which rows are on screen right now".
class CommitGraphView extends ConsumerStatefulWidget {
  const CommitGraphView({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<CommitGraphView> createState() => _CommitGraphViewState();
}

class _CommitGraphViewState extends ConsumerState<CommitGraphView> {
  final ScrollController _controller = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  /// Focus owner for the commit list, so `_SelectionShortcuts`' bindings
  /// only fire while the list is what the user is actually working in.
  ///
  /// Focus is requested explicitly from [_publish] rather than relying on
  /// the rows' `InkWell`s: an InkWell is focusable for keyboard traversal
  /// but a plain tap does not move focus to it, so without this the very
  /// gesture that creates a selection would leave focus wherever it was
  /// (typically the filter field), and Shift+↑/↓, Ctrl/Cmd+A and Esc would
  /// all silently do nothing.
  final FocusNode _listFocus = FocusNode(debugLabel: 'CommitGraphView list');

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _listFocus.dispose();
    _controller
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_controller.hasClients) return;
    _requestVisibleMeta(_controller.position.viewportDimension);
  }

  /// `offset ÷ kCommitRowHeight` rather than measuring children: every row
  /// is a fixed `kCommitRowHeight` (the ListView below sets `itemExtent`),
  /// so this is exact and cheap, unlike walking rendered children.
  List<String> _visibleOids(double viewportHeight) {
    final GraphSnapshotView graph = ref.read(
      repoGraphProvider(widget.identity),
    );
    if (graph.rows.isEmpty || viewportHeight <= 0) return const <String>[];

    // Scroll position indexes the *rendered* list, which under a filter is
    // the match list rather than the whole snapshot -- so the visible range
    // is computed in list positions and then mapped back to snapshot rows.
    // Without this step, scrolling a filtered list would prefetch metadata
    // for whichever unfiltered rows happened to sit at the same offset.
    final List<int> rows = matchingRowIndices(
      query: ref.read(commitSearchQueryProvider(widget.identity)),
      graph: graph,
      metaCache: ref.read(commitMetaProvider(widget.identity)),
    );
    if (rows.isEmpty) return const <String>[];

    final double offset = _controller.hasClients ? _controller.offset : 0;
    final int lastPosition = rows.length - 1;
    final int first = (offset / kCommitRowHeight).floor().clamp(
      0,
      lastPosition,
    );
    final int last = ((offset + viewportHeight) / kCommitRowHeight)
        .ceil()
        .clamp(0, lastPosition);
    return <String>[
      for (int p = first; p <= last; p++)
        if (rows[p] < graph.oidsHex.length) graph.oidsHex[rows[p]],
    ];
  }

  /// Skips oids already cached (see `requestCommitMeta`'s own dedup), so
  /// this can be called freely on every scroll tick and every rebuild
  /// without turning a fast scroll into a `cat-file` request storm.
  void _requestVisibleMeta(double viewportHeight) {
    final List<String> oids = _visibleOids(viewportHeight);
    if (oids.isEmpty) return;
    requestCommitMeta(ref, widget.identity, oids);
  }

  Future<void> _createBranchFromCommit(
    BuildContext context,
    WidgetRef ref,
    RepoIdentity identity,
    String commitOid,
  ) async {
    final String? name = await promptText(
      context,
      title: 'New Branch from Commit',
      label: 'Branch name',
    );
    if (name == null || !mounted) return;
    ref
        .read(repoSessionProvider(identity).notifier)
        .createBranch(name: name, startPoint: commitOid);
  }

  StateController<ListSelection<String>> get _selectionController =>
      ref.read(commitSelectionProvider(widget.identity).notifier);

  /// Publishes a new selection and keeps the single-target surfaces in step
  /// with its anchor: the changed-files panel reloads for the new anchor and
  /// any file drilled into under the previous one is cleared, since it may
  /// not exist in this commit at all.
  ///
  /// Written through [commitSelectionProvider] rather than to
  /// `selectedCommitProvider`, which is now that selection's anchor read
  /// back out (see its doc comment) and no longer independently writable.
  void _publish(ListSelection<String> next) {
    _listFocus.requestFocus();
    final String? previousAnchor = _selectionController.state.anchor;
    _selectionController.state = next;
    final String? anchor = next.anchor;
    if (anchor == null || anchor == previousAnchor) return;
    ref.read(selectedCommitFilePathProvider(widget.identity).notifier).state =
        null;
    requestCommitFiles(ref, widget.identity, anchor);
  }

  /// Applies one of spec page 13's three mouse rows.
  ///
  /// [visibleOids] is the list **as rendered** -- under a filter that is the
  /// match list, not the whole snapshot. A Shift-range therefore never
  /// reaches across rows the user cannot see. Contiguity is a separate
  /// question answered against the unfiltered snapshot (see
  /// [_selectedAreContiguous]), which is why a range taken under a filter
  /// can be a perfectly good selection and still, correctly, be too gappy
  /// to cherry-pick.
  void _onRowSelect(
    String oid,
    SelectionGesture gesture,
    List<String> visibleOids,
  ) {
    final ListSelection<String> current = _selectionController.state;
    _publish(switch (gesture) {
      SelectionGesture.single => current.single(oid),
      SelectionGesture.toggle => current.toggle(oid),
      SelectionGesture.range => current.range(oid, visibleOids),
    });
  }

  /// Spec page 13's right-click rule, run before the menu is built: an
  /// already-selected row leaves the selection alone; any other row
  /// collapses to just itself first.
  void _normaliseSelectionForMenu(String oid) {
    final ListSelection<String> current = _selectionController.state;
    if (current.contains(oid)) return;
    _publish(current.single(oid));
  }

  /// `Shift + ↑ / ↓`: 以鍵盤延伸範圍 — move the selection's free end one
  /// row in [delta]'s direction, measured in the rendered list so it tracks
  /// what the user sees.
  ///
  /// The free end is the end that is **not** the anchor, mirroring what a
  /// Shift-click does: the anchor stays pinned and the other end travels.
  /// Picking "whichever end lies in the direction of travel" instead would
  /// make Shift+Up after a downward range grow it upward rather than shrink
  /// it back, which is not how any list behaves.
  void _extendSelection(int delta, List<String> visibleOids) {
    if (visibleOids.isEmpty) return;
    final ListSelection<String> current = _selectionController.state;
    final List<String> ordered = current.orderedBy(visibleOids);
    final String? anchor = current.anchor;
    if (ordered.isEmpty || anchor == null || !visibleOids.contains(anchor)) {
      _publish(current.single(visibleOids.first));
      return;
    }
    final String freeEnd = ordered.first == anchor
        ? ordered.last
        : ordered.first;
    final int from = visibleOids.indexOf(freeEnd);
    final int next = (from + delta).clamp(0, visibleOids.length - 1);
    _publish(current.range(visibleOids[next], visibleOids));
  }

  String get _repoId => Uri.encodeComponent(widget.identity.workDir);

  RepoSessionController get _session =>
      ref.read(repoSessionProvider(widget.identity).notifier);

  /// The selection in history order, newest first -- the order History
  /// itself renders and the order the menu's counted labels describe.
  List<String> _selectedNewestFirst() {
    final GraphSnapshotView graph = ref.read(
      repoGraphProvider(widget.identity),
    );
    return ref
        .read(commitSelectionProvider(widget.identity))
        .orderedBy(graph.oidsHex);
  }

  /// gbm_cherry_pick and gbm_revert both take commits **oldest first** (see
  /// gbm_capi.h: revert states it shares cherry-pick's convention), and
  /// History is newest-first. Reversing here rather than at each call site
  /// keeps the one place that has to know about it findable.
  List<String> _selectedOldestFirst() =>
      _selectedNewestFirst().reversed.toList(growable: false);

  void _copySelectedShas() {
    // One per line, per MULTIACTS' 「支援 — 每行一個 hash 複製」.
    Clipboard.setData(ClipboardData(text: _selectedNewestFirst().join('\n')));
  }

  /// COMPARES 3: 「History 內 Ctrl/Cmd 點選兩個 commit → 右鍵 Compare」.
  ///
  /// With two selected, both sides are filled directly, older on the left so
  /// the diff reads forwards in time -- the same older-left/newer-right
  /// convention `_compareStash` follows. With one, only the left is known,
  /// and the Compare tab's own ref picker chooses the right, exactly as
  /// 05-D's "Compare with…" on a tag already does.
  void _compareSelection() {
    final List<String> ordered = _selectedNewestFirst();
    if (ordered.isEmpty) return;
    final String tabId = ordered.length >= 2
        ? ref
              .read(compareTabsProvider(widget.identity).notifier)
              .open(left: ordered.last, right: ordered.first)
        : ref
              .read(compareTabsProvider(widget.identity).notifier)
              .open(left: ordered.first);
    context.go(RoutePaths.compareFor(_repoId, tabId));
  }

  /// 05-E's "Compare with working copy": the right side is the live tree,
  /// which [CompareTabSpec] models as a null right rather than a ref string
  /// (gbm_capi has a genuinely different call for it).
  void _compareWithWorkingCopy(String oid) {
    final String tabId = ref
        .read(compareTabsProvider(widget.identity).notifier)
        .open(left: oid);
    context.go(RoutePaths.compareFor(_repoId, tabId));
  }

  Future<void> _exportSelectedPatches() async {
    final String? dir = await ref.read(fileSavePickerProvider).pickDirectory();
    if (dir == null || !mounted) return;
    // Oldest first so the generated 0001-, 0002-… numbering runs forwards
    // through history, matching what `git format-patch` produces for a range.
    _session.exportPatches(_selectedOldestFirst(), dir);
  }

  @override
  Widget build(BuildContext context) {
    final GraphSnapshotView graph = ref.watch(
      repoGraphProvider(widget.identity),
    );
    final bool isRefreshing = ref.watch(
      repoIsRefreshingProvider(widget.identity),
    );
    final Map<String, CommitMeta> metaCache = ref.watch(
      commitMetaProvider(widget.identity),
    );
    final ListSelection<String> selection = ref.watch(
      commitSelectionProvider(widget.identity),
    );
    final RefSnapshot refs = ref.watch(repoRefsProvider(widget.identity));
    final String effectiveEmail = ref.watch(
      repoSessionProvider(
        widget.identity,
      ).select((state) => state.effectiveIdentity.email),
    );
    final bool conflictActive = ref.watch(
      repoSessionProvider(
        widget.identity,
      ).select((RepoSessionState state) => state.conflictActive),
    );
    final GbmColors colors = context.gbmColors;

    final String query = ref.watch(commitSearchQueryProvider(widget.identity));
    final List<int> visibleRows = matchingRowIndices(
      query: query,
      graph: graph,
      metaCache: metaCache,
    );

    if (graph.rows.isEmpty) {
      return Center(
        child: isRefreshing
            ? const CircularProgressIndicator()
            : Text(
                'No commits yet',
                style: TextStyle(color: colors.textTertiary),
              ),
      );
    }

    return Column(
      children: <Widget>[
        _CommitSearchField(
          controller: _searchController,
          focusNode: ref.watch(historySearchFocusNodeProvider(widget.identity)),
          matchCount: visibleRows.length,
          totalCount: graph.rows.length,
          onChanged: (String value) =>
              ref
                      .read(commitSearchQueryProvider(widget.identity).notifier)
                      .state =
                  value,
        ),
        Expanded(
          child: visibleRows.isEmpty
              ? Center(
                  child: Text(
                    'No commit matches "$query".',
                    style: TextStyle(
                      fontSize: GbmTypography.textSm,
                      color: colors.textTertiary,
                    ),
                  ),
                )
              : _buildList(
                  graph,
                  visibleRows,
                  query,
                  metaCache,
                  selection,
                  refs,
                  effectiveEmail,
                  conflictActive,
                ),
        ),
      ],
    );
  }

  Widget _buildList(
    GraphSnapshotView graph,
    List<int> visibleRows,
    String query,
    Map<String, CommitMeta> metaCache,
    ListSelection<String> selection,
    RefSnapshot refs,
    String effectiveEmail,
    bool conflictActive,
  ) {
    // Contiguity is judged against the **unfiltered** snapshot, not the
    // rendered list: three commits that look adjacent under a filter are
    // not a range git can replay, so cherry-pick and revert correctly stay
    // disabled for them (MULTIACTS).
    final bool contiguous = selection.isContiguousIn(graph.oidsHex);
    // The rendered order, as oids. Every selection transition is expressed
    // against this rather than against `visibleRows` (snapshot indices), so
    // a range never silently spans rows a filter is hiding.
    final List<String> visibleOids = <String>[
      for (final int index in visibleRows)
        if (index < graph.oidsHex.length) graph.oidsHex[index],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _requestVisibleMeta(constraints.maxHeight);
        });
        // One plan for the whole list, from the width this build actually
        // got. Deliberately not computed inside CommitRow: author and date
        // are trailing fixed-width columns, so a row that decided for itself
        // -- the HEAD row, say, which is also the one most likely to carry
        // ref chips -- would stop lining up with its neighbours and the list
        // would stop reading as a table.
        // Spec page 02 item 16's three settings -- which columns are on,
        // what order they sit in, and how wide each one was dragged to --
        // arrive as one value so the row, the ladder and (later) the resize
        // strips cannot each derive them differently.
        final GraphColumnLayout columnLayout = ref.watch(
          graphColumnLayoutProvider,
        );
        final CommitRowColumnPlan plan = planCommitRowColumns(
          availableWidth: constraints.maxWidth,
          laneCount: graph.laneCount,
          showGraph: query.isEmpty,
          order: columnLayout.order,
          widths: columnLayout.widths,
          // Width may still take a column the user asked to keep; it can
          // never bring back one they switched off -- planCommitRowColumns
          // starts from this set and only ever subtracts.
          hiddenByUser: columnLayout.hiddenStorageIds,
        );
        return _SelectionShortcuts(
          focusNode: _listFocus,
          onSelectAll: () =>
              _publish(_selectionController.state.selectAll(visibleOids)),
          onCollapse: () =>
              _publish(_selectionController.state.collapseToAnchor()),
          onExtend: (int delta) => _extendSelection(delta, visibleOids),
          child: ListView.builder(
            controller: _controller,
            itemExtent: kCommitRowHeight,
            itemCount: visibleRows.length,
            itemBuilder: (context, position) {
              // `position` walks the filtered result list; `index` is the
              // row's real place in the unfiltered snapshot, which is what
              // the graph edge lookups are keyed on.
              final int index = visibleRows[position];
              final GraphRow row = graph.rows[index];
              final String oid = index < graph.oidsHex.length
                  ? graph.oidsHex[index]
                  : '';
              final CommitMeta? meta = metaCache[oid];
              return CommitRow(
                row: row,
                oidHex: oid,
                graph: graph,
                rowIndex: index,
                maxLane: graph.laneCount,
                plan: plan,
                meta: meta,
                showGraph: query.isEmpty,
                selected: oid.isNotEmpty && selection.contains(oid),
                refChips: oid.isEmpty
                    ? const <RefChipData>[]
                    : refChipsForCommit(refs, oid),
                isOwnCommit:
                    meta != null &&
                    effectiveEmail.isNotEmpty &&
                    meta.author.email == effectiveEmail,
                onSelect: oid.isEmpty
                    ? null
                    : (SelectionGesture gesture) =>
                          _onRowSelect(oid, gesture, visibleOids),
                onContextMenuRequested: oid.isEmpty
                    ? null
                    : () => _normaliseSelectionForMenu(oid),
                menuSelectionCount: selection.length,
                menuSelectionIsContiguous: contiguous,
                conflictActive: conflictActive,
                menuTitle: selection.length > 1
                    ? '${selection.length} commits'
                    : null,
                onCopySha: oid.isEmpty ? null : _copySelectedShas,
                onCheckout: oid.isEmpty
                    ? null
                    : () => _session.checkout(target: oid, detach: true),
                onMerge: oid.isEmpty
                    ? null
                    // gbm_merge_branch's `target` is pushed straight into
                    // `git merge <target>` (MergeOps.cpp), so an oid is a
                    // perfectly good merge target -- no oid-to-branch-name
                    // resolution step is needed despite the parameter's name.
                    : () => _session.mergeBranch(oid, MergeMode.noFastForward),
                onCherryPick: oid.isEmpty
                    ? null
                    : () => _session.cherryPick(_selectedOldestFirst()),
                onRevert: oid.isEmpty
                    ? null
                    : () => _session.revert(_selectedOldestFirst()),
                onCreateBranchHere: oid.isEmpty
                    ? null
                    : () => _createBranchFromCommit(
                        context,
                        ref,
                        widget.identity,
                        oid,
                      ),
                onCompare: oid.isEmpty ? null : _compareSelection,
                onRebaseOntoHere: oid.isEmpty
                    ? null
                    : () => context.push(
                        RoutePaths.rebaseOntoDialogFor(_repoId, target: oid),
                      ),
                onResetBranchHere: oid.isEmpty
                    ? null
                    : () => context.push(
                        RoutePaths.resetBranchDialogFor(_repoId, target: oid),
                      ),
                onExportAsPatch: oid.isEmpty ? null : _exportSelectedPatches,
                onCompareWithWorkingCopy: oid.isEmpty
                    ? null
                    : () => _compareWithWorkingCopy(oid),
              );
            },
          ),
        );
      },
    );
  }
}

/// The in-place commit filter (spec page 02 item 3, Edit → Find in history).
///
/// Shows `matches/total` on the right the way the sidebar's branch filter
/// does (spec page 02 item 14: "右側顯示 命中/總數"), so the two filters read
/// the same. Esc clears and returns to the unfiltered list, also matching the
/// sidebar's stated behaviour.
class _CommitSearchField extends StatelessWidget {
  const _CommitSearchField({
    required this.controller,
    required this.focusNode,
    required this.matchCount,
    required this.totalCount,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final int matchCount;
  final int totalCount;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final bool filtering = controller.text.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space2,
        vertical: GbmSpacing.space1,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search, size: 14, color: colors.textTertiary),
          const SizedBox(width: GbmSpacing.space1),
          Expanded(
            child: Shortcuts(
              shortcuts: <ShortcutActivator, Intent>{
                LogicalKeySet(LogicalKeyboardKey.escape): const DismissIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  DismissIntent: CallbackAction<DismissIntent>(
                    onInvoke: (DismissIntent intent) {
                      controller.clear();
                      onChanged('');
                      return null;
                    },
                  ),
                },
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  onChanged: onChanged,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: 'Filter by message, author or hash prefix',
                    hintStyle: TextStyle(
                      fontSize: GbmTypography.textSm,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (filtering)
            Text(
              '$matchCount/$totalCount',
              style: TextStyle(
                fontFamily: GbmTypography.fontMono,
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}

/// Keyboard half of spec page 13's `MULTIKEYS`, scoped to the commit list.
///
/// **Deliberately not registered app-wide.** Ctrl/Cmd+A is also every text
/// field's "select all text", so binding it in `WorkspaceActionShortcuts`
/// would steal it from the commit summary box and the history filter. Living
/// here means it only fires while focus is inside the list -- a row's own
/// `InkWell` takes focus when tapped, which puts the focus chain through
/// this widget, so no explicit focus plumbing is needed.
///
/// [GbmSelectAllIntent] rather than Flutter's `SelectAllTextIntent` for the
/// same reason `workspace_screen.dart`'s handler offers it first: a list and
/// an editor need the same key to mean two different things, and focus is
/// what tells them apart.
class _SelectionShortcuts extends StatelessWidget {
  const _SelectionShortcuts({
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
    // Shortcuts/Actions sit **above** [focusNode], not below it. A key event
    // dispatches to the primary focus and then walks its *ancestors*, so a
    // Shortcuts nested inside the focused node would never see anything.
    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true):
            const GbmExtendSelectionIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
            const GbmExtendSelectionIntent(1),
        // Both modifiers are registered rather than branching on platform:
        // an unheld modifier simply never matches, and this keeps the list
        // working under a remote/VM session where the platform reported and
        // the keyboard actually attached disagree.
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
