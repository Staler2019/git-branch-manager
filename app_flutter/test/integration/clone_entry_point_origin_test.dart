// R13 / R12: a clone's refusal or failure belongs to the Log of the window
// it was started from, so File → Clone repository… in a repository window
// opens the Clone dialog naming that repository as its origin.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/workspace/widgets/workspace_action_shortcuts.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

void main() {
  testWidgets('File → Clone repository… names this repository as origin', (
    tester,
  ) async {
    await pumpWorkspace(
      tester,
      identity: _identity,
      topLevelRoutes: <RouteBase>[
        GoRoute(
          path: RoutePaths.cloneRepositoryDialog,
          builder: (context, state) => Scaffold(
            body: Text('origin ${state.uri.queryParameters['origin']}'),
          ),
        ),
      ],
    );
    tester
        .widget<WorkspaceActionShortcuts>(find.byType(WorkspaceActionShortcuts))
        .handlers[GbmActionId.fileCloneRepository]!();
    await tester.pumpAndSettle();
    expect(find.text('origin /test/repo'), findsOneWidget);
  });
}
