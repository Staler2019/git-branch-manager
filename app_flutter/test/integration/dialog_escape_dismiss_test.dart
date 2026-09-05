// worktree-dialogs-spec.html's G5 work item ("拿掉 ✕ 關閉鈕，改靠
// Escape") rests on a premise the spec states as fact ("Esc already
// closes") but this repo had never pinned with a test: gbm_dialog_shell.dart
// itself has no Escape/Shortcuts code at all, and dialog_route.dart's own
// doc comment *claims* "consistent Esc/back dismissal" as prose, not as
// something a test enforces. Before G5a can remove the only visible close
// affordance, this file turns that claim into a fact a red would actually
// catch.
//
// It works because every routed dialog goes through `dialogRoute()`
// (routing/dialog_route.dart), which sets `barrierDismissible: true` on the
// underlying `CustomTransitionPage`/`ModalRoute`. Flutter's own
// `_ModalScope` (widgets/routes.dart) wraps every `ModalRoute`'s content in
// an `Actions` block binding `DismissIntent` to a `_DismissModalAction` that
// pops when `route.barrierDismissible` is true, and `WidgetsApp` binds
// `LogicalKeyboardKey.escape` to `DismissIntent` in its default shortcut
// map -- so Escape dismissing a `barrierDismissible` route is a Flutter
// framework guarantee, not something `GbmDialogShell` or `dialogRoute()`
// implement themselves. This test exists to catch a regression of *that*
// wiring (e.g. `barrierDismissible` flipped to false, or a future dialog
// route built without `dialogRoute()`), not to newly implement it.
//
// Three representative dialogs, per [TEST-tiers]'s integration-tier
// requirement to cross the real seam rather than pumping a bare widget:
// Create Tag (the simplest -- no pre-fill, no nested interactive controls),
// Rename Branch (a TextField, so Escape must not be swallowed by text-field
// focus first), Checkout (a RadioGroup of nested RadioListTiles, the
// "does a nested Shortcuts-like control eat the key" case).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/dialogs/checkout/checkout_dialog.dart';
import 'package:gbm_flutter/features/dialogs/create_tag/create_tag_dialog.dart';
import 'package:gbm_flutter/features/dialogs/rename_branch/rename_branch_dialog.dart';
import 'package:gbm_flutter/routing/dialog_route.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

final String _repoId = Uri.encodeComponent(_identity.workDir);

// Rename Branch's `widget.branchName ?? session.refs.head.branchName`
// resolves to a local branch that has to actually exist in the session's
// refs, or the dialog draws its "not found" fallback (no TextField) instead
// of the rename form -- this is what a real repository looks like from
// this dialog's point of view.
final RepoSessionState _stateWithBranch = RepoSessionState(
  isOpen: true,
  refs: RefSnapshot(
    head: HeadInfo(
      kind: HeadKind.branch,
      branchName: 'main',
      fullRef: 'refs/heads/main',
      target: 'a' * 40,
    ),
    refs: <RefInfo>[
      RefInfo(
        fullName: 'refs/heads/main',
        shortName: 'main',
        kind: RefKind.localBranch,
        target: 'a' * 40,
        upstream: '',
        ahead: 0,
        behind: 0,
        hasTrackingInfo: false,
        isGone: false,
        isHead: true,
        isSymbolic: false,
        worktreePath: '',
      ),
    ],
    refCountGuardTripped: false,
    totalRefCount: 1,
  ),
);

final List<RouteBase> _dialogRoutes = <RouteBase>[
  dialogRoute(
    path: RoutePaths.createTagDialog,
    builder: (context, state) => CreateTagDialogContent(identity: _identity),
  ),
  dialogRoute(
    path: RoutePaths.renameBranchDialog,
    builder: (context, state) => RenameBranchDialogContent(identity: _identity),
  ),
  dialogRoute(
    path: RoutePaths.checkoutDialog,
    builder: (context, state) => CheckoutDialogContent(identity: _identity),
  ),
];

Future<void> _pressEscape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
}

void main() {
  group('Escape dismisses a routed dialog', () {
    testWidgets('Create Tag', (tester) async {
      final pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _stateWithBranch,
        topLevelRoutes: _dialogRoutes,
      );

      pumped.router.push(RoutePaths.createTagDialogFor(_repoId));
      await tester.pumpAndSettle();
      expect(find.byType(CreateTagDialogContent), findsOneWidget);

      await _pressEscape(tester);

      expect(find.byType(CreateTagDialogContent), findsNothing);
    });

    testWidgets('Rename Branch -- a TextField does not swallow Escape', (
      tester,
    ) async {
      final pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _stateWithBranch,
        topLevelRoutes: _dialogRoutes,
      );

      pumped.router.push(RoutePaths.renameBranchDialogFor(_repoId));
      await tester.pumpAndSettle();
      expect(find.byType(RenameBranchDialogContent), findsOneWidget);

      // Focus the field first -- the case where Escape would be swallowed
      // by the field's own editing shortcuts before it ever reaches the
      // modal's DismissIntent binding. Scoped to the dialog's own subtree:
      // the sidebar underneath it (still mounted -- the dialog route is
      // non-opaque) has its own filter TextField, and an unscoped
      // find.byType(TextField).first can silently match that one instead.
      await tester.tap(
        find
            .descendant(
              of: find.byType(RenameBranchDialogContent),
              matching: find.byType(TextField),
            )
            .first,
      );
      await tester.pump();

      await _pressEscape(tester);

      expect(find.byType(RenameBranchDialogContent), findsNothing);
    });

    testWidgets('Checkout -- a nested RadioGroup does not swallow Escape', (
      tester,
    ) async {
      final pumped = await pumpWorkspace(
        tester,
        identity: _identity,
        initialState: _stateWithBranch,
        topLevelRoutes: _dialogRoutes,
      );

      pumped.router.push(RoutePaths.checkoutDialogFor(_repoId));
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutDialogContent), findsOneWidget);

      await _pressEscape(tester);

      expect(find.byType(CheckoutDialogContent), findsNothing);
    });
  });
}
