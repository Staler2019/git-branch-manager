import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/models/release_asset.dart';
import '../../../data/models/update_state.dart';
import '../../../data/repositories/app_preferences_repository.dart';
import '../../../data/repositories/open_repo_sessions.dart';
import '../../../data/repositories/update_repository.dart';
import '../../../data/services/desktop_launcher.dart';
import '../../../theme/gbm_theme.dart';
import '../../../theme/tokens.dart';
import '../../../widgets/gbm_banner.dart';
import '../../../widgets/gbm_button.dart';
import '../../../widgets/gbm_dialog_shell.dart';

/// The update flow's one screen, routed as `/dialogs/update`.
///
/// App-scoped rather than repo-scoped (like About and Preferences): an
/// update is not a property of any open repository, and this has to be
/// reachable from `WelcomeScreen`, which has no repository at all.
///
/// **No indeterminate progress indicator appears here, in any state.** One
/// schedules frames forever, so any test that `pumpAndSettle`s a screen
/// showing one times out rather than failing on its own assertion --
/// CLAUDE.md records that trap costing a full device-tier batch. A download
/// with no known total renders an empty determinate bar instead.
class UpdateDialogContent extends ConsumerStatefulWidget {
  const UpdateDialogContent({super.key});

  @override
  ConsumerState<UpdateDialogContent> createState() =>
      _UpdateDialogContentState();
}

