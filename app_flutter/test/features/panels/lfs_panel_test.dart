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

void main() {
  group('LfsPanel (spec P19 PANELSPEC)', () {
    testWidgets('the toolbar carries PANELSPEC\'s four actions', (
      tester,
    ) async {
      await _pump(tester);

      for (final String label in const <String>[
        'Track…',
        'Untrack',
        'Fetch',
        'Prune',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

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

    testWidgets('Untrack is disabled with no pattern selected', (tester) async {
      await _pump(tester);

      expect(panelButton(tester, 'Untrack').onPressed, isNull);
      // Fetch and Prune act on the repository, not on a selection.
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
      // must not survive pointing at it.
      expect(panelButton(tester, 'Untrack').onPressed, isNull);
    });

    testWidgets('Track… reveals a field that dispatches trackLfsPattern', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester);

      await tester.tap(find.text('Track…'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '*.mp4');
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

    testWidgets('a repository with no tracked patterns says so', (
      tester,
    ) async {
      await _pump(tester, patterns: const <String>[]);

      expect(find.text('No tracked patterns'), findsOneWidget);
    });
  });
}
