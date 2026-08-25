import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/status_bar/background_task.dart';
import 'package:gbm_flutter/features/status_bar/status_bar.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_badge.dart';

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
              hasUnreadLog: false,
              onOpenLog: () {},
              onCancelTask: (_) {},
            ),
          ),
        ),
      );

      await tester.pump();

      // Should show branch name
      expect(find.text('main'), findsWidgets);
      // Should show ahead/behind (compact format with arrows)
      expect(find.text('2↑'), findsOneWidget);
      expect(find.text('1↓'), findsOneWidget);
    });

    testWidgets('shows error badge when hasUnreadLog is true', (tester) async {
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
              hasUnreadLog: true,
              onOpenLog: () {},
              onCancelTask: (_) {},
            ),
          ),
        ),
      );

      await tester.pump();

      // Should show error badge (GbmBadge with ! label)
      expect(find.byType(GbmBadge), findsOneWidget);
      expect(find.text('!'), findsOneWidget);
    });

    testWidgets('shows single task in progress zone', (tester) async {
      final task = BackgroundTask.fetch(
        id: 'fetch-1',
        label: 'Fetching',
        current: 50,
        total: 100,
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
              hasUnreadLog: false,
              onOpenLog: () {},
              onCancelTask: (_) {},
            ),
          ),
        ),
      );

      await tester.pump();

      // Should show task label
      expect(find.text('Fetching'), findsOneWidget);
      // Should show progress indicator
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('folds N>1 tasks to "+N task" text', (tester) async {
      final tasks = [
        BackgroundTask.fetch(
          id: 'fetch-1',
          label: 'Fetching',
          current: 50,
          total: 100,
        ),
        BackgroundTask.push(
          id: 'push-1',
          label: 'Pushing',
          current: 0,
          total: 1,
        ),
        BackgroundTask.pull(
          id: 'pull-1',
          label: 'Pulling',
          current: 0,
          total: 1,
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
              hasUnreadLog: false,
              onOpenLog: () {},
              onCancelTask: (_) {},
            ),
          ),
        ),
      );

      await tester.pump();

      // Should show fold indicator
      expect(find.text('+2 more'), findsOneWidget);
    });

    testWidgets('tapping "+N more" expands the folded tasks (spec page 10 '
        'STATUSPARTS #2: "其餘作業摺疊成 +N task，點了展開清單")', (tester) async {
      final tasks = [
        BackgroundTask.fetch(
          id: 'fetch-1',
          label: 'Fetching',
          current: 50,
          total: 100,
        ),
        BackgroundTask.push(
          id: 'push-1',
          label: 'Pushing',
          current: 0,
          total: 1,
        ),
        BackgroundTask.checkout(
          id: 'checkout-1',
          label: 'Checking out',
          current: 0,
          total: 1,
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
              hasUnreadLog: false,
              onOpenLog: () {},
              onCancelTask: (id) => cancelledId = id,
            ),
          ),
        ),
      );
      await tester.pump();

      // Before expanding: only the foreground task's label is visible,
      // the two folded ones are not.
      expect(find.text('Fetching'), findsOneWidget);
      expect(find.text('Pushing'), findsNothing);
      expect(find.text('Checking out'), findsNothing);

      await tester.tap(find.text('+2 more'));
      await tester.pumpAndSettle();

      // After expanding: both folded tasks' labels are now visible.
      expect(find.text('Pushing'), findsOneWidget);
      expect(find.text('Checking out'), findsOneWidget);

      // A cancellable folded task (push) has a live Cancel button that
      // reaches the same onCancelTask callback the foreground task uses.
      final Finder cancelButtons = find.widgetWithText(TextButton, 'Cancel');
      expect(cancelButtons, findsNWidgets(2));
      await tester.tap(cancelButtons.first);
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
      final task = BackgroundTask.checkout(
        id: 'checkout-1',
        label: 'Checking out',
        current: 0,
        total: 1,
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
              hasUnreadLog: false,
              onOpenLog: () {},
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
      final task = BackgroundTask.fetch(
        id: 'fetch-1',
        label: 'Fetching',
        current: 0,
        total: 1,
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
              hasUnreadLog: false,
              onOpenLog: () {},
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
      final task = BackgroundTask.fetch(
        id: 'fetch-1',
        label: 'Fetching',
        current: 50,
        total: 100,
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
              hasUnreadLog: false,
              onOpenLog: () {},
              onCancelTask: (_) {},
            ),
          ),
        ),
      );

      await tester.pump();

      // Both repo status and task should be visible
      expect(find.text('develop'), findsWidgets);
      expect(find.text('Fetching'), findsOneWidget);
      expect(find.text('3↑'), findsOneWidget);
    });

    testWidgets('tapping error badge calls onOpenLog', (tester) async {
      var logOpened = false;

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
              hasUnreadLog: true,
              onOpenLog: () {
                logOpened = true;
              },
              onCancelTask: (_) {},
            ),
          ),
        ),
      );

      await tester.pump();

      // Find and tap the error badge
      final badge = find.byType(GestureDetector);
      expect(badge, findsWidgets);

      // Tap the last badge (should be error badge)
      await tester.tap(badge.last);
      await tester.pump();

      expect(logOpened, isTrue);
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
              hasUnreadLog: false,
              onOpenLog: () {},
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
      final colors = buildGbmTheme(
        GbmThemeVariant.darkTechnical,
      ).extension<GbmColors>()!;
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
              hasUnreadLog: false,
              onOpenLog: () {},
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
              hasUnreadLog: false,
              onOpenLog: () {},
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
              hasUnreadLog: false,
              onOpenLog: () {},
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
              hasUnreadLog: false,
              onOpenLog: () {},
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
      expect(find.text('main'), findsWidgets);
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
              hasUnreadLog: false,
              onOpenLog: () {},
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
              hasUnreadLog: false,
              onOpenLog: () {},
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
      expect(find.text('main'), findsOneWidget);
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
              hasUnreadLog: false,
              onOpenLog: () {},
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
              hasUnreadLog: false,
              onOpenLog: () {},
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
              hasUnreadLog: false,
              onOpenLog: () {},
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
      expect(find.text('2↑'), findsNothing);
      expect(find.text('1↓'), findsNothing);
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
      expect(find.text('2↑'), findsOneWidget);
      expect(find.text('1↓'), findsOneWidget);
    });

    testWidgets('shows even with zero ahead and behind', (tester) async {
      // A branch in sync when its upstream vanished reports 0/0, which
      // renders nothing at all today -- exactly the case where the user has
      // no other signal that the upstream is gone.
      await pump(tester, upstreamGone: true, ahead: 0, behind: 0);

      expect(find.text('upstream gone'), findsOneWidget);
    });
  });
}
