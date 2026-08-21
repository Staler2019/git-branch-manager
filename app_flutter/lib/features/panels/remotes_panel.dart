import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/ref_snapshot.dart';
import '../../data/models/remote_info.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../routing/route_paths.dart';
import '../../widgets/gbm_button.dart';
import 'add_remote_prompt.dart';
import 'gbm_panel_tab_shell.dart';
import 'panel_widgets.dart';

/// `manage-remotes` as a tab (spec page 14 `IAMAP`), on page 19's template.
///
/// P19 `PANELSPEC` row:
/// - list: remote 名稱 + URL
/// - detail: fetch / push URL、tracking ref 數、最後 fetch
/// - toolbar: Add、Edit、Prune、Remove
///
/// Three things about this panel are deliberate and were checked rather than
/// assumed -- it is the first port where the dialog and `PANELSPEC` disagree:
///
/// **The dialog's per-row Fetch / Pull / Push are gone.** Two independent
/// spec tables exclude them: `PANELSPEC`'s toolbar is Add/Edit/Prune/Remove,
/// and P04 `MENUS`' Remote menu is Add remote… / Fetch all remotes / Prune
/// remote branches / Manage remotes…. Fetching one named remote is covered
/// (as a superset) by Fetch all remotes; pulling or pushing a *non-upstream*
/// remote is a real capability loss, recorded on #76 rather than kept as an
/// off-spec extra. Same convention as Tier 6a's dropped `Clear`.
///
/// **Edit renders disabled.** `gbm_capi.h` has `gbm_remote_add`/`_remove`/
/// `_fetch`/`_prune` and no set-url entry point, so there is nothing to call.
/// Disabled-with-a-reason rather than hidden, matching File → New
/// repository… / Clone repository…, which are drawn by the spec and disabled
/// for the same "no capi" reason.
///
/// **tracking ref 數 is derived, not absent.** It is a count of the refs
/// already in `RefSnapshot` -- see [_trackingRefCount]. 最後 fetch has no
/// source at all (nothing reports `.git/FETCH_HEAD`'s mtime), so that one
/// field is absent, the 待提交數 precedent.
class RemotesPanel extends ConsumerStatefulWidget {
  const RemotesPanel({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<RemotesPanel> createState() => _RemotesPanelState();
}

class _RemotesPanelState extends ConsumerState<RemotesPanel> {
  /// By name rather than index: a refresh can reorder the list, and an index
  /// would then point the detail pane at a different remote than the one the
  /// user clicked.
  String? _selectedName;

  @override
  void initState() {
    super.initState();
    Future.microtask(_session.refreshRemotes);
  }

  RepoSessionController get _session =>
      ref.read(repoSessionProvider(widget.identity).notifier);

  /// How many remote-tracking refs belong to [remoteName].
  ///
  /// Prefix-matched on `fullName` (`refs/remotes/<name>/…`), never a
  /// first-slash split of `shortName` -- that split is the live bug tracked
  /// as #74, and on a full ref name it would yield `"refs"`.
  int _trackingRefCount(RefSnapshot refs, String remoteName) {
    final String prefix = 'refs/remotes/$remoteName/';
    return refs.refs
        .where(
          (RefInfo r) =>
              r.kind == RefKind.remoteBranch && r.fullName.startsWith(prefix),
        )
        .length;
  }

  Future<void> _add() async {
    final ({String name, String url})? result = await promptAddRemote(context);
    if (result == null || !mounted) return;
    _session.addRemote(result.name, result.url);
  }

  @override
  Widget build(BuildContext context) {
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final List<RemoteInfo> remotes = session.remotes;
    final RemoteInfo? selected = remotes
        .where((RemoteInfo r) => r.name == _selectedName)
        .firstOrNull;

    return GbmPanelTabShell(
      storageId: 'panel.remotes',
      detailIsEmpty: selected == null,
      emptyDetailMessage: 'Select a remote to see its details',
      toolbar: <Widget>[
        GbmButton(label: 'Add…', onPressed: _add),
        const Tooltip(
          message: 'Changing a remote URL is not supported yet',
          child: GbmButton(label: 'Edit…', onPressed: null),
        ),
        // Prune stays a dialog: `IAMAP` files prune-remote-branches under
        // "中型表單 / 確認框", not under the twelve panels, and it needs a
        // dry-run preview the user confirms.
        GbmButton(
          label: 'Prune',
          onPressed: selected == null
              ? null
              : () => context.push(
                  RoutePaths.pruneRemoteBranchesDialogFor(
                    Uri.encodeComponent(widget.identity.workDir),
                    remote: selected.name,
                  ),
                ),
        ),
        GbmButton(
          label: 'Remove',
          kind: GbmButtonKind.danger,
          onPressed: selected == null
              ? null
              : () {
                  _session.removeRemote(selected.name);
                  setState(() => _selectedName = null);
                },
        ),
      ],
      list: remotes.isEmpty
          ? const PanelEmptyList(message: 'No remotes configured')
          : ListView.builder(
              itemCount: remotes.length,
              itemBuilder: (context, i) => PanelListRow(
                title: remotes[i].name,
                subtitle: remotes[i].fetchUrl,
                selected: remotes[i].name == _selectedName,
                onTap: () => setState(() => _selectedName = remotes[i].name),
              ),
            ),
      detail: selected == null
          ? const SizedBox.shrink()
          : PanelDetailColumn(
              children: <Widget>[
                PanelDetailField(
                  label: 'Fetch URL',
                  value: selected.fetchUrl,
                  mono: true,
                ),
                PanelDetailField(
                  label: 'Push URL',
                  // git reports the fetch URL as the push URL when no
                  // separate pushurl is configured, so an empty string here
                  // means "not configured", not "cannot push".
                  value: selected.pushUrl.isEmpty
                      ? '${selected.fetchUrl} (same as fetch)'
                      : selected.pushUrl,
                  mono: true,
                ),
                PanelDetailField(
                  label: 'Tracking refs',
                  value: '${_trackingRefCount(session.refs, selected.name)}',
                ),
              ],
            ),
    );
  }
}
