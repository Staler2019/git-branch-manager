// RemotesPanel against spec page 19's PANELSPEC row for manage-remotes:
//
//   list:    remote 名稱 + URL
//   detail:  fetch / push URL、tracking ref 數、最後 fetch
//   toolbar: Add、Edit、Prune、Remove
//
// 最後 fetch is deliberately absent (no data source) and Edit is
// deliberately disabled (no capi) -- see RemotesPanel's class doc. The
// Add/Remove wiring assertions are carried over from the deleted
// manage_remotes_dialog_test.dart: the carrier changed, the guarantee that
// `git remote add`/`remove` work end-to-end did not.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/remote_info.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/panel_filter_field.dart';
import 'package:gbm_flutter/features/panels/panel_widgets.dart';
import 'package:gbm_flutter/features/panels/remotes_panel.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_repo_session.dart';
import 'panel_test_support.dart';

const RemoteInfo _origin = RemoteInfo(
  name: 'origin',
  fetchUrl: 'https://example.com/repo.git',
  pushUrl: 'https://example.com/repo.git',
);

const RemoteInfo _fork = RemoteInfo(
  name: 'fork',
  fetchUrl: 'https://example.com/fork.git',
  pushUrl: '',
);

RefInfo _remoteBranch(String fullName) => RefInfo(
  fullName: fullName,
  shortName: fullName.replaceFirst('refs/remotes/', ''),
  kind: RefKind.remoteBranch,
  target: 'abc1234',
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isGone: false,
  isHead: false,
  isSymbolic: false,
  worktreePath: '',
);

final RefSnapshot _refs = RefSnapshot(
  head: RefSnapshot.empty.head,
  refs: <RefInfo>[
    _remoteBranch('refs/remotes/origin/main'),
    _remoteBranch('refs/remotes/origin/feature/a'),
    _remoteBranch('refs/remotes/fork/main'),
    // A local branch whose name merely starts the same way must not be
    // counted -- the count is a fullName prefix match, not a name match.
    RefInfo(
      fullName: 'refs/heads/origin-mirror',
      shortName: 'origin-mirror',
      kind: RefKind.localBranch,
      target: 'abc1234',
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isGone: false,
      isHead: false,
      isSymbolic: false,
      worktreePath: '',
    ),
  ],
  refCountGuardTripped: false,
  totalRefCount: 4,
);

Future<PumpedPanel> _pump(
  WidgetTester tester, {
  List<RemoteInfo> remotes = const <RemoteInfo>[_origin, _fork],
}) => pumpPanel(
  tester,
  RemotesPanel(identity: panelTestIdentity),
  state: RepoSessionState(isOpen: true, remotes: remotes, refs: _refs),
  extraRoutes: <RouteBase>[
    GoRoute(
      path: RoutePaths.pruneRemoteBranchesDialog,
      builder: (context, state) =>
          Scaffold(body: Text('prune:${state.uri.queryParameters['remote']}')),
    ),
  ],
);

/// Types into the Add-remote dialog's field whose `labelText` is [label].
///
/// Scoped by label rather than by `find.byType(TextField).first`/`.last`,
/// which is what these tests used until the toolbar grew a filter -- also a
/// `TextField`, and one that sits *before* the dialog's fields in the tree,
/// so `.first` silently started typing the remote name into the filter box
/// ([TEST-design-system-swap-breaks-finders]). The Cancel test went on
/// passing throughout, because "addRemote was not dispatched" is true when
/// you fill in the wrong box too.
Future<void> _fill(WidgetTester tester, String label, String value) async {
  await tester.enterText(
    find.ancestor(of: find.text(label), matching: find.byType(TextField)),
    value,
  );
  await tester.pumpAndSettle();
}

