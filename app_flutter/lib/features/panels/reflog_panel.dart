import 'package:flutter/material.dart';
import 'package:gbm_flutter/data/repositories/panel_tabs_repository.dart';
import 'package:gbm_flutter/features/panels/panel_storage_id.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/commit_meta.dart';
import '../../data/models/reflog_entry.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../routing/route_paths.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_button.dart';
import '../history_graph/widgets/graph_date_format.dart';
import 'gbm_panel_tab_shell.dart';
import 'panel_filter_field.dart';
import 'panel_status_line.dart';
import 'panel_toolbar_spec.dart';
import 'panel_widgets.dart';

/// `reflog` as a tab (spec page 14 `IAMAP`), on page 19's template.
///
/// P19 `PANELSPEC` row:
/// - list: reflog 項目（時間 + 動作）
/// - detail: 該 commit 的明細與可回得的 ref
/// - toolbar: Restore branch、Checkout、Copy SHA
///
/// **Which segment each action lands in (P19 rule 2).** `Restore branch…` is
/// the only one that creates anything, so it is primary. `Checkout` acts on
/// this repository — maintenance — and only `Copy SHA` leaves the app at
/// all, so it is the 「跳出去」 segment on its own.
///
/// This is a deliberate reading of `Checkout`, which is the least obvious of
/// the three: it is not「跳出去」 despite moving HEAD, because the thing it
/// changes is the repository this panel belongs to. What the third segment
/// collects is actions whose *result lands outside the app* — the clipboard
/// here, a file manager in `manage-submodules`, a directory of `.patch`
/// files in `patches`.
///
/// **Nothing moves to the detail action row**: none of the three is
/// 破壞性. The panel exists to *recover* commits, and its most forceful
/// action creates a branch.
///
/// **The ref selector is not in the toolbar.** `PANELSPEC` names three
/// actions and a reflog is always *of* some ref, so which ref to read is a
/// parameter of the list, not a fourth action — it sits above the list where
/// the list's own scope belongs.
///
/// 該 commit 的明細 comes from `commitMetaCache`, requested per selection.
/// It can legitimately be missing for a moment (the reply is an FFI event)
/// and, for a reflog entry whose commit has since been garbage-collected,
/// permanently — the detail says which case it is rather than rendering
/// blank.
class ReflogPanel extends ConsumerStatefulWidget {
  const ReflogPanel({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<ReflogPanel> createState() => _ReflogPanelState();
}

class _ReflogPanelState extends ConsumerState<ReflogPanel> {
  /// Empty means HEAD, which is what `gbm_request_reflog` treats an empty
  /// ref as.
  final TextEditingController _refController = TextEditingController();
  String _loadedRef = 'HEAD';
  int? _selectedIndex;
  String _query = '';

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _session.requestReflog());
  }

  @override
  void dispose() {
    _refController.dispose();
    super.dispose();
  }

  RepoSessionController get _session =>
      ref.read(repoSessionProvider(widget.identity).notifier);

  void _load() {
    final String ref = _refController.text.trim();
    setState(() {
      _loadedRef = ref.isEmpty ? 'HEAD' : ref;
      _selectedIndex = null;
    });
    _session.requestReflog(ref: ref);
  }

  /// Matches the action text **and the oid**, though the row draws only the
  /// former.
  ///
  /// Filtering on something invisible is normally a smell; here it is the
  /// case the filter exists for. Someone arriving with a hash out of
  /// `git reflog`'s own output has nothing else to paste, and the row
  /// deliberately shows 動作 over 時間 (P19's list column) rather than the
  /// oid, so a message-only filter would answer 「no entries」 to the one
  /// query a reflog is most often searched by.
  bool _matchesQuery(ReflogEntry entry) {
    if (_query.trim().isEmpty) return true;
    final String needle = _query.trim().toLowerCase();
    return entry.message.toLowerCase().contains(needle) ||
        entry.oid.toLowerCase().contains(needle);
  }

  void _select(ReflogEntry entry) {
    setState(() => _selectedIndex = entry.index);
    // Cheap and idempotent: the controller merges replies into
    // commitMetaCache, so re-requesting an already-cached oid is a no-op
    // from the UI's point of view.
    _session.requestCommitMeta(<String>[entry.oid]);
  }

