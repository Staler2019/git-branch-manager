import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/stash_entry.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_button.dart';
import '../../widgets/gbm_row.dart';
import '../history_graph/widgets/graph_date_format.dart';
import 'gbm_panel_tab_shell.dart';
import 'panel_file_diff_detail.dart';

/// `manage-stashes` as a tab (spec page 14 `IAMAP`), laid out on page 19's
/// shared template.
///
/// P19 `PANELSPEC` row:
/// - list: stash 編號 + 訊息 + 時間
/// - detail: 檔案清單 + diff（唯讀）
/// - toolbar: Apply、Pop、Drop、Create
///
/// The dialog this replaces put Apply/Pop/Drop as three mini-buttons *inside
/// every row*; P19 puts them in the toolbar, acting on the selection. That
/// is the safer arrangement as well as the specified one -- Drop is
/// destructive and irreversible, and a per-row Drop sits one stray click
/// away from the row you actually meant.
class StashesPanel extends ConsumerStatefulWidget {
  const StashesPanel({
    super.key,
    required this.identity,
    this.initialSelectedIndex,
  });

  final RepoIdentity identity;

  /// Pre-selects a stash (and requests its diff), set by the sidebar's 05-H
  /// "View diff". Re-applied in [State.didUpdateWidget] as well as
  /// [State.initState]: re-opening this panel focuses the existing tab
  /// rather than building a new one, so a second "View diff" on a different
  /// stash arrives as a widget update, not a fresh mount.
  final int? initialSelectedIndex;

  @override
  ConsumerState<StashesPanel> createState() => _StashesPanelState();
}

class _StashesPanelState extends ConsumerState<StashesPanel> {
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialSelectedIndex;
    Future.microtask(() {
      _session.refreshStashes();
      if (widget.initialSelectedIndex case final int index) {
        _session.requestStashDiff(index);
      }
    });
  }

  @override
  void didUpdateWidget(StashesPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final int? incoming = widget.initialSelectedIndex;
    if (incoming != null && incoming != oldWidget.initialSelectedIndex) {
      _select(incoming);
    }
  }

  RepoSessionController get _session =>
      ref.read(repoSessionProvider(widget.identity).notifier);

  void _select(int index) {
    setState(() => _selectedIndex = index);
    _session.requestStashDiff(index);
  }

  @override
  Widget build(BuildContext context) {
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final List<StashEntry> stashes = session.stashes;
    final StashDiffReply? diff = session.lastStashDiff;
    // Indices shift when a stash is dropped or popped, so a selection that
    // no longer exists must fall back to "nothing selected" rather than
    // silently pointing the toolbar at a different stash.
    final bool hasSelection = stashes.any(
      (StashEntry s) => s.index == _selectedIndex,
    );
    final int? selected = hasSelection ? _selectedIndex : null;

    return GbmPanelTabShell(
      storageId: 'panel.stashes',
      detailIsEmpty: selected == null,
      emptyDetailMessage: 'Select a stash to see its changes',
      toolbar: <Widget>[
        GbmButton(
          label: 'Apply',
          onPressed: selected == null
              ? null
              : () => _session.applyStash(selected),
        ),
        GbmButton(
          label: 'Pop',
          onPressed: selected == null
              ? null
              : () {
                  _session.applyStash(selected, pop: true);
                  setState(() => _selectedIndex = null);
                },
        ),
        GbmButton(
          label: 'Drop',
          kind: GbmButtonKind.danger,
          onPressed: selected == null
              ? null
              : () {
                  _session.dropStash(selected);
                  setState(() => _selectedIndex = null);
                },
        ),
        // Creating a stash is spec's own "Stash changes" dialog (P06
        // DIALOGS, Branch -> Stash changes) -- it has options (message,
        // include untracked, keep staged), so it is not a toolbar action
        // that can just fire.
        GbmButton(
          label: 'Create…',
          onPressed: () => context.push(
            RoutePaths.stashChangesDialogFor(
              Uri.encodeComponent(widget.identity.workDir),
            ),
          ),
        ),
      ],
      list: stashes.isEmpty
          ? Center(
              child: Text(
                'No stashes',
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: context.gbmColors.textTertiary,
                ),
              ),
            )
          : ListView.builder(
              itemCount: stashes.length,
              itemBuilder: (context, i) => _StashListRow(
                entry: stashes[i],
                selected: stashes[i].index == selected,
                onTap: () => _select(stashes[i].index),
              ),
            ),
      detail: selected == null
          ? const SizedBox.shrink()
          : (diff != null && diff.index == selected)
          // 檔案清單 + diff（唯讀）: DiffPage alone renders hunks with no
          // per-file header, so the file list is the wrapper's job.
          ? PanelFileDiffDetail(
              diff: diff.diff,
              storageId: 'panel.stashes.detail',
            )
          : const Center(child: CircularProgressIndicator()),
    );
  }
}

/// P19 list column: stash 編號 + 訊息 + 時間.
class _StashListRow extends StatelessWidget {
  const _StashListRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final StashEntry entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return GbmRow(
      selected: selected,
      onTap: onTap,
      height: GbmSpacing.rowHeightComfortable + GbmSpacing.space3,
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'stash@{${entry.index}}: ${entry.message}',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
                fontWeight: GbmTypography.weightMedium,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              formatGraphDate(
                DateTime.fromMillisecondsSinceEpoch(entry.timestamp * 1000),
                DateTime.now(),
              ),
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
