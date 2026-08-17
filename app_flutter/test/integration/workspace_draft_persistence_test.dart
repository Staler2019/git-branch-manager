// Integration coverage for the last uncovered "intent A -> intent B 無殘留"
// item of the approved plan: History<->Working Copy round trip must not
// lose the commit message draft. WorkingCopyView's own doc comment states
// the commit draft lives in workingCopyDraftProvider (survives tab
// switches) rather than the widget's local TextEditingController, which
// is disposed every time the ShellRoute swaps the child out for History --
// this test drives the real WorkingCopyView (via pumpWorkspace's
// workingCopyBuilder override) to prove that claim holds through an actual
// GoRouter navigation, not just a provider-level unit test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/working_copy/working_copy_view.dart';
import 'package:gbm_flutter/routing/route_paths.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

void main() {
  testWidgets(
    'commit message draft survives a History <-> Working Copy round trip',
    (tester) async {
      final pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        workingCopyBuilder: (context, state) =>
            WorkingCopyView(identity: _identity),
      );

      pumped.router.go(
        RoutePaths.workingCopyFor(Uri.encodeComponent(_identity.workDir)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WorkingCopyView), findsOneWidget);

      final Finder summaryField = find
          .descendant(
            of: find.byType(WorkingCopyView),
            matching: find.byType(TextField),
          )
          .first;
      await tester.enterText(summaryField, 'wip: draft survives tab switch');
      await tester.pumpAndSettle();

      // Navigate away -- disposes WorkingCopyView's State, and with it the
      // local TextEditingController the field above was reading from.
      pumped.router.go(
        RoutePaths.historyFor(Uri.encodeComponent(_identity.workDir)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WorkingCopyView), findsNothing);

      pumped.router.go(
        RoutePaths.workingCopyFor(Uri.encodeComponent(_identity.workDir)),
      );
      await tester.pumpAndSettle();
      expect(find.byType(WorkingCopyView), findsOneWidget);

      final TextField reopenedField = tester.widget<TextField>(
        find
            .descendant(
              of: find.byType(WorkingCopyView),
              matching: find.byType(TextField),
            )
            .first,
      );
      expect(
        reopenedField.controller?.text,
        'wip: draft survives tab switch',
        reason:
            'workingCopyDraftProvider must re-seed the freshly rebuilt '
            "WorkingCopyView's summary controller -- a new State instance "
            'must not mean a blank draft.',
      );
    },
  );
}
