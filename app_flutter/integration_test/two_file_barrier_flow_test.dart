// Device-tier E2E for plan Slice B, the case the user reported: a new file
// staged whole, then its middle lines unstaged again. In `2 file` the staged
// card is cut where the unstaged lines go (使用者裁定「所有檔案都套用」), and
// each half acts on its own lines through the real index.
//
// The index is written by `git add` of the four-line version before the app
// opens, then the work tree gets all six -- the same state a reverse apply
// of L3-L4 leaves, without patch text in the fixture
// ([TEST-no-dart-process-while-core-runs-git]: git runs only before the app
// opens and after it settles).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_board.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

const String _index = 'L1\nL2\nL5\nL6\n';
const String _workTree = 'L1\nL2\nL3\nL4\nL5\nL6\n';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repo;

  setUp(() {
    repo = createTempGitRepo(prefix: 'gbm_e2e_two_file_barrier_');
    File('$repo/n.txt').writeAsStringSync(_index);
    runGit(repo, <String>['add', 'n.txt']);
    File('$repo/n.txt').writeAsStringSync(_workTree);
  });

  tearDown(() => deleteTempGitRepo(repo));

  testWidgets('the second staged card unstages only L5 and L6', (tester) async {
    await pumpRealAppOn(tester, repo);
    await tester.tap(find.text('Working Copy'));
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(
      find
          .descendant(
            of: find.byType(WorkingCopyBoard),
            matching: find.text('n.txt'),
          )
          .first,
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));
    await tester.tap(find.text('2 file'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final Finder unstage = find.descendant(
      of: find.byType(ScopedDiffView).at(1),
      matching: find.text('Unstage 2 lines'),
    );
    expect(unstage, findsNWidgets(2), reason: 'the staged card is cut');
    // Nothing staged sits level with the unstaged L3-L4.
    Finder row(int c, String text) => find.descendant(
      of: find.byType(ScopedDiffView).at(c),
      matching: find.text(text, findRichText: true),
    );
    expect(
      tester.getRect(row(1, 'L5')).top,
      greaterThanOrEqualTo(tester.getRect(row(0, 'L4')).bottom),
    );

    await tester.tap(unstage.at(1));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final String cached =
        runGit(repo, <String>['diff', '--cached', '--', 'n.txt']).stdout
            as String;
    final List<String> added = <String>[
      for (final String l in cached.split('\n'))
        if (l.startsWith('+') && !l.startsWith('+++')) l,
    ];
    expect(added, <String>['+L1', '+L2'], reason: cached);
    expect(File('$repo/n.txt').readAsStringSync(), _workTree);
  });
}
