// The `target` query parameter that lets 05-B's "Rebase current onto here"
// and 05-E's "Rebase onto here" / "Reset branch to here…" open a dialog
// already aimed at the row that was right-clicked, instead of making the
// user re-pick what they just chose.
//
// Mirrors renameBranchDialogFor's shape, which is the template these two
// follow.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/rebase_onto/rebase_onto_dialog.dart';
import 'package:gbm_flutter/features/dialogs/reset_branch/reset_branch_dialog.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');
const String _oid = 'abcdef0123456789abcdef0123456789abcdef01';

RefInfo _branch(String name) => RefInfo(
  fullName: 'refs/heads/$name',
  shortName: name,
  kind: RefKind.localBranch,
  target: 'f' * 40,
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: name == 'main',
  isSymbolic: false,
  worktreePath: '',
);

RepoSessionState _state() => RepoSessionState(
  isOpen: true,
  refs: RefSnapshot(
    head: const HeadInfo(
      kind: HeadKind.branch,
      branchName: 'main',
      fullRef: 'refs/heads/main',
      target: 'f',
    ),
    refs: <RefInfo>[_branch('main'), _branch('feature')],
    refCountGuardTripped: false,
    totalRefCount: 2,
  ),
);

Future<void> _pump(WidgetTester tester, Widget dialog) async {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      repoSessionProvider(
        _identity,
      ).overrideWith((ref) => FakeRepoSessionController(_identity, _state())),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(body: dialog),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('route helpers', () {
    test('omit the query parameter entirely when there is no target', () {
      expect(
        RoutePaths.resetBranchDialogFor('r'),
        '/repo/r/dialogs/reset-branch',
      );
      expect(
        RoutePaths.rebaseOntoDialogFor('r'),
        '/repo/r/dialogs/rebase-onto',
      );
    });

    test('carry the target when given one', () {
      expect(
        RoutePaths.resetBranchDialogFor('r', target: _oid),
        '/repo/r/dialogs/reset-branch?target=$_oid',
      );
      expect(
        RoutePaths.rebaseOntoDialogFor('r', target: 'feature'),
        '/repo/r/dialogs/rebase-onto?target=feature',
      );
    });
  });

  group('ResetBranchDialogContent', () {
    testWidgets('pre-fills the target field when given one', (tester) async {
      await _pump(
        tester,
        ResetBranchDialogContent(identity: _identity, target: _oid),
      );
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        _oid,
      );
    });

    testWidgets('falls back to the current branch with no target', (
      tester,
    ) async {
      await _pump(tester, ResetBranchDialogContent(identity: _identity));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'main',
      );
    });
  });

  group('RebaseOntoDialogContent', () {
    testWidgets('pre-selects a branch target that is already an option', (
      tester,
    ) async {
      await _pump(
        tester,
        RebaseOntoDialogContent(identity: _identity, target: 'feature'),
      );
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .initialValue,
        'feature',
      );
    });

    testWidgets('adds a commit oid as its own option rather than dropping '
        'a target the user explicitly picked', (tester) async {
      // The dropdown lists branches only; without the synthetic entry
      // DropdownButtonFormField asserts on an initialValue that is not
      // among its items.
      await _pump(
        tester,
        RebaseOntoDialogContent(identity: _identity, target: _oid),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('commit ${_oid.substring(0, 8)}'), findsOneWidget);
    });

    testWidgets('leaves Start rebase disabled with no target at all', (
      tester,
    ) async {
      await _pump(tester, RebaseOntoDialogContent(identity: _identity));
      expect(
        tester
            .widget<DropdownButtonFormField<String>>(
              find.byType(DropdownButtonFormField<String>),
            )
            .initialValue,
        isNull,
      );
    });
  });
}
