// Device-tier E2E for the three Tier 1 (#51-#53) context-menu flows that
// were previously only ever going to be checked by hand.
//
// Why these three specifically: each one's failure mode lives *past* the
// widget tier. `test/features/**` proves the menu item renders and calls
// back; `test/integration/**` proves the callback reaches the controller;
// neither can prove that the resulting FFI call edits the right bytes on
// disk, that the composed path is the one the OS would actually open, or
// that a Compare tab really materialises in the real router. That is the
// gap this file closes.
//
// Everything here runs against the real gbm_capi library and a real temp
// git repository. The one seam left fake is `desktopLauncherProvider`, and
// only in the 05-F test -- see its comment.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/services/desktop_launcher.dart';
import 'package:gbm_flutter/data/services/file_save_picker.dart';
import 'package:gbm_flutter/features/compare/compare_page.dart';
import 'package:gbm_flutter/features/history_graph/commit_graph_view.dart';
import 'package:gbm_flutter/widgets/gbm_row.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

/// Committed content of the fixture file. Three short lines, so a
/// single-line discard has an unambiguous expected result and its
/// neighbours are visible in the same hunk.
const String _committed = 'alpha\nbravo\ncharlie\n';

/// Two separate insertions. Discarding only the first must leave the second
/// exactly where it is -- that is what makes this a line-granularity test
/// rather than a "something changed" one.
const String _modified = 'alpha\nINSERTED_ONE\nbravo\nINSERTED_TWO\ncharlie\n';

/// Records what would have been launched instead of spawning it.
class _RecordingStarter {
  final List<({String executable, List<String> arguments})> calls =
      <({String executable, List<String> arguments})>[];

  Future<bool> call(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
  }) async {
    calls.add((executable: executable, arguments: arguments));
    return true;
  }
}

/// Answers the native save panel with a canned path. Faked for the same
/// reason [_RecordingStarter] is: a real save panel would block the run, and
/// what can actually be wrong is which path the export writes to, not
/// whether macOS can draw a modal.
class _FixedSavePicker implements FileSavePicker {
  _FixedSavePicker(this.savePath);

  final String savePath;

  @override
  Future<String?> saveFile({required String suggestedName}) async => savePath;

  @override
  Future<String?> pickDirectory() async => null;

  @override
  Future<List<String>> openFiles({
    List<String> extensions = const <String>[],
  }) async => const <String>[];
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repoPath;

  setUp(() {
    repoPath = createTempGitRepo();
    File('$repoPath/fixture.txt').writeAsStringSync(_committed);
    runGit(repoPath, <String>['add', 'fixture.txt']);
    runGit(repoPath, <String>['commit', '-m', 'Add fixture']);
    File('$repoPath/fixture.txt').writeAsStringSync(_modified);
  });

  tearDown(() => deleteTempGitRepo(repoPath));

