import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/ref_snapshot.dart';
import '../../../data/repositories/app_preferences_repository.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// Shown when Push is invoked on a branch that has diverged from its
/// upstream.
///
/// Spec page 06: "顯示會被覆蓋的遠端 commit 數。可在 Preferences 關閉此確認"
/// -- the overwritten-commit count is the branch's `behind`, i.e. exactly
/// the commits that exist on the remote and not locally. Suppressing the
/// confirmation is [AppPreferences.confirmForcePush]; the checkbox here
/// writes that preference directly so the user does not have to go hunting
/// for it in Preferences afterwards.
///
/// The push itself uses `--force-with-lease` (`forceWithLease: true`), not a
/// bare `--force`: if someone else pushed after the ahead/behind counts
/// shown here were computed, the push is refused instead of destroying work
/// this dialog never mentioned.
///
/// Routed as `/repo/:repoId/dialogs/force-push`.
class ForcePushDialogContent extends ConsumerStatefulWidget {
  const ForcePushDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<ForcePushDialogContent> createState() =>
      _ForcePushDialogContentState();
}

class _ForcePushDialogContentState
    extends ConsumerState<ForcePushDialogContent> {
  bool _dontAskAgain = false;

  RefInfo? _headRef(RepoSessionState session) {
    if (session.refs.head.fullRef.isEmpty) return null;
    for (final RefInfo ref in session.refs.refs) {
      if (ref.fullName == session.refs.head.fullRef) return ref;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final RefInfo? head = _headRef(session);
    final String branch = session.refs.head.branchName.isNotEmpty
        ? session.refs.head.branchName
        : 'HEAD';
    final int overwritten = head?.behind ?? 0;
    final int pushing = head?.ahead ?? 0;
    final String upstream = head?.upstream ?? '';

    return GbmDialogShell(
      title: 'Force Push',
      actions: <Widget>[
        GbmButton(label: 'Cancel', onPressed: () => context.pop()),
        const SizedBox(width: GbmSpacing.space2),
        GbmButton(
          label: 'Force push',
          kind: GbmButtonKind.danger,
          onPressed: () async {
            if (_dontAskAgain) {
              await ref
                  .read(appPreferencesProvider.notifier)
                  .update((AppPreferences p) => p.copyWith(
                        confirmForcePush: false,
                      ));
            }
            if (!context.mounted) return;
            ref
                .read(repoSessionProvider(widget.identity).notifier)
                .pushChanges(forceWithLease: true);
            context.pop();
          },
        ),
      ],
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            upstream.isEmpty
                ? '$branch has diverged from its upstream.'
                : '$branch has diverged from $upstream.',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          if (overwritten > 0)
            Text(
              '$overwritten commit(s) currently on the remote will be '
              'overwritten and will no longer be reachable there.',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.danger,
                height: GbmTypography.leadingNormal,
              ),
            )
          else
            Text(
              'No remote commits will be overwritten.',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textSecondary,
              ),
            ),
          const SizedBox(height: GbmSpacing.space1),
          Text(
            '$pushing local commit(s) will be pushed.',
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          Text(
            'Pushed with --force-with-lease: if the remote changed again '
            'since these numbers were read, the push is refused rather than '
            'overwriting work not listed here.',
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.textTertiary,
              height: GbmTypography.leadingNormal,
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          CheckboxListTile(
            value: _dontAskAgain,
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              'Do not ask again',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
            ),
            subtitle: Text(
              'Re-enable under Preferences → Advanced.',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textTertiary,
              ),
            ),
            onChanged: (bool? value) =>
                setState(() => _dontAskAgain = value ?? false),
          ),
        ],
      ),
    );
  }
}
