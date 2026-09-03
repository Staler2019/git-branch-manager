import 'package:flutter/gestures.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../actions/gbm_selection_gesture.dart';
import '../../data/models/commit_meta.dart';
import '../../data/models/graph_column.dart';
import '../../data/models/graph_snapshot.dart';
import '../../data/models/list_selection.dart';
import '../../data/models/ref_snapshot.dart';
import '../../data/models/working_copy_status.dart';
import '../../data/repositories/branch_repository.dart';
import '../../data/repositories/compare_tabs_repository.dart';
import '../../data/services/file_save_picker.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../data/repositories/working_copy_repository.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_icon_button.dart';
import '../../widgets/lucide_icon.dart';
import 'commit_list_render.dart';
import 'commit_search.dart';
import '../../data/repositories/graph_columns_repository.dart';
import 'widgets/commit_row.dart';
import 'widgets/working_copy_row.dart';
import 'widgets/graph_columns_selector.dart';
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

  /// The width the column being dragged had when the gesture started, plus
  /// the pointer's travel since. Accumulated rather than applied frame by
  /// frame because [GraphColumnWidthNotifier.setWidth] clamps: adding each
  /// delta to the *clamped* value makes a drag past `minWidth` and back
  /// lag behind the pointer by however far it overshot.
  double _resizeStartWidth = 0;
  double _resizeTravel = 0;

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
  ///
  /// The file-count request is gated on the Changed files column being
  /// visible, and the gate is read *here* rather than latched at mount:
  /// switching the column on rebuilds this widget, which re-runs the
  /// post-frame callback below, so the rows already on screen are counted
  /// immediately instead of staying blank until the next scroll.
  void _requestVisibleMeta(double viewportHeight) {
    final List<String> oids = _visibleOids(viewportHeight);
    if (oids.isEmpty) return;
    requestCommitMeta(ref, widget.identity, oids);
    final bool wantsFileCounts = isGraphColumnVisible(
      ref.read(graphColumnVisibilityProvider),
      GbmGraphColumnId.changedFiles.storageId,
    );
    if (wantsFileCounts) {
      requestCommitFileCounts(ref, widget.identity, oids);
    }
  }

  /// 05-E's "New branch from here…".
  ///
  /// Used to be `promptText`'s single-field box with the commit oid passed
  /// straight to `createBranch(startPoint:)` -- silent, the same defect as
  /// the sidebar's 05-B ([SPEC-cell-names-capability] adjacent: a capability
  /// existing is not evidence the UI shows it). The real dialog draws the
  /// oid as a picked row under COMMIT and lets it be changed before the
  /// branch is created.
  void _createBranchFromCommit(BuildContext context, String commitOid) =>
      context.push(
        RoutePaths.newBranchDialogFor(_repoId, startPoint: commitOid),
      );

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
    // The uncommitted row shares this selection but is not a commit, so there
    // are no changed files to ask the core for -- the request would be
    // `git diff-tree` against an oid that does not exist.
    if (anchor == kWorkingCopySelectionId) return;
    requestCommitFiles(ref, widget.identity, anchor);
  }

  /// Selects History's uncommitted-changes row.
  ///
  /// Replaces the whole selection rather than adding to it: it is not a commit,
  /// so it can never take part in a range or a multi-commit action, and leaving
  /// commits selected beside it would put the detail panel in two states at
  /// once.
  void _selectWorkingCopyRow() {
    _publish(
      const ListSelection<String>(
        items: <String>[kWorkingCopySelectionId],
        anchor: kWorkingCopySelectionId,
      ),
    );
  }

  /// Plain ↑/↓: moves the single selection one row in painted order.
  ///
  /// The uncommitted row is index 0 of that order whenever it exists, which
  /// is the whole of 「first commit + ↑ reaches it, ↓ comes back」. It is not
  /// in [visibleOids] -- it is not a commit and never enters the ListView --
  /// so the navigable order is assembled here rather than anywhere the graph
  /// row indices are keyed on.
  ///
  /// Shift+↑/↓ deliberately does **not** get the same treatment: a range
  /// spanning the uncommitted row is not a range git could replay, and
  /// [_extendSelection] already restarts from the first commit when the
  /// anchor is not a visible oid.
  void _moveSelection(
    int delta,
    List<String> visibleOids,
    bool hasWorkingCopyRow,
  ) {
    final List<String> navigable = hasWorkingCopyRow
        ? <String>[kWorkingCopySelectionId, ...visibleOids]
        : visibleOids;
    if (navigable.isEmpty) return;
    final String? anchor = _selectionController.state.anchor;
    final int from = anchor == null ? -1 : navigable.indexOf(anchor);
    final int next = from < 0
        ? 0
        : (from + delta).clamp(0, navigable.length - 1);
    _publish(_selectionController.state.single(navigable[next]));
    _revealListIndex(next - (hasWorkingCopyRow ? 1 : 0));
  }

  /// Scrolls the ListView just far enough that row [index] is fully visible,
  /// and not at all when it already is. A negative index is the uncommitted
  /// row, which is pinned above the scrollable and therefore always visible.
  ///
  /// Arithmetic rather than `Scrollable.ensureVisible`: every row is exactly
  /// `kCommitRowHeight` tall (the list sets `itemExtent`), and the target row
  /// is usually not built yet -- which is precisely when ensureVisible has no
  /// context to work from.
  void _revealListIndex(int index) {
    if (index < 0 || !_controller.hasClients) return;
    final ScrollPosition position = _controller.position;
    final double top = index * kCommitRowHeight;
    final double bottom = top + kCommitRowHeight;
    if (top < position.pixels) {
      _controller.jumpTo(math.max(position.minScrollExtent, top));
    } else if (bottom > position.pixels + position.viewportDimension) {
      _controller.jumpTo(
        math.min(position.maxScrollExtent, bottom - position.viewportDimension),
      );
    }
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
    // Through the narrow providers, not the whole session -- an unfiltered
    // watch rebuilds the list on every publish, including the commit-metadata
    // replies the list itself asks for while scrolling
    // ([FLU-watch-a-record-not-the-state]).
    final int pendingChangeCount = ref.watch(
      repoWorkingCopyStatusProvider(
        widget.identity,
      ).select((WorkingCopyStatus status) => status.pendingChangeCount),
    );
    final CommitListRender render = CommitListRender.from(
      graph: graph,
      visibleRows: visibleRows,
      query: query,
      metaCache: metaCache,
      selection: selection,
      refs: refs,
      effectiveEmail: effectiveEmail,
      conflictActive: conflictActive,
      pendingChangeCount: pendingChangeCount,
      workingCopyRowSelected: ref.watch(
        workingCopyRowSelectedProvider(widget.identity),
      ),
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

    // The search field is a non-flex child and `RenderFlex` lays those out
    // first, so left to its own intrinsic height it overflows the moment the
    // pane is shorter than it -- `Expanded` is handed zero and cannot rescue
    // anything. That is the vertical twin of the narrow-window round's rule,
    // and it is what threw `A RenderFlex overflowed by 2.3 pixels on the
    // bottom` on a real run.
    //
    // Clamping here rather than raising `splitterMainFiles.minExtent`: that
    // splitter's 140px minimum is spec'd (`main.files`, min 140px) and
    // already protects the filling pane, so the heights that reach this code
    // come from the *window* or from a transient first-frame constraint --
    // neither of which a splitter minimum can bound.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double searchHeight = math.min(
          kHistorySearchFieldHeight,
          constraints.maxHeight,
        );
        return Column(
          children: <Widget>[
            SizedBox(
              height: searchHeight,
              // Below its natural height the field's own row is squeezed;
              // clipping keeps that silent instead of painting outside the
              // pane. It is only reachable in the degenerate sizes above.
              child: ClipRect(
                child: _CommitSearchField(
                  controller: _searchController,
                  focusNode: ref.watch(
                    historySearchFocusNodeProvider(widget.identity),
                  ),
                  matchCount: visibleRows.length,
                  totalCount: graph.rows.length,
                  onChanged: (String value) =>
                      ref
                              .read(
                                commitSearchQueryProvider(
                                  widget.identity,
                                ).notifier,
                              )
                              .state =
                          value,
                ),
              ),
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
                  : _buildList(render),
            ),
          ],
        );
      },
    );
  }

  Widget _buildList(CommitListRender render) {
    final GraphSnapshotView graph = render.graph;
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
          showGraph: render.query.isEmpty,
          order: columnLayout.order,
          widths: columnLayout.widths,
          // Width may still take a column the user asked to keep; it can
          // never bring back one they switched off -- planCommitRowColumns
          // starts from this set and only ever subtracts.
          hiddenByUser: columnLayout.hiddenStorageIds,
        );
        return _SelectionShortcuts(
          focusNode: _listFocus,
          onSelectAll: () => _publish(
            _selectionController.state.selectAll(render.visibleOids),
          ),
          onCollapse: () =>
              _publish(_selectionController.state.collapseToAnchor()),
          onExtend: (int delta) => _extendSelection(delta, render.visibleOids),
          onMove: (int delta) => _moveSelection(
            delta,
            render.visibleOids,
            render.showWorkingCopyRow,
          ),
          child: Stack(
            children: <Widget>[
              Column(
                children: <Widget>[
                  // Pinned above the list, never inside it -- see
                  // HistoryWorkingCopyRow's doc for why the ListView must not
                  // grow a row. Absent entirely when the working copy is clean.
                  if (render.showWorkingCopyRow)
                    HistoryWorkingCopyRow(
                      pendingChangeCount: render.pendingChangeCount,
                      selected: render.workingCopyRowSelected,
                      connectsDown: render.connectsToHead,
                      onTap: _selectWorkingCopyRow,
                    ),
                  Expanded(child: _buildRows(render, plan)),
                ],
              ),
              // Spec page 02 item 16's "欄寬各自可拖曳並記憶", reached without
              // a header row -- the mockup has none. See
              // kColumnResizeHandleWidth for why an invisible strip and not
              // a visible grip.
              for (final ColumnResizeHandle handle in resizeHandlesFor(plan))
                _ColumnResizeStrip(
                  key: ValueKey<String>(
                    'graphColumnResize.${handle.id.storageId}',
                  ),
                  handle: handle,
                  onDragStart: () {
                    // The width on screen, not the width in storage. For
                    // every column but Graph they are the same; Graph's
                    // stored value is a cap, so starting from it would mean
                    // a leftward drag moved nothing until the cursor caught
                    // up with the cap. See `renderedWidthOf`.
                    _resizeStartWidth =
                        plan.renderedWidthOf(handle.id) ??
                        columnLayout.widthOf(handle.id);
                    _resizeTravel = 0;
                  },
                  onDragUpdate: (double dx) {
                    _resizeTravel += dx;
                    ref
                        .read(graphColumnWidthProvider.notifier)
                        .setWidth(
                          handle.id,
                          _resizeStartWidth + _resizeTravel * handle.dragSign,
                        );
                  },
                  onDragEnd: () => ref
                      .read(graphColumnWidthProvider.notifier)
                      .commitWidths(),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRows(CommitListRender render, CommitRowColumnPlan plan) {
    final GraphSnapshotView graph = render.graph;
    // Watched here rather than gathered into CommitListRender: the counts are
    // conditional on the column being on, and that is a function of `plan`,
    // which is a function of this build's width -- so it cannot be settled
    // where the rest of the model is. A user who never switches the column on
    // never subscribes, and the list does not rebuild for a reply it would
    // not draw.
    final Map<String, int> fileCounts =
        plan.shows(GbmGraphColumnId.changedFiles)
        ? ref.watch(commitFileCountProvider(widget.identity))
        : const <String, int>{};

    return ListView.builder(
      controller: _controller,
      itemExtent: kCommitRowHeight,
      itemCount: render.visibleRows.length,
      itemBuilder: (context, position) {
        // `position` walks the filtered result list; `index` is the
        // row's real place in the unfiltered snapshot, which is what
        // the graph edge lookups are keyed on.
        final int index = render.visibleRows[position];
        final GraphRow row = graph.rows[index];
        final String oid = index < graph.oidsHex.length
            ? graph.oidsHex[index]
            : '';
        final CommitMeta? meta = render.metaCache[oid];
        return CommitRow(
          row: row,
          oidHex: oid,
          graph: graph,
          rowIndex: index,
          // `position`, not `index`: the join is to whatever the list paints
          // first, which under a filter is not snapshot row 0.
          connectsUpToUncommitted: render.connectsToHead && position == 0,
          maxLane: graph.laneCount,
          plan: plan,
          meta: meta,
          fileCount: fileCounts[oid],
          showGraph: render.query.isEmpty,
          selected: oid.isNotEmpty && render.selection.contains(oid),
          refChips: oid.isEmpty
              ? const <RefChipData>[]
              : refChipsForCommit(render.refs, oid),
          isOwnCommit:
              meta != null &&
              render.effectiveEmail.isNotEmpty &&
              meta.author.email == render.effectiveEmail,
          onSelect: oid.isEmpty
              ? null
              : (SelectionGesture gesture) =>
                    _onRowSelect(oid, gesture, render.visibleOids),
          onContextMenuRequested: oid.isEmpty
              ? null
              : () => _normaliseSelectionForMenu(oid),
          menuSelectionCount: render.selection.length,
          menuSelectionIsContiguous: render.contiguous,
          conflictActive: render.conflictActive,
          menuTitle: render.selection.length > 1
              ? '${render.selection.length} commits'
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
              : () => _createBranchFromCommit(context, oid),
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
    );
  }
}

/// One column boundary's invisible grab strip, laid over the commit list.
///
/// The strip has to be invisible in behaviour as well as in paint: it lies
/// over live commit rows, and a click on it must select the row underneath
/// exactly as a click two pixels to the left would. What makes that work is
/// **`MouseRegion(opaque: false)`**, and the reason is narrower than it
/// looks -- `RenderMouseRegion.hitTest` is `super.hitTest(...) && _opaque`,
/// so a non-opaque region records its subtree's hit-test entries and *still*
/// returns false, letting the enclosing [Stack] carry on to the [ListView]
/// behind it. Both the strip's recognizer and the row's therefore end up in
/// the same gesture arena, and the arena picks by gesture kind: a horizontal
/// drag has no competitor here, a tap has no recognizer on this side at all.
/// The same non-opacity is what keeps hover reaching the row, so its
/// highlight does not go dead in an 8px band.
///
/// [HitTestBehavior.translucent] on the [GestureDetector] says the same
/// thing one layer down and is the honest value for a detector that must
/// never consume a tap -- but it is **not** what carries the behaviour
/// today. Measured, not assumed: with the [MouseRegion] in place, flipping
/// this to `opaque` changes nothing, while flipping the region to
/// `opaque: true` blocks the tap outright. `history_column_resize_test.dart`
/// asserts the click-through directly, because none of this is visible in
/// the widget tree -- a strip that swallows taps looks identical.
class _ColumnResizeStrip extends StatelessWidget {
  const _ColumnResizeStrip({
    super.key,
    required this.handle,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final ColumnResizeHandle handle;
  final VoidCallback onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  Widget build(BuildContext context) {
    // The strip straddles the boundary rather than sitting beside it.
    final double edge = handle.offset - kColumnResizeHandleWidth / 2;
    return Positioned(
      top: 0,
      bottom: 0,
      left: handle.fromRight ? null : edge,
      right: handle.fromRight ? edge : null,
      width: kColumnResizeHandleWidth,
      child: MouseRegion(
        opaque: false,
        cursor: SystemMouseCursors.resizeColumn,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          // The column has to sit under the pointer, not `kTouchSlop`
          // behind it. `DragStartBehavior.start` -- GestureDetector's
          // default -- takes the position at which the recognizer won the
          // arena as the drag origin, so the first 20px of every grab are
          // silently discarded and the boundary trails the cursor for the
          // rest of the gesture. `.down` reports from where the pointer
          // actually went down.
          dragStartBehavior: DragStartBehavior.down,
          onHorizontalDragStart: (_) => onDragStart(),
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              onDragUpdate(d.delta.dx),
          onHorizontalDragEnd: (_) => onDragEnd(),
        ),
      ),
    );
  }
}

/// The height of History's filter row.
///
/// Spec's own compact row (`--row-h-compact:26px`), not a number invented
/// here. Before this was pinned, the row took whatever
/// `TextField(isDense: true)` came to -- **37px** under the test font, which
/// was both 11px of vertical space spent on a control nobody reads and the
/// exact threshold below which the History pane overflowed. A predictable
/// height fixes the density and the assertion together.
const double kHistorySearchFieldHeight = GbmSpacing.rowHeightCompact;

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
      key: const ValueKey<String>('history-search-field'),
      height: kHistorySearchFieldHeight,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
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
                    // Zero, not the dense default: `isDense` still reserves
                    // 8px top and bottom, which is what pushed the row to
                    // 37px. The Row centres the field, so the text stays
                    // vertically centred without it.
                    contentPadding: EdgeInsets.zero,
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
          const SizedBox(width: GbmSpacing.space1),
          const _ColumnsButton(),
        ],
      ),
    );
  }
}

/// Spec page 02 item 16's "History 標題列右側一顆按鈕", drawn with the
/// `columns-3` glyph the mockup labels it with (`spec_logic.js:800`).
///
/// "標題列" means four different things across this spec (see CLAUDE.md #68);
/// here it is the History panel's own top row, not the tab row and not the OS
/// window title -- the mockup pins the icon to the panel's caption
/// (`spec_raw.html:1298`), one line above the graph, not to the tab strip
/// that sits above that.
///
/// Stateful only to own a [GlobalKey]: the popover is anchored to this
/// button's rect, and a `RenderBox` is the only thing that knows it.
class _ColumnsButton extends StatefulWidget {
  const _ColumnsButton();

  @override
  State<_ColumnsButton> createState() => _ColumnsButtonState();
}

class _ColumnsButtonState extends State<_ColumnsButton> {
  final GlobalKey _key = GlobalKey();

  void _open() {
    final RenderBox? box =
        _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    showGraphColumnsPopover(
      context,
      anchor: box.localToGlobal(Offset.zero) & box.size,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GbmIconButton(
      key: _key,
      tooltip: 'Graph columns',
      icon: LucideIcon(
        'columns-3',
        size: 14,
        color: context.gbmColors.textTertiary,
      ),
      onPressed: _open,
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
    required this.onMove,
    required this.child,
  });

  final FocusNode focusNode;
  final VoidCallback onSelectAll;
  final VoidCallback onCollapse;
  final ValueChanged<int> onExtend;

  /// Plain ↑/↓. Bound above the list's own [Focus], so it wins over the
  /// ambient `ScrollAction` a focused Scrollable would otherwise run -- the
  /// selection moving *and* scrolling into view is what a list does with an
  /// arrow key, and a list that only scrolled would leave the selection
  /// behind off-screen.
  final ValueChanged<int> onMove;
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
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const GbmMoveSelectionIntent(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const GbmMoveSelectionIntent(1),
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
          GbmMoveSelectionIntent: CallbackAction<GbmMoveSelectionIntent>(
            onInvoke: (GbmMoveSelectionIntent intent) {
              onMove(intent.delta);
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
