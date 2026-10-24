// Device-tier E2E for spec page 07's MSGS table, Cherry-pick row: the
// trailing "(cherry picked from commit …)" line, which Preferences → Git can
// turn off. Drives the real chain the widget and capi tiers each see only
// half of: the Preferences switch -> repoSessionProvider ->
// RepoSessionController.cherryPickRecordsOrigin -> gbm_cherry_pick's
// `recordOrigin` across dart:ffi -> `git cherry-pick -x`.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/key_shortcuts.dart';
import 'support/real_repo_harness.dart';

const String _picked = 'Feature work';
const String _switchTitle =
    '（預設）cherry-pick 時加上「(cherry picked from commit …)」';

String _git(String repoPath, List<String> args) =>
    runGit(repoPath, args).stdout.toString().trim();

/// main's tip, read from its loose ref file: a git process started from the
/// test while the app runs git makes the app's git fail
/// ([TEST-no-dart-process-while-core-runs-git]).
String _mainTip(String repo) =>
    File('$repo/.git/refs/heads/main').readAsStringSync().trim();

/// Right-clicks the [_picked] row and chooses Cherry-pick, then waits for
/// main to move.
Future<void> _cherryPickFromHistory(WidgetTester tester, String repo) async {
  final String before = _mainTip(repo);
  await tester.tap(
    find.descendant(of: find.byType(CommitRow), matching: find.text(_picked)),
    buttons: kSecondaryMouseButton,
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Cherry-pick'));
  await pumpUntil(tester, () => _mainTip(repo) != before);
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repoPath;
  late String pickedHex;

  setUp(() {
    repoPath = createTempGitRepo();
    runGit(repoPath, <String>['switch', '--quiet', '-c', 'feature']);
    File('$repoPath/feature.txt').writeAsStringSync('f\n');
    runGit(repoPath, <String>['add', 'feature.txt']);
    runGit(repoPath, <String>['commit', '-m', _picked]);
    pickedHex = _git(repoPath, <String>['rev-parse', 'HEAD']);
    // main moves on, so the pick lands on a different parent than the
    // original and can never reproduce its object id.
    runGit(repoPath, <String>['switch', '--quiet', 'main']);
    File('$repoPath/main.txt').writeAsStringSync('m\n');
    runGit(repoPath, <String>['add', 'main.txt']);
    runGit(repoPath, <String>['commit', '-m', 'Main work']);
  });

  tearDown(() => deleteTempGitRepo(repoPath));

  testWidgets('on by default: the picked commit ends with the source line', (
    tester,
  ) async {
    await pumpRealAppOn(tester, repoPath);

    await _cherryPickFromHistory(tester, repoPath);

    expect(
      _git(repoPath, <String>['log', '-1', '--format=%B']),
      '$_picked\n\n(cherry picked from commit $pickedHex)',
    );
  });

  testWidgets('switched off in Preferences: no source line', (tester) async {
    final SharedPreferences prefs = await pumpRealAppOn(tester, repoPath);
    // The real store is the developer's own; never leave the switch off.
    addTearDown(() => prefs.remove('appPrefs.cherryPickAddsSourceLine'));

    await pressActionShortcut(tester, GbmActionId.filePreferences);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Git'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(_switchTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(_switchTitle));
    await tester.pumpAndSettle();
    expect(prefs.getBool('appPrefs.cherryPickAddsSourceLine'), isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text(_switchTitle), findsNothing);

    await _cherryPickFromHistory(tester, repoPath);

    expect(_git(repoPath, <String>['log', '-1', '--format=%B']), _picked);
  });
}
