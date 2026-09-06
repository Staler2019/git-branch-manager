// Device-tier E2E for the round trip the user reported: an untracked file,
// every line staged, then every line unstaged again.
//
// Why it needs this tier. The defect lives entirely below Dart -- a reverse
// `git apply --cached` exits 0 and leaves the index entry in place holding
// the empty blob, so porcelain goes on reporting `A` and the file stays in
// the Staged column reading +0. Every fake in `test/` answers from a scripted
// `WorkingCopyStatus`, so the one thing that could disagree with the fix is
// the real index. `GitIntegrationTest.cpp`'s
// UnstagingEveryLineOfAnUntrackedFileReturnsItToUntracked covers the C++ half
// and is called from C++, never through `dart:ffi` -- whose `lookupFunction`
// matches by symbol name and never by signature
// ([TEST-ffi-matches-symbol-only]).
//
// The assertion is on `git status --porcelain=v2` rather than on the UI, for
// the same reason `stage_lines_flow_test.dart`'s is on `git diff --cached`: a
// button that dispatches into a void looks identical in every other tier.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_board.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

/// Three lines, contiguous, so 變體 B's scope rule leaves exactly one card
/// and its button reads 「Stage 3 lines」 -- a single press that really does
/// cover *every* changed line, which is the gate the fix turns on.
const String _untracked = 'alpha\nbravo\ncharlie\n';

String _porcelain(String repo) =>
    runGit(repo, <String>['status', '--porcelain=v2', '--', 'fresh.txt']).stdout
        as String;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repo;

  setUp(() {
    repo = createTempGitRepo(prefix: 'gbm_e2e_untracked_unstage_');
    File('$repo/fresh.txt').writeAsStringSync(_untracked);
  });

  tearDown(() => deleteTempGitRepo(repo));

  testWidgets('an untracked file staged in full and unstaged again is '
      'untracked again', (tester) async {
    await pumpRealAppOn(tester, repo);
    await tester.tap(find.text('Working Copy'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(
      _porcelain(repo).startsWith('? '),
      isTrue,
      reason: 'the fixture starts untracked\n${_porcelain(repo)}',
    );

    await tester.tap(
      find.descendant(
        of: find.byType(WorkingCopyBoard),
        matching: find.text('fresh.txt'),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // An untracked file has no staged side at all until this press, so the
    // merged list holds exactly one card.
    await tester.tap(find.text('Stage 3 lines'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(
      _porcelain(repo).contains(' A'),
      isTrue,
      reason: 'staging every line adds it to the index\n${_porcelain(repo)}',
    );

    // The row moved to the Staged column; re-select it there so the diff pane
    // is certainly showing this file rather than relying on the selection
    // surviving the move.
    await tester.tap(
      find.descendant(
        of: find.byType(WorkingCopyBoard),
        matching: find.text('fresh.txt'),
      ),
    );
    await tester.pumpAndSettle(const Duration(seconds: 2));

    await tester.tap(find.text('Unstage 3 lines'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // The whole claim, in the one form the user can see. Not 「the index
    // entry is gone」 -- that is the implementation talking to itself, and it
    // is satisfied by states porcelain would still call staged.
    final String after = _porcelain(repo);
    expect(
      after.startsWith('? '),
      isTrue,
      reason:
          'unstaging every line of an added file must return it to '
          'untracked; a reverse patch leaves an empty blob behind and '
          'porcelain keeps calling it A\n$after',
    );

    // And the file itself is untouched -- unstaging never rewrites the work
    // tree, so all three lines are still on disk.
    expect(File('$repo/fresh.txt').readAsStringSync(), _untracked);
  });
}
