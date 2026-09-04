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
        GbmButton(
          label: 'Force push',
          kind: GbmButtonKind.danger,
          onPressed: () async {
            if (_dontAskAgain) {
              await ref
                  .read(appPreferencesProvider.notifier)
                  .update(
                    (AppPreferences p) => p.copyWith(confirmForcePush: false),
                  );
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
                ? '$branch 已經和 upstream 分岔。'
                : '$branch 已經和 $upstream 分岔。',
            style: TextStyle(
              fontSize: GbmTypography.textSm,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          if (overwritten > 0)
            Text(
              '遠端目前有 $overwritten 個 commit 會被覆蓋，之後在那裡就找不到了。',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.danger,
                height: GbmTypography.leadingNormal,
              ),
            )
          else
            Text(
              '不會覆蓋遠端的任何 commit。',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textSecondary,
              ),
            ),
          const SizedBox(height: GbmSpacing.space1),
          Text(
            '會推送 $pushing 個本地 commit。',
            style: TextStyle(
              fontSize: GbmTypography.textXs,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: GbmSpacing.space2),
          Text(
            '使用 --force-with-lease 推送：如果讀到這些數字之後遠端又有新變動，'
            '這次推送會被拒絕，而不是覆蓋掉沒列在這裡的工作。',
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
              '不要再問',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textPrimary,
              ),
            ),
            subtitle: Text(
              '可在 Preferences → Advanced 重新開啟。',
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
