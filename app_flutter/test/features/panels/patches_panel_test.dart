// PatchesPanel against spec page 19's PANELSPEC row for patches:
//
//   list:    .patch 檔或待建清單
//   detail:  patch 內容 diff 預覽
//   toolbar: Create from commits、Apply…、Save as
//
// The list genuinely holds both kinds of row ("或"), which is what most of
// these assert. Import… is a fourth button on purpose -- gbm_patch_import
// and its three sequencer calls have no spec'd entry point.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/list_selection.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/history_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/services/file_save_picker.dart';
import 'package:gbm_flutter/features/panels/panel_diff_text.dart';
import 'package:gbm_flutter/features/panels/patch_text_loader.dart';
import 'package:gbm_flutter/features/panels/panel_filter_field.dart';
import 'package:gbm_flutter/features/panels/panel_widgets.dart';
import 'package:gbm_flutter/features/panels/patches_panel.dart';

import '../../support/fake_repo_session.dart';
import 'panel_test_support.dart';

const Signature _who = Signature(
  name: 'Ada',
  email: 'ada@example.com',
  when: 1755000000,
  tzOffsetMinutes: 0,
);

const CommitMeta _meta = CommitMeta(
  oid: 'aaaaaaa',
  tree: 't',
  parents: <String>[],
  author: _who,
  committer: _who,
  subject: 'add the guard',
  body: '',
  signedCommit: false,
);

const String _patchText =
    'diff --git a/lib/main.dart b/lib/main.dart\n'
    '@@ -1,2 +1,2 @@\n'
    '-old line\n'
    '+new line\n';

/// Records what was asked for and answers with canned paths, so no native
/// modal ever opens during a test run.
class _FakePicker implements FileSavePicker {
  _FakePicker({this.files = const <String>[], this.directory});

  final List<String> files;
  final String? directory;
  int openFilesCalls = 0;
  int pickDirectoryCalls = 0;

  @override
  Future<List<String>> openFiles({
    List<String> extensions = const <String>[],
  }) async {
    openFilesCalls++;
    return files;
  }

  @override
  Future<String?> pickDirectory() async {
    pickDirectoryCalls++;
    return directory;
  }

  @override
  Future<String?> saveFile({required String suggestedName}) async => null;
}

