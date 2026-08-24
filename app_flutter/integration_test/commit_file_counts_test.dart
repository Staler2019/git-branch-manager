// Device-tier E2E for the two places a commit's file changes are counted:
// the Changed files *column* (spec page 02 item 16) and the Changed files
// *panel*'s per-row +N/-N badge (spec page 02 item 10).
//
// Why this file has to exist, and why a widget test cannot replace it:
// `gbm_request_commit_file_counts` is a new C entry point with a matching
// `dart:ffi` typedef, and **nothing else in the suite crosses that seam**.
// `test/**` runs on `FakeGbmBindings`; `tests/capi/CommitMetaApiTest.cpp`
// calls the C++ side directly. `lookupFunction` matches by symbol name and
// never by signature, so an arity or type mismatch between the two halves
// compiles, analyzes and unit-tests clean, then corrupts the stack the first
// time a real user switches the column on. Same trap as
// `rename_branch_flow_test.dart`'s, and CLAUDE.md's Tier 0c note.
//
// The counts are asserted against a real repository rather than a fixture,
// because the property that matters -- a merge commit reporting its
// first-parent file count rather than 0 -- is a fact about git's own
// behaviour, which a fake has no way to be wrong about.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/history_graph/widgets/changed_files_panel.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

/// The side branch's file count, and therefore the merge's first-parent
/// count. Three rather than one so the assertion cannot be satisfied by a
/// stray "1" elsewhere in the row, and so a regression to the old
/// merge-shows-nothing behaviour cannot coincide with a neighbouring value.
const int _sideFiles = 3;

/// Builds: initial commit -> side branch (3 files) -> main commit (1 file)
/// -> a real merge.
///
/// The two parents touch *different* paths on purpose. With a shared path a
/// first-parent count and an all-parents count would agree, and this could
/// not tell the shipped `--diff-merges=first-parent` from the
/// `-m --first-parent` trap it replaced (see `DiffService`'s own note).
void _buildMergeHistory(String repo) {
  runGit(repo, <String>['checkout', '-b', 'side']);
  for (int i = 0; i < _sideFiles; i++) {
    File('$repo/side$i.txt').writeAsStringSync('from the side $i\n');
  }
  runGit(repo, <String>['add', '.']);
  runGit(repo, <String>['commit', '-m', 'side commit']);

  runGit(repo, <String>['checkout', 'main']);
  File('$repo/main.txt').writeAsStringSync('from main\n');
  runGit(repo, <String>['add', 'main.txt']);
  runGit(repo, <String>['commit', '-m', 'main commit']);

  runGit(repo, <String>['merge', '--no-ff', '-m', 'merge side', 'side']);
}

/// The commit row whose subject is [subject].
Finder _rowFor(String subject) =>
    find.ancestor(of: find.text(subject), matching: find.byType(CommitRow));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repo;

  setUp(() {
    repo = createTempGitRepo(prefix: 'gbm_e2e_counts_');
    _buildMergeHistory(repo);
  });

  tearDown(() => deleteTempGitRepo(repo));

  testWidgets('switching the column on shows real counts, merge included', (
    tester,
  ) async {
    await pumpRealAppOn(tester, repo);

    // Off by default (spec's GRAPH_COLS `on: false`), asserted before the
    // toggle so a column that was somehow already on could not make the rest
    // of this pass for free. `pumpRealAppOn` clears `graphColumns.*` from the
    // machine's real preferences store precisely so this holds.
    expect(_rowFor('merge side'), findsOneWidget);
    expect(
      find.descendant(of: _rowFor('merge side'), matching: find.text('3')),
      findsNothing,
    );

    // Switched on the way a user would -- through the real header button and
    // the real picker -- rather than by writing the provider, so the whole
    // chain from the tick to the FFI call is what is under test.
    await tester.tap(find.byTooltip('Graph columns'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Changed files'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(4, 4)); // dismiss the popover
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // The claim this file exists for. Before the DiffService fix a merge's
    // first-parent diff was empty, so this row would have read 0.
    expect(
      find.descendant(
        of: _rowFor('merge side'),
        matching: find.text('$_sideFiles'),
      ),
      findsOneWidget,
      reason: 'the merge must report its first-parent file count, not 0',
    );
    expect(
      find.descendant(of: _rowFor('merge side'), matching: find.text('0')),
      findsNothing,
    );

    // And an ordinary commit is counted too, so the assertion above is not
    // passing because merges are special-cased into some fallback.
    expect(
      find.descendant(of: _rowFor('main commit'), matching: find.text('1')),
      findsOneWidget,
    );
  });

  testWidgets(
    'the Changed files panel badges a selected commit\'s line counts',
    (tester) async {
      // Spec page 02 item 10. The counts reach the badge through a chain no
      // other tier crosses end to end: DiffService joins `diff-tree --numstat`
      // onto the raw list, capi serialises two new JSON keys, and the Dart
      // model decodes them with a hard `as int`. test/** runs on
      // FakeGbmBindings and tests/capi/** stops at the C++ side, so a payload
      // the two halves disagree about is invisible everywhere but here -- and
      // a stale libgbm_capi would surface as a Dart decode error rather than
      // as a missing badge.
      //
      // Its own commit rather than one of _buildMergeHistory's: +7/-3 is
      // asymmetric and appears nowhere else on screen, where the fixture's
      // one-line files would give a "+1" that half the UI could produce.
      File('$repo/counts.txt').writeAsStringSync('l1\nl2\nl3\nl4\nl5\n');
      runGit(repo, <String>['add', 'counts.txt']);
      runGit(repo, <String>['commit', '-m', 'add counts']);
      File(
        '$repo/counts.txt',
      ).writeAsStringSync('l1\nA\nB\nC\nD\nE\nF\nG\nl5\n');
      runGit(repo, <String>['add', 'counts.txt']);
      runGit(repo, <String>['commit', '-m', 'edit counts']);

      await pumpRealAppOn(tester, repo);

      expect(_rowFor('edit counts'), findsOneWidget);
      await tester.tap(_rowFor('edit counts'));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final Finder panel = find.byType(ChangedFilesPanelCore);
      expect(
        find.descendant(of: panel, matching: find.text('counts.txt')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: panel, matching: find.text('+7')),
        findsOneWidget,
        reason: 'the added-line badge must carry the real numstat count',
      );
      expect(
        find.descendant(of: panel, matching: find.text('-3')),
        findsOneWidget,
        reason: 'the removed-line badge must not repeat the added count',
      );
    },
  );
}