class _UpdateDialogContentState extends ConsumerState<UpdateDialogContent> {
  @override
  void initState() {
    super.initState();
    // Deferred a frame: `check()` publishes a new state synchronously, and
    // writing a provider during the first build is the
    // "Tried to modify a provider while the widget tree was building" throw
    // this repo has already fixed once in sidebar_panel.dart.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Only from rest. Re-opening the dialog mid-download must not restart
      // the check and discard the bytes already fetched.
      if (ref.read(updateProvider).status == UpdateStatus.idle) {
        ref.read(updateProvider.notifier).check();
      }
    });
  }

  /// Releases every live `gbm_capi` session before the process hands over to
  /// the detached updater. An interrupted refresh would otherwise strand a
  /// `git` child holding `.git/index.lock` in a repository the user still
  /// has open -- and the *new* build would open onto that lock.
  Future<void> _closeSessions() async {
    ref.read(openRepoSessionsProvider).closeAll();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final UpdateState state = ref.watch(updateProvider);
    final UpdateController controller = ref.read(updateProvider.notifier);

    return GbmDialogShell(
      title: 'Software update',
      actions: _actions(context, state, controller),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (state.status == UpdateStatus.failed && state.errorMessage != null)
            Padding(
              padding: const EdgeInsets.only(bottom: GbmSpacing.space3),
              child: GbmWarningBanner(message: state.errorMessage!),
            ),
          Text(
            _headline(state),
            style: TextStyle(
              fontSize: GbmTypography.textBase,
              color: colors.textPrimary,
            ),
          ),
          if (state.blockedReason != null) ...<Widget>[
            const SizedBox(height: GbmSpacing.space2),
            Text(
              state.blockedReason!,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textSecondary,
              ),
            ),
          ],
          if (_notes(state) case final String notes) ...<Widget>[
            const SizedBox(height: GbmSpacing.space3),
            Text(
              notes,
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.textSecondary,
              ),
            ),
          ],
          if (_showsProgress(state)) ...<Widget>[
            const SizedBox(height: GbmSpacing.space3),
            // `?? 0` rather than null: see the class doc comment.
            LinearProgressIndicator(value: state.progress ?? 0),
            const SizedBox(height: GbmSpacing.space1),
            Text(
              _progressLabel(state),
              style: TextStyle(
                fontSize: GbmTypography.textXs,
                color: colors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: GbmSpacing.space4),
        ],
      ),
    );
  }

  String _headline(UpdateState state) {
    return switch (state.status) {
      UpdateStatus.idle || UpdateStatus.checking => 'Checking for updates…',
      UpdateStatus.developmentBuild =>
        'Development build — updates are disabled.',
      UpdateStatus.upToDate =>
        'You are up to date (${state.release?.version}).',
      UpdateStatus.available =>
        'Version ${state.release?.version} is '
            'available.',
      UpdateStatus.downloading => 'Downloading ${state.release?.version}…',
      UpdateStatus.verifying => 'Verifying the download…',
      UpdateStatus.readyToInstall =>
        'Version ${state.release?.version} is ready. The app will close and '
            'reopen on the new version.',
      UpdateStatus.installing => 'Installing…',
      UpdateStatus.failed => 'The update did not complete.',
    };
  }

  /// Release notes, only where they inform a decision the user still has.
  String? _notes(UpdateState state) {
    if (state.status != UpdateStatus.available) return null;
    final String notes = state.release?.notes.trim() ?? '';
    return notes.isEmpty ? null : notes;
  }

  bool _showsProgress(UpdateState state) =>
      state.status == UpdateStatus.downloading ||
      state.status == UpdateStatus.verifying;

  String _progressLabel(UpdateState state) {
    if (state.status == UpdateStatus.verifying) {
      return 'Checking the download against $kChecksumManifestName.';
    }
    if (state.totalBytes <= 0) return 'Starting…';
    return '${_mb(state.downloadedBytes)} of ${_mb(state.totalBytes)} MB';
  }

  static String _mb(int bytes) => (bytes / (1024 * 1024)).toStringAsFixed(1);

  /// Records the offered release as skipped and closes the offer.
  ///
  /// Stored as [AppVersion.toString] renders it (`9.9.9`, no `v`), which is
  /// the form `UpdateController.checkAutomatically` compares against -- a
  /// tag string would silently never match.
  void _skip(WidgetRef ref, UpdateState state) {
    final LatestRelease? release = state.release;
    if (release == null) return;
    ref
        .read(appPreferencesProvider.notifier)
        .update(
          (AppPreferences p) =>
              p.copyWith(skippedVersion: release.version.toString()),
        );
    ref.read(updateProvider.notifier).dismiss();
  }

  List<Widget> _actions(
    BuildContext context,
    UpdateState state,
    UpdateController controller,
  ) {
    const Widget gap = SizedBox(width: GbmSpacing.space2);
    Widget close([String label = 'Close']) =>
        GbmButton(label: label, onPressed: () => context.pop());

    switch (state.status) {
      case UpdateStatus.idle:
      case UpdateStatus.checking:
      case UpdateStatus.installing:
        // Nothing to press: installing is past the point of no return -- the
        // detached script is already running and this process cannot recall
        // it.
        return <Widget>[];

      case UpdateStatus.developmentBuild:
      case UpdateStatus.upToDate:
        return <Widget>[close()];

      case UpdateStatus.available:
        return <Widget>[
          close(),
          gap,
          // Suppresses only the *automatic* check, and only for this exact
          // version -- Help → Check for updates… still reports it, and the
          // Preferences → General row names it and offers to undo. Without
          // this button `skippedVersion` would be a setting nothing could
          // ever set.
          GbmButton(
            label: 'Skip this version',
            kind: GbmButtonKind.secondary,
            onPressed: () => _skip(ref, state),
          ),
          gap,
          if (state.canSelfInstall)
            GbmButton(
              label: 'Download and install',
              kind: GbmButtonKind.primary,
              onPressed: controller.download,
            )
          else
            // Offering a download that can never be installed would spend
            // 24MB to arrive at a failure the user cannot act on.
            GbmButton(
              label: 'Open releases page',
              kind: GbmButtonKind.primary,
              onPressed: () => ref
                  .read(desktopLauncherProvider)
                  .openUrl(GbmUrls.releasesPage),
            ),
        ];

      case UpdateStatus.downloading:
      case UpdateStatus.verifying:
        return <Widget>[
          GbmButton(label: 'Cancel', onPressed: controller.cancel),
        ];

      case UpdateStatus.readyToInstall:
        return <Widget>[
          GbmButton(label: 'Cancel', onPressed: controller.cancel),
          gap,
          GbmButton(
            label: 'Install and restart',
            kind: GbmButtonKind.primary,
            onPressed: () => controller.install(beforeExit: _closeSessions),
          ),
        ];

      case UpdateStatus.failed:
        return <Widget>[
          close(),
          gap,
          GbmButton(
            label: 'Try again',
            kind: GbmButtonKind.primary,
            onPressed: controller.check,
          ),
        ];
    }
  }
}
