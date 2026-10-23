import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/auto_fetch_gate.dart';
import 'package:gbm_flutter/data/repositories/auto_fetch_scheduler.dart';

/// A periodic timer the test ticks by hand, so an interval is a call rather
/// than a wait.
class _FakePeriodicTimer implements Timer {
  _FakePeriodicTimer(this.period, this._onTick);

  final Duration period;
  final void Function(Timer) _onTick;
  bool _active = true;
  int _ticks = 0;

  void fire() {
    if (!_active) return;
    _ticks++;
    _onTick(this);
  }

  @override
  bool get isActive => _active;

  @override
  int get tick => _ticks;

  @override
  void cancel() => _active = false;
}

const AutoFetchConditions _clear = AutoFetchConditions(
  pausedAfterAuthFailure: false,
  autoFetchInFlight: false,
  dialogOpen: false,
  credentialPromptPending: false,
  conflictActive: false,
  foregroundOperationActive: false,
);

class _Harness {
  _Harness() {
    scheduler =
        AutoFetchSchedulerFactory(
          periodic: (Duration period, void Function(Timer) onTick) {
            final _FakePeriodicTimer timer = _FakePeriodicTimer(period, onTick);
            timers.add(timer);
            return timer;
          },
        ).create(
          readConditions: () => conditions,
          fetch: () => fetches++,
          onPaused: () => pauses++,
        );
  }

  late final AutoFetchScheduler scheduler;
  final List<_FakePeriodicTimer> timers = <_FakePeriodicTimer>[];
  AutoFetchConditions conditions = _clear;
  int fetches = 0;
  int pauses = 0;

  Iterable<_FakePeriodicTimer> get live =>
      timers.where((_FakePeriodicTimer t) => t.isActive);

  /// The one live timer; every test that ticks expects exactly one.
  _FakePeriodicTimer get timer => live.single;

  void finishBackground({bool succeeded = true, String? codeName}) =>
      scheduler.onFetchFinished(
        background: true,
        succeeded: succeeded,
        errorCodeName: codeName,
      );
}

void main() {
  test('enabled: fetches once on open, then every autoFetchMinutes', () {
    final _Harness h = _Harness();
    h.scheduler.configure(enabled: true, minutes: 10);

    expect(h.fetches, 1);
    expect(h.timer.period, const Duration(minutes: 10));

    h.finishBackground();
    h.timer.fire();
    expect(h.fetches, 2);
  });

  test('disabled: no fetch on open and no timer', () {
    final _Harness h = _Harness();
    h.scheduler.configure(enabled: false, minutes: 10);

    expect(h.fetches, 0);
    expect(h.live, isEmpty);
  });

  test('turning it off cancels the timer; on again fetches and re-arms', () {
    final _Harness h = _Harness();
    h.scheduler.configure(enabled: true, minutes: 10);
    h.finishBackground();

    h.scheduler.configure(enabled: false, minutes: 10);
    expect(h.live, isEmpty);

    h.scheduler.configure(enabled: true, minutes: 10);
    expect(h.fetches, 2);
    expect(h.live.length, 1);
  });

  test('a new interval restarts the timer without an extra fetch', () {
    final _Harness h = _Harness();
    h.scheduler.configure(enabled: true, minutes: 10);
    h.finishBackground();

    h.scheduler.configure(enabled: true, minutes: 3);
    expect(h.timer.period, const Duration(minutes: 3));
    expect(h.timers.length, 2);
    expect(h.fetches, 1);
  });

  test('the same settings again are a no-op', () {
    final _Harness h = _Harness();
    h.scheduler.configure(enabled: true, minutes: 10);
    h.scheduler.configure(enabled: true, minutes: 10);

    expect(h.timers.length, 1);
    expect(h.fetches, 1);
  });

  test('an interval below one minute runs every minute, never busy-loops', () {
    final _Harness h = _Harness();
    h.scheduler.configure(enabled: true, minutes: 0);

    expect(h.timer.period, const Duration(minutes: 1));
  });

  test('a tick the gate refuses is skipped, not retried early', () {
    final _Harness h = _Harness();
    h.conditions = _clear.copyWith(conflictActive: true);
    h.scheduler.configure(enabled: true, minutes: 10);
    expect(h.fetches, 0);

    h.conditions = _clear;
    expect(h.fetches, 0);
    h.timer.fire();
    expect(h.fetches, 1);
  });

  test('the previous auto fetch still in flight skips the tick', () {
    final _Harness h = _Harness();
    h.scheduler.configure(enabled: true, minutes: 10);

    h.timer.fire();
    expect(h.fetches, 1);

    h.finishBackground();
    h.timer.fire();
    expect(h.fetches, 2);
  });

  test('a manual fetch finishing does not end the in-flight auto fetch', () {
    final _Harness h = _Harness();
    h.scheduler.configure(enabled: true, minutes: 10);

    h.scheduler.onFetchFinished(background: false, succeeded: true);
    h.timer.fire();
    expect(h.fetches, 1);
  });

  for (final String codeName in <String>['Auth', 'HostKey']) {
    test('a background $codeName failure pauses until a manual fetch '
        'succeeds', () {
      final _Harness h = _Harness();
      h.scheduler.configure(enabled: true, minutes: 10);

      h.finishBackground(succeeded: false, codeName: codeName);
      expect(h.scheduler.paused, isTrue);
      expect(h.pauses, 1);
      h.timer.fire();
      expect(h.fetches, 1);

      h.scheduler.onFetchFinished(
        background: false,
        succeeded: false,
        errorCodeName: codeName,
      );
      expect(h.scheduler.paused, isTrue);

      h.scheduler.onFetchFinished(background: false, succeeded: true);
      expect(h.scheduler.paused, isFalse);
      h.timer.fire();
      expect(h.fetches, 2);
    });
  }

  test('a network failure does not pause: the next interval retries', () {
    final _Harness h = _Harness();
    h.scheduler.configure(enabled: true, minutes: 10);

    h.finishBackground(succeeded: false, codeName: 'Network');
    expect(h.scheduler.paused, isFalse);
    expect(h.pauses, 0);
    h.timer.fire();
    expect(h.fetches, 2);
  });

  test('turning auto fetch off and on does not lift a pause', () {
    final _Harness h = _Harness();
    h.scheduler.configure(enabled: true, minutes: 10);
    h.finishBackground(succeeded: false, codeName: 'Auth');

    h.scheduler.configure(enabled: false, minutes: 10);
    h.scheduler.configure(enabled: true, minutes: 10);
    expect(h.fetches, 1);
  });

  test('dispose cancels the timer and ignores later calls', () {
    final _Harness h = _Harness();
    h.scheduler.configure(enabled: true, minutes: 10);
    final _FakePeriodicTimer timer = h.timer;

    h.scheduler.dispose();
    expect(timer.isActive, isFalse);

    h.scheduler.configure(enabled: true, minutes: 5);
    expect(h.live, isEmpty);
    expect(h.fetches, 1);
  });
}