Future<PumpedPanel> _pump(
  WidgetTester tester, {
  _FakePicker? picker,
  List<String> selectedCommits = const <String>[],
  String patchText = _patchText,
  Object? loadError,
}) => pumpPanel(
  tester,
  PatchesPanel(identity: panelTestIdentity),
  state: const RepoSessionState(
    isOpen: true,
    commitMetaCache: <String, CommitMeta>{'aaaaaaa': _meta},
  ),
  overrides: <Override>[
    fileSavePickerProvider.overrideWithValue(picker ?? _FakePicker()),
    patchTextLoaderProvider.overrideWithValue((String path) async {
      if (loadError != null) throw loadError;
      return patchText;
    }),
    commitSelectionProvider(panelTestIdentity).overrideWith(
      (ref) => ListSelection<String>(
        items: selectedCommits,
        anchor: selectedCommits.isEmpty ? null : selectedCommits.first,
      ),
    ),
  ],
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

/// Applies two `.patch` files whose **basenames share no word with the
/// directory that holds one of them**, which is what lets the filter tests
/// tell「比對檔名」from「比對整個路徑」apart.
Future<PumpedPanel> _pumpTwoFiles(WidgetTester tester) async {
  final PumpedPanel pumped = await _pump(
    tester,
    picker: _FakePicker(
      files: const <String>[
        '/tmp/vendor/0001-fix.patch',
        '/tmp/0002-add.patch',
      ],
    ),
  );
  await tester.tap(find.text('Apply…'));
  await tester.pumpAndSettle();
  return pumped;
}

void main() {
  group('PatchesPanel (spec P19 PANELSPEC)', () {
    testWidgets('the toolbar carries PANELSPEC\'s three actions', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Create from commits'), findsOneWidget);
      expect(find.text('Apply…'), findsOneWidget);
      expect(find.text('Save as…'), findsOneWidget);
    });

    // No entry point anywhere in the spec, and dropping it would orphan
    // gbm_patch_import plus its continue/skip/abort.
    testWidgets('Import… is present beyond the spec\'d three', (tester) async {
      await _pump(tester);

      expect(find.text('Import…'), findsOneWidget);
    });

    testWidgets('an empty panel says where a patch comes from', (tester) async {
      await _pump(tester);

      expect(
        find.text('Select commits in History, or apply a .patch file'),
        findsOneWidget,
      );
      expect(panelButton(tester, 'Create from commits').onPressed, isNull);
      expect(panelButton(tester, 'Save as…').onPressed, isNull);
    });

    // 待建清單: commits queued for export are rows in the same list as
    // files, which is what P19's 「或」 asks for.
    testWidgets('Create from commits queues the History selection', (
      tester,
    ) async {
      await _pump(tester, selectedCommits: const <String>['aaaaaaa']);
      await tester.tap(find.text('Create from commits'));
      await tester.pumpAndSettle();

      // The subject comes from commitMetaCache, not the raw oid.
      expect(find.text('add the guard'), findsOneWidget);
      expect(find.textContaining('To be created'), findsOneWidget);
    });

    testWidgets('a queued commit has no preview until it is written', (
      tester,
    ) async {
      await _pump(tester, selectedCommits: const <String>['aaaaaaa']);
      await tester.tap(find.text('Create from commits'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('add the guard'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Not written yet'), findsOneWidget);
      expect(find.byType(PanelDiffText), findsNothing);
    });

    testWidgets('Save as… exports the queued commits to a chosen directory', (
      tester,
    ) async {
      final _FakePicker picker = _FakePicker(directory: '/tmp/out');
      final PumpedPanel pumped = await _pump(
        tester,
        picker: picker,
        selectedCommits: const <String>['aaaaaaa'],
      );
      await tester.tap(find.text('Create from commits'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as…'));
      await tester.pumpAndSettle();

      expect(picker.pickDirectoryCalls, 1);
      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'exportPatches',
      );
      expect(cmd.args['commitHexes'], <String>['aaaaaaa']);
      expect(cmd.args['outputDir'], '/tmp/out');
    });

    testWidgets('cancelling the directory picker exports nothing', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        picker: _FakePicker(),
        selectedCommits: const <String>['aaaaaaa'],
      );
      await tester.tap(find.text('Create from commits'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save as…'));
      await tester.pumpAndSettle();

      expect(
        pumped.fake.commandLog.where(
          (FakeCommand c) => c.name == 'exportPatches',
        ),
        isEmpty,
      );
    });

    testWidgets('Apply… applies the picked files and lists them', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        picker: _FakePicker(files: const <String>['/tmp/0001-fix.patch']),
      );
      await tester.tap(find.text('Apply…'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'applyPatchFiles',
      );
      expect(cmd.args['files'], <String>['/tmp/0001-fix.patch']);
      expect(find.text('0001-fix.patch'), findsOneWidget);
    });

    // A .patch on disk was never parsed, so the preview colours git's text
    // rather than pretending to a ParsedDiff it does not have.
    testWidgets('a file row previews its text as a coloured diff', (
      tester,
    ) async {
      await _pump(
        tester,
        picker: _FakePicker(files: const <String>['/tmp/0001-fix.patch']),
      );
      await tester.tap(find.text('Apply…'));
      await tester.pumpAndSettle();

      expect(find.byType(PanelDiffText), findsOneWidget);
      expect(find.text('+new line'), findsOneWidget);
      expect(find.text('-old line'), findsOneWidget);
    });

    // A patch can be deleted between being picked and being previewed.
    testWidgets('an unreadable patch says so instead of showing nothing', (
      tester,
    ) async {
      await _pump(
        tester,
        picker: _FakePicker(files: const <String>['/tmp/gone.patch']),
        loadError: const FileSystemException('No such file'),
      );
      await tester.tap(find.text('Apply…'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not read this patch'), findsOneWidget);
    });

    testWidgets('the toolbar follows P19 rule 2\'s four segments', (
      tester,
    ) async {
      await _pump(tester);

      expectPanelTemplate(
        tester,
        primary: const <String>['Create from commits'],
        maintenance: const <String>['Apply…', 'Import…'],
        external: const <String>['Save as…'],
        listHeader: 'Patches · 0',
        statusBar: RegExp(r'^0 patches$'),
      );
    });

    testWidgets('the filter narrows the list, the header and the status line', (
      tester,
    ) async {
      await _pumpTwoFiles(tester);
      expect(find.byType(PanelListRow), findsNWidgets(2));

      await _filter(tester, '0002');

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('0002-add.patch'), findsOneWidget);
      expect(find.text('Patches · 1'), findsOneWidget);
      expect(find.text('2 patches · 命中 1'), findsOneWidget);
    });

    // The discriminating case. A row's title is the *basename* and its
    // subtitle is the full path, so 「vendor」 -- a directory segment that
    // appears in neither basename -- is the only kind of query that tells a
    // title-only filter apart from one that reads the whole row
    // ([TEST-fixture-cannot-disagree]). Every query that hits a basename
    // is answered identically by both.
    testWidgets('a directory segment matches, not just the file name', (
      tester,
    ) async {
      await _pumpTwoFiles(tester);

      await _filter(tester, 'vendor');

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('0001-fix.patch'), findsOneWidget);
    });

    // 「Select commits in History…」 would be a lie here -- there are two
    // patches, the filter is hiding them.
    testWidgets('a filter that hides everything says so, not "none queued"', (
      tester,
    ) async {
      await _pumpTwoFiles(tester);

      await _filter(tester, 'zzz');

      expect(find.text('No patch matches the filter'), findsOneWidget);
      expect(
        find.text('Select commits in History, or apply a .patch file'),
        findsNothing,
      );
    });

    testWidgets('Import… runs git am on the picked files', (tester) async {
      final PumpedPanel pumped = await _pump(
        tester,
        picker: _FakePicker(files: const <String>['/tmp/series.mbox']),
      );
      await tester.tap(find.text('Import…'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'importPatches',
      );
      expect(cmd.args['patchFiles'], <String>['/tmp/series.mbox']);
    });
  });
}
