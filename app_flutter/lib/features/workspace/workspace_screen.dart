import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/history_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../widgets/gbm_banner.dart';
import '../history_graph/commit_graph_view.dart';
import '../sidebar/sidebar_panel.dart';
import 'widgets/top_bar.dart';

/// The repository shell: sidebar + top bar + commit graph. The Dart analog
/// of `MainWindow` (src/app/views/MainWindow.cpp). Route `/repo/:repoId` --
/// see routing/app_router.dart. Owns the session's lifetime: opening this
/// route lazily opens the `gbm_capi` session (see
/// data/repositories/repo_session_repository.dart), and Riverpod's
/// autoDispose-free family provider is torn down (closing the session) once
/// nothing is watching it anymore, i.e. once this route is popped.
class WorkspaceScreen extends ConsumerWidget {
  const WorkspaceScreen({super.key, required this.identity});

  final RepoIdentity identity;

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
          if (session.lastError case final error?) GbmWarningBanner(message: error.message),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SidebarPanel(identity: identity),
                Expanded(child: CommitGraphView(identity: identity)),
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
