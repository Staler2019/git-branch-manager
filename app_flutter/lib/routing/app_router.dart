import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/repositories/repo_identity.dart';
import '../features/repo_list/repo_list_screen.dart';
import '../features/workspace/workspace_screen.dart';
import 'route_paths.dart';

/// `repoId` in the route is the URL-encoded working-directory path -- simple
/// and sufficient while a "repository" is identified by nothing more than
/// its work tree (see [RepoIdentity]); a real opaque id (matching
/// `RepoRecord.id` from the discovery database) can replace this once
/// `features/repo_list` reads from `discoveryProvider` instead of manual
/// entry (M1's known limitation, see repo_list_screen.dart).
String repoIdFor(String workDir) => Uri.encodeComponent(workDir);

RepoIdentity repoIdentityFromRouteParam(String repoId) => RepoIdentity.forWorkDir(Uri.decodeComponent(repoId));

/// Only `/` and `/repo/:repoId` exist so far -- see the plan's routing-table
/// section for the full design (`/repo/:repoId/history|diff/:commitId|
/// working-copy` nested routes, `/repo/:repoId/conflicts`, and the 30+
/// `/repo/:repoId/dialogs/<name>` routes), added milestone by milestone as
/// the screens behind them are implemented.
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: RoutePaths.repoList,
    routes: <RouteBase>[
      GoRoute(path: RoutePaths.repoList, builder: (context, state) => const RepoListScreen()),
      GoRoute(
        path: RoutePaths.workspace,
        builder: (context, state) {
          final String repoId = state.pathParameters['repoId']!;
          return WorkspaceScreen(identity: repoIdentityFromRouteParam(repoId));
        },
      ),
    ],
  );
});
