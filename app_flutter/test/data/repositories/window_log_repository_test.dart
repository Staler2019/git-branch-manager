// The no-repository window's Log (R13): a welcome-screen clone that fails or
// is cancelled has no session to log into, so the window holds its own.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/app_preferences_repository.dart';
import 'package:gbm_flutter/data/repositories/window_log_repository.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

AppLogEntry _app(int n) => AppLogEntry(
  whenEpochMs: n,
  level: OperationLogLevel.info,
  message: 'line $n',
);

OperationRecord _git(int id, {bool running = false}) => OperationRecord(
  whenEpochMs: id,
  repoDir: '',
  argv: const <String>['clone'],
  commandLine: 'git clone',
  exitCode: 0,
  durationMs: 0,
  stderrText: '',
  cancelled: false,
  timedOut: false,
  id: id,
  running: running,
);

void main() {
  test('records app lines and git records in order, moving the revision', () {
    final WindowLogController log = WindowLogController(maxEntries: 10);
    log.recordAppLog(_app(1));
    log.recordLogEntry(_git(2));
    expect(log.state.entries.map((GbmLogEntry e) => e.whenEpochMs), <int>[
      1,
      2,
    ]);
    expect(log.state.revision, 2);
  });

  test('a git outcome replaces its running row', () {
    final WindowLogController log = WindowLogController(maxEntries: 10);
    log.recordLogEntry(_git(5, running: true));
    log.recordLogEntry(_git(5));
    expect(log.state.entries.length, 1);
    expect((log.state.entries.single as OperationRecord).running, isFalse);
  });

  test('keeps at most maxEntries', () {
    final WindowLogController log = WindowLogController(maxEntries: 2);
    for (int i = 1; i <= 3; i++) {
      log.recordAppLog(_app(i));
    }
    expect(log.state.entries.map((GbmLogEntry e) => e.whenEpochMs), <int>[
      2,
      3,
    ]);
  });

  // R12: a successful clone's rows leave the window that started it.
  test('retract removes those git records and moves the revision', () {
    final WindowLogController log = WindowLogController(maxEntries: 10);
    log.recordAppLog(_app(1));
    log.recordLogEntry(_git(2));
    log.recordLogEntry(_git(3));
    log.retractLogEntries(<int>{2});
    expect(log.state.entries.map((GbmLogEntry e) => e.whenEpochMs), <int>[
      1,
      3,
    ]);
    expect(log.state.revision, 4);
  });

  test('a line arriving after dispose is dropped, not thrown', () {
    final WindowLogController log = WindowLogController(maxEntries: 10);
    log.dispose();
    expect(() => log.recordAppLog(_app(1)), returnsNormally);
    expect(() => log.recordLogEntry(_git(1)), returnsNormally);
    expect(() => log.retractLogEntries(<int>{1}), returnsNormally);
  });

  test(
    'the provider takes its cap from Preferences → Log memory limit',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'appPrefs.logMemoryLimit': 2,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);
      expect(container.read(appPreferencesProvider).logMemoryLimit, 2);
      final WindowLogController log = container.read(
        windowLogProvider.notifier,
      );
      for (int i = 1; i <= 3; i++) {
        log.recordAppLog(_app(i));
      }
      expect(container.read(windowLogProvider).entries.length, 2);
    },
  );
}
