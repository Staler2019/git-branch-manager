import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/history_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_banner.dart';
import '../sidebar/sidebar_panel.dart';
import 'widgets/menu_bar_row.dart';
import 'widgets/tab_row.dart';
import 'widgets/top_bar.dart';

/// The repository shell: menu bar + top bar + tab switcher + sidebar, with
/// `child` (History or Working Copy, see routing/app_router.dart's
/// ShellRoute) as the main pane. The Dart analog of `MainWindow`
/// (src/app/views/MainWindow.cpp). Owns the session's lifetime: opening any
/// child route lazily opens the `gbm_capi` session (see
/// data/repositories/repo_session_repository.dart), and Riverpod's
/// family provider is torn down (closing the session) once nothing is
/// watching it anymore, i.e. once every child route under this shell is
/// popped.
///
/// `ConsumerStatefulWidget` rather than `ConsumerWidget` solely to hold
/// [_sidebarVisible] -- the menu bar's "Toggle sidebar" item
/// (menu_bar_row.dart) needs somewhere to flip a bool, and this is pure
/// transient UI state scoped to one open workspace, not app/session state
/// worth a provider of its own.
class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.identity,
    required this.child,
  });

  final RepoIdentity identity;
  final Widget child;

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  bool _sidebarVisible = true;

  @override
  Widget build(BuildContext context) {
    final RepoIdentity identity = widget.identity;
    final RepoSessionState session = ref.watch(repoSessionProvider(identity));
    final String repoId = repoIdForRoute(identity);

    // Pushed automatically -- a credential prompt is not something the user
    // chose to open, unlike every other dialog route. See
    // CredentialDialogContent's doc comment for the reverse direction
    // (answering pops it back here without waiting for this to go null).
    ref.listen(
      repoSessionProvider(identity).select((state) => state.credentialPrompt),
      (previous, next) {
        if (next != null && previous == null) {
          context.push(RoutePaths.credentialDialogFor(repoId));
        }
      },
    );

    // Same auto-push pattern as credentialPrompt above -- a checkout
    // refused on a dirty work tree is not something the user chose to open
    // a dialog for either.
    ref.listen(
      repoSessionProvider(identity).select((state) => state.checkoutChoices),
      (previous, next) {
        if (next.isNotEmpty && (previous?.isEmpty ?? true)) {
          context.push(RoutePaths.checkoutRecoveryDialogFor(repoId));
        }
      },
    );

    // Same auto-push pattern, for the "not fully merged" -> "Force delete"
    // recovery flow (see DeleteBranchRecoveryDialogContent's doc comment).
    ref.listen(
      repoSessionProvider(
        identity,
      ).select((state) => state.deleteBranchChoices),
      (previous, next) {
        if (next.isNotEmpty && (previous?.isEmpty ?? true)) {
          context.push(RoutePaths.deleteBranchRecoveryDialogFor(repoId));
        }
      },
    );

    if (!session.isOpen) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.go(RoutePaths.repoList)),
        ),
        body: Center(
          child: Text(
            session.lastError?.message ?? 'Opening repository…',
            style: TextStyle(color: context.gbmColors.textSecondary),
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: <Widget>[
          MenuBarRow(
            repoId: repoId,
            sidebarVisible: _sidebarVisible,
            onToggleSidebar: () =>
                setState(() => _sidebarVisible = !_sidebarVisible),
            onFetch: () =>
                ref.read(repoSessionProvider(identity).notifier).fetchRemote(),
            onPull: () =>
                ref.read(repoSessionProvider(identity).notifier).pullChanges(),
            onPush: () =>
                ref.read(repoSessionProvider(identity).notifier).pushChanges(),
          ),
          TopBar(
            repoName: _displayName(identity.workDir),
            repoState: session.repoState,
            isRefreshing: session.isRefreshing,
            onRefresh: () => refreshRepoHistory(ref, identity),
            onBack: () => context.go(RoutePaths.repoList),
          ),
          TabRow(
            repoId: repoId,
            pendingChangeCount: session.workingCopyStatus.entries.length,
          ),
          if (session.workingCopyStatus.conflicted.isNotEmpty)
            _ConflictBanner(
              repoId: repoId,
              count: session.workingCopyStatus.conflicted.length,
            )
          else if (session.lastError case final error?)
            GbmWarningBanner(message: error.message),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (_sidebarVisible) SidebarPanel(identity: identity),
                Expanded(child: widget.child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _displayName(String workDir) {
    final List<String> segments = workDir
        .split(RegExp(r'[\\/]'))
        .where((s) => s.isNotEmpty)
        .toList();
    return segments.isEmpty ? workDir : segments.last;
  }
}

/// Resolves the `:repoId` route segment for `identity` -- the inverse of
/// `repoIdentityFromRouteParam` in routing/app_router.dart. Kept here
/// (rather than importing app_router.dart, which would create a routing ->
/// workspace -> routing import cycle) since it is a one-line pure function.
String repoIdForRoute(RepoIdentity identity) =>
    Uri.encodeComponent(identity.workDir);

class _ConflictBanner extends StatelessWidget {
  const _ConflictBanner({required this.repoId, required this.count});

  final String repoId;
  final int count;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space4,
        vertical: GbmSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: colors.diffDelBg,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              '$count file${count == 1 ? '' : 's'} conflicted',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.diffDelText,
              ),
            ),
          ),
          TextButton(
            onPressed: () => context.go(RoutePaths.conflictsFor(repoId)),
            child: Text(
              'Resolve…',
              style: TextStyle(
                fontSize: GbmTypography.textSm,
                color: colors.diffDelText,
                fontWeight: GbmTypography.weightSemibold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
