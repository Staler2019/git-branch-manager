// SubmodulesPanel against spec page 19's PANELSPEC row for
// manage-submodules:
//
//   list:    路徑 + 目前 commit
//   detail:  URL、預期 vs 實際 commit、是否初始化
//   toolbar: Init、Update、Sync、Open
//
// 預期 commit is absent (SubmoduleInfo has no gitlink oid), and the toolbar
// deliberately carries Add…/Deinit beyond the spec'd four because
// gbm_submodule_add/_deinit have no spec'd entry point anywhere. Both are
// asserted here so a future "clean-up" reads them as decisions.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/submodule_info.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:flutter/material.dart';
import 'package:gbm_flutter/features/panels/panel_filter_field.dart';
import 'package:gbm_flutter/features/panels/panel_widgets.dart';
import 'package:gbm_flutter/features/panels/submodules_panel.dart';

import '../../support/fake_repo_session.dart';
import 'panel_test_support.dart';

const SubmoduleInfo _vendored = SubmoduleInfo(
  name: 'vendor/libgit',
  path: 'vendor/libgit',
  url: 'https://example.com/libgit.git',
  branch: 'main',
  headOid: 'a1b2c3d',
  state: SubmoduleState.modified,
);

const SubmoduleInfo _uninitialized = SubmoduleInfo(
  name: 'vendor/docs',
  path: 'vendor/docs',
  url: 'https://example.com/docs.git',
  branch: '',
  headOid: '',
  state: SubmoduleState.notInitialized,
);

Future<PumpedPanel> _pump(
  WidgetTester tester, {
  List<SubmoduleInfo> submodules = const <SubmoduleInfo>[
    _vendored,
    _uninitialized,
  ],
}) => pumpPanel(
  tester,
  SubmodulesPanel(identity: panelTestIdentity),
  state: RepoSessionState(isOpen: true, submodules: submodules),
);

Future<void> _select(WidgetTester tester, String path) async {
  await tester.tap(find.text(path));
  await tester.pumpAndSettle();
}

void main() {
  group('SubmodulesPanel (spec P19 PANELSPEC)', () {
    // PANELSPEC's four actions are all still here; what rule 2 decides is
    // *which segment* each sits in. 主要建立動作 is `Add…` -- the only
    // action that creates a submodule. `Init` is not a creation: it checks
    // out a submodule the superproject already records, which is
    // maintenance, and it is batch-shaped (`paths:`) exactly like Update and
    // Sync. `Open` leaves the panel, so it is 跳出去的動作.
    testWidgets(
      'the toolbar carries rule 2\'s segments, and no danger action',
      (tester) async {
        await _pump(tester);

        expectPanelTemplate(
          tester,
          primary: const <String>['Add…'],
          maintenance: const <String>['Init', 'Update', 'Sync'],
          external: const <String>['Open'],
          notOnToolbar: const <String>['Deinit'],
          listHeader: 'Submodules · 2',
          statusBar: RegExp(r'^2 submodules$'),
        );
      },
    );

    testWidgets(
      'Deinit sits in the detail action row, against its right edge',
      (tester) async {
        await _pump(tester);
        await _select(tester, 'vendor/libgit');

        expectDangerPinnedRight(tester, 'Deinit');
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
        'docs',
      );
      await tester.pumpAndSettle();

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('Submodules · 1'), findsOneWidget);
      expect(find.text('2 submodules · 命中 1'), findsOneWidget);
    });

    // The discriminating case for URL matching: 「libgit.git」 is in
    // _vendored's URL and in neither path (the path is 「vendor/libgit」,
    // without the .git). The test above cannot see this -- its query
    // 「docs」 is in the path as well, so a path-only filter answers it
    // correctly ([TEST-fixture-cannot-disagree]).
    testWidgets('the filter matches a URL neither path contains', (
      tester,
    ) async {
      await _pump(tester);

      await tester.enterText(
        find.descendant(
          of: find.byType(PanelFilterField),
          matching: find.byType(TextField),
        ),
        'libgit.git',
      );
      await tester.pumpAndSettle();

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('vendor/libgit'), findsWidgets);
    });

    // Not in PANELSPEC, kept on purpose: gbm_submodule_add/_deinit have no
    // other entry point in the whole spec, so matching the table exactly
    // would orphan two working capi calls.
    testWidgets('Add… and Deinit are present beyond the spec\'d four', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Add…'), findsOneWidget);
      // Deinit is destructive, so rule 2 puts it in the detail action row;
      // it exists only while a submodule is selected.
      expect(find.text('Deinit'), findsNothing);
      await _select(tester, 'vendor/libgit');
      expect(find.text('Deinit'), findsOneWidget);
    });

    testWidgets('the list shows each path over its current commit', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('vendor/libgit'), findsOneWidget);
      expect(find.text('a1b2c3d'), findsOneWidget);
    });

    // An uninitialized submodule's headOid is empty, and an empty subtitle
    // would read as a rendering bug rather than as a state.
    testWidgets('an uninitialized submodule says so instead of showing ""', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('not initialized'), findsOneWidget);
    });

    testWidgets('the detail pane is empty until a submodule is selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        find.text('Select a submodule to see its details'),
        findsOneWidget,
      );
    });

    testWidgets('the detail pane shows URL, commit and initialized state', (
      tester,
    ) async {
      await _pump(tester);
      await _select(tester, 'vendor/libgit');

      expect(find.text('URL'), findsOneWidget);
      expect(find.text('https://example.com/libgit.git'), findsOneWidget);
      expect(find.text('Current commit'), findsOneWidget);
      expect(find.text('Initialized'), findsOneWidget);
      // `state` is what survives of 預期 vs 實際: modified *means* they differ.
      expect(find.text('Yes · modified'), findsOneWidget);
    });

    testWidgets('the four spec\'d actions are disabled with no selection', (
      tester,
    ) async {
      await _pump(tester);

      for (final String label in const <String>[
        'Init',
        'Update',
        'Sync',
        'Open',
      ]) {
        expect(panelButton(tester, label).onPressed, isNull, reason: label);
      }
      // Add… creates a new one, so it never needs a selection.
      expect(panelButton(tester, 'Add…').onPressed, isNotNull);
    });

    // A never-initialized submodule's directory exists but is empty --
    // opening it would show the user nothing and look broken.
    testWidgets('Open stays disabled for an uninitialized submodule', (
      tester,
    ) async {
      await _pump(tester);
      await _select(tester, 'vendor/docs');

      expect(panelButton(tester, 'Init').onPressed, isNotNull);
      expect(panelButton(tester, 'Open').onPressed, isNull);
    });

    testWidgets('Update dispatches for the selected path with init', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester);
      await _select(tester, 'vendor/libgit');
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'updateSubmodules',
      );
      expect(cmd.args['paths'], <String>['vendor/libgit']);
      expect(cmd.args['init'], isTrue);
    });

    testWidgets('a repository with no submodules says so', (tester) async {
      await _pump(tester, submodules: const <SubmoduleInfo>[]);

      expect(find.text('No submodules'), findsOneWidget);
    });
  });
}
