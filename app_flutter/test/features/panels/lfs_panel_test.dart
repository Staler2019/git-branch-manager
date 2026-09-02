// LfsPanel against spec page 19's PANELSPEC row for manage-lfs:
//
//   list:    追蹤型別 + 檔數 + 大小
//   detail:  對應檔案、本地快取狀態
//   toolbar: Track、Untrack、Fetch、Prune
//
// 大小 is absent (LfsFileInfo carries no byte count), 檔數 is derived via
// lfsPatternMatches, and Pull is a fifth toolbar button on purpose -- see
// LfsPanel's class doc. All three are asserted so a later "clean-up" reads
// them as decisions rather than as drift.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/lfs_state.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/lfs_panel.dart';
import 'package:gbm_flutter/features/panels/panel_filter_field.dart';
import 'package:gbm_flutter/features/panels/panel_widgets.dart';

import '../../support/fake_repo_session.dart';
import 'panel_test_support.dart';

const List<String> _patterns = <String>['*.psd', 'models/'];

const List<LfsFileInfo> _files = <LfsFileInfo>[
  LfsFileInfo(path: 'art/logo.psd', oid: 'aaa', downloadedLocally: true),
  LfsFileInfo(path: 'art/hero.psd', oid: 'bbb', downloadedLocally: false),
  LfsFileInfo(path: 'models/big.onnx', oid: 'ccc', downloadedLocally: true),
];

Future<PumpedPanel> _pump(
  WidgetTester tester, {
  List<String> patterns = _patterns,
  List<LfsFileInfo> files = _files,
  LfsInstallation? installation = const LfsInstallation(
    available: true,
    version: '3.4.0',
  ),
}) => pumpPanel(
  tester,
  LfsPanel(identity: panelTestIdentity),
  state: RepoSessionState(
    isOpen: true,
    lfsPatterns: patterns,
    lfsFiles: files,
    lfsInstallation: installation,
  ),
);

