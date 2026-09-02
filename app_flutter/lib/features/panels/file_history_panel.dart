import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/file_history_entry.dart';
import '../../data/models/parsed_diff.dart';
import '../../data/repositories/compare_tabs_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../routing/route_paths.dart';
import '../../widgets/gbm_button.dart';
import '../diff/diff_page.dart';
import '../history_graph/widgets/graph_date_format.dart';
import 'gbm_panel_tab_shell.dart';
import 'panel_filter_field.dart';
import 'panel_status_line.dart';
import 'panel_toolbar_spec.dart';
import 'panel_widgets.dart';

/// `file-history` as a tab (spec page 14 `IAMAP`), on page 19's template.
/// Opened per file from 05-F's `History ▸ File history…`, so two files are
/// two tabs — see [GbmPanelKind.isPerSubject].
///
/// P19 `PANELSPEC` row:
/// - list: 該檔的 commit 清單
/// - detail: 逐版 diff（唯讀）
/// - toolbar: 欄位選擇器、含重命名、Compare
///
/// **Which segment each action lands in (P19 rule 2), and why the primary
/// segment is empty.** A file history creates nothing, so 主要建立動作 is
/// empty and draws no placeholder. With 欄位選擇器 absent (below),
/// `Renames followed` is the whole maintenance segment, and `Compare…` is
/// 「跳出去」 — it opens a Compare tab and navigates to it.
///
/// **「含重命名」 is not a toggle, and rendering it as one would be a lie.**
/// `gbm_request_file_history` documents itself as "following renames the
/// way `git log --follow` does" — it is unconditional, with no parameter to
/// turn it off. So the control shows the state (on) and is disabled with
/// that reason, rather than offering a switch that would silently do
/// nothing.
///
/// **「欄位選擇器」 is absent.** The list is [PanelListRow], whose two lines
/// are fixed by P19's own template ("只換欄位不換造型"); a per-panel column
/// chooser would be a second list implementation, and spec gives no
/// column set to choose from. Tracked on #76.
class FileHistoryPanel extends ConsumerStatefulWidget {
  const FileHistoryPanel({
    super.key,
    required this.identity,
    required this.path,
  });

  final RepoIdentity identity;

  /// Repository-relative path this tab is about.
  final String path;

  @override
  ConsumerState<FileHistoryPanel> createState() => _FileHistoryPanelState();
}

class _FileHistoryPanelState extends ConsumerState<FileHistoryPanel> {
  String? _selectedOid;
  String _query = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _session.requestFileHistory(widget.path));
  }

  @override
  void didUpdateWidget(FileHistoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-opening this panel for a different file focuses the existing tab
    // (per-subject tabs are keyed on kind + subject), so a new path can
    // arrive as an update rather than a fresh mount.
    if (widget.path != oldWidget.path) {
      setState(() => _selectedOid = null);
      _session.requestFileHistory(widget.path);
    }
  }

  RepoSessionController get _session =>
      ref.read(repoSessionProvider(widget.identity).notifier);

  /// Matches the subject, the author's name **and the oid**, though the row
  /// draws only the first two.
  ///
  /// Same reasoning as the reflog panel: someone arriving with a hash from
  /// `git log` output has nothing else to paste, and this row deliberately
  /// leads with the subject rather than the oid.
  bool _matchesQuery(FileHistoryEntry entry) {
    if (_query.trim().isEmpty) return true;
    final String needle = _query.trim().toLowerCase();
    return entry.subject.toLowerCase().contains(needle) ||
        entry.author.name.toLowerCase().contains(needle) ||
        entry.oid.toLowerCase().contains(needle);
  }

  void _select(FileHistoryEntry entry) {
    setState(() => _selectedOid = entry.oid);
    // The path this commit touched is the *renamed-from* path when this
    // entry is a rename, otherwise the tab's own path -- asking for the
    // current name inside a commit that predates the rename returns
    // nothing.
    _session.requestCommitFileDiff(entry.oid, _pathAt(entry));
  }

  String _pathAt(FileHistoryEntry entry) =>
      entry.renamedFrom.isEmpty ? widget.path : entry.renamedFrom;

  @override
  Widget build(BuildContext context) {
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final List<FileHistoryEntry> entries = session.lastFileHistory;
    final List<FileHistoryEntry> visible = entries
        .where(_matchesQuery)
        .toList(growable: false);
    final FileHistoryEntry? selected = entries
        .where((FileHistoryEntry e) => e.oid == _selectedOid)
        .firstOrNull;
    final ParsedDiff? diff = session.selectedCommitFileDiff;

    return GbmPanelTabShell(
      storageId: 'panel.fileHistory',
      detailIsEmpty: selected == null,
      emptyDetailMessage: 'Select a commit to see how it changed this file',
      toolbar: PanelToolbarSpec(
        maintenance: <Widget>[
          const Tooltip(
            message:
                'File history always follows renames (git log --follow); '
                'there is no way to turn it off',
            child: GbmButton(
              label: 'Renames followed',
              kind: GbmButtonKind.ghost,
              onPressed: null,
            ),
          ),
        ],
        external: <Widget>[
          // Compare needs a revision to compare *from*; the other side is
          // filled in by the Compare page's own ref picker, the convention
          // sidebar_panel.dart's _compareTag()/_compareStash() established.
          GbmButton(
            label: 'Compare…',
            kind: GbmButtonKind.ghost,
            onPressed: selected == null
                ? null
                : () {
                    final String tabId = ref
                        .read(compareTabsProvider(widget.identity).notifier)
                        .open(left: selected.oid, right: null);
                    context.go(
                      RoutePaths.compareFor(
                        Uri.encodeComponent(widget.identity.workDir),
                        tabId,
                      ),
                    );
                  },
          ),
        ],
        filter: PanelFilterField(
          query: _query,
          onChanged: (String value) => setState(() => _query = value),
        ),
      ),
      listHeader: PanelListHeaderText(text: 'Commits · ${visible.length}'),
      statusBar: PanelStatusBarText(
        text: panelStatusLine(
          total: entries.length,
          shown: visible.length,
          noun: 'commit',
        ),
      ),
      list: visible.isEmpty
          ? PanelEmptyList(
              message: entries.isEmpty
                  ? 'No commits touched this file'
                  : 'No commit matches the filter',
            )
          : ListView.builder(
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final FileHistoryEntry e = visible[i];
                return PanelListRow(
                  title: e.subject,
                  subtitle: <String>[
                    e.author.name,
                    formatGraphDate(
                      DateTime.fromMillisecondsSinceEpoch(e.author.when * 1000),
                      DateTime.now(),
                    ),
                    // A rename is the one status worth surfacing in the
                    // list: it explains why the path changes further down.
                    if (e.renamedFrom.isNotEmpty)
                      'renamed from ${e.renamedFrom}',
                  ].join(' · '),
                  selected: e.oid == _selectedOid,
                  onTap: () => _select(e),
                );
              },
            ),
      detail: selected == null
          ? const SizedBox.shrink()
          : diff == null
          ? const Center(child: CircularProgressIndicator())
          : DiffPage(diff: diff),
    );
  }
}
