import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/refresh_timings.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/status_bar/background_task.dart';
import 'package:gbm_flutter/features/status_bar/status_bar.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/widgets/gbm_badge.dart';
import 'package:gbm_flutter/widgets/lucide_icon.dart';

WorkingCopyStatus _createConflictedStatus(List<String> conflictedPaths) {
  final entries = conflictedPaths
      .map(
        (path) => WorkingCopyEntry(
          path: path,
          oldPath: '',
          untracked: false,
          staged: false,
          indexStatus: FileChangeKind.modified,
          hasUnstagedChange: false,
          worktreeStatus: FileChangeKind.modified,
          unstagedAdded: 0,
          unstagedRemoved: 0,
          stagedAdded: 0,
          stagedRemoved: 0,
          conflict: ConflictKind.bothModified,
          ancestorBlob: '',
          oursBlob: '',
          theirsBlob: '',
          similarity: 0,
          isSubmodule: false,
          isConflicted: true,
        ),
      )
      .toList(growable: false);
  return WorkingCopyStatus(entries: entries);
}

void main() {
  group('StatusBar', () {
    // Deleting TopBar moved RepoState.describe here. It is empty for an
    // ordinary repository, and the only signal it carries that no other
    // surface in the window carries is `indexLocked` -- ConflictBanner
    // renders on conflictActive, which indexLocked does not set. Without
    // these two tests the deletion would have dropped it silently, which is
    // exactly the shape of loss this repo keeps finding after the fact.
    testWidgets('shows the repo state label when git reports one', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 0,
              behind: 0,
              commitCount: 3,
              lastScanDuration: const Duration(milliseconds: 10),
              graphLaneCapacity: 4,
              backgroundTasks: const [],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
              repoState: const RepoState(
                flags: 0,
                isClean: true,
                isSequencerOperation: false,
                rebaseStep: 0,
                rebaseTotal: 0,
                rebaseOntoLabel: '',
                indexLocked: true,
                indexLockAgeSeconds: 2,
                describe: 'another Git process appears to be running',
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(
        find.text('another Git process appears to be running'),
        findsOneWidget,
      );
    });

    testWidgets('shows nothing extra when the repo state label is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 0,
              behind: 0,
              commitCount: 3,
              lastScanDuration: const Duration(milliseconds: 10),
              graphLaneCapacity: 4,
              backgroundTasks: const [],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
              // describe is '' for an ordinary repository -- the common case,
              // where this must add no noise to the status bar.
              repoState: const RepoState(
                flags: 0,
                isClean: true,
                isSequencerOperation: false,
                rebaseStep: 0,
                rebaseTotal: 0,
                rebaseOntoLabel: '',
                indexLocked: false,
                indexLockAgeSeconds: 0,
                describe: '',
              ),
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.text(''), findsNothing);
      expect(find.textContaining('main ↑'), findsWidgets);
    });

    testWidgets('renders repo status zone when no task is running', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 2,
              behind: 1,
              commitCount: 42,
              lastScanDuration: const Duration(milliseconds: 150),
              graphLaneCapacity: 8,
              backgroundTasks: const [],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
            ),
          ),
        ),
      );

      await tester.pump();

      // P10 mock: `<span>main ↑2 ↓0</span>` -- one run, arrows first.
      expect(find.text('main ↑2 ↓1'), findsOneWidget);
    });

    testWidgets('shows single task in progress zone', (tester) async {
      final task = BackgroundTask(
        id: 'fetch-1',
        label: 'Fetching',
        current: 50,
        total: 100,
        cancellable: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 0,
              behind: 0,
              commitCount: 10,
              lastScanDuration: const Duration(milliseconds: 100),
              graphLaneCapacity: 6,
              backgroundTasks: [task],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
            ),
          ),
        ),
      );

      await tester.pump();

      // P10 mock: `Cloning design-tokens — 12,480 / 31,206` -- the count
      // rides in the label.
      expect(find.text('Fetching — 50 / 100'), findsOneWidget);
      // Should show progress indicator
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    // Spec page 10 P10 #2: 「其餘作業摺疊成 +N task」; its mockup draws
    // "+1 task". The chip used to read "+N more".
    testWidgets('folds N>1 tasks to "+N task" text', (tester) async {
      final tasks = [
        BackgroundTask(
          id: 'fetch-1',
          label: 'Fetching',
          current: 50,
          total: 100,
          cancellable: true,
        ),
        BackgroundTask(
          id: 'push-1',
          label: 'Pushing',
          current: 0,
          total: 1,
          cancellable: true,
        ),
        BackgroundTask(
          id: 'pull-1',
          label: 'Pulling',
          current: 0,
          total: 1,
          cancellable: true,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 0,
              behind: 0,
              commitCount: 10,
              lastScanDuration: const Duration(milliseconds: 100),
              graphLaneCapacity: 6,
              backgroundTasks: tasks,
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
            ),
          ),
        ),
      );

      await tester.pump();

      // Should show fold indicator
      expect(find.text('+2 task'), findsOneWidget);
    });

    testWidgets('tapping "+N more" expands the folded tasks (spec page 10 '
        'STATUSPARTS #2: "其餘作業摺疊成 +N task，點了展開清單")', (tester) async {
      final tasks = [
        BackgroundTask(
          id: 'fetch-1',
          label: 'Fetching',
          current: 50,
          total: 100,
          cancellable: true,
        ),
        BackgroundTask(
          id: 'push-1',
          label: 'Pushing',
          current: 0,
          total: 1,
          cancellable: true,
        ),
        BackgroundTask(
          id: 'checkout-1',
          label: 'Checking out',
          current: 0,
          total: 1,
          cancellable: false,
        ),
      ];
      String? cancelledId;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 0,
              behind: 0,
              commitCount: 10,
              lastScanDuration: const Duration(milliseconds: 100),
              graphLaneCapacity: 6,
              backgroundTasks: tasks,
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (id) => cancelledId = id,
            ),
          ),
        ),
      );
      await tester.pump();

      // Before expanding: only the foreground task's label is visible,
      // the two folded ones are not.
      expect(find.text('Fetching — 50 / 100'), findsOneWidget);
      expect(find.text('Pushing'), findsNothing);
      expect(find.text('Checking out'), findsNothing);

      await tester.tap(find.text('+2 task'));
      await tester.pumpAndSettle();

      // After expanding: both folded tasks' labels are now visible.
      expect(find.text('Pushing'), findsOneWidget);
      expect(find.text('Checking out'), findsOneWidget);

      // A cancellable folded task (push) has a live Cancel button that
      // reaches the same onCancelTask callback the foreground task uses.
      // The first Cancel is the foreground task's own, which the mock keeps
      // beside `+N task`; the folded two follow it in the expanded list.
      final Finder cancelButtons = find.widgetWithText(TextButton, 'Cancel');
      expect(cancelButtons, findsNWidgets(3));
      await tester.tap(cancelButtons.at(1));
      expect(cancelledId, 'push-1');

      // A non-cancellable folded task (checkout) has its Cancel button
      // disabled, same rule as the foreground task's own Cancel button.
      final TextButton checkoutCancel = tester.widget<TextButton>(
        cancelButtons.last,
      );
      expect(checkoutCancel.onPressed, isNull);
    });

    testWidgets('non-cancellable task Cancel button is disabled', (
      tester,
    ) async {
      final task = BackgroundTask(
        id: 'checkout-1',
        label: 'Checking out',
        current: 0,
        total: 1,
        cancellable: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 0,
              behind: 0,
              commitCount: 10,
              lastScanDuration: const Duration(milliseconds: 100),
              graphLaneCapacity: 6,
              backgroundTasks: [task],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
            ),
          ),
        ),
      );

      await tester.pump();

      // Should show disabled Cancel button (grayed out)
      final cancelButton = find.byType(TextButton);
      expect(cancelButton, findsOneWidget);
      final button = tester.widget<TextButton>(cancelButton);
      expect(button.onPressed, isNull);
    });

    testWidgets('cancellable task Cancel button is enabled', (tester) async {
      var cancelledId = '';
      final task = BackgroundTask(
        id: 'fetch-1',
        label: 'Fetching',
        current: 0,
        total: 1,
        cancellable: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 0,
              behind: 0,
              commitCount: 10,
              lastScanDuration: const Duration(milliseconds: 100),
              graphLaneCapacity: 6,
              backgroundTasks: [task],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (id) {
                cancelledId = id;
              },
            ),
          ),
        ),
      );

      await tester.pump();

      // Should show enabled Cancel button
      final cancelButton = find.byType(TextButton);
      expect(cancelButton, findsOneWidget);

      await tester.tap(cancelButton);
      await tester.pump();

      expect(cancelledId, 'fetch-1');
    });

    testWidgets('repo status zone visible even with task in progress', (
      tester,
    ) async {
      final task = BackgroundTask(
        id: 'fetch-1',
        label: 'Fetching',
        current: 50,
        total: 100,
        cancellable: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'develop',
              ahead: 3,
              behind: 2,
              commitCount: 99,
              lastScanDuration: const Duration(milliseconds: 200),
              graphLaneCapacity: 12,
              backgroundTasks: [task],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
            ),
          ),
        ),
      );

      await tester.pump();

      // Both repo status and task should be visible
      expect(find.text('develop ↑3 ↓2'), findsOneWidget);
      expect(find.text('Fetching — 50 / 100'), findsOneWidget);
    });

    testWidgets('displays rebase conflict status with danger background', (
      tester,
    ) async {
      final repoState = RepoState(
        flags: RepoStateFlags.rebaseMerge,
        isClean: false,
        isSequencerOperation: true,
        rebaseStep: 3,
        rebaseTotal: 8,
        rebaseOntoLabel: 'main',
        indexLocked: false,
        indexLockAgeSeconds: null,
        describe: 'rebasing',
      );
      final workingCopyStatus = _createConflictedStatus([
        'file1.dart',
        'file2.dart',
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 2,
              behind: 0,
              commitCount: 42,
              lastScanDuration: const Duration(milliseconds: 150),
              graphLaneCapacity: 8,
              backgroundTasks: const [],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
              repoState: repoState,
              workingCopyStatus: workingCopyStatus,
              conflictActive: true,
            ),
          ),
        ),
      );

      await tester.pump();

      // Should have danger background (check for danger color)
      final colors = buildGbmTheme(GbmThemeVariant.darkTechnical)
          .extension<GbmColors>()!;
      final container = find
          .descendant(
            of: find.byType(StatusBar),
            matching: find.byType(Container),
          )
          .first;
      final containerWidget = tester.widget<Container>(container);
      final decoration = containerWidget.decoration as BoxDecoration?;
      expect(
        decoration?.color,
        colors.danger.withValues(alpha: 0.15),
        reason: 'Background should be danger color when conflict is active',
      );

      // Should show full conflict label with step/total
      expect(find.text('REBASE 3/8 · 2 conflicted'), findsOneWidget);
    });

    testWidgets('displays merge conflict status with operation name only', (
      tester,
    ) async {
      final repoState = RepoState(
        flags: RepoStateFlags.merge,
        isClean: false,
        isSequencerOperation: true,
        rebaseStep: 0,
        rebaseTotal: 0,
        rebaseOntoLabel: '',
        indexLocked: false,
        indexLockAgeSeconds: null,
        describe: 'merging',
      );
      final workingCopyStatus = _createConflictedStatus(['conflict.txt']);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 0,
              behind: 0,
              commitCount: 10,
              lastScanDuration: const Duration(milliseconds: 100),
              graphLaneCapacity: 6,
              backgroundTasks: const [],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
              repoState: repoState,
              workingCopyStatus: workingCopyStatus,
              conflictActive: true,
            ),
          ),
        ),
      );

      await tester.pump();

      // Should show full conflict label (operation + conflict count, no step/total)
      expect(find.text('MERGE · 1 conflicted'), findsOneWidget);
    });

    testWidgets('displays cherry-pick conflict status', (tester) async {
      final repoState = RepoState(
        flags: RepoStateFlags.cherryPick,
        isClean: false,
        isSequencerOperation: true,
        rebaseStep: 0,
        rebaseTotal: 0,
        rebaseOntoLabel: '',
        indexLocked: false,
        indexLockAgeSeconds: null,
        describe: 'cherry-picking',
      );
      final workingCopyStatus = _createConflictedStatus([
        'a.txt',
        'b.txt',
        'c.txt',
      ]);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 0,
              behind: 0,
              commitCount: 10,
              lastScanDuration: const Duration(milliseconds: 100),
              graphLaneCapacity: 6,
              backgroundTasks: const [],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
              repoState: repoState,
              workingCopyStatus: workingCopyStatus,
              conflictActive: true,
            ),
          ),
        ),
      );

      await tester.pump();

      // Should show full conflict label
      expect(find.text('CHERRY-PICK · 3 conflicted'), findsOneWidget);
    });

    testWidgets('displays revert conflict status', (tester) async {
      final repoState = RepoState(
        flags: RepoStateFlags.revert,
        isClean: false,
        isSequencerOperation: true,
        rebaseStep: 0,
        rebaseTotal: 0,
        rebaseOntoLabel: '',
        indexLocked: false,
        indexLockAgeSeconds: null,
        describe: 'reverting',
      );
      final workingCopyStatus = _createConflictedStatus(['x.dart']);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 0,
              behind: 0,
              commitCount: 10,
              lastScanDuration: const Duration(milliseconds: 100),
              graphLaneCapacity: 6,
              backgroundTasks: const [],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
              repoState: repoState,
              workingCopyStatus: workingCopyStatus,
              conflictActive: true,
            ),
          ),
        ),
      );

      await tester.pump();

      // Should show full conflict label
      expect(find.text('REVERT · 1 conflicted'), findsOneWidget);
    });

    testWidgets('normal status bar when no conflict', (tester) async {
      final repoState = RepoState(
        flags: 0,
        isClean: true,
        isSequencerOperation: false,
        rebaseStep: 0,
        rebaseTotal: 0,
        rebaseOntoLabel: '',
        indexLocked: false,
        indexLockAgeSeconds: null,
        describe: 'normal',
      );
      final workingCopyStatus = const WorkingCopyStatus(entries: []);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 0,
              behind: 0,
              commitCount: 10,
              lastScanDuration: const Duration(milliseconds: 100),
              graphLaneCapacity: 6,
              backgroundTasks: const [],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
              repoState: repoState,
              workingCopyStatus: workingCopyStatus,
              conflictActive: false,
            ),
          ),
        ),
      );

      await tester.pump();

      // Should show normal branch status
      expect(find.textContaining('main ↑'), findsWidgets);
      // Should NOT show conflict status labels
      expect(find.textContaining('conflicted'), findsNothing);
    });

    testWidgets('shows just conflict count when no operation name', (
      tester,
    ) async {
      // Edge case: conflict active but no operation name
      // (e.g., git apply --3way case)
      final repoState = RepoState(
        flags: 0, // No operation flags set
        isClean: false,
        isSequencerOperation: false, // Not a sequencer operation
        rebaseStep: 0,
        rebaseTotal: 0,
        rebaseOntoLabel: '',
        indexLocked: false,
        indexLockAgeSeconds: null,
        describe: 'normal',
      );
      final workingCopyStatus = _createConflictedStatus(['conflict.txt']);

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 0,
              behind: 0,
              commitCount: 10,
              lastScanDuration: const Duration(milliseconds: 100),
              graphLaneCapacity: 6,
              backgroundTasks: const [],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
              repoState: repoState,
              workingCopyStatus: workingCopyStatus,
              conflictActive: true,
            ),
          ),
        ),
      );

      await tester.pump();

      // Should show just the conflict count when no operation name
      expect(find.text('1 conflicted'), findsOneWidget);
    });
    testWidgets('renders the selection summary alongside repo status', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 0,
              behind: 0,
              commitCount: 42,
              lastScanDuration: const Duration(milliseconds: 100),
              graphLaneCapacity: 6,
              backgroundTasks: const [],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
              selectionSummary: '4 commits \u00b7 contiguous',
            ),
          ),
        ),
      );

      await tester.pump();

      // Additive, not a replacement: spec page 13 asks for the summary in the
      // status bar without taking the repo status away.
      expect(find.text('4 commits \u00b7 contiguous'), findsOneWidget);
      expect(find.textContaining('main ↑'), findsOneWidget);
      expect(find.text('42c'), findsOneWidget);
    });

    testWidgets('omits the selection summary when it is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 0,
              behind: 0,
              commitCount: 42,
              lastScanDuration: const Duration(milliseconds: 100),
              graphLaneCapacity: 6,
              backgroundTasks: const [],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
            ),
          ),
        ),
      );

      await tester.pump();

      expect(find.textContaining('commits'), findsNothing);
    });

    testWidgets('a conflict takes zone 1 from the selection summary', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 0,
              behind: 0,
              commitCount: 42,
              lastScanDuration: const Duration(milliseconds: 100),
              graphLaneCapacity: 6,
              backgroundTasks: const [],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
              repoState: const RepoState(
                flags: RepoStateFlags.merge,
                isClean: false,
                isSequencerOperation: true,
                rebaseStep: 0,
                rebaseTotal: 0,
                rebaseOntoLabel: '',
                indexLocked: false,
                indexLockAgeSeconds: null,
                describe: 'merging',
              ),
              workingCopyStatus: _createConflictedStatus(<String>['a.txt']),
              conflictActive: true,
              selectionSummary: '4 commits \u00b7 contiguous',
            ),
          ),
        ),
      );

      await tester.pump();

      // The stopped sequencer is the thing that must be readable at a glance.
      expect(find.text('MERGE \u00b7 1 conflicted'), findsOneWidget);
      expect(find.text('4 commits \u00b7 contiguous'), findsNothing);
    });
  });
  group('StatusBar upstreamGone', () {
    Future<void> pump(
      WidgetTester tester, {
      required bool upstreamGone,
      int ahead = 2,
      int behind = 1,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: ahead,
              behind: behind,
              upstreamGone: upstreamGone,
              commitCount: 42,
              lastScanDuration: const Duration(milliseconds: 150),
              graphLaneCapacity: 8,
              backgroundTasks: const [],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('replaces the ahead/behind counts', (tester) async {
      // Spec page 02: 「status bar 的 ahead/behind 改顯示 upstream gone」.
      // Replaces, not joins: the counts are measured against an upstream
      // that no longer exists, so showing "2↑ 1↓ upstream gone" would state
      // a distance from nothing.
      await pump(tester, upstreamGone: true);

      expect(find.text('upstream gone'), findsOneWidget);
      expect(find.text('main ↑2 ↓1'), findsNothing);
      expect(find.text('main'), findsOneWidget);
    });

    testWidgets('leaves the branch name and commit count alone', (
      tester,
    ) async {
      await pump(tester, upstreamGone: true);

      expect(find.text('main'), findsWidgets);
      expect(find.text('42c'), findsOneWidget);
    });

    testWidgets('false keeps the existing counts', (tester) async {
      await pump(tester, upstreamGone: false);

      expect(find.text('upstream gone'), findsNothing);
      expect(find.text('main ↑2 ↓1'), findsOneWidget);
    });

    testWidgets('shows even with zero ahead and behind', (tester) async {
      // A branch in sync when its upstream vanished reports 0/0, which
      // renders nothing at all today -- exactly the case where the user has
      // no other signal that the upstream is gone.
      await pump(tester, upstreamGone: true, ahead: 0, behind: 0);

      expect(find.text('upstream gone'), findsOneWidget);
    });
  });

  group('showRefreshTimings', () {
    Future<void> pumpWithTimings(
      WidgetTester tester, {
      required bool showRefreshTimings,
      RefreshTimings refreshTimings = const RefreshTimings(),
    }) {
      return tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 0,
              behind: 0,
              commitCount: 3,
              lastScanDuration: const Duration(milliseconds: 10),
              graphLaneCapacity: 4,
              backgroundTasks: const [],
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
              showRefreshTimings: showRefreshTimings,
              refreshTimings: refreshTimings,
            ),
          ),
        ),
      );
    }

    testWidgets('off by default: no timing text even with landed stamps', (
      tester,
    ) async {
      final DateTime focus = DateTime(2026, 1, 1, 12, 0, 0, 0);
      await pumpWithTimings(
        tester,
        showRefreshTimings: false,
        refreshTimings: RefreshTimings(
          focusAt: focus,
          refsAt: focus.add(const Duration(milliseconds: 7)),
        ),
      );

      expect(find.textContaining('refs'), findsNothing);
    });

    testWidgets('on, but nothing has landed yet: draws nothing', (
      tester,
    ) async {
      await pumpWithTimings(
        tester,
        showRefreshTimings: true,
        refreshTimings: const RefreshTimings(),
      );

      expect(find.textContaining('refs'), findsNothing);
      expect(find.textContaining('status'), findsNothing);
      expect(find.textContaining('diff'), findsNothing);
    });

    testWidgets('on, with landed stamps: paints refreshTimingsLabel verbatim', (
      tester,
    ) async {
      final DateTime focus = DateTime(2026, 1, 1, 12, 0, 0, 0);
      final RefreshTimings timings = RefreshTimings(
        focusAt: focus,
        refsAt: focus.add(const Duration(milliseconds: 7)),
        statusAt: focus.add(const Duration(milliseconds: 32)),
        firstDiffAt: focus.add(const Duration(milliseconds: 118)),
      );
      await pumpWithTimings(
        tester,
        showRefreshTimings: true,
        refreshTimings: timings,
      );

      // Asserted against the real formatter rather than a literal string, so
      // this test cannot drift from refreshTimingsLabel's own stage order.
      expect(find.text(refreshTimingsLabel(timings)), findsOneWidget);
    });
  });

  // Spec page 10 TASKS: a task whose total is not known yet is still running,
  // and has to look like it. `value: 0.0` drew a static empty track with an
  // "N/0" count -- indistinguishable from nothing happening.
  group('StatusBar progress for a task with no known total', () {
    Future<void> pumpTasks(
      WidgetTester tester,
      List<BackgroundTask> tasks,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: StatusBar(
              currentBranch: 'main',
              ahead: 0,
              behind: 0,
              commitCount: 10,
              lastScanDuration: const Duration(milliseconds: 100),
              graphLaneCapacity: 6,
              backgroundTasks: tasks,
              onOpenError: () {},
              onToggleLog: () {},
              onCancelTask: (_) {},
            ),
          ),
        ),
      );
      await tester.pump();
    }

    BackgroundTask scan({int current = 1200, int total = 0}) => BackgroundTask(
      id: 'history-scan',
      label: 'Reading history',
      current: current,
      total: total,
      cancellable: false,
    );

    testWidgets('total 0 draws an animated (indeterminate) bar', (
      tester,
    ) async {
      await pumpTasks(tester, <BackgroundTask>[scan()]);

      final LinearProgressIndicator bar = tester
          .widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          );
      expect(bar.value, isNull);
    });

    testWidgets('total 0 shows the count alone, never "N/0"', (tester) async {
      await pumpTasks(tester, <BackgroundTask>[scan()]);

      expect(find.text('Reading history — 1,200'), findsOneWidget);
      expect(find.textContaining('/ 0'), findsNothing);
    });

    testWidgets('a git task counts nothing, so it draws no count at all', (
      tester,
    ) async {
      // Core reports no object counts (使用者裁定: 計數「改spec，沒有計畫」),
      // so `gitCommand` is current 0 / total 0. A lone "0" beside the bar
      // reads as an object count that is stuck.
      await pumpTasks(tester, <BackgroundTask>[
        BackgroundTask.gitCommand(
          id: 'git-1',
          label: 'Pushing origin',
          queuedOperationId: 7,
        ),
      ]);

      expect(find.text('Pushing origin'), findsOneWidget);
      expect(find.textContaining('—'), findsNothing);
    });

    testWidgets('a known total keeps a determinate bar and "N/M"', (
      tester,
    ) async {
      await pumpTasks(tester, <BackgroundTask>[scan(current: 50, total: 100)]);

      final LinearProgressIndicator bar = tester
          .widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          );
      expect(bar.value, 0.5);
      expect(find.text('Reading history — 50 / 100'), findsOneWidget);
    });

    testWidgets('a finished task lingers as a full bar, not a spinning one', (
      tester,
    ) async {
      await pumpTasks(tester, <BackgroundTask>[scan()]);
      await pumpTasks(tester, const <BackgroundTask>[]);

      final LinearProgressIndicator bar = tester
          .widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          );
      expect(bar.value, 1.0);

      // The linger timer is 3 s; let it fire so no timer outlives the test.
      await tester.pump(const Duration(seconds: 3));
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('a sequencer stopped on the user draws a still bar', (
      tester,
    ) async {
      // A merge stopped at a conflict has no step count (total 0) but nothing
      // is running: animating it would claim work that is not happening.
      await pumpTasks(tester, <BackgroundTask>[
        BackgroundTask.stoppedSequencer(
          id: 'sequencer',
          label: 'Merging',
          current: 0,
          total: 0,
        ),
      ]);

      final LinearProgressIndicator bar = tester
          .widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          );
      expect(bar.value, 0.0);
    });

    testWidgets('a task that starts during the linger is shown at once', (
      tester,
    ) async {
      // A pull with stash-first runs `stash push` then `pull`: the second
      // must not sit hidden behind the first one's 3-second linger.
      await pumpTasks(tester, <BackgroundTask>[scan()]);
      await pumpTasks(tester, const <BackgroundTask>[]);
      expect(find.text('Reading history — 1,200'), findsOneWidget);

      await pumpTasks(tester, <BackgroundTask>[
        BackgroundTask.gitCommand(
          id: 'git-9',
          label: 'Pulling',
          queuedOperationId: 4,
        ),
      ]);

      expect(find.text('Pulling'), findsOneWidget);
      expect(find.textContaining('Reading history'), findsNothing);

      // And when that one finishes, it is the one that lingers.
      await pumpTasks(tester, const <BackgroundTask>[]);
      expect(find.text('Pulling'), findsOneWidget);
      expect(find.textContaining('Reading history'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a folded task with total 0 is indeterminate too', (
      tester,
    ) async {
      await pumpTasks(tester, <BackgroundTask>[
        scan(current: 50, total: 100),
        BackgroundTask(
          id: 'git-7',
          label: 'Fetching origin',
          current: 0,
          total: 0,
          cancellable: false,
        ),
      ]);
      await tester.tap(find.text('+1 task'));
      // Not pumpAndSettle: an indeterminate bar never settles
      // ([TEST-no-pumpandsettle-with-spinner]).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final List<LinearProgressIndicator> bars = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .toList();
      expect(bars.map((b) => b.value), <double?>[0.5, null]);
    });
  });

  // P10's status bar mock, taken whole (open-with-apps-spec.html screen 3,
  // rulings Q2「這個分支整條 bar 改成照 mock」 and Q7「S1–S8 全做」). The
  // container, verbatim: `gap:9px;height:26px;padding:0 10px;
  // background:var(--surface-panel);font-size:10.5px;color:var(--text-tertiary)`.
  group('StatusBar follows the P10 mock', () {
    final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);

    Future<void> pumpBar(
      WidgetTester tester, {
      List<BackgroundTask> tasks = const <BackgroundTask>[],
      int ahead = 2,
      int behind = 0,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: StatusBar(
                currentBranch: 'main',
                ahead: ahead,
                behind: behind,
                commitCount: 10,
                lastScanDuration: const Duration(milliseconds: 100),
                graphLaneCapacity: 6,
                backgroundTasks: tasks,
                onOpenError: () {},
                onToggleLog: () {},
                onCancelTask: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    BackgroundTask clone({int current = 12480, int total = 31206}) =>
        BackgroundTask(
          id: 'clone',
          label: 'Cloning design-tokens',
          current: current,
          total: total,
          cancellable: true,
        );

    // The painted style, not `Text.style`: the bar sets its size and colour
    // once through DefaultTextStyle, so a field read would see null.
    TextStyle styleOf(WidgetTester tester, String text) =>
        tester.renderObject<RenderParagraph>(find.text(text)).text.style!;

    testWidgets('S1: 26 high, 10 from the left edge', (tester) async {
      await pumpBar(tester);
      expect(tester.getSize(find.byType(StatusBar)).height, 26);
      expect(
        tester.getTopLeft(find.text('main ↑2 ↓0')).dx -
            tester.getTopLeft(find.byType(StatusBar)).dx,
        10,
      );
    });

    testWidgets('S2: the branch run is 10.5 textTertiary, not emphasised', (
      tester,
    ) async {
      await pumpBar(tester);
      final TextStyle style = styleOf(tester, 'main ↑2 ↓0');
      expect(style.fontSize, 10.5);
      expect(style.color, colors.textTertiary);
      expect(style.fontWeight, isNot(GbmTypography.weightMedium));
      expect(styleOf(tester, '10c').fontSize, 10.5);
    });

    testWidgets('S3: arrows lead, and a zero is still written', (tester) async {
      await pumpBar(tester, ahead: 0, behind: 0);
      expect(find.text('main ↑0 ↓0'), findsOneWidget);
    });

    testWidgets('items sit 9 apart', (tester) async {
      await pumpBar(tester);
      expect(
        tester.getTopLeft(find.text('10c')).dx -
            tester.getTopRight(find.text('main ↑2 ↓0')).dx,
        9,
      );
    });

    testWidgets('S5: a 1×12 rule after zone 1, and one before +N task', (
      tester,
    ) async {
      final Finder rules = find.byKey(const ValueKey<String>('status-rule'));
      await pumpBar(tester, tasks: <BackgroundTask>[clone()]);
      expect(rules, findsOneWidget);
      expect(tester.getSize(rules), const Size(1, 12));
      expect((tester.widget<Container>(rules).color), colors.borderSubtle);

      await pumpBar(
        tester,
        tasks: <BackgroundTask>[
          clone(),
          clone().copyWith(id: 'b'),
        ],
      );
      expect(rules, findsNWidgets(2));
      expect(
        tester.getTopLeft(rules.last).dx,
        lessThan(tester.getTopLeft(find.text('+1 task')).dx),
      );
      expect(
        tester.getTopLeft(rules.last).dx,
        greaterThan(tester.getTopLeft(find.text('Cancel')).dx),
      );
      await tester.pumpWidget(const SizedBox());
    });

    // W-D7: TASKS' two phases 「各自顯示實際數字」 -- without the phase word
    // the count restarting at resolving would read as going backwards.
    testWidgets('a task with a phase names it before the count', (
      tester,
    ) async {
      await pumpBar(
        tester,
        tasks: <BackgroundTask>[
          BackgroundTask.cloneJob(
            id: 'clone-1',
            label: 'Cloning design-tokens',
            phase: 'resolving deltas',
            current: 3912,
            total: 20477,
          ),
        ],
      );
      expect(
        find.text('Cloning design-tokens — resolving deltas 3,912 / 20,477'),
        findsOneWidget,
      );
    });

    testWidgets('S6: one line -- loader, label with count, 74×4 bar, Cancel', (
      tester,
    ) async {
      await pumpBar(tester, tasks: <BackgroundTask>[clone()]);

      // The Log entry's terminal icon is a LucideIcon too; ask by name.
      final LucideIcon loader = tester.widget<LucideIcon>(
        find.byWidgetPredicate(
          (Widget w) => w is LucideIcon && w.name == 'loader-circle',
        ),
      );
      expect(loader.size, 12);
      expect(loader.color, colors.accent);

      final Finder label = find.text('Cloning design-tokens — 12,480 / 31,206');
      expect(label, findsOneWidget);

      final Finder bar = find.byType(LinearProgressIndicator);
      expect(tester.getSize(bar), const Size(74, 4));
      final LinearProgressIndicator indicator = tester
          .widget<LinearProgressIndicator>(bar);
      expect(indicator.backgroundColor, colors.surfaceSunken);
      expect(
        (indicator.valueColor! as AlwaysStoppedAnimation<Color>).value,
        colors.accent,
      );
      expect(
        tester
            .widget<ClipRRect>(
              find.ancestor(of: bar, matching: find.byType(ClipRRect)),
            )
            .borderRadius,
        BorderRadius.circular(999),
      );

      // Same row, in the mock's order.
      final double y = tester.getCenter(label).dy;
      expect(tester.getCenter(bar).dy, y);
      expect(tester.getCenter(find.text('Cancel')).dy, y);
      expect(
        tester.getTopLeft(bar).dx,
        greaterThan(tester.getTopRight(label).dx),
      );
      expect(
        tester.getTopLeft(find.text('Cancel')).dx,
        greaterThan(tester.getTopRight(bar).dx),
      );
      final TextStyle cancel = styleOf(tester, 'Cancel');
      expect(cancel.color, colors.textLink);
      expect(cancel.fontSize, 10.5);
    });

    testWidgets('counts are grouped by thousands', (tester) async {
      await pumpBar(
        tester,
        tasks: <BackgroundTask>[clone(current: 100000, total: 1000000)],
      );
      expect(
        find.text('Cloning design-tokens — 100,000 / 1,000,000'),
        findsOneWidget,
      );
      await pumpBar(
        tester,
        tasks: <BackgroundTask>[clone(current: 999, total: 1000)],
      );
      expect(find.text('Cloning design-tokens — 999 / 1,000'), findsOneWidget);
    });

    testWidgets('S7: +N task is textTertiary', (tester) async {
      await pumpBar(
        tester,
        tasks: <BackgroundTask>[
          clone(),
          clone().copyWith(id: 'b'),
        ],
      );
      expect(styleOf(tester, '+1 task').color, colors.textTertiary);
      expect(styleOf(tester, '+1 task').fontSize, 10.5);
    });
  });

  // Zone 3, P10 #3: 「有 error 未讀時……常駐紅色摘要，可點開直接跳到該筆
  // log」. The mock: `{{ icErr }}Push rejected` (`gap:5px;color:
  // var(--danger)`) then `{{ icTerminal }}Log` (`gap:4px`), at the right end
  // (rulings 「照 mockup：右端、Log 左邊」, Q6 Toggle).
  // The no-repository window (P15 A #5) reuses this bar: zone 1 states the
  // scan result in place of a branch, zones 2 and 3 are unchanged.
  group('StatusBar.window', () {
    Future<void> pumpWindow(
      WidgetTester tester, {
      List<BackgroundTask> tasks = const <BackgroundTask>[],
      GbmLogEntry? unread,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: StatusBar.window(
                windowSummary: '掃描 3 個來源資料夾 · 找到 41 個 repository · 331 ms',
                backgroundTasks: tasks,
                unreadError: unread,
                onOpenError: () {},
                onToggleLog: () {},
                onCancelTask: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('zone 1 is the summary, with no branch or commit count', (
      tester,
    ) async {
      await pumpWindow(tester);
      expect(
        find.text('掃描 3 個來源資料夾 · 找到 41 個 repository · 331 ms'),
        findsOneWidget,
      );
      expect(find.textContaining('↑'), findsNothing);
      expect(find.text('0c'), findsNothing);
      expect(find.text('Log'), findsOneWidget);
    });

    testWidgets('keeps the progress zone and the error summary', (
      tester,
    ) async {
      await pumpWindow(
        tester,
        tasks: const <BackgroundTask>[
          BackgroundTask(
            id: 'clone-1',
            label: 'Cloning design-tokens',
            current: 12480,
            total: 31206,
            cancellable: true,
          ),
        ],
        unread: const AppLogEntry(
          whenEpochMs: 1,
          level: OperationLogLevel.error,
          message: 'git clone failed',
        ),
      );
      expect(
        find.text('Cloning design-tokens — 12,480 / 31,206'),
        findsOneWidget,
      );
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('git clone failed'), findsOneWidget);
    });
  });

  group('StatusBar zone 3: error summary and Log entry', () {
    final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);
    const AppLogEntry error = AppLogEntry(
      whenEpochMs: 1,
      level: OperationLogLevel.error,
      message: 'Could not run "Rider": zsh:1: command not found: rider',
    );

    late int opened;
    late int toggled;

    Future<void> pumpZone3(WidgetTester tester, {GbmLogEntry? unread}) async {
      opened = 0;
      toggled = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: StatusBar(
                currentBranch: 'main',
                ahead: 0,
                behind: 0,
                commitCount: 10,
                lastScanDuration: const Duration(milliseconds: 100),
                graphLaneCapacity: 6,
                backgroundTasks: const <BackgroundTask>[],
                unreadError: unread,
                onOpenError: () => opened++,
                onToggleLog: () => toggled++,
                onCancelTask: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    LucideIcon iconBefore(WidgetTester tester, String text) => tester
        .widgetList<LucideIcon>(find.byType(LucideIcon))
        .lastWhere(
          (LucideIcon icon) =>
              tester.getTopLeft(find.byWidget(icon)).dx <
              tester.getTopLeft(find.text(text)).dx,
        );

    testWidgets('the Log entry is always there, at the right edge', (
      tester,
    ) async {
      await pumpZone3(tester);
      expect(find.text('Log'), findsOneWidget);
      expect(find.byType(GbmBadge), findsNothing);
      expect(
        tester.getTopRight(find.byType(StatusBar)).dx -
            tester.getTopRight(find.text('Log')).dx,
        10,
      );
      final LucideIcon icon = iconBefore(tester, 'Log');
      expect(icon.name, 'terminal');
      expect(icon.size, 12);
      expect(icon.color, colors.textTertiary);
      expect(
        tester.getTopLeft(find.text('Log')).dx -
            tester.getTopRight(find.byWidget(icon)).dx,
        4,
      );
    });

    testWidgets('no unread error: no summary at all', (tester) async {
      await pumpZone3(tester);
      expect(find.textContaining('Could not run'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is LucideIcon && w.name == 'circle-x',
        ),
        findsNothing,
      );
    });

    testWidgets('an unread error: a red summary left of Log', (tester) async {
      await pumpZone3(tester, unread: error);
      final Finder summary = find.text(error.message);
      expect(summary, findsOneWidget);
      final RenderParagraph paragraph = tester.renderObject<RenderParagraph>(
        summary,
      );
      expect(paragraph.text.style!.color, colors.danger);
      expect(paragraph.text.style!.fontSize, 10.5);
      expect(
        tester.getTopRight(summary).dx,
        lessThan(tester.getTopLeft(find.text('Log')).dx),
      );
      final LucideIcon icon = iconBefore(tester, error.message);
      expect(icon.name, 'circle-x');
      expect(icon.size, 12);
      expect(icon.color, colors.danger);
      expect(
        tester.getTopLeft(summary).dx -
            tester.getTopRight(find.byWidget(icon)).dx,
        5,
      );
      expect(find.byType(GbmBadge), findsNothing);
    });

    testWidgets('a long summary stops at 320 and says the rest on hover', (
      tester,
    ) async {
      final AppLogEntry long = AppLogEntry(
        whenEpochMs: 1,
        level: OperationLogLevel.error,
        message: 'x' * 400,
      );
      await pumpZone3(tester, unread: long);
      final Finder summary = find.byKey(
        const ValueKey<String>('status-error-summary'),
      );
      expect(tester.getSize(summary).width, lessThanOrEqualTo(320));
      final Text text = tester.widget<Text>(find.text(long.message));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(find.byTooltip(long.message), findsOneWidget);
    });

    testWidgets('the summary jumps; Log toggles', (tester) async {
      await pumpZone3(tester, unread: error);
      await tester.tap(find.text(error.message));
      expect((opened, toggled), (1, 0));
      await tester.tap(find.text('Log'));
      expect((opened, toggled), (1, 1));
    });

    testWidgets('both show a click cursor', (tester) async {
      await pumpZone3(tester, unread: error);
      for (final String text in <String>[error.message, 'Log']) {
        final MouseRegion region = tester.widget<MouseRegion>(
          find
              .ancestor(of: find.text(text), matching: find.byType(MouseRegion))
              .first,
        );
        expect(region.cursor, SystemMouseCursors.click, reason: text);
      }
    });
  });
}
