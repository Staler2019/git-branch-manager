import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../actions/gbm_action_id.dart';
import '../../../data/models/remote_info.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// Preview-then-confirm prune of stale remote-tracking branches (spec page
/// 06/P6), backed by commit 2/3's `RemoteOps::prunePreview`/`prune` and
/// commit 4's `requestRemotePrunePreview`/`pruneRemote`. Routed as
/// `/repo/:repoId/dialogs/prune-remote-branches`.
///
/// Same preview-list-then-single-confirm-button shape as
/// `CleanUntrackedDialogContent` -- no extra confirmation modal on top,
/// matching this codebase's established convention for a destructive
/// action whose own dialog already requires explicit selection (see
/// `ManageStashesDialogContent`'s Drop button, which has no confirm modal
/// either). Unlike Clean, which always removes everything previewed, this
/// lets the user deselect individual refs first -- pruning is scoped to
/// stale remote-tracking refs specifically, and a preview entry the user
/// recognizes as still wanted should be easy to keep.
class PruneRemoteBranchesDialogContent extends ConsumerStatefulWidget {
  const PruneRemoteBranchesDialogContent({
    super.key,
    required this.identity,
    this.initialRemote,
  });

  final RepoIdentity identity;

  /// Which remote to preview on open. The Remotes panel's `Prune` acts on
  /// the row the user selected, so landing on `remotes.first` instead would
  /// silently prune a different remote than the one they were looking at.
  /// Null (no query parameter) keeps the previous behaviour.
  final String? initialRemote;

  @override
  ConsumerState<PruneRemoteBranchesDialogContent> createState() =>
      _PruneRemoteBranchesDialogContentState();
}

class _PruneRemoteBranchesDialogContentState
    extends ConsumerState<PruneRemoteBranchesDialogContent> {
  String? _selectedRemote;
  final Set<String> _selectedRefs = <String>{};
  String? _previewedForRemote;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final List<RemoteInfo> remotes = ref.read(
        repoSessionProvider(widget.identity).select((state) => state.remotes),
      );
      if (remotes.isEmpty) return;
      final String? requested = widget.initialRemote;
      final bool exists = remotes.any((RemoteInfo r) => r.name == requested);
      _pickRemote(exists ? requested! : remotes.first.name);
    });
  }

  void _pickRemote(String remoteName) {
    setState(() => _selectedRemote = remoteName);
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .requestRemotePrunePreview(remoteName);
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<RemoteInfo> remotes = ref.watch(
      repoSessionProvider(widget.identity).select((state) => state.remotes),
    );
    final RemotePrunePreview? preview = ref.watch(
      repoSessionProvider(
        widget.identity,
      ).select((state) => state.lastRemotePrunePreview),
    );

    // A fresh preview for the currently selected remote replaces the
    // selection with "everything staged for pruning", the same default
    // CleanUntrackedDialogContent's unconditional list implies -- but only
    // once per preview, so a user's manual deselection survives unrelated
    // rebuilds (e.g. an unrelated RepoSessionState field changing).
    if (preview != null &&
        preview.remote == _selectedRemote &&
        _previewedForRemote != preview.remote) {
      _previewedForRemote = preview.remote;
      _selectedRefs
        ..clear()
        ..addAll(preview.refs.map((e) => e.ref));
    }

    // `preview != null &&`, not `preview?.remote ==` -- the latter reads as
    // 「the preview we have is for the remote we are showing」 but is also
    // true when both are null, which happens on every dialog's first build
    // (`_selectedRemote` is only assigned inside `initState`'s
    // `Future.microtask`). A bare `preview!` on that path used to throw.
    final List<String> previewRefs =
        (preview != null && preview.remote == _selectedRemote)
        ? preview.refs.map((e) => e.ref).toList(growable: false)
        : const <String>[];

    return GbmDialogShell(
      title: 'Prune Remote Branches',
      actionId: GbmActionId.remotePruneRemoteBranches,
      width: 560,
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label:
              'Prune ${_selectedRefs.length} Branch'
              '${_selectedRefs.length == 1 ? '' : 'es'}',
          kind: GbmButtonKind.primary,
          onPressed: _selectedRefs.isEmpty || _selectedRemote == null
              ? null
              : () {
                  ref
                      .read(repoSessionProvider(widget.identity).notifier)
                      .pruneRemote(
                        _selectedRemote!,
                        _selectedRefs.toList(growable: false),
                      );
                  context.pop();
                },
        ),
      ],
      child: SizedBox(
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // The spec asks for this line by position, not just by content:
            // 「只清遠端已不存在的 tracking ref，不是刪遠端分支 — 標題列下方
            // 一行寫明這件事」. The distinction it draws is the whole risk of
            // the dialog, and nothing in the app stated it.
            Text(
              '只清除遠端已經不存在的 tracking ref，不會刪掉遠端分支，也不會動到本地分支。',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
                height: GbmTypography.leadingNormal,
              ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            if (remotes.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: GbmSpacing.space2),
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _selectedRemote,
                  items: <DropdownMenuItem<String>>[
                    for (final RemoteInfo remote in remotes)
                      DropdownMenuItem<String>(
                        value: remote.name,
                        child: Text(remote.name),
                      ),
                  ],
                  onChanged: (String? value) {
                    if (value != null) _pickRemote(value);
                  },
                ),
              ),
            if (remotes.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    '沒有設定任何 remote',
                    style: TextStyle(color: colors.textTertiary),
                  ),
                ),
              )
            else if (previewRefs.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    '沒有需要清除的 tracking ref',
                    style: TextStyle(color: colors.textTertiary),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: previewRefs.length,
                  itemBuilder: (context, index) {
                    final String ref = previewRefs[index];
                    return CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _selectedRefs.contains(ref),
                      title: Text(
                        ref,
                        style: TextStyle(
                          fontSize: GbmTypography.textSm,
                          color: colors.textPrimary,
                        ),
                      ),
                      onChanged: (bool? checked) => setState(() {
                        if (checked ?? false) {
                          _selectedRefs.add(ref);
                        } else {
                          _selectedRefs.remove(ref);
                        }
                      }),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
