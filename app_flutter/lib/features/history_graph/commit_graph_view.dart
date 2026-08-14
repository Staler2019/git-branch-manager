import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/commit_meta.dart';
import '../../data/models/graph_snapshot.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import 'widgets/commit_row.dart';

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

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
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
    final double offset = _controller.hasClients ? _controller.offset : 0;
    final int lastRow = graph.rows.length - 1;
    final int first = (offset / kCommitRowHeight).floor().clamp(0, lastRow);
    final int last = ((offset + viewportHeight) / kCommitRowHeight)
        .ceil()
        .clamp(0, lastRow);
    return <String>[
      for (int i = first; i <= last && i < graph.oidsHex.length; i++)
        graph.oidsHex[i],
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
    final GbmColors colors = context.gbmColors;

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

    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _requestVisibleMeta(constraints.maxHeight);
        });
        return ListView.builder(
          controller: _controller,
          itemExtent: kCommitRowHeight,
          itemCount: graph.rows.length,
          itemBuilder: (context, index) {
            final GraphRow row = graph.rows[index];
            final String oid = index < graph.oidsHex.length
                ? graph.oidsHex[index]
                : '';
            return CommitRow(
              row: row,
              oidHex: oid,
              graph: graph,
              rowIndex: index,
              maxLane: graph.laneCount,
              meta: metaCache[oid],
              selected: oid.isNotEmpty && oid == selectedOid,
              onTap: oid.isEmpty
                  ? null
                  : () =>
                        ref
                                .read(
                                  selectedCommitProvider(
                                    widget.identity,
                                  ).notifier,
                                )
                                .state =
                            oid,
            );
          },
        );
      },
    );
  }
}
