// The auto fetch, mounted for real inside WorkspaceScreen: the scheduler's
// own rules are AutoFetchScheduler's unit tests; these pin that each input
// reaches it from its single source -- Preferences, the session's
// fetchFinished, the root navigator's dialogs, credentialPrompt,
// isActionEnabled's conflict gate and the status bar's running tasks -- and
// that a pause is said where spec P11 item 9 says failures go (status bar +
// log, no banner).
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/app_log_events.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/models/repo_state.dart';
import 'package:gbm_flutter/data/repositories/app_preferences_repository.dart';
import 'package:gbm_flutter/data/repositories/auto_fetch_scheduler.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/routing/dialog_open_observer.dart';
import 'package:gbm_flutter/routing/dialog_route.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';
import 'package:go_router/go_router.dart';

import '../support/fake_repo_session.dart';
import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');
final RepoIdentity _other = RepoIdentity.forWorkDir('/test/other');

/// A periodic timer ticked by hand: an interval is a call, not a wait.
class _ManualTimer implements Timer {
  _ManualTimer(this.period, this._onTick);

  final Duration period;
  final void Function(Timer) _onTick;
  bool _active = true;

  void fire() {
    if (_active) _onTick(this);
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => 0;

  @override
  void cancel() => _active = false;
}

class _Clock {
  final List<_ManualTimer> timers = <_ManualTimer>[];

  _ManualTimer get live => timers.where((_ManualTimer t) => t.isActive).single;

  Timer periodic(Duration period, void Function(Timer) onTick) {
    final _ManualTimer timer = _ManualTimer(period, onTick);
    timers.add(timer);
    return timer;
  }
}

int _autoFetches(FakeRepoSessionController controller) => controller.commandLog
    .where(
      (FakeCommand c) =>
          c.name == 'fetchRemote' && c.args['background'] == true,
    )
    .length;

/// The fake's fetchRemote only records, so the outcome is attributed the way
/// the real one does it: record the request, then deliver its event.
void _finishAutoFetch(
  FakeRepoSessionController controller, {
  Map<String, dynamic>? error,
}) {
  controller.debugRecordFetch(background: true);
  controller.debugHandleEvent(
    GbmEvent(
      GbmEventType.workingCopyOperationFinished,
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'succeeded': error == null,
          'error': ?error,
          'choices': <dynamic>[],
          'summary': '',
          'kind': 'fetch',
        }),
      ),
    ),
  );
}

const Map<String, dynamic> _authError = <String, dynamic>{
  'code': 5,
  'codeName': 'Auth',
  'message': 'Git needs credentials',
  'detail': '',
  'argv': <String>[],
  'exitCode': 128,
};

Future<PumpedWorkspace> _pump(
  WidgetTester tester,
  _Clock clock, {
  bool enabled = true,
  DialogOpenObserver? observer,
  List<RouteBase> topLevelRoutes = const <RouteBase>[],
  List<RepoIdentity> otherIdentities = const <RepoIdentity>[],
}) => pumpWorkspace(
  tester,
  identity: _identity,
  initialPrefs: <String, Object>{
    'appPrefs.autoFetchEnabled': enabled,
    'appPrefs.autoFetchMinutes': 10,
  },
  observers: <NavigatorObserver>[?observer],
  topLevelRoutes: topLevelRoutes,
  otherIdentities: otherIdentities,
  overrides: <Override>[
    autoFetchSchedulerFactoryProvider.overrideWithValue(
      AutoFetchSchedulerFactory(periodic: clock.periodic),
    ),
    if (observer != null)
      dialogOpenObserverProvider.overrideWithValue(observer),
  ],
);

