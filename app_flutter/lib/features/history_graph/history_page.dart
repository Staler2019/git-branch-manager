import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/chrome_visibility_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../theme/tokens.dart';
import '../../widgets/split_pane.dart';
import 'commit_graph_view.dart';
import 'widgets/changed_files_panel.dart';
import 'widgets/commit_detail_panel.dart';

/// History tab page, composed exactly as spec P02 describes it: 「History 分頁：
/// 右側 Changed files（02-10）+ 下方 Commit detail（02-08）」.
///
/// Two nested splitters, both named by the spec's own SPLITTERS table:
/// - `main.files`  「中央 ↔ Changed files」, vertical divider, 186px, min 140.
///   The files column is the *trailing* fixed pane, so it sits on the right.
///   Its storage id carries a `.v2` suffix: extent mode persists a raw pixel
///   value (`split_pane.dart`'s `[extentPx]`), so the height anyone had
///   already dragged this band to while it lived *below* the graph would come
///   back as a column *width* on the new axis. Dropping the old key is the
///   migration -- the stored number has no meaning across an axis flip.
///   `main.detail` deliberately keeps its id: it is ratio mode, and 62/38
///   still reads as "the graph gets more" whichever way the divider runs.
/// - `main.detail` 「Commit list ↔ Commit detail」, horizontal divider, 62/38,
///   min 160. Nested inside the centre, so the graph and the detail share one
///   column and the files list spans their full height.
///
/// It used to be the other way round in both dimensions -- detail on the right,
/// files below -- and worse: the files/graph split passed the graph as pane 0
/// of an extent-mode vertical splitter, which pins pane 0 to the *bottom* at
/// its fixed height. The commit graph, the whole point of the page, rendered
/// as a 186px strip under a full-height file list. Nothing at any tier covered
/// the page's composition, which is how three wrong placements stayed green;
/// `test/features/history_graph/history_page_layout_test.dart` is that cover.
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

    // View -> Commit detail (Ctrl/Cmd+D) drops the inner splitter entirely
    // rather than shrinking it, so the graph gets the full height instead of
    // leaving a zero-height pane and its divider behind. The splitter's stored
    // ratio is untouched, so re-showing restores the height last dragged to.
    final Widget centre = showDetail
        ? GbmSplitPane(
            axis: Axis.vertical,
            spec: GbmLayout.splitterMainDetail,
            storageId: 'main.detail',
            children: <Widget>[
              CommitGraphView(identity: identity),
              CommitDetailPanel(identity: identity),
            ],
          )
        : CommitGraphView(identity: identity);

    return GbmSplitPane(
      axis: Axis.horizontal,
      spec: GbmLayout.splitterMainFiles,
      storageId: 'main.files.v2',
      fixedPaneEnd: GbmFixedPaneEnd.trailing,
      children: <Widget>[
        ChangedFilesPanel(identity: identity),
        centre,
      ],
    );
  }
}