  @override
  Widget build(BuildContext context) {
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final List<ReflogEntry> entries = session.lastReflog;
    final List<ReflogEntry> visible = entries
        .where(_matchesQuery)
        .toList(growable: false);
    final ReflogEntry? selected = entries
        .where((ReflogEntry e) => e.index == _selectedIndex)
        .firstOrNull;

    return GbmPanelTabShell(
      storageId: panelStorageId(GbmPanelKind.reflog),
      detailIsEmpty: selected == null,
      emptyDetailMessage: 'Select a reflog entry to see its commit',
      toolbar: PanelToolbarSpec(
        primary: <Widget>[
          // Restoring a branch needs a name, so it opens the new-branch
          // dialog with this entry's oid as the start point rather than
          // inventing a second name-entry surface.
          GbmButton(
            label: 'Restore branch…',
            kind: GbmButtonKind.primary,
            onPressed: selected == null
                ? null
                : () => context.push(
                    RoutePaths.newBranchDialogFor(
                      Uri.encodeComponent(widget.identity.workDir),
                      startPoint: selected.oid,
                    ),
                  ),
          ),
        ],
        maintenance: <Widget>[
          // Checking out a bare oid always detaches -- there is no branch at
          // a reflog entry, which is the whole reason this panel exists.
          GbmButton(
            label: 'Checkout',
            kind: GbmButtonKind.ghost,
            onPressed: selected == null
                ? null
                : () => _session.checkout(target: selected.oid, detach: true),
          ),
        ],
        external: <Widget>[
          GbmButton(
            label: 'Copy SHA',
            kind: GbmButtonKind.ghost,
            onPressed: selected == null
                ? null
                : () => Clipboard.setData(ClipboardData(text: selected.oid)),
          ),
        ],
        filter: PanelFilterField(
          query: _query,
          onChanged: (String value) => setState(() => _query = value),
        ),
      ),
      listHeader: PanelListHeaderText(text: 'Reflog · ${visible.length}'),
      statusBar: PanelStatusBarText(
        text: panelStatusLine(
          total: entries.length,
          shown: visible.length,
          noun: 'entry',
          nounPlural: 'entries',
        ),
      ),
      list: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(GbmSpacing.space2),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _refController,
                    onSubmitted: (_) => _load(),
                    decoration: const InputDecoration(
                      hintText: 'HEAD',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: GbmSpacing.space2),
                GbmButton(label: 'Load', onPressed: _load),
              ],
            ),
          ),
          Expanded(
            child: visible.isEmpty
                ? PanelEmptyList(
                    message: entries.isEmpty
                        ? 'No reflog entries'
                        : 'No reflog entry matches the filter',
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, i) {
                      final ReflogEntry e = visible[i];
                      return PanelListRow(
                        // 動作 over 時間 -- the action is what someone
                        // scanning a reflog is looking for.
                        title: e.message,
                        subtitle: formatGraphDate(
                          DateTime.fromMillisecondsSinceEpoch(
                            e.who.when * 1000,
                          ),
                          DateTime.now(),
                        ),
                        selected: e.index == _selectedIndex,
                        onTap: () => _select(e),
                      );
                    },
                  ),
          ),
        ],
      ),
      detail: selected == null
          ? const SizedBox.shrink()
          : _ReflogDetail(
              entry: selected,
              ref: _loadedRef,
              meta: session.commitMetaCache[selected.oid],
            ),
    );
  }
}

/// P19 detail column: 該 commit 的明細 + 可回得的 ref.
class _ReflogDetail extends StatelessWidget {
  const _ReflogDetail({
    required this.entry,
    required this.ref,
    required this.meta,
  });

  final ReflogEntry entry;
  final String ref;
  final CommitMeta? meta;

  @override
  Widget build(BuildContext context) {
    return PanelDetailColumn(
      children: <Widget>[
        // 可回得的 ref: `<ref>@{N}` is the revision string that gets this
        // state back, which is the thing worth copying out of this panel.
        PanelDetailField(
          label: 'Recoverable as',
          value: '$ref@{${entry.index}}',
          mono: true,
        ),
        PanelDetailField(label: 'Commit', value: entry.oid, mono: true),
        PanelDetailField(label: 'Action', value: entry.message),
        PanelDetailField(
          label: 'Logged by',
          value: '${entry.who.name} <${entry.who.email}>',
        ),
        if (meta != null) ...<Widget>[
          PanelDetailField(label: 'Subject', value: meta!.subject),
          if (meta!.body.trim().isNotEmpty)
            PanelDetailField(label: 'Body', value: meta!.body.trim()),
          PanelDetailField(
            label: 'Author',
            value: '${meta!.author.name} <${meta!.author.email}>',
          ),
        ] else
          // Two different causes, and the user can act on the second one:
          // a commit only reachable through the reflog can be lost to gc.
          const PanelDetailField(
            label: 'Commit details',
            value: 'Loading, or no longer in the object database',
          ),
      ],
    );
  }
}