  /// Working Copy tab -> select fixture.txt -> its unstaged diff is on
  /// screen. Shared by the 05-G and 05-F tests below.
  Future<void> openFixtureDiff(WidgetTester tester) async {
    await tester.tap(find.text('Working Copy'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.text('fixture.txt'), findsOneWidget);
    await tester.tap(find.text('fixture.txt'));
    await tester.pumpAndSettle(const Duration(seconds: 1));
  }

  testWidgets('05-G: discarding one diff line reverts only that line on disk', (
    tester,
  ) async {
    await pumpRealAppOn(tester, repoPath);
    await openFixtureDiff(tester);

    // Both insertions are in the same hunk, so this also proves the
    // hunk-relative line index survives the URL round-trip intact.
    expect(find.text('INSERTED_ONE'), findsOneWidget);
    expect(find.text('INSERTED_TWO'), findsOneWidget);

    await tester.tap(find.text('INSERTED_ONE'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(
      find.text('Discard…'),
      findsOneWidget,
      reason: 'spec 05-G names the single-line case "Discard…"',
    );

    await tester.tap(find.text('Discard…'));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // The confirmation is not optional: this is the one action in the app
    // where a mis-click is unrecoverable.
    expect(find.text('Discard Line'), findsOneWidget);
    await tester.tap(find.text('Discard line'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(
      File('$repoPath/fixture.txt').readAsStringSync(),
      'alpha\nbravo\nINSERTED_TWO\ncharlie\n',
      reason:
          'INSERTED_ONE reverted, INSERTED_TWO and every committed line '
          'left alone -- a whole-file discard would have removed both',
    );

    // And git agrees the file is still dirty (the second insertion), so
    // the discard did not quietly restore the whole path. Not trimmed:
    // the leading space is the porcelain field that distinguishes a
    // worktree modification (' M') from a staged one ('M ').
    expect(
      runGit(repoPath, <String>[
        'status',
        '--porcelain',
        'fixture.txt',
      ]).stdout.toString(),
      ' M fixture.txt\n',
    );
  });

  testWidgets('05-F: Open file passes the OS the absolute path of the '
      'right file', (tester) async {
    // The only faked seam in this file. Left fake because the real
    // DesktopLauncher spawns `open`, which would put a text editor window
    // on the machine running the suite and tell us nothing extra: what can
    // actually be wrong here is the repo-relative -> absolute path
    // composition, and that is what this asserts.
    final _RecordingStarter starter = _RecordingStarter();
    await pumpRealAppOn(
      tester,
      repoPath,
      extraOverrides: <Override>[
        desktopLauncherProvider.overrideWithValue(
          DesktopLauncher(start: starter.call, operatingSystem: 'macos'),
        ),
      ],
    );
    await openFixtureDiff(tester);

    await tester.tap(find.text('fixture.txt'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(find.text('Open file'), findsOneWidget);
    expect(find.text('Show in file manager'), findsOneWidget);

    await tester.tap(find.text('Open file'));
    await tester.pumpAndSettle();

    expect(starter.calls.single.executable, 'open');
    expect(
      starter.calls.single.arguments,
      <String>['$repoPath/fixture.txt'],
      reason:
          'entry.path is repo-relative; handing the OS that directly would '
          'resolve against the process cwd, not the repository',
    );
  });

  testWidgets(
    '05-K: Compare with working copy opens a Compare tab for that commit',
    (tester) async {
      await pumpRealAppOn(tester, repoPath);

      // History is the initial route; select the commit that introduced the
      // fixture so its Changed files panel has a row to right-click.
      await tester.tap(find.text('Add fixture'));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      expect(
        find.text('CHANGED FILES'),
        findsOneWidget,
        reason: 'selecting a commit populates the Changed files panel',
      );

      // Targets the whole row rather than its Text: the secondary-tap
      // handler wraps the GbmRow, so this is the widget actually under
      // test. (The Text works too -- an earlier miss here was the stale
      // `panelLayout.*` preference `pumpRealAppOn` now clears, not the
      // finder.)
      final Finder fileRow = find.ancestor(
        of: find.text('fixture.txt'),
        matching: find.byType(GbmRow),
      );
      expect(fileRow, findsOneWidget);
      await tester.tap(fileRow, buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('Compare with working copy'), findsOneWidget);

      await tester.tap(find.text('Compare with working copy'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // A real Compare tab, reached by `go` (a ShellRoute sibling switch),
      // not stacked over History by `push` -- so the Compare route is the
      // ShellRoute's live child, with History gone rather than underneath.
      expect(find.byType(ComparePage), findsOneWidget);
      expect(find.byType(CommitGraphView), findsNothing);
      expect(
        find.text('Working Copy'),
        findsWidgets,
        reason:
            'the right-hand ref picker reads Working Copy -- a null `right` '
            'is what CompareTabSpec means by it',
      );
    },
  );

  /// History -> select the fixture commit -> right-click its file row. Shared
  /// by the two 05-K export tests below.
  Future<void> openCommitFileMenu(WidgetTester tester) async {
    await tester.tap(find.text('Add fixture'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    // GbmRow, not ListTile: the Changed files list moved onto the design
    // system's own row in fix/history-density-and-branch-filter, because a
    // dense ListTile still reserves more height than spec's 26px commit row.
    final Finder fileRow = find.ancestor(
      of: find.text('fixture.txt'),
      matching: find.byType(GbmRow),
    );
    expect(fileRow, findsOneWidget);
    await tester.tap(fileRow, buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
  }

  /// The export round-trips through a real FFI event, which `pumpAndSettle`
  /// has no way to wait for -- it settles animations, not native callbacks.
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (int i = 0; i < 60 && !done(); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets(
    '05-K: Open file at this revision writes the commit\'s bytes, not the '
    'working copy\'s, and hands that file to the OS',
    (tester) async {
      final _RecordingStarter starter = _RecordingStarter();
      await pumpRealAppOn(
        tester,
        repoPath,
        extraOverrides: <Override>[
          desktopLauncherProvider.overrideWithValue(
            DesktopLauncher(start: starter.call, operatingSystem: 'macos'),
          ),
        ],
      );
      await openCommitFileMenu(tester);

      expect(find.text('Open file at this revision'), findsOneWidget);
      await tester.tap(find.text('Open file at this revision'));
      await pumpUntil(tester, () => starter.calls.isNotEmpty);

      expect(starter.calls, hasLength(1));
      expect(starter.calls.single.executable, 'open');
      final String opened = starter.calls.single.arguments.single;
      expect(File(opened).existsSync(), isTrue, reason: opened);
      // The whole point of the flow: the working copy holds _modified, and
      // what landed on disk is what the commit held.
      expect(File(opened).readAsStringSync(), _committed);
      expect(
        opened,
        endsWith('.txt'),
        reason: 'without the extension the OS has no file association',
      );
    },
  );

  testWidgets('05-K: Save this revision as… writes the commit\'s bytes to '
      'the chosen path', (tester) async {
    final String destination = '$repoPath/../saved-revision.txt';
    await pumpRealAppOn(
      tester,
      repoPath,
      extraOverrides: <Override>[
        fileSavePickerProvider.overrideWithValue(_FixedSavePicker(destination)),
      ],
    );
    await openCommitFileMenu(tester);

    await tester.tap(find.text('More actions'));
    await tester.pumpAndSettle();
    expect(find.text('Save this revision as…'), findsOneWidget);
    await tester.tap(find.text('Save this revision as…'));
    await pumpUntil(tester, () => File(destination).existsSync());

    expect(File(destination).existsSync(), isTrue, reason: destination);
    expect(File(destination).readAsStringSync(), _committed);
    File(destination).deleteSync();
  });
}
