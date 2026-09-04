// StashesPanel against spec page 19's PANELSPEC row for manage-stashes:
//
//   list:    stash 編號 + 訊息 + 時間
//   detail:  檔案清單 + diff（唯讀）
//   toolbar: Apply、Pop、Drop、Create
//
// The dialog this replaces put Apply/Pop/Drop inside every row; P19 puts
// them in the toolbar acting on the selection, so the tests that matter
// most here are the selection gates -- a Drop that fires against no
// selection, or against a stale index after a pop, is irreversible.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/models/stash_entry.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:flutter/material.dart';
import 'package:gbm_flutter/features/panels/panel_file_diff_detail.dart';
import 'package:gbm_flutter/features/panels/panel_filter_field.dart';
import 'package:gbm_flutter/features/panels/panel_widgets.dart';
import 'package:gbm_flutter/features/panels/stashes_panel.dart';

import '../../support/fake_repo_session.dart';
import 'panel_test_support.dart';

const StashEntry _stash0 = StashEntry(
  index: 0,
  message: 'WIP on main: 9be5523 tab row',
  oid: 'aaaaaaa',
  timestamp: 1755000000,
);

const StashEntry _stash1 = StashEntry(
  index: 1,
  message: 'debug logging',
  oid: 'bbbbbbb',
  timestamp: 1754000000,
);

const List<StashEntry> _stashes = <StashEntry>[_stash0, _stash1];

const DiffFile _file = DiffFile(
  oldPath: 'lib/main.dart',
  newPath: 'lib/main.dart',
  kind: FileChangeKind.modified,
  oldMode: '100644',
  newMode: '100644',
  oldBlob: 'aaa',
  newBlob: 'bbb',
  binary: false,
  similarity: 0,
  addedLines: 1,
  removedLines: 0,
  displayPath: 'lib/main.dart',
  hunks: <DiffHunk>[],
);

const StashDiffReply _diffOfStash1 = StashDiffReply(
  index: 1,
  diff: ParsedDiff(files: <DiffFile>[_file], truncated: false, inputBytes: 42),
);

Future<PumpedPanel> _pump(
  WidgetTester tester, {
  List<StashEntry> stashes = _stashes,
  StashDiffReply? diff,
  int? initialSelectedIndex,
}) => pumpPanel(
  tester,
  StashesPanel(
    identity: panelTestIdentity,
    initialSelectedIndex: initialSelectedIndex,
  ),
  state: RepoSessionState(isOpen: true, stashes: stashes, lastStashDiff: diff),
);

