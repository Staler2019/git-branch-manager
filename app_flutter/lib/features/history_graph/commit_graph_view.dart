import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/commit_meta.dart';
import '../../data/models/graph_snapshot.dart';
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

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
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
    final String? selectedOid = ref.watch(
      selectedCommitProvider(widget.identity),
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
                  selectedOid,
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
    String? selectedOid,
    RefSnapshot refs,
    String effectiveEmail,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _requestVisibleMeta(constraints.maxHeight);
        });
        return ListView.builder(
          controller: _controller,
          itemExtent: kCommitRowHeight,
          itemCount: visibleRows.length,
          itemBuilder: (context, position) {
            // `position` walks the filtered result list; `index` is the row's
            // real place in the unfiltered snapshot, which is what selection
            // and the graph edge lookups are keyed on.
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
              selected: oid.isNotEmpty && oid == selectedOid,
              refChips: oid.isEmpty
                  ? const <RefChipData>[]
                  : refChipsForCommit(refs, oid),
              isOwnCommit:
                  meta != null &&
                  effectiveEmail.isNotEmpty &&
                  meta.author.email == effectiveEmail,
              onTap: oid.isEmpty
                  ? null
                  : () {
                      ref
                              .read(
                                selectedCommitProvider(
                                  widget.identity,
                                ).notifier,
                              )
                              .state =
                          oid;
                      ref
                              .read(
                                selectedCommitFilePathProvider(
                                  widget.identity,
                                ).notifier,
                              )
                              .state =
                          null;
                      requestCommitFiles(ref, widget.identity, oid);
                    },
              onCheckout: oid.isEmpty
                  ? null
                  : () => ref
                        .read(repoSessionProvider(widget.identity).notifier)
                        .checkout(target: oid, detach: true),
              onCherryPick: oid.isEmpty
                  ? null
                  : () => ref
                        .read(repoSessionProvider(widget.identity).notifier)
                        .cherryPick([oid]),
              onRevert: oid.isEmpty
                  ? null
                  : () => ref
                        .read(repoSessionProvider(widget.identity).notifier)
                        .revert([oid]),
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
