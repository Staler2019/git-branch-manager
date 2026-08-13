import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/status_bar/background_task.dart';
import 'package:gbm_flutter/features/status_bar/status_bar.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_badge.dart';

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
  });
}
