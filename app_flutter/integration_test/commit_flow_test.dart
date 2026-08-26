// Device-tier E2E (Phase 4): modify a tracked file, stage it, type a commit
// summary, commit -- against the real gbm_capi.dylib/.so and a real temp
// git repo. Verifies both through the UI and by shelling back into the same
// repo with `git log`, so a false-positive from stale widget state can't
// pass silently.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/working_copy/widgets/commit_message_box.dart';
import 'package:gbm_flutter/features/working_copy/widgets/working_copy_board.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repoPath;

  setUp(() {
    repoPath = createTempGitRepo();
    File(
      '$repoPath/README.md',
    ).writeAsStringSync('# gbm e2e fixture\n\nmodified by commit_flow_test.\n');
  });

  tearDown(() => deleteTempGitRepo(repoPath));

  testWidgets(
    'modify -> stage -> commit -> new commit lands in History and on disk',
    (tester) async {
      await pumpRealAppOn(tester, repoPath);

      // Working Copy tab: the modified README should be listed unstaged.
      await tester.tap(find.text('Working Copy'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('README.md'), findsOneWidget);

      // Type the commit summary first (see this repo's H2 finding in
      // docs/reports/code-review-2026-08.md: the Commit button only
      // recomputes on an unrelated rebuild, not on the controller's own
      // text changes) -- staging the file below is that rebuild trigger.
      final Finder summaryField = find
          .descendant(
            of: find.byType(CommitMessageBox),
            matching: find.byType(TextField),
          )
          .first;
      await tester.enterText(summaryField, 'E2E commit');
      await tester.pump();

      // Stage the file by dragging its row into the Staged column. There
      // is no checkbox to tap any more -- spec P03 變體 B removed every one
      // of them and made the drag the only way a file changes side, and
      // this test still tapped `find.byType(Checkbox).first` afterwards.
      // Nothing caught it: the device tier runs in no CI job and is not
      // part of `flutter test`.
      final Finder unstagedRow = find.descendant(
        of: find.byType(WorkingCopyBoard),
        matching: find.text('README.md'),
      );
      final Rect board = tester.getRect(find.byType(WorkingCopyBoard));
      final Offset from = tester.getCenter(unstagedRow);
      // A quarter in from the board's right edge: inside the Staged
      // column's DragTarget, and clear of the column header above it.
      final Offset to = Offset(board.right - board.width * 0.25, from.dy);

      final TestGesture drag = await tester.startGesture(from);
      // Past kTouchSlop in two steps: a single moveTo can be consumed as
      // the drag's own start and leave the Draggable never picked up.
      await tester.pump(const Duration(milliseconds: 50));
      await drag.moveTo(Offset(from.dx + 40, from.dy));
      await tester.pump();
      await drag.moveTo(to);
      await tester.pump();
      await drag.up();
      await tester.pumpAndSettle(const Duration(seconds: 1));

      // The column headers carry their own counts, so this says "the file
      // really crossed" without depending on the row key, which gains a
      // `-selected` suffix while the row is selected.
      expect(
        find.text('Staged \u00b7 1'),
        findsOneWidget,
        reason: 'the drag moved the row into the Staged column',
      );
      expect(find.text('Unstaged \u00b7 0'), findsOneWidget);

      final Finder commitButton = find.widgetWithText(GbmButton, 'Commit');
      expect(commitButton, findsOneWidget);
      final GbmButton commit = tester.widget<GbmButton>(commitButton);
      expect(
        commit.onPressed,
        isNotNull,
        reason: 'staged.isNotEmpty && summary.isNotEmpty should enable Commit',
      );

      await tester.tap(commitButton);
      await tester.pumpAndSettle(const Duration(seconds: 1));

      final ProcessResult log = runGit(repoPath, <String>[
        'log',
        '-1',
        '--pretty=%s',
      ]);
      expect(log.stdout.toString().trim(), 'E2E commit');

      final ProcessResult status = runGit(repoPath, <String>[
        'status',
        '--porcelain',
      ]);
      expect(
        status.stdout.toString().trim(),
        isEmpty,
        reason: 'the working tree should be clean after the real commit',
      );

      // History reflects the new commit once switched back.
      await tester.tap(find.text('History'));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(find.text('E2E commit'), findsOneWidget);
    },
  );
}
