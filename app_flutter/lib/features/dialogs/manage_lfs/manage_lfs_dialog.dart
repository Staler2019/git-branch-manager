import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/lfs_state.dart';
import '../../../data/repositories/repo_identity.dart';
import '../../../data/repositories/repo_session_repository.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The Dart analog of `ManageLfsDialog` (src/app/dialogs/ManageLfsDialog.cpp).
/// Routed as `/repo/:repoId/dialogs/manage-lfs`.
class ManageLfsDialogContent extends ConsumerStatefulWidget {
  const ManageLfsDialogContent({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<ManageLfsDialogContent> createState() =>
      _ManageLfsDialogContentState();
}

class _ManageLfsDialogContentState
    extends ConsumerState<ManageLfsDialogContent> {
  final TextEditingController _patternController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () =>
          ref.read(repoSessionProvider(widget.identity).notifier).refreshLfs(),
    );
  }

  @override
  void dispose() {
    _patternController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final RepoSessionState session = ref.watch(
      repoSessionProvider(widget.identity),
    );
    final RepoSessionController notifier = ref.read(
      repoSessionProvider(widget.identity).notifier,
    );
    final LfsInstallation? installation = session.lfsInstallation;

    return GbmDialogShell(
      title: 'Git LFS',
      width: 640,
      actions: <Widget>[
        GbmButton(
          label: 'Close',
          kind: GbmButtonKind.primary,
          onPressed: () => context.pop(),
        ),
      ],
      child: SizedBox(
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (installation == null)
              Text(
                'Checking for git-lfs…',
                style: TextStyle(color: colors.textTertiary),
              )
            else if (!installation.available)
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'git-lfs is not installed',
                      style: TextStyle(
                        fontSize: GbmTypography.textSm,
                        color: colors.danger,
                      ),
                    ),
                  ),
                ],
              )
            else
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      installation.version,
                      style: TextStyle(
                        fontSize: GbmTypography.textSm,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  GbmButton(label: 'Pull', onPressed: () => notifier.pullLfs()),
                  const SizedBox(width: GbmSpacing.space1),
                  GbmButton(
                    label: 'Fetch',
                    onPressed: () => notifier.fetchLfs(),
                  ),
                  const SizedBox(width: GbmSpacing.space1),
                  GbmButton(
                    label: 'Prune',
                    onPressed: () => notifier.pruneLfs(),
                  ),
                ],
              ),
            if (installation != null && !installation.available) ...<Widget>[
              const SizedBox(height: GbmSpacing.space2),
              Align(
                alignment: Alignment.centerLeft,
                child: GbmButton(
                  label: 'Install (Local)',
                  onPressed: () => notifier.installLfs(),
                ),
              ),
            ],
            const SizedBox(height: GbmSpacing.space3),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _patternController,
                    decoration: const InputDecoration(
                      hintText: '*.psd',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: GbmSpacing.space2),
                GbmButton(
                  label: 'Track',
                  onPressed: () {
                    final String pattern = _patternController.text.trim();
                    if (pattern.isEmpty) return;
                    notifier.trackLfsPattern(pattern);
                    _patternController.clear();
                  },
                ),
              ],
            ),
            const SizedBox(height: GbmSpacing.space2),
            Text(
              'TRACKED PATTERNS',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                fontWeight: GbmTypography.weightSemibold,
                color: colors.textTertiary,
              ),
            ),
            SizedBox(
              height: 60,
              child: session.lfsPatterns.isEmpty
                  ? Center(
                      child: Text(
                        'None',
                        style: TextStyle(
                          fontSize: GbmTypography.textXs,
                          color: colors.textTertiary,
                        ),
                      ),
                    )
                  : ListView(
                      children: <Widget>[
                        for (final pattern in session.lfsPatterns)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              pattern,
                              style: TextStyle(
                                fontSize: GbmTypography.textSm,
                                fontFamily: 'monospace',
                                color: colors.textPrimary,
                              ),
                            ),
                            trailing: IconButton(
                              icon: Icon(
                                Icons.close,
                                size: 14,
                                color: colors.textTertiary,
                              ),
                              onPressed: () =>
                                  notifier.untrackLfsPattern(pattern),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: GbmSpacing.space2),
            Text(
              'TRACKED FILES',
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                fontWeight: GbmTypography.weightSemibold,
                color: colors.textTertiary,
              ),
            ),
            Expanded(
              child: session.lfsFiles.isEmpty
                  ? Center(
                      child: Text(
                        'None',
                        style: TextStyle(
                          fontSize: GbmTypography.textXs,
                          color: colors.textTertiary,
                        ),
                      ),
                    )
                  : ListView(
                      children: <Widget>[
                        for (final file in session.lfsFiles)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              file.path,
                              style: TextStyle(
                                fontSize: GbmTypography.textSm,
                                color: colors.textPrimary,
                              ),
                            ),
                            trailing: Text(
                              file.downloadedLocally
                                  ? 'downloaded'
                                  : 'not downloaded',
                              style: TextStyle(
                                fontSize: GbmTypography.textXs,
                                color: colors.textTertiary,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
