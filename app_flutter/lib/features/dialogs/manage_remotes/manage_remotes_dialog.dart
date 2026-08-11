import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/remote_info.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of the remote-sync half of `PushPullDialog`/repository
/// settings (src/app/dialogs). Routed as
/// `/repo/:repoId/dialogs/manage-remotes`. Only lists and syncs against
/// remotes that already exist (`git remote add`/`remove` are not yet part
/// of the capi surface -- see src/core/git/ops/RemoteOps.h, which only
/// covers list/fetch/pull/push).
class ManageRemotesDialogContent extends ConsumerStatefulWidget {
  const ManageRemotesDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<ManageRemotesDialogContent> createState() => _ManageRemotesDialogContentState();
}

class _ManageRemotesDialogContentState extends ConsumerState<ManageRemotesDialogContent> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(repoSessionProvider(widget.identity).notifier).refreshRemotes());
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final List<RemoteInfo> remotes = ref.watch(
      repoSessionProvider(widget.identity).select((state) => state.remotes),
    );

    return GbmDialogShell(
      title: 'Remotes',
      width: 640,
      actions: <Widget>[GbmButton(label: 'Close', onPressed: () => context.pop())],
      child: SizedBox(
        height: 280,
        child: remotes.isEmpty
            ? Center(child: Text('No remotes configured', style: TextStyle(color: colors.textTertiary)))
            : ListView(
                children: <Widget>[
                  for (final remote in remotes) _RemoteRow(identity: widget.identity, remote: remote),
                ],
              ),
      ),
    );
  }
}

class _RemoteRow extends ConsumerWidget {
  const _RemoteRow({required this.identity, required this.remote});

  final RepoIdentity identity;
  final RemoteInfo remote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final GbmColors colors = context.gbmColors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GbmSpacing.space2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(remote.name, style: TextStyle(fontSize: GbmTypography.textSm, color: colors.textPrimary, fontWeight: GbmTypography.weightMedium)),
                Text(remote.fetchUrl, style: TextStyle(fontSize: GbmTypography.textXs, color: colors.textTertiary), overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          TextButton(
            onPressed: () => ref.read(repoSessionProvider(identity).notifier).fetchRemote(remoteName: remote.name, prune: true),
            child: Text('Fetch', style: TextStyle(fontSize: GbmTypography.textXs, color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () => ref.read(repoSessionProvider(identity).notifier).pullChanges(remoteName: remote.name),
            child: Text('Pull', style: TextStyle(fontSize: GbmTypography.textXs, color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () => ref.read(repoSessionProvider(identity).notifier).pushChanges(remoteName: remote.name),
            child: Text('Push', style: TextStyle(fontSize: GbmTypography.textXs, color: colors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
