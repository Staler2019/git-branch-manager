import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/features/log_drawer/log_drawer.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

void main() {
  group('LogDrawer', () {
    testWidgets('renders operation records with correct format', (
      tester,
    ) async {
      final records = [
        OperationRecord(
          whenEpochMs: 1692000000000,
          repoDir: '/path/to/repo',
          argv: ['git', 'fetch'],
          commandLine: 'git fetch',
          exitCode: 0,
          durationMs: 1500,
          stderrText: '',
          cancelled: false,
          timedOut: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(body: LogDrawer(records: records)),
        ),
      );

      await tester.pump();

      // Should show command
      expect(find.text('git fetch'), findsOneWidget);
      // Should show duration
      expect(find.text('1500ms'), findsOneWidget);
      // Should show a formatted time (HH:mm:ss, local time) -- computed the
      // same way the widget does rather than hardcoded, so this doesn't
      // depend on the test machine's timezone.
      final DateTime when = DateTime.fromMillisecondsSinceEpoch(1692000000000);
      final String expectedTime =
          '${when.hour.toString().padLeft(2, '0')}:'
          '${when.minute.toString().padLeft(2, '0')}:'
          '${when.second.toString().padLeft(2, '0')}';
      expect(find.text(expectedTime), findsOneWidget);
    });

    testWidgets('shows error level for failed operations', (tester) async {
      final records = [
        OperationRecord(
          whenEpochMs: 1692000000000,
          repoDir: '/path/to/repo',
          argv: ['git', 'push'],
          commandLine: 'git push',
          exitCode: 1,
          durationMs: 500,
          stderrText: 'Permission denied',
          cancelled: false,
          timedOut: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(body: LogDrawer(records: records)),
        ),
      );

      await tester.pump();

      // Should show exit code
      expect(find.text('exit 1'), findsOneWidget);
      // Should show stderr
      expect(find.text('Permission denied'), findsOneWidget);
    });

    testWidgets('shows cancelled indicator for cancelled tasks', (
      tester,
    ) async {
      final records = [
        OperationRecord(
          whenEpochMs: 1692000000000,
          repoDir: '/path/to/repo',
          argv: ['git', 'clone'],
          commandLine: 'git clone https://example.com/repo',
          exitCode: 0,
          durationMs: 300,
          stderrText: '',
          cancelled: true,
          timedOut: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(body: LogDrawer(records: records)),
        ),
      );

      await tester.pump();

      // Should show cancelled indicator (either as icon or text)
      expect(find.byType(Icon), findsWidgets);
    });

    testWidgets('Copy All button puts formatted text on clipboard', (
      tester,
    ) async {
      // Mock the platform channel directly rather than relying on
      // Clipboard.getData()'s real round-trip through flutter_test's
      // implicit clipboard fake, which was observed to hang indefinitely
      // in this suite (both isolated and as part of the full run).
      String? clipboardText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            clipboardText =
                (methodCall.arguments as Map<Object?, Object?>)['text']
                    as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      final records = [
        OperationRecord(
          whenEpochMs: 1692000000000,
          repoDir: '/path/to/repo',
          argv: ['git', 'fetch'],
          commandLine: 'git fetch origin',
          exitCode: 0,
          durationMs: 1000,
          stderrText: '',
          cancelled: false,
          timedOut: false,
        ),
        OperationRecord(
          whenEpochMs: 1692000001000,
          repoDir: '/path/to/repo',
          argv: ['git', 'push'],
          commandLine: 'git push origin main',
          exitCode: 0,
          durationMs: 500,
          stderrText: '',
          cancelled: false,
          timedOut: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(body: LogDrawer(records: records)),
        ),
      );

      await tester.pump();

      // Find and tap Copy All button
      final copyButton = find.text('Copy All');
      expect(copyButton, findsOneWidget);

      await tester.tap(copyButton);
      await tester.pump();

      // Verify clipboard data was set
      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('git fetch origin'));
      expect(clipboardText, contains('git push origin main'));
    });

    testWidgets('filter control hides non-matching entries', (tester) async {
      final records = [
        OperationRecord(
          whenEpochMs: 1692000000000,
          repoDir: '/path/to/repo',
          argv: ['git', 'fetch'],
          commandLine: 'git fetch',
          exitCode: 0,
          durationMs: 1000,
          stderrText: '',
          cancelled: false,
          timedOut: false,
        ),
        OperationRecord(
          whenEpochMs: 1692000001000,
          repoDir: '/path/to/repo',
          argv: ['git', 'push'],
          commandLine: 'git push',
          exitCode: 1,
          durationMs: 500,
          stderrText: 'Error',
          cancelled: false,
          timedOut: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(body: LogDrawer(records: records)),
        ),
      );

      await tester.pump();

      // Initially both should be visible
      expect(find.text('git fetch'), findsOneWidget);
      expect(find.text('git push'), findsOneWidget);

      // Tap the "Error" filter button specifically -- find.text('Error')
      // alone is ambiguous here because the failed record's stderrText is
      // also literally the string 'Error', so it would match both the
      // filter button and the rendered stderr text.
      final errorFilterButton = find.widgetWithText(TextButton, 'Error');
      expect(errorFilterButton, findsOneWidget);
      await tester.tap(errorFilterButton);
      await tester.pump();

      // After filtering, only the failed record should remain.
      expect(find.text('git push'), findsOneWidget);
      expect(find.text('git fetch'), findsNothing);
    });

    testWidgets('empty log shows message', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(body: LogDrawer(records: const [])),
        ),
      );

      await tester.pump();

      // Should show empty state message
      expect(find.text('No operations recorded yet'), findsOneWidget);
    });

    testWidgets('Save As button is present but may be disabled', (
      tester,
    ) async {
      final records = [
        OperationRecord(
          whenEpochMs: 1692000000000,
          repoDir: '/path/to/repo',
          argv: ['git', 'fetch'],
          commandLine: 'git fetch',
          exitCode: 0,
          durationMs: 1000,
          stderrText: '',
          cancelled: false,
          timedOut: false,
        ),
      ];

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(body: LogDrawer(records: records)),
        ),
      );

      await tester.pump();

      // Save As button should exist (may be disabled)
      final saveButton = find.text('Save As');
      expect(saveButton, findsWidgets);
    });
  });
}