void main() {
  group('StashesPanel (spec P19 PANELSPEC)', () {
    // The same seven template facts every P19 panel states, through the
    // shared assertion. `Drop` is the one PANELSPEC action that is NOT on
    // the toolbar: rule 2 sends 破壞性動作 to the detail action row, and the
    // boundary this repo draws is 「毀掉使用者拿不回來的東西」 -- `Pop`
    // deletes the stash too, but only after applying it to the work tree,
    // and the ref survives in the stash reflog, so it stays in maintenance.
    testWidgets(
      'the toolbar carries rule 2\'s segments, and no danger action',
      (tester) async {
        await _pump(tester);

        expectPanelTemplate(
          tester,
          primary: const <String>['Create…'],
          maintenance: const <String>['Apply', 'Pop'],
          notOnToolbar: const <String>['Drop'],
          listHeader: 'Stashes · 2',
          statusBar: RegExp(r'^2 stashes$'),
        );
      },
    );

    testWidgets('Drop sits in the detail action row, against its right edge', (
      tester,
    ) async {
      await _pump(tester, diff: _diffOfStash1);
      await tester.tap(find.text('stash@{1}: debug logging'));
      await tester.pumpAndSettle();

      expectDangerPinnedRight(tester, 'Drop');
    });

    // 「接了卻不篩的 filter 是會說謊的控制項」 -- the predicate, the header
    // count and the status line's 命中 clause together, the same way the
    // reference panel states it.
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
        'debug',
      );
      await tester.pumpAndSettle();

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('stash@{1}: debug logging'), findsOneWidget);
      expect(find.text('Stashes · 1'), findsOneWidget);
      expect(find.text('2 stashes · 命中 1'), findsOneWidget);
    });

    testWidgets('the list shows stash number, message and time per row', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        find.text('stash@{0}: WIP on main: 9be5523 tab row'),
        findsOneWidget,
      );
      expect(find.text('stash@{1}: debug logging'), findsOneWidget);
      // 時間: rendered through the same formatter the commit graph uses,
      // so this asserts a row carries one rather than re-testing its text.
      expect(find.textContaining('20'), findsWidgets);
    });

    testWidgets('the detail pane is empty until a stash is selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Select a stash to see its changes'), findsOneWidget);
      expect(find.byType(PanelFileDiffDetail), findsNothing);
    });

    testWidgets('selecting a stash requests its diff and renders it', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester, diff: _diffOfStash1);

      await tester.tap(find.text('stash@{1}: debug logging'));
      await tester.pumpAndSettle();

      expect(
        pumped.fake.commandLog.where(
          (FakeCommand c) => c.name == 'requestStashDiff',
        ),
        hasLength(1),
      );
      expect(find.byType(PanelFileDiffDetail), findsOneWidget);
      // 檔案清單: the diff carries its own per-file header.
      expect(find.text('lib/main.dart'), findsOneWidget);
    });

    // Drop is now *absent* rather than disabled with nothing selected, and
    // that is rule 4 rather than a regression: the action row lives at the
    // bottom of the detail column, and with no stash selected there is no
    // detail to put it under. Stated as `findsNothing` rather than as a null
    // `onPressed`, because those are different claims and only one of them
    // is true now ([FLU-menu-enabled-is-visual-only] is about a *rendered*
    // control that must say it is unavailable; this one is not rendered).
    testWidgets('Apply and Pop are disabled with nothing selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(panelButton(tester, 'Apply').onPressed, isNull);
      expect(panelButton(tester, 'Pop').onPressed, isNull);
      expect(find.text('Drop'), findsNothing);
      // Create… never depends on a selection -- it makes a new stash.
      expect(panelButton(tester, 'Create…').onPressed, isNotNull);
    });

    // The diff is seeded so the detail pane is not the loading spinner --
    // an indeterminate CircularProgressIndicator animates forever, and
    // pumpAndSettle times out rather than failing the real assertion.
    testWidgets('Drop dispatches against the selected stash', (tester) async {
      final PumpedPanel pumped = await _pump(tester, diff: _diffOfStash1);

      await tester.tap(find.text('stash@{1}: debug logging'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Drop'));
      await tester.pumpAndSettle();

      final FakeCommand drop = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'dropStash',
      );
      expect(drop.args['index'], 1);
      // Dropping shifts every higher index down, so the selection must
      // clear rather than silently point at a different stash -- and with
      // the selection gone the whole detail action row goes with it.
      expect(find.text('Drop'), findsNothing);
    });

    // The sidebar's 05-H "View diff" opens this panel with ?select=N, and
    // re-opening focuses the existing tab instead of mounting a new one --
    // so the pre-selection has to survive arriving as a widget update.
    testWidgets('initialSelectedIndex preselects and requests that diff', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        diff: _diffOfStash1,
        initialSelectedIndex: 1,
      );

      expect(find.byType(PanelFileDiffDetail), findsOneWidget);
      expect(
        pumped.fake.commandLog.where(
          (FakeCommand c) => c.name == 'requestStashDiff',
        ),
        hasLength(1),
      );
    });

    // Indices shift after a pop or an external drop. A selection that no
    // longer exists must fall back to "nothing selected".
    testWidgets('a selection that no longer exists disables the toolbar', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        diff: _diffOfStash1,
        initialSelectedIndex: 1,
      );

      expect(panelButton(tester, 'Apply').onPressed, isNotNull);

      pumped.fake.emit(
        const RepoSessionState(isOpen: true, stashes: <StashEntry>[_stash0]),
      );
      await tester.pumpAndSettle();

      expect(panelButton(tester, 'Apply').onPressed, isNull);
      expect(find.text('Drop'), findsNothing);
    });

    testWidgets('an empty repository shows an empty-list message', (
      tester,
    ) async {
      await _pump(tester, stashes: const <StashEntry>[]);

      expect(find.text('No stashes'), findsOneWidget);
    });
  });
}