Future<void> _select(WidgetTester tester, String name) async {
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

void main() {
  group('RemotesPanel (spec P19 PANELSPEC)', () {
    testWidgets(
      'the toolbar carries rule 2\'s segments, and no danger action',
      (tester) async {
        await _pump(tester);

        expectPanelTemplate(
          tester,
          primary: const <String>['Add…'],
          maintenance: const <String>['Edit…', 'Prune'],
          notOnToolbar: const <String>['Remove'],
          listHeader: 'Remotes · 2',
          statusBar: RegExp(r'^2 remotes$'),
        );
      },
    );

    testWidgets(
      'Remove sits in the detail action row, against its right edge',
      (tester) async {
        await _pump(tester);
        await _select(tester, 'fork');

        expectDangerPinnedRight(tester, 'Remove');
      },
    );

    testWidgets('the filter narrows the list, the header and the status line', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.byType(PanelListRow), findsNWidgets(2));

      await tester.enterText(
        find.descendant(
          of: find.byType(PanelFilterField),
          matching: find.byType(TextField),
        ),
        'fork',
      );
      await tester.pumpAndSettle();

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('Remotes · 1'), findsOneWidget);
      expect(find.text('2 remotes · 命中 1'), findsOneWidget);
    });

    // The URL is matched as well as the name, and this is the case that
    // tells them apart: 「repo.git」 appears only in origin's URL, so a
    // filter reading the name alone would drop it.
    testWidgets('the filter matches a URL, not only the remote name', (
      tester,
    ) async {
      await _pump(tester);

      await tester.enterText(
        find.descendant(
          of: find.byType(PanelFilterField),
          matching: find.byType(TextField),
        ),
        'repo.git',
      );
      await tester.pumpAndSettle();

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('origin'), findsOneWidget);
    });

    // Spec draws Edit; gbm_capi.h has no set-url entry point. Disabled and
    // explained beats hidden -- hiding reads as "this app cannot do it",
    // which is true, but silently.
    testWidgets('Edit is disabled and says why', (tester) async {
      await _pump(tester);

      expect(panelButton(tester, 'Edit…').onPressed, isNull);
      expect(
        tester
            .widget<Tooltip>(
              find.ancestor(
                of: find.text('Edit…'),
                matching: find.byType(Tooltip),
              ),
            )
            .message,
        contains('not supported'),
      );
    });

    // Selecting a remote must not enable it either -- an unbacked action
    // does not become backed by having a target.
    testWidgets('Edit stays disabled with a remote selected', (tester) async {
      await _pump(tester);
      await _select(tester, 'origin');

      expect(panelButton(tester, 'Edit…').onPressed, isNull);
    });

    testWidgets('the list shows each remote name over its URL', (tester) async {
      await _pump(tester);

      expect(find.text('origin'), findsOneWidget);
      expect(find.text('https://example.com/repo.git'), findsOneWidget);
      expect(find.text('fork'), findsOneWidget);
      expect(find.text('https://example.com/fork.git'), findsOneWidget);
    });

    testWidgets('the detail pane is empty until a remote is selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Select a remote to see its details'), findsOneWidget);
    });

    testWidgets('the detail pane shows fetch URL, push URL and ref count', (
      tester,
    ) async {
      await _pump(tester);
      await _select(tester, 'origin');

      expect(find.text('Fetch URL'), findsOneWidget);
      expect(find.text('Push URL'), findsOneWidget);
      expect(find.text('Tracking refs'), findsOneWidget);
      // origin/main and origin/feature/a, not fork/main and not the local
      // branch named origin-mirror.
      expect(find.text('2'), findsOneWidget);
    });

    // git reports the fetch URL as the push URL when no pushurl is set, so
    // an empty string means "not configured", not "cannot push".
    testWidgets('an unset push URL is labelled rather than left blank', (
      tester,
    ) async {
      await _pump(tester);
      await _select(tester, 'fork');

      expect(
        find.text('https://example.com/fork.git (same as fetch)'),
        findsOneWidget,
      );
    });

    testWidgets('Prune and Remove are disabled with nothing selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(panelButton(tester, 'Prune').onPressed, isNull);
      // Absent rather than disabled: rule 4 puts the action row at the
      // bottom of the *detail* column, and with nothing selected there is
      // no detail to hang it under.
      expect(find.text('Remove'), findsNothing);
      // Add… never needs a selection.
      expect(panelButton(tester, 'Add…').onPressed, isNotNull);
    });

    // Prune stays a dialog (IAMAP files it under 中型表單/確認框), and it
    // must open against the row the user selected -- landing on the dialog's
    // own "first remote" default would preview a different remote.
    testWidgets('Prune opens the prune dialog for the selected remote', (
      tester,
    ) async {
      await _pump(tester);
      await _select(tester, 'fork');
      await tester.tap(find.text('Prune'));
      await tester.pumpAndSettle();

      expect(find.text('prune:fork'), findsOneWidget);
    });

    testWidgets('Remove reaches removeRemote with that remote\'s name', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester);
      await _select(tester, 'fork');
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      final FakeCommand removed = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'removeRemote',
      );
      expect(removed.args['name'], 'fork');
    });

    testWidgets('Add… with both fields filled reaches addRemote', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester);

      await tester.tap(find.text('Add…'));
      await tester.pumpAndSettle();
      await _fill(tester, 'Name', 'upstream');
      await _fill(tester, 'URL', 'https://example.com/upstream.git');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      final FakeCommand added = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'addRemote',
      );
      expect(added.args['name'], 'upstream');
      expect(added.args['url'], 'https://example.com/upstream.git');
    });

    testWidgets('Cancel does not reach addRemote', (tester) async {
      final PumpedPanel pumped = await _pump(tester);

      await tester.tap(find.text('Add…'));
      await tester.pumpAndSettle();
      await _fill(tester, 'Name', 'upstream');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(
        pumped.fake.commandLog.where((FakeCommand c) => c.name == 'addRemote'),
        isEmpty,
      );
    });

    // Both fields are required; the prompt stays open rather than silently
    // discarding what was typed.
    testWidgets('Add with an empty URL does not reach addRemote', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester);

      await tester.tap(find.text('Add…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'upstream');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(
        pumped.fake.commandLog.where((FakeCommand c) => c.name == 'addRemote'),
        isEmpty,
      );
      expect(find.text('Add remote'), findsOneWidget);
    });

    testWidgets('a repository with no remotes says so', (tester) async {
      await _pump(tester, remotes: const <RemoteInfo>[]);

      expect(find.text('No remotes configured'), findsOneWidget);
    });
  });
}