Future<void> _filter(WidgetTester tester, String query) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(PanelFilterField),
      matching: find.byType(TextField),
    ),
    query,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('LfsPanel (spec P19 PANELSPEC)', () {
    // PANELSPEC's toolbar cell lists four actions; P19 rule 2 says 破壞性
    // 動作不放工具列. Three of the four are on the toolbar and `Untrack` is
    // not -- the same reconciliation the round applied to worktrees'
    // `Remove`, stashes' `Drop` and submodules' `Deinit`. The four-word
    // cell is a list of the panel's *actions*, not a claim about where each
    // one sits; rule 2 is the more specific statement about position.
    testWidgets(
      'all four PANELSPEC actions exist, three of them on the toolbar',
      (tester) async {
        await _pump(tester);

        for (final String label in const <String>['Track…', 'Fetch', 'Prune']) {
          expect(find.text(label), findsOneWidget, reason: label);
        }

        // Present, but only once a pattern is selected -- see the detail
        // action row test below.
        expect(find.text('Untrack'), findsNothing);
        await tester.tap(find.text('*.psd'));
        await tester.pumpAndSettle();
        expect(find.text('Untrack'), findsOneWidget);
      },
    );

    // Fetch only fills the object cache; without Pull the working tree keeps
    // its pointer files, so dropping Pull to match the table would leave the
    // repository unusable for LFS content.
    testWidgets('Pull is present beyond the spec\'d four', (tester) async {
      await _pump(tester);

      expect(find.text('Pull'), findsOneWidget);
      expect(panelButton(tester, 'Pull').onPressed, isNotNull);
    });

    testWidgets('the list shows each pattern over its derived file count', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('*.psd'), findsOneWidget);
      expect(find.text('2 files'), findsOneWidget);
      expect(find.text('models/'), findsOneWidget);
      // Singular, not "1 files".
      expect(find.text('1 file'), findsOneWidget);
    });

    testWidgets('the detail pane is empty until a pattern is selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        find.text('Select a tracked pattern to see its files'),
        findsOneWidget,
      );
    });

    testWidgets('selecting a pattern lists its files with cache state', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('*.psd'));
      await tester.pumpAndSettle();

      expect(find.text('art/logo.psd'), findsOneWidget);
      expect(find.text('art/hero.psd'), findsOneWidget);
      // models/big.onnx belongs to the other pattern.
      expect(find.text('models/big.onnx'), findsNothing);
      expect(find.text('cached'), findsOneWidget);
      expect(find.text('pointer only'), findsOneWidget);
    });

    // Was 「Untrack is disabled」 while it lived on the toolbar. Under P19
    // rule 4 it is in the detail action row, and the shell draws no action
    // row over an empty detail -- so with nothing selected the correct
    // assertion is that the button is *absent*, not that it is greyed.
    testWidgets('Untrack is absent with no pattern selected', (tester) async {
      await _pump(tester);

      expect(find.text('Untrack'), findsNothing);
      // Fetch and Prune act on the repository, not on a selection, so they
      // stay enabled on the toolbar with nothing selected.
      expect(panelButton(tester, 'Fetch').onPressed, isNotNull);
      expect(panelButton(tester, 'Prune').onPressed, isNotNull);
    });

    testWidgets('Untrack dispatches the selected pattern', (tester) async {
      final PumpedPanel pumped = await _pump(tester);
      await tester.tap(find.text('models/'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Untrack'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'untrackLfsPattern',
      );
      expect(cmd.args['pattern'], 'models/');
      // The pattern is about to disappear from the list, so the selection
      // must not survive pointing at it -- and with the selection gone the
      // detail is empty, which takes the whole action row with it.
      expect(find.text('Untrack'), findsNothing);
    });

    testWidgets('Track… reveals a field that dispatches trackLfsPattern', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester);

      await tester.tap(find.text('Track…'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.ancestor(
          of: find.text('Pattern (e.g. *.psd)'),
          matching: find.byType(TextField),
        ),
        '*.mp4',
      );
      await tester.tap(find.text('Track'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'trackLfsPattern',
      );
      expect(cmd.args['pattern'], '*.mp4');
    });

    // Every action in this panel fails without git-lfs, so the state has to
    // say so and offer the fix rather than showing an empty pattern list.
    testWidgets('an uninstalled LFS shows an install affordance', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        installation: const LfsInstallation(available: false, version: ''),
      );

      expect(
        find.text('Git LFS is not installed for this repository'),
        findsOneWidget,
      );
      await tester.tap(find.text('Install for this repository'));
      await tester.pumpAndSettle();

      expect(
        pumped.fake.commandLog.where((FakeCommand c) => c.name == 'installLfs'),
        hasLength(1),
      );
    });

    testWidgets('the toolbar follows P19 rule 2\'s four segments', (
      tester,
    ) async {
      await _pump(tester);

      expectPanelTemplate(
        tester,
        primary: const <String>['Track…'],
        maintenance: const <String>['Fetch', 'Prune', 'Pull'],
        notOnToolbar: const <String>['Untrack'],
        listHeader: 'Tracked patterns · 2',
        statusBar: RegExp(r'^2 patterns$'),
      );
    });

    testWidgets(
      'Untrack sits in the detail action row, against its right edge',
      (tester) async {
        await _pump(tester);
        await tester.tap(find.text('*.psd'));
        await tester.pumpAndSettle();

        expectDangerPinnedRight(tester, 'Untrack');
      },
    );

    testWidgets('the filter narrows the list, the header and the status line', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.byType(PanelListRow), findsNWidgets(2));

      await _filter(tester, 'psd');

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('*.psd'), findsOneWidget);
      expect(find.text('Tracked patterns · 1'), findsOneWidget);
      expect(find.text('2 patterns · 命中 1'), findsOneWidget);
    });

    // The discriminating case. This list's rows are *patterns*, and a
    // plausible alternative reading -- filter by the files a pattern claims
    // -- answers every query that appears in both identically: 「psd」 is in
    // `*.psd` and in `art/logo.psd`, 「models」 in `models/` and in
    // `models/big.onnx`. 「logo」 is in a file path and in no pattern, so it
    // is the only query that tells the two implementations apart
    // ([TEST-fixture-cannot-disagree]).
    testWidgets('a word that is only in a file path matches no pattern', (
      tester,
    ) async {
      await _pump(tester);

      await _filter(tester, 'logo');

      expect(find.byType(PanelListRow), findsNothing);
      expect(find.text('2 patterns · 命中 0'), findsOneWidget);
    });

    // 「No tracked patterns」 would be a lie here -- there are two, the
    // filter is hiding them.
    testWidgets('a filter that hides everything says so, not "none tracked"', (
      tester,
    ) async {
      await _pump(tester);

      await _filter(tester, 'zzz');

      expect(find.text('No pattern matches the filter'), findsOneWidget);
      expect(find.text('No tracked patterns'), findsNothing);
    });

    testWidgets('a repository with no tracked patterns says so', (
      tester,
    ) async {
      await _pump(tester, patterns: const <String>[]);

      expect(find.text('No tracked patterns'), findsOneWidget);
    });
  });
}