void main() {
  testWidgets('enabled: fetches in the background on open, then each '
      'interval', (WidgetTester tester) async {
    final _Clock clock = _Clock();
    final PumpedWorkspace pumped = await _pump(tester, clock);

    expect(_autoFetches(pumped.controller), 1);
    expect(clock.live.period, const Duration(minutes: 10));

    _finishAutoFetch(pumped.controller);
    clock.live.fire();
    expect(_autoFetches(pumped.controller), 2);
  });

  testWidgets('off by default: nothing runs until Preferences turns it on', (
    WidgetTester tester,
  ) async {
    final _Clock clock = _Clock();
    final PumpedWorkspace pumped = await _pump(tester, clock, enabled: false);
    expect(_autoFetches(pumped.controller), 0);
    expect(clock.timers, isEmpty);

    await pumped.container
        .read(appPreferencesProvider.notifier)
        .update(
          (AppPreferences p) =>
              p.copyWith(autoFetchEnabled: true, autoFetchMinutes: 3),
        );
    await tester.pump();

    expect(_autoFetches(pumped.controller), 1);
    expect(clock.live.period, const Duration(minutes: 3));
  });

  testWidgets('switching repository fetches the new one and stops the old '
      "one's timer", (WidgetTester tester) async {
    final _Clock clock = _Clock();
    final PumpedWorkspace pumped = await _pump(
      tester,
      clock,
      otherIdentities: <RepoIdentity>[_other],
    );
    final _ManualTimer first = clock.live;

    pumped.router.go(
      RoutePaths.historyFor(Uri.encodeComponent(_other.workDir)),
    );
    await tester.pumpAndSettle();

    expect(first.isActive, isFalse);
    expect(_autoFetches(pumped.otherControllers[_other]!), 1);
    clock.live.fire();
    expect(_autoFetches(pumped.controller), 1);
    // Drains the tier-2 fallback the switch's refreshRepoStatus() arms
    // (workspace_identity_switch_refresh_test.dart).
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('an Auth failure pauses it, says so in the status bar, and '
      'raises no banner', (WidgetTester tester) async {
    final _Clock clock = _Clock();
    final PumpedWorkspace pumped = await _pump(tester, clock);

    _finishAutoFetch(pumped.controller, error: _authError);
    await tester.pump();

    expect(pumped.controller.state.lastError, isNull);
    expect(find.byType(GbmWarningBanner), findsNothing);
    final String paused = AppLogEvents.autoFetchPaused(
      'Auth',
      atEpochMs: 0,
    ).message;
    expect(
      find.descendant(
        of: find.byKey(const ValueKey<String>('status-error-summary')),
        matching: find.text(paused),
      ),
      findsOneWidget,
    );

    clock.live.fire();
    expect(_autoFetches(pumped.controller), 1);
  });

  testWidgets('an open dialog skips the tick; closed, the next one runs', (
    WidgetTester tester,
  ) async {
    final _Clock clock = _Clock();
    final DialogOpenObserver observer = DialogOpenObserver();
    final PumpedWorkspace pumped = await _pump(
      tester,
      clock,
      observer: observer,
      topLevelRoutes: <RouteBase>[
        dialogRoute(path: '/probe-dialog', builder: (_, _) => const Text('d')),
      ],
    );
    _finishAutoFetch(pumped.controller);

    pumped.router.push<void>('/probe-dialog');
    await tester.pumpAndSettle();
    clock.live.fire();
    expect(_autoFetches(pumped.controller), 1);

    pumped.router.pop();
    await tester.pumpAndSettle();
    clock.live.fire();
    expect(_autoFetches(pumped.controller), 2);
  });

  testWidgets('a pending credential prompt skips the tick', (
    WidgetTester tester,
  ) async {
    final _Clock clock = _Clock();
    final PumpedWorkspace pumped = await _pump(
      tester,
      clock,
      // Answers the auto-push; no observer, so only credentialPrompt can
      // be what skips.
      topLevelRoutes: <RouteBase>[
        dialogRoute(
          path: RoutePaths.credentialDialog,
          builder: (_, _) => const Text('credential'),
        ),
      ],
    );
    _finishAutoFetch(pumped.controller);

    pumped.controller.emit(
      pumped.controller.state.copyWith(credentialPrompt: 'Password'),
    );
    await tester.pumpAndSettle();
    clock.live.fire();
    expect(_autoFetches(pumped.controller), 1);
  });

  testWidgets('a conflict skips the tick', (WidgetTester tester) async {
    final _Clock clock = _Clock();
    final PumpedWorkspace pumped = await _pump(tester, clock);
    _finishAutoFetch(pumped.controller);

    pumped.controller.emit(
      pumped.controller.state.copyWith(
        repoState: const RepoState(
          flags: RepoStateFlags.cherryPick,
          isClean: false,
          isSequencerOperation: true,
          rebaseStep: 1,
          rebaseTotal: 3,
          rebaseOntoLabel: '',
          indexLocked: false,
          indexLockAgeSeconds: null,
          describe: '',
        ),
      ),
    );
    await tester.pump();
    clock.live.fire();
    expect(_autoFetches(pumped.controller), 1);
  });

  testWidgets('a running foreground git task skips the tick', (
    WidgetTester tester,
  ) async {
    final _Clock clock = _Clock();
    final PumpedWorkspace pumped = await _pump(tester, clock);
    _finishAutoFetch(pumped.controller);

    pumped.controller.emit(
      pumped.controller.state.withOperationRecord(
        const OperationRecord(
          whenEpochMs: 0,
          repoDir: '/test/repo',
          argv: <String>['git', '-C', '/test/repo', 'push', 'origin'],
          commandLine: 'git push origin',
          exitCode: 0,
          durationMs: 0,
          stderrText: '',
          cancelled: false,
          timedOut: false,
          id: 77,
          running: true,
          queuedOperationId: 41,
        ),
        maxEntries: 2000,
      ),
    );
    await tester.pump();
    clock.live.fire();
    expect(_autoFetches(pumped.controller), 1);
  });
}
