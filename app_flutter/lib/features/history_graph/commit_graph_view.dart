import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
class CommitGraphView extends ConsumerWidget {
  const CommitGraphView({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GraphSnapshotView graph = ref.watch(repoGraphProvider(identity));
    final bool isRefreshing = ref.watch(repoIsRefreshingProvider(identity));
    final GbmColors colors = context.gbmColors;

    if (graph.rows.isEmpty) {
      return Center(
        child: isRefreshing
            ? const CircularProgressIndicator()
            : Text('No commits yet', style: TextStyle(color: colors.textTertiary)),
      );
    }

    return ListView.builder(
      itemCount: graph.rows.length,
      itemBuilder: (context, index) {
        final GraphRow row = graph.rows[index];
        return CommitRow(
          row: row,
          oidHex: index < graph.oidsHex.length ? graph.oidsHex[index] : '',
          previousLane: index > 0 ? graph.rows[index - 1].lane : null,
          nextLane: index < graph.rows.length - 1 ? graph.rows[index + 1].lane : null,
          maxLane: graph.laneCount,
        );
      },
    );
  }
}
