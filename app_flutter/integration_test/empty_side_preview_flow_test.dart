// Device-tier E2E for plan Slice E: an untracked file staged in full leaves
// nothing unstaged, and in `2 file` with the full-file view on, the unstaged
// column draws the file anyway -- the work tree and the index both hold it
// (使用者回報 2026-10-31「the unstaged should keep shows the file preview as
// there's text already exists there」).
//
// Those rows are fill rows of a column with no diff of its own, so nothing
// framed among them can be staged. Every widget test of that runs on
// `FakeGbmBindings`; only here does a stage reach `git apply --cached`, so
// the assertion reads `git diff --cached`.
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_board.dart';
import 'package:gbm_flutter/widgets/gbm_icon_button.dart';
import 'package:integration_test/integration_test.dart';

import 'support/key_shortcuts.dart';
import 'support/real_repo_harness.dart';

const String _untracked = 'alpha\nbravo\ncharlie\n';

/// Read only once the app has settled ([TEST-no-dart-process-while-core-runs-git]).
String _staged(String repo) =>
    runGit(repo, <String>['diff', '--cached', '--', 'fresh.txt']).stdout
        as String;

Finder _unstagedColumn(String text) => find.descendant(
  of: find.byType(ScopedDiffView).first,
  matching: find.text(text),
);

Future<void> _selectFile(WidgetTester tester) async {
  await tester.tap(
    find
        .descendant(
          of: find.byType(WorkingCopyBoard),
          matching: find.text('fresh.txt'),
        )
        .first,
  );
  await tester.pumpAndSettle(const Duration(seconds: 2));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repo;

  setUp(() {
    repo = createTempGitRepo(prefix: 'gbm_e2e_empty_side_');
    File('$repo/fresh.txt').writeAsStringSync(_untracked);
  });

  tearDown(() => deleteTempGitRepo(repo));

  testWidgets('a new file staged whole shows in the unstaged column, and a '
      'drag over it stages nothing', (tester) async {
    await pumpRealAppOn(tester, repo);
    await tester.tap(find.text('Working Copy'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _selectFile(tester);

    await tester.tap(find.text('Stage 3 lines'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await _selectFile(tester);

    await tester.tap(find.text('2 file'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(
      find.byWidgetPredicate(
        (Widget w) =>
            w is GbmIconButton &&
            w.icon is Icon &&
            (w.icon as Icon).icon == Icons.expand,
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    for (final String line in <String>['alpha', 'bravo', 'charlie']) {
      expect(_unstagedColumn(line), findsOneWidget, reason: line);
    }
    final String before = _staged(repo);
    expect(before, contains('+alpha'), reason: 'the fixture is staged');

    final Rect start = tester.getRect(_unstagedColumn('alpha'));
    final Rect end = tester.getRect(_unstagedColumn('charlie'));
    final TestGesture gesture = await tester.startGesture(
      Offset(start.left + 1, start.center.dy),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();
    for (final double t in const <double>[0.25, 0.5, 0.75, 1.0]) {
      await gesture.moveTo(
        Offset.lerp(
          Offset(start.left + 1, start.center.dy),
          Offset(end.right - 1, end.center.dy),
          t,
        )!,
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    await tester.pump();
    await gesture.removePointer();

    expect(find.text('一次性'), findsNothing);
    await pressActionShortcut(tester, GbmActionId.repositoryStageSelectedLines);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(_staged(repo), before);
    expect(File('$repo/fresh.txt').readAsStringSync(), _untracked);
  });
}
