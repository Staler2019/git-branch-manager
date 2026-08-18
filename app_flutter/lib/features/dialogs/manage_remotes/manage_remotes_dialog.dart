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
/// `/repo/:repoId/dialogs/manage-remotes`. Lists, syncs, adds, and removes
/// remotes -- see src/core/git/ops/RemoteOps.h's makeAddRemoteOperation()/
/// makeRemoveRemoteOperation().
class ManageRemotesDialogContent extends ConsumerStatefulWidget {
  const ManageRemotesDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<ManageRemotesDialogContent> createState() =>
      _ManageRemotesDialogContentState();
}

class _ManageRemotesDialogContentState
    extends ConsumerState<ManageRemotesDialogContent> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(repoSessionProvider(widget.identity).notifier)
          .refreshRemotes(),
    );
  }

  Future<void> _addRemote(BuildContext context) async {
    final ({String name, String url})? result = await _promptAddRemote(context);
    if (result == null || !mounted) return;
    ref
        .read(repoSessionProvider(widget.identity).notifier)
        .addRemote(result.name, result.url);
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
      actions: <Widget>[
        GbmButton(label: 'Add remote…', onPressed: () => _addRemote(context)),
        GbmButton(label: 'Close', onPressed: () => context.pop()),
      ],
      child: SizedBox(
        height: 280,
        child: remotes.isEmpty
            ? Center(
                child: Text(
                  'No remotes configured',
                  style: TextStyle(color: colors.textTertiary),
                ),
              )
            : ListView(
                children: <Widget>[
                  for (final remote in remotes)
                    _RemoteRow(identity: widget.identity, remote: remote),
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
                Text(
                  remote.name,
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.textPrimary,
                    fontWeight: GbmTypography.weightMedium,
                  ),
                ),
                Text(
                  remote.fetchUrl,
                  style: TextStyle(
                    fontSize: GbmTypography.textXs,
                    color: colors.textTertiary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => ref
                .read(repoSessionProvider(identity).notifier)
                .fetchRemote(remoteName: remote.name, prune: true),
            child: Text(
              'Fetch',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => ref
                .read(repoSessionProvider(identity).notifier)
                .pullChanges(remoteName: remote.name),
            child: Text(
              'Pull',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => ref
                .read(repoSessionProvider(identity).notifier)
                .pushChanges(remoteName: remote.name),
            child: Text(
              'Push',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
          ),
          TextButton(
            onPressed: () => ref
                .read(repoSessionProvider(identity).notifier)
                .removeRemote(remote.name),
            child: Text(
              'Remove',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Prompts for both a name and a URL at once -- unlike every other
/// branch/tag rename/create flow, adding a remote genuinely needs two
/// values, so this doesn't fit promptText's single-field shape. Returns
/// null if cancelled, or either field is left empty.
Future<({String name, String url})?> _promptAddRemote(BuildContext context) {
  final TextEditingController nameController = TextEditingController();
  final TextEditingController urlController = TextEditingController();
  return showDialog<({String name, String url})>(
    context: context,
    builder: (dialogContext) {
      final GbmColors colors = dialogContext.gbmColors;
      ({String name, String url})? resultFromControllers() {
        final String name = nameController.text.trim();
        final String url = urlController.text.trim();
        return name.isEmpty || url.isEmpty ? null : (name: name, url: url);
      }

      // Only pops on a valid result -- leaving the dialog open (with
      // whatever the user already typed still in place) is the signal
      // that a required field is missing, rather than silently discarding
      // the input by closing anyway.
      void submitIfValid() {
        final ({String name, String url})? result = resultFromControllers();
        if (result != null) {
          Navigator.of(dialogContext).pop(result);
        }
      }

      return AlertDialog(
        title: const Text('Add Remote'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Name',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'URL',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => submitIfValid(),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: colors.textSecondary),
            ),
          ),
          TextButton(onPressed: submitIfValid, child: const Text('Add')),
        ],
      );
    },
  );
}
