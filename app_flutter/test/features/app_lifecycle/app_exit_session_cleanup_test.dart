import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/auto_reopen_marker_repository.dart';
import 'package:gbm_flutter/data/repositories/open_repo_sessions.dart';
import 'package:gbm_flutter/features/app_lifecycle/app_exit_session_cleanup.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The registry `AppExitSessionCleanup` must reach at exit time. A real
/// `RepoSessionController` would register itself through its constructor
/// ([open_repo_sessions_test.dart]'s `_TrackingSession`); here a bare
/// recorder is enough, since what this tier owns is only that the widget
/// asks the registry to close everything, not that the registry itself
/// works (that is `open_repo_sessions_test.dart`'s job).
class _Recorder implements ClosableRepoSession {
  int closes = 0;

  @override
  void closeNativeSession() => closes++;

  @override
  void recordAppLog(AppLogEntry entry) {}
}

late SharedPreferences _prefs;

Future<OpenRepoSessions> _pump(
  WidgetTester tester, {
  Map<String, Object> prefs = const <String, Object>{},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  _prefs = await SharedPreferences.getInstance();
  final OpenRepoSessions sessions = OpenRepoSessions();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(_prefs),
        openRepoSessionsProvider.overrideWithValue(sessions),
      ],
      child: const MaterialApp(
        home: AppExitSessionCleanup(child: Scaffold(body: Text('app'))),
      ),
    ),
  );
  return sessions;
}

void main() {
  group('AppExitSessionCleanup', () {
    testWidgets('closes every open session when the app is asked to exit', (
      WidgetTester tester,
    ) async {
      final OpenRepoSessions sessions = await _pump(tester);
      final _Recorder a = _Recorder();
      final _Recorder b = _Recorder();
      sessions
        ..register(a)
        ..register(b);

      // Flutter never pops a route on Cmd+Q / the window's close button /
      // File -> Exit's SystemNavigator.pop() -- there is no route to pop.
      // handleRequestAppExit() is what the engine actually calls on that
      // path (WidgetsBinding.handleRequestAppExit(), which fans out to
      // every registered WidgetsBindingObserver's didRequestAppExit() --
      // an AppLifecycleListener is one such observer, and this is the same
      // call the real quit path drives).
      final AppExitResponse response = await tester.binding
          .handleRequestAppExit();

      expect(a.closes, 1);
      expect(b.closes, 1);
      expect(response, AppExitResponse.exit);
    });

    // A quit before the reopened repository's first load settled is still a quit, not a
    // crash: the next launch must reopen it rather than say it ended while opening it.
    testWidgets('clears the auto-reopen marker, after closing the sessions', (
      WidgetTester tester,
    ) async {
      final OpenRepoSessions sessions = await _pump(
        tester,
        prefs: <String, Object>{AutoReopenMarkerRepository.key: '/r'},
      );
      bool markerWhenClosed = false;
      sessions.addAfterCloseAll(
        () => markerWhenClosed = _prefs.containsKey(
          AutoReopenMarkerRepository.key,
        ),
      );

      await tester.binding.handleRequestAppExit();

      expect(_prefs.containsKey(AutoReopenMarkerRepository.key), isFalse);
      expect(markerWhenClosed, isTrue, reason: 'cleared after closeAll');
    });

    testWidgets('renders its child unchanged', (WidgetTester tester) async {
      await _pump(tester);
      await tester.pumpAndSettle();

      expect(find.text('app'), findsOneWidget);
    });

    testWidgets('does not respond to exit requests once disposed', (
      WidgetTester tester,
    ) async {
      final OpenRepoSessions sessions = await _pump(tester);
      final _Recorder a = _Recorder();
      sessions.register(a);

      // Unmount the widget -- its AppLifecycleListener must be disposed
      // along with it, or a stale observer keeps firing after the widget
      // it belonged to is gone.
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      await tester.binding.handleRequestAppExit();

      expect(a.closes, 0);
    });
  });
}
