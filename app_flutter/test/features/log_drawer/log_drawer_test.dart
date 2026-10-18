import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/features/log_drawer/log_drawer.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/lucide_icon.dart';

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

  group('LogDrawer level filter partitions records', () {
    /// A superseded `for-each-ref`: Session::refreshHistory() SIGTERMs the
    /// in-flight read before posting a newer one, so it lands in the log as
    /// cancelled with 128 + SIGTERM = 143.
    OperationRecord cancelledRead() => OperationRecord(
      whenEpochMs: 1692000000000,
      repoDir: '/path/to/repo',
      argv: const <String>['git', 'for-each-ref'],
      commandLine: 'git for-each-ref',
      exitCode: 143,
      durationMs: 20,
      stderrText: '',
      cancelled: true,
      timedOut: false,
    );

    OperationRecord rejectedPush() => OperationRecord(
      whenEpochMs: 1692000001000,
      repoDir: '/path/to/repo',
      argv: const <String>['git', 'push'],
      commandLine: 'git push',
      exitCode: 1,
      durationMs: 500,
      stderrText: '',
      cancelled: false,
      timedOut: false,
    );

    Future<void> pumpWith(
      WidgetTester tester,
      List<OperationRecord> records,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(body: LogDrawer(records: records)),
        ),
      );
      await tester.pump();
    }

    Future<void> selectFilter(WidgetTester tester, String label) async {
      await tester.tap(find.widgetWithText(TextButton, label));
      await tester.pump();
    }

    testWidgets('Warning shows a cancelled record', (tester) async {
      await pumpWith(tester, <OperationRecord>[
        cancelledRead(),
        rejectedPush(),
      ]);
      await selectFilter(tester, 'Warning');

      expect(find.text('git for-each-ref'), findsOneWidget);
      expect(find.text('git push'), findsNothing);
    });

    testWidgets('Error does NOT also show the cancelled record', (
      tester,
    ) async {
      // The regression this pins: the warning predicate used to be
      // `failed && !cancelled && !timedOut` while the error predicate was
      // `cancelled || timedOut || exitCode != 0`, making warning a strict
      // subset of error -- so Error showed everything Warning did.
      await pumpWith(tester, <OperationRecord>[
        cancelledRead(),
        rejectedPush(),
      ]);
      await selectFilter(tester, 'Error');

      expect(find.text('git push'), findsOneWidget);
      expect(find.text('git for-each-ref'), findsNothing);
    });

    testWidgets('Info shows neither', (tester) async {
      await pumpWith(tester, <OperationRecord>[
        cancelledRead(),
        rejectedPush(),
      ]);
      await selectFilter(tester, 'Info');

      expect(find.text('git for-each-ref'), findsNothing);
      expect(find.text('git push'), findsNothing);
    });
  });

  group('LogDrawer row shows the level in words', () {
    Future<void> pumpWith(
      WidgetTester tester,
      List<OperationRecord> records,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(body: LogDrawer(records: records)),
        ),
      );
      await tester.pump();
    }

    OperationRecord recordWith({
      String commandLine = 'git status',
      int exitCode = 0,
      bool cancelled = false,
      bool timedOut = false,
      bool benignExit = false,
    }) {
      return OperationRecord(
        whenEpochMs: 1692000000000,
        repoDir: '/path/to/repo',
        argv: const <String>['git', 'status'],
        commandLine: commandLine,
        exitCode: exitCode,
        durationMs: 10,
        stderrText: '',
        cancelled: cancelled,
        timedOut: timedOut,
        benignExit: benignExit,
      );
    }

    testWidgets('a cancelled row reads CANCELLED, not just a red icon', (
      tester,
    ) async {
      // Before this, cancellation was signalled only by a red stop_circle
      // icon -- the same colour as a genuine failure, with no word anywhere
      // on screen to tell the two apart. The level strings existed only in
      // the export path.
      await pumpWith(tester, <OperationRecord>[
        recordWith(exitCode: 143, cancelled: true),
      ]);

      expect(find.text('CANCELLED'), findsOneWidget);
    });

    testWidgets('a rejected command reads ERROR', (tester) async {
      await pumpWith(tester, <OperationRecord>[recordWith(exitCode: 1)]);
      expect(find.text('ERROR'), findsOneWidget);
    });

    // The reported defect, at the surface that showed it: `git config --local
    // --get user.name` exits 1 when the key is unset, and every refresh drew
    // two of these in danger red.
    testWidgets('a declared answer reads INFO and draws no exit chip', (
      tester,
    ) async {
      await pumpWith(tester, <OperationRecord>[
        recordWith(
          commandLine: 'git config --local --get user.name',
          exitCode: 1,
          benignExit: true,
        ),
      ]);

      expect(find.text('INFO'), findsOneWidget);
      expect(find.text('ERROR'), findsNothing);
      // The chip and the icon are asserted separately on purpose: they are
      // two different reads of the same record, and an earlier draft fixed
      // only the level -- which would have left the row saying INFO next to a
      // red error icon.
      expect(find.text('exit 1'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is Icon && w.icon == Icons.error,
        ),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is Icon && w.icon == Icons.check_circle,
        ),
        findsOneWidget,
      );
    });

    testWidgets('the same row without the declaration still shouts', (
      tester,
    ) async {
      // The control. Without it the case above passes for a drawer that
      // stopped reading exitCode at all.
      await pumpWith(tester, <OperationRecord>[
        recordWith(
          commandLine: 'git config --local --get user.name',
          exitCode: 1,
        ),
      ]);

      expect(find.text('ERROR'), findsOneWidget);
      expect(find.text('exit 1'), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (Widget w) => w is Icon && w.icon == Icons.error,
        ),
        findsOneWidget,
      );
    });

    testWidgets('a timeout reads TIMEOUT', (tester) async {
      await pumpWith(tester, <OperationRecord>[
        recordWith(exitCode: 143, timedOut: true),
      ]);
      expect(find.text('TIMEOUT'), findsOneWidget);
    });

    testWidgets('a clean run reads INFO', (tester) async {
      await pumpWith(tester, <OperationRecord>[recordWith()]);
      expect(find.text('INFO'), findsOneWidget);
    });

    testWidgets('the command line renders control characters visibly', (
      tester,
    ) async {
      await pumpWith(tester, <OperationRecord>[
        recordWith(
          commandLine:
              'git for-each-ref "--format=%(refname)'
              '\u001f%(objecttype)"',
        ),
      ]);

      expect(
        find.text(r'git for-each-ref "--format=%(refname)\x1f%(objecttype)"'),
        findsOneWidget,
      );
    });
  });

  // Spec page 10's LOGRULES 記什麼 row asks for 「應用層事件（開啟 repo、切
  // 分支、prune 掉哪些 ref）」 alongside git invocations, and page 10's own
  // mockup draws one as a warning row with no exit code and no duration.
  group('LogDrawer renders app-level events', () {
    Future<void> pumpEntries(WidgetTester tester, List<GbmLogEntry> entries) {
      return tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(body: LogDrawer(records: entries)),
        ),
      );
    }

    const AppLogEntry goneMarked = AppLogEntry(
      whenEpochMs: 1692000000000,
      level: OperationLogLevel.warning,
      message:
          'origin/graph-lanes no longer exists on the remote '
          '- marked as gone (not pruned)',
    );

    testWidgets('an app event shows its message and level word', (
      tester,
    ) async {
      await pumpEntries(tester, <GbmLogEntry>[goneMarked]);

      expect(find.text(goneMarked.message), findsOneWidget);
      expect(find.text('WARNING'), findsOneWidget);
    });

    // An app event is not a process. Printing `0ms` beside it would read as
    // a git invocation that returned instantly.
    testWidgets('an app event shows no duration and no exit code', (
      tester,
    ) async {
      await pumpEntries(tester, <GbmLogEntry>[
        const AppLogEntry(
          whenEpochMs: 1692000000000,
          level: OperationLogLevel.error,
          message: 'Something went wrong',
        ),
      ]);

      expect(find.textContaining('ms'), findsNothing);
      expect(find.textContaining('exit '), findsNothing);
    });

    // The filter is the reason GbmLogEntry carries `level` rather than
    // leaving the drawer to pattern-match on the subtype: an app warning has
    // to land in the same bucket a cancelled git read does.
    testWidgets('an app warning is filtered as a warning, not as an error', (
      tester,
    ) async {
      await pumpEntries(tester, <GbmLogEntry>[goneMarked]);

      await tester.tap(find.text('Error'));
      await tester.pump();
      expect(find.text(goneMarked.message), findsNothing);

      await tester.tap(find.text('Warning'));
      await tester.pump();
      expect(find.text(goneMarked.message), findsOneWidget);
    });

    // The export and the row are one code path per field on purpose -- they
    // drifted apart once already (LOGRULES' three levels were not a
    // partition), so the `(exit N, Nms)` suffix has to be absent in both.
    testWidgets('the export writes no exit code for an app event', (
      tester,
    ) async {
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

      await pumpEntries(tester, <GbmLogEntry>[goneMarked]);
      await tester.tap(find.text('Copy All'));
      await tester.pump();

      expect(clipboardText, contains('WARNING'));
      expect(clipboardText, contains(goneMarked.message));
      expect(clipboardText, isNot(contains('exit ')));
      expect(clipboardText, isNot(contains('ms)')));
    });

    // The other half of "a benign row reads INFO": the screen stops shouting,
    // and the support artifact keeps the number. `_formatRecord` prints the
    // exit code for every OperationRecord regardless of level, and that is
    // load-bearing rather than incidental -- someone reading a copied log to
    // diagnose a bug needs to see that git answered 1, even though the row it
    // came from was not worth a red icon.
    testWidgets('the export still carries a benign exit code', (tester) async {
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

      await pumpEntries(tester, <GbmLogEntry>[
        OperationRecord(
          whenEpochMs: 1692000000000,
          repoDir: '/path/to/repo',
          argv: const <String>[
            'git',
            'config',
            '--local',
            '--get',
            'user.name',
          ],
          commandLine: 'git config --local --get user.name',
          exitCode: 1,
          durationMs: 3,
          stderrText: '',
          cancelled: false,
          timedOut: false,
          benignExit: true,
        ),
      ]);
      await tester.tap(find.text('Copy All'));
      await tester.pump();

      expect(clipboardText, contains('INFO'));
      expect(clipboardText, contains('(exit 1, 3ms)'));
    });
  });

  // 「新增 RUNNING 字樣」「最後面就不用執行中敘述了」.
  group('LogDrawer draws a running row', () {
    final OperationRecord running = OperationRecord(
      whenEpochMs: 1692000000000,
      repoDir: '/path/to/repo',
      argv: const <String>['git', 'diff', '--numstat'],
      commandLine: 'git diff --numstat',
      exitCode: 0,
      durationMs: 0,
      stderrText: '',
      cancelled: false,
      timedOut: false,
      id: 41,
      running: true,
    );

    Future<void> pumpRunning(
      WidgetTester tester, {
      bool reduceMotion = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduceMotion),
            child: Scaffold(body: LogDrawer(records: <GbmLogEntry>[running])),
          ),
        ),
      );
      await tester.pump();
    }

    Finder loader() => find.byWidgetPredicate(
      (Widget w) => w is LucideIcon && w.name == 'loader-circle',
    );

    testWidgets('the row reads RUNNING in the accent colour, with a loader', (
      tester,
    ) async {
      await pumpRunning(tester);

      final Text label = tester.widget<Text>(find.text('RUNNING'));
      final GbmColors colors = tester.element(find.text('RUNNING')).gbmColors;
      expect(label.style?.color, colors.accent);
      expect(find.text('INFO'), findsNothing);
      expect(loader(), findsOneWidget);
      expect(tester.widget<LucideIcon>(loader()).color, colors.accent);
      expect(find.byIcon(Icons.check_circle), findsNothing);
    });

    testWidgets('no duration and no exit while the outcome is unknown', (
      tester,
    ) async {
      await pumpRunning(tester);

      expect(find.text('0ms'), findsNothing);
      expect(find.textContaining('exit'), findsNothing);
      expect(find.textContaining('執行中'), findsNothing);
    });

    testWidgets('the loader turns, unless motion is reduced', (tester) async {
      await pumpRunning(tester);
      expect(
        find.ancestor(of: loader(), matching: find.byType(RotationTransition)),
        findsOneWidget,
      );

      await pumpRunning(tester, reduceMotion: true);
      expect(
        find.ancestor(of: loader(), matching: find.byType(RotationTransition)),
        findsNothing,
      );
      expect(loader(), findsOneWidget);
    });

    testWidgets('Info shows it and Error does not', (tester) async {
      await pumpRunning(tester);

      await tester.tap(find.text('Error'));
      await tester.pump();
      expect(find.text('git diff --numstat'), findsNothing);

      await tester.tap(find.text('Info'));
      await tester.pump();
      expect(find.text('git diff --numstat'), findsOneWidget);
    });

    testWidgets('the export writes RUNNING with no exit or duration', (
      tester,
    ) async {
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

      await pumpRunning(tester);
      await tester.tap(find.text('Copy All'));
      await tester.pump();

      expect(clipboardText, contains('RUNNING'));
      expect(clipboardText, contains('git diff --numstat'));
      expect(clipboardText, isNot(contains('exit ')));
      expect(clipboardText, isNot(contains('ms)')));
    });
  });

  // 「log限時欄位與作業時間隔開成為獨立一欄」「顯示欄位名稱應該是另一個開關」
  // 「你目前欄位名稱與欄位內容位置沒有對起來」 -- design spec screen 3.
  group('LogDrawer columns', () {
    OperationRecord git({
      required String commandLine,
      int exitCode = 0,
      int durationMs = 1500,
      bool timedOut = false,
      bool running = false,
      int timeoutMs = 120000,
      int idleTimeoutMs = 0,
      int id = 1,
    }) => OperationRecord(
      whenEpochMs: 1692000000000,
      repoDir: '/path/to/repo',
      argv: const <String>['git'],
      commandLine: commandLine,
      exitCode: exitCode,
      durationMs: durationMs,
      stderrText: '',
      cancelled: false,
      timedOut: timedOut,
      id: id,
      running: running,
      timeoutMs: timeoutMs,
      idleTimeoutMs: idleTimeoutMs,
    );

    final OperationRecord local = git(commandLine: 'git status', id: 1);
    final OperationRecord network = git(
      commandLine: 'git fetch --progress origin',
      exitCode: 1,
      durationMs: 61020,
      timedOut: true,
      timeoutMs: 0,
      idleTimeoutMs: 60000,
      id: 2,
    );
    final OperationRecord running = git(
      commandLine: 'git diff --numstat',
      running: true,
      durationMs: 0,
      id: 3,
    );

    Future<void> pumpDrawer(
      WidgetTester tester,
      List<GbmLogEntry> records, {
      bool showTimeouts = false,
      bool showColumnHeaders = false,
    }) async {
      await tester.binding.setSurfaceSize(const Size(1000, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: LogDrawer(
              records: records,
              showTimeouts: showTimeouts,
              showColumnHeaders: showColumnHeaders,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('no limit column and no header row by default', (tester) async {
      await pumpDrawer(tester, <GbmLogEntry>[local]);

      expect(find.text('限 120s'), findsNothing);
      expect(find.text('層級'), findsNothing);
    });

    testWidgets('the limit column says which limit each command ran under', (
      tester,
    ) async {
      await pumpDrawer(tester, <GbmLogEntry>[
        local,
        network,
        running,
      ], showTimeouts: true);

      expect(find.text('限 120s'), findsNWidgets(2), reason: 'local + running');
      expect(find.text('無傳輸 60s'), findsOneWidget);
    });

    testWidgets('the header row names the columns, 時限 only with its column', (
      tester,
    ) async {
      await pumpDrawer(tester, <GbmLogEntry>[local], showColumnHeaders: true);
      for (final String name in <String>['層級', '時間', '指令', '耗時', 'exit']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('時限'), findsNothing);

      await pumpDrawer(
        tester,
        <GbmLogEntry>[local],
        showColumnHeaders: true,
        showTimeouts: true,
      );
      expect(find.text('時限'), findsOneWidget);
    });

    // The defect the user reported on the first draft: names and contents
    // drifting apart. Every name is compared with the cell under it.
    testWidgets('each column name sits over its column', (tester) async {
      await pumpDrawer(
        tester,
        <GbmLogEntry>[network],
        showColumnHeaders: true,
        showTimeouts: true,
      );

      double left(String text) => tester.getRect(find.text(text)).left;
      double right(String text) => tester.getRect(find.text(text)).right;
      final DateTime when = DateTime.fromMillisecondsSinceEpoch(1692000000000);
      final String time =
          '${when.hour.toString().padLeft(2, '0')}:'
          '${when.minute.toString().padLeft(2, '0')}:'
          '${when.second.toString().padLeft(2, '0')}';

      expect(left('層級'), left('TIMEOUT'));
      expect(left('時間'), left(time));
      expect(left('指令'), left('git fetch --progress origin'));
      expect(right('耗時'), right('61020ms'));
      expect(left('exit'), left('exit 1'));
      expect(left('時限'), left('無傳輸 60s'));
    });

    // Fixed width, right-aligned: durations of any length end on one edge,
    // which is what lets the limit column line up at all.
    testWidgets('durations end on one edge', (tester) async {
      await pumpDrawer(tester, <GbmLogEntry>[local, network]);

      expect(
        tester.getRect(find.text('1500ms')).right,
        tester.getRect(find.text('61020ms')).right,
      );
    });

    testWidgets('the export carries the limit whether or not it is shown', (
      tester,
    ) async {
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

      await pumpDrawer(tester, <GbmLogEntry>[local, network, running]);
      await tester.tap(find.text('Copy All'));
      await tester.pump();

      expect(clipboardText, contains('(exit 0, 1500ms, limit 120000ms)'));
      expect(clipboardText, contains('(exit 1, 61020ms, idle limit 60000ms)'));
      expect(clipboardText, contains('git diff --numstat  (limit 120000ms)'));
    });
  });

  // The status bar's red summary 「可點開直接跳到該筆 log」 (P10 #3,
  // open-with-apps-spec.html screen 3): the drawer scrolls to the row and
  // paints it `--diff-del-bg`, the mock's own ground for an error row.
  group('LogDrawer focus (jump from the status bar)', () {
    final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);
    const AppLogEntry target = AppLogEntry(
      whenEpochMs: 1692000000000,
      level: OperationLogLevel.error,
      message: 'Could not run "Rider": boom',
    );
    AppLogEntry info(int i) => AppLogEntry(
      whenEpochMs: 1692000001000 + i,
      level: OperationLogLevel.info,
      message: 'info $i',
    );

    /// Returns the frames it took to settle: each search probe is a frame,
    /// so this bounds how many the jump spent.
    Future<int> pumpDrawer(
      WidgetTester tester,
      List<GbmLogEntry> records, {
      GbmLogEntry? focus,
      int serial = 0,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: SizedBox(
              height: 300,
              child: LogDrawer(
                records: records,
                focusEntry: focus,
                focusSerial: serial,
              ),
            ),
          ),
        ),
      );
      return tester.pumpAndSettle();
    }

    Finder ground() => find.byKey(const ValueKey<String>('log-row-focus'));

    testWidgets('the focused row, and only it, gets diffDelBg', (tester) async {
      await pumpDrawer(tester, <GbmLogEntry>[info(0), target, info(1)]);
      expect(ground(), findsNothing);

      await pumpDrawer(
        tester,
        <GbmLogEntry>[info(0), target, info(1)],
        focus: target,
        serial: 1,
      );
      expect(ground(), findsOneWidget);
      expect(tester.widget<ColoredBox>(ground()).color, colors.diffDelBg);
      expect(
        find.descendant(of: ground(), matching: find.text(target.message)),
        findsOneWidget,
      );
    });

    testWidgets('a filter that hides the row is put back to All', (
      tester,
    ) async {
      final List<GbmLogEntry> records = <GbmLogEntry>[info(0), target];
      await pumpDrawer(tester, records);
      await tester.tap(find.text('Info'));
      await tester.pumpAndSettle();
      expect(find.text(target.message), findsNothing);

      await pumpDrawer(tester, records, focus: target, serial: 1);
      expect(find.text(target.message), findsOneWidget);
      expect(find.text('info 0'), findsOneWidget, reason: 'All, not Error');
    });

    testWidgets('an Error filter already shows it, and is left alone', (
      tester,
    ) async {
      final List<GbmLogEntry> records = <GbmLogEntry>[info(0), target];
      await pumpDrawer(tester, records);
      await tester.tap(find.text('Error'));
      await tester.pumpAndSettle();

      await pumpDrawer(tester, records, focus: target, serial: 1);
      expect(find.text(target.message), findsOneWidget);
      expect(find.text('info 0'), findsNothing);
    });

    testWidgets('a row far up the list is scrolled into view', (tester) async {
      // git refreshes keep logging after a failure, so the error is rarely
      // the newest line: 300 newer rows put it far outside the viewport.
      // 150 older ones keep it off the end of the scroll range, where the
      // clamp would make centring impossible.
      final List<GbmLogEntry> records = <GbmLogEntry>[
        for (int i = 0; i < 150; i++) info(1000 + i),
        target,
        for (int i = 0; i < 300; i++) info(i),
      ];
      await pumpDrawer(tester, records);
      expect(find.text(target.message), findsNothing);

      await pumpDrawer(tester, records, focus: target, serial: 1);
      final Finder row = find.text(target.message);
      expect(row, findsOneWidget);
      final Rect list = tester.getRect(find.byType(ListView));
      final Rect rect = tester.getRect(row);
      expect(rect.top, greaterThanOrEqualTo(list.top));
      expect(rect.bottom, lessThanOrEqualTo(list.bottom));
      // Centred, not merely somewhere inside: the row is the reason the
      // drawer moved.
      final Rect ground = tester.getRect(
        find.byKey(const ValueKey<String>('log-row-focus')),
      );
      expect((ground.center.dy - list.center.dy).abs(), lessThan(1));
    });

    // Rows wrap, so their heights vary and the first, even-height estimate
    // lands wide of the row; the steps that follow have to walk the rest of
    // the way, in the right direction.
    testWidgets('uneven row heights still reach the row', (tester) async {
      AppLogEntry tall(int i) => AppLogEntry(
        whenEpochMs: 1692000002000 + i,
        level: OperationLogLevel.info,
        message: 'tall $i ${'x' * 1200}',
      );
      // The newest rows, built first, are short; the tall ones sit between
      // them and the target, so an estimate from what is built undershoots.
      final List<GbmLogEntry> records = <GbmLogEntry>[
        for (int i = 0; i < 100; i++) info(1000 + i),
        target,
        for (int i = 0; i < 100; i++) tall(i),
        for (int i = 0; i < 40; i++) info(i),
      ];
      await pumpDrawer(tester, records);
      final int frames = await pumpDrawer(
        tester,
        records,
        focus: target,
        serial: 1,
      );
      final Rect list = tester.getRect(find.byType(ListView));
      final Rect ground = tester.getRect(
        find.byKey(const ValueKey<String>('log-row-focus')),
      );
      expect((ground.center.dy - list.center.dy).abs(), lessThan(1));
      // An estimate, doubling, then halving: a handful of probes. Fixed
      // steps through 100 screen-tall rows would take hundreds.
      expect(frames, lessThan(25));
    });

    // The newest rows are tall, so an estimate from them overshoots and the
    // search has to come back down past rows it has already left.
    testWidgets('an overshooting estimate comes back to the row', (
      tester,
    ) async {
      AppLogEntry tall(int i) => AppLogEntry(
        whenEpochMs: 1692000003000 + i,
        level: OperationLogLevel.info,
        message: 'tall $i ${'x' * 1200}',
      );
      final List<GbmLogEntry> records = <GbmLogEntry>[
        for (int i = 0; i < 300; i++) info(1000 + i),
        target,
        for (int i = 0; i < 60; i++) info(i),
        for (int i = 0; i < 10; i++) tall(i),
      ];
      await pumpDrawer(tester, records);
      final int frames = await pumpDrawer(
        tester,
        records,
        focus: target,
        serial: 1,
      );
      final Rect list = tester.getRect(find.byType(ListView));
      final Rect ground = tester.getRect(
        find.byKey(const ValueKey<String>('log-row-focus')),
      );
      expect((ground.center.dy - list.center.dy).abs(), lessThan(1));
      expect(frames, lessThan(25));
    });

    testWidgets('the same serial does not jump again', (tester) async {
      final List<GbmLogEntry> records = <GbmLogEntry>[
        target,
        for (int i = 0; i < 300; i++) info(i),
      ];
      await pumpDrawer(tester, records, focus: target, serial: 1);
      // The user scrolls back down to the newest rows by hand.
      await tester.drag(find.byType(ListView), const Offset(0, -20000));
      await tester.pumpAndSettle();
      expect(find.text(target.message), findsNothing);

      // A rebuild with a longer log but the same request must not yank the
      // view back up.
      await pumpDrawer(
        tester,
        <GbmLogEntry>[...records, info(999)],
        focus: target,
        serial: 1,
      );
      expect(find.text(target.message), findsNothing);
    });
  });
}
