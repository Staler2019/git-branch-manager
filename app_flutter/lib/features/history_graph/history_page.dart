import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/chrome_visibility_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../theme/tokens.dart';
import '../../widgets/split_pane.dart';
import 'commit_graph_view.dart';
import 'widgets/changed_files_panel.dart';
import 'widgets/commit_detail_panel.dart';

/// History tab page composing nested split panes:
/// - Main horizontal split: commit graph list (62%) ↔ commit detail (38%)
/// - Vertical split on main pane: graph (fills) ↔ changed files (186px default)
class HistoryPage extends ConsumerWidget {
  const HistoryPage({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool showDetail = ref.watch(
      chromeVisibilityProvider.select(
        (ChromeVisibility c) => c.commitDetailVisible,
      ),
    );

    // Left pane: commit graph + changed files (vertical split)
    final Widget listPane = GbmSplitPane(
      axis: Axis.vertical,
      spec: GbmLayout.splitterMainFiles,
      storageId: 'main.files',
      children: [
        CommitGraphView(identity: identity),
        ChangedFilesPanel(identity: identity),
      ],
    );

    // View → Commit detail (Ctrl/Cmd+D) collapses the right pane entirely
    // rather than shrinking it: the split pane is dropped, so the list gets
    // the full width instead of leaving a zero-width pane and its divider
    // behind. The splitter's own stored ratio is untouched, so re-showing
    // the panel restores the width the user last dragged it to.
    if (!showDetail) return listPane;

    return GbmSplitPane(
      axis: Axis.horizontal,
      spec: GbmLayout.splitterMainDetail,
      storageId: 'main.detail',
      children: [
        listPane,
        // Right pane: commit detail / file diff
        CommitDetailPanel(identity: identity),
      ],
    );
  }
}
