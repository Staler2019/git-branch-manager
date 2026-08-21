import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../actions/gbm_selection_gesture.dart';
import '../../data/models/commit_meta.dart';
import '../../data/models/graph_snapshot.dart';
import '../../data/models/list_selection.dart';
import '../../data/models/ref_snapshot.dart';
import '../../data/repositories/branch_repository.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/prompt_text_dialog.dart';
import 'commit_search.dart';
import 'widgets/commit_row.dart';
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
  ) {
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
                onCheckout: oid.isEmpty
                    ? null
                    : () => ref
                          .read(repoSessionProvider(widget.identity).notifier)
                          .checkout(target: oid, detach: true),
                onCherryPick: oid.isEmpty
                    ? null
                    : () => ref
                          .read(repoSessionProvider(widget.identity).notifier)
                          .cherryPick(<String>[oid]),
                onRevert: oid.isEmpty
                    ? null
                    : () => ref
                          .read(repoSessionProvider(widget.identity).notifier)
                          .revert(<String>[oid]),
                onCreateBranchHere: oid.isEmpty
                    ? null
                    : () => _createBranchFromCommit(
                        context,
                        ref,
                        widget.identity,
                        oid,
                      ),
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
