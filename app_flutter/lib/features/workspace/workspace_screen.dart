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
import 'widgets/top_bar.dart';

/// The repository shell: sidebar + top bar + tab switcher, with `child`
/// (History or Working Copy, see routing/app_router.dart's ShellRoute) as
/// the main pane. The Dart analog of `MainWindow` (src/app/views/
/// MainWindow.cpp). Owns the session's lifetime: opening any child route
/// lazily opens the `gbm_capi` session (see
/// data/repositories/repo_session_repository.dart), and Riverpod's
/// family provider is torn down (closing the session) once nothing is
/// watching it anymore, i.e. once every child route under this shell is
/// popped.
class WorkspaceScreen extends ConsumerWidget {
  const WorkspaceScreen({super.key, required this.identity, required this.child});

  final RepoIdentity identity;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final RepoSessionState session = ref.watch(repoSessionProvider(identity));

    if (!session.isOpen) {
      return Scaffold(
        appBar: AppBar(leading: BackButton(onPressed: () => context.go(RoutePaths.repoList))),
        body: Center(
          child: Text(session.lastError?.message ?? 'Opening repository…', style: TextStyle(color: context.gbmColors.textSecondary)),
        ),
      );
    }

    final String repoId = repoIdForRoute(identity);

    return Scaffold(
      body: Column(
        children: <Widget>[
          TopBar(
            repoName: _displayName(identity.workDir),
            repoState: session.repoState,
            isRefreshing: session.isRefreshing,
            onRefresh: () => refreshRepoHistory(ref, identity),
            onBack: () => context.go(RoutePaths.repoList),
          ),
          _TabRow(repoId: repoId),
          if (session.lastError case final error?) GbmWarningBanner(message: error.message),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SidebarPanel(identity: identity),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _displayName(String workDir) {
    final List<String> segments = workDir.split(RegExp(r'[\\/]')).where((s) => s.isNotEmpty).toList();
    return segments.isEmpty ? workDir : segments.last;
  }
}

/// Resolves the `:repoId` route segment for `identity` -- the inverse of
/// `repoIdentityFromRouteParam` in routing/app_router.dart. Kept here
/// (rather than importing app_router.dart, which would create a routing ->
/// workspace -> routing import cycle) since it is a one-line pure function.
String repoIdForRoute(RepoIdentity identity) => Uri.encodeComponent(identity.workDir);

class _TabRow extends StatelessWidget {
  const _TabRow({required this.repoId});

  final String repoId;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final String location = GoRouterState.of(context).uri.toString();
    final bool onWorkingCopy = location.endsWith('/working-copy');

    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space3),
      decoration: BoxDecoration(color: colors.surfacePanel, border: Border(bottom: BorderSide(color: colors.borderSubtle))),
      child: Row(
        children: <Widget>[
          _Tab(label: 'History', active: !onWorkingCopy, onTap: () => context.go(RoutePaths.historyFor(repoId))),
          const SizedBox(width: GbmSpacing.space4),
          _Tab(label: 'Working Copy', active: onWorkingCopy, onTap: () => context.go(RoutePaths.workingCopyFor(repoId))),
        ],
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({required this.label, required this.active, required this.onTap});

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: GbmSpacing.space2),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: active ? colors.accent : Colors.transparent, width: 2)),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: GbmTypography.textSm,
            fontWeight: GbmTypography.weightMedium,
            color: active ? colors.textPrimary : colors.textSecondary,
          ),
        ),
      ),
    );
  }
}
