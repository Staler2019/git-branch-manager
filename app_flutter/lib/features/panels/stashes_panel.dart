import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/stash_entry.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../routing/route_paths.dart';
import '../../widgets/gbm_button.dart';
import '../history_graph/widgets/graph_date_format.dart';
import 'gbm_panel_tab_shell.dart';
import 'panel_filter_field.dart';
import 'panel_status_line.dart';
import 'panel_toolbar_spec.dart';
import 'panel_file_diff_detail.dart';
import 'panel_widgets.dart';

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
///
/// **Where the 破壞性 line falls between `Pop` and `Drop`.** Rule 2 keeps
/// destructive actions off the toolbar, and PANELSPEC's toolbar cell lists
/// all four actions -- so one of them has to move, and which one is a
/// judgement this panel owns rather than a detail of the matrix.
///
/// 破壞性 here means *destroys work the user cannot get back*. `Pop` deletes
/// the stash, but only after applying it to the work tree, and the commit it
/// pointed at survives in the stash reflog (`git stash apply <sha>` can
/// restore it), so nothing is lost -- it stays in the maintenance segment.
/// `Drop` throws the changes away with nothing applied anywhere; it moves to
/// the detail action row. The same boundary keeps `Abort` and `Reset` on the
/// interactive-rebase and bisect toolbars: those restore a prior state.
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
  String _query = '';

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

  bool _matchesQuery(StashEntry stash) {
    if (_query.trim().isEmpty) return true;
    final String needle = _query.trim().toLowerCase();
    return stash.message.toLowerCase().contains(needle) ||
        'stash@{${stash.index}}'.contains(needle);
  }

  /// Rule 6's 「實際數量與耗時」, with **no 耗時 clause** -- this panel runs
  /// one `git stash list` and measures nothing per row, so a duration here
  /// would be invented. Worktrees prints 掃描 N ms because it really does
  /// time a per-worktree status pass; printing one where nothing was timed
  /// is decorating a count, not reporting one.
  String _statusLine({required int total, required int shown}) =>
      panelStatusLine(
        total: total,
        shown: shown,
        noun: 'stash',
        nounPlural: 'stashes',
      );

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
    final List<StashEntry> visible = stashes.where(_matchesQuery).toList();

    return GbmPanelTabShell(
      storageId: 'panel.stashes',
      detailIsEmpty: selected == null,
      emptyDetailMessage: 'Select a stash to see its changes',
      toolbar: PanelToolbarSpec(
        primary: <Widget>[
          // 主要建立動作. Creating a stash is spec's own "Stash changes"
          // dialog (P06 DIALOGS, Branch -> Stash changes) -- it has options
          // (message, include untracked, keep staged), so it opens rather
          // than firing. It is the only toolbar action independent of the
          // selection, which is also what makes it the primary one.
          GbmButton(
            label: 'Create…',
            kind: GbmButtonKind.primary,
            onPressed: () => context.push(
              RoutePaths.stashChangesDialogFor(
                Uri.encodeComponent(widget.identity.workDir),
              ),
            ),
          ),
        ],
        maintenance: <Widget>[
          GbmButton(
            label: 'Apply',
            kind: GbmButtonKind.ghost,
            onPressed: selected == null
                ? null
                : () => _session.applyStash(selected),
          ),
          GbmButton(
            label: 'Pop',
            kind: GbmButtonKind.ghost,
            onPressed: selected == null
                ? null
                : () {
                    _session.applyStash(selected, pop: true);
                    setState(() => _selectedIndex = null);
                  },
          ),
        ],
        filter: PanelFilterField(
          query: _query,
          onChanged: (String value) => setState(() => _query = value),
        ),
      ),
      detailActions: PanelDetailActions(
        dangerActions: <Widget>[
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
        ],
      ),
      listHeader: PanelListHeaderText(text: 'Stashes · ${visible.length}'),
      statusBar: PanelStatusBarText(
        text: _statusLine(total: stashes.length, shown: visible.length),
      ),
      list: visible.isEmpty
          ? PanelEmptyList(
              message: stashes.isEmpty
                  ? 'No stashes'
                  : 'No stash matches the filter',
            )
          : ListView.builder(
              itemCount: visible.length,
              // P19 list column: stash 編號 + 訊息 + 時間.
              itemBuilder: (context, i) => PanelListRow(
                title: 'stash@{${visible[i].index}}: ${visible[i].message}',
                subtitle: formatGraphDate(
                  DateTime.fromMillisecondsSinceEpoch(
                    visible[i].timestamp * 1000,
                  ),
                  DateTime.now(),
                ),
                selected: visible[i].index == selected,
                onTap: () => _select(visible[i].index),
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
