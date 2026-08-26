// Device-tier E2E for the Working Copy board's `+N -N` badges (spec page 03).
//
// Why this file has to exist, and why nothing already in the suite covers it:
// C1 added four fields to `WorkingCopyEntry` -- `unstagedAdded`,
// `unstagedRemoved`, `stagedAdded`, `stagedRemoved` -- which travel from two
// extra `git diff --numstat` passes in `WorkingCopyStatusReader`, through
// four new keys in `JsonCodec.cpp`, into a Dart model that decodes them with
// a hard `as int`. **No other tier crosses that whole seam**: `test/**` runs
// on `FakeGbmBindings` (which invents the numbers), and
// `tests/unit/GitIntegrationTest.cpp` stops at the C++ struct. `dart:ffi`'s
// `lookupFunction` matches by symbol name and never by signature, so the two
// halves can disagree about a payload while compiling, analyzing and
// unit-testing clean -- and a stale `build/native/libgbm_capi.dylib` would
// show up as a missing badge rather than as any kind of error. Same trap and
// same reason as `commit_file_counts_test.dart`'s second test, one layer
// over.
//
// The counts are deliberately four different numbers -- +7/-3 unstaged and
// +2/-1 staged -- so no assertion here can be satisfied by another badge on
// screen, and so a wiring mistake that reads the *other* column's pair
// (which is a real hazard: a partly-staged file carries all four at once)
// fails instead of coinciding.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_board.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

/// Leaves `counts.txt` with +2/-1 in the index and +7/-3 in the work tree.
///
/// Two `git add`s with an edit in between is the only way to get a file whose
/// staged and unstaged numbers differ -- which is the case the four separate
/// fields exist for, and the one a single pair of numbers could not express.
void _buildPartlyStagedFile(String repo) {
  File('$repo/counts.txt').writeAsStringSync('l1\nl2\nl3\nl4\nl5\n');
  runGit(repo, <String>['add', 'counts.txt']);
  runGit(repo, <String>['commit', '-m', 'add counts']);

  // Index vs HEAD: l2 replaced by S1/S2 -> +2 -1.
  File('$repo/counts.txt').writeAsStringSync('l1\nS1\nS2\nl3\nl4\nl5\n');
  runGit(repo, <String>['add', 'counts.txt']);

  // Work tree vs index: l3/l4/l5 replaced by seven lines -> +7 -3.
  File(
    '$repo/counts.txt',
  ).writeAsStringSync('l1\nS1\nS2\nA\nB\nC\nD\nE\nF\nG\n');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repo;

  setUp(() {
    repo = createTempGitRepo(prefix: 'gbm_e2e_wc_counts_');
    _buildPartlyStagedFile(repo);
  });

  tearDown(() => deleteTempGitRepo(repo));

  testWidgets('each column badges its own side of a partly-staged file', (
    tester,
  ) async {
    await pumpRealAppOn(tester, repo);

    await tester.tap(find.text('Working Copy'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final Finder board = find.byType(WorkingCopyBoard);
    expect(board, findsOneWidget);

    // The file is in both columns at once, which is what makes the four
    // numbers distinguishable in the first place.
    expect(
      find.descendant(of: board, matching: find.text('counts.txt')),
      findsNWidgets(2),
    );

    for (final (String label, String side) in const <(String, String)>[
      ('+7', 'unstaged added'),
      ('-3', 'unstaged removed'),
      ('+2', 'staged added'),
      ('-1', 'staged removed'),
    ]) {
      expect(
        find.descendant(of: board, matching: find.text(label)),
        findsOneWidget,
        reason:
            'the $side count must reach the badge through the real dylib; a '
            'capi field the Dart side does not actually receive shows up '
            'here as a badge that never renders',
      );
    }
  });
}
