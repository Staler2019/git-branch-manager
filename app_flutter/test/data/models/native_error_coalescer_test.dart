import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/native_error_coalescer.dart';
import 'package:gbm_flutter/data/models/native_error_report.dart';

class _FakeTimer implements Timer {
  _FakeTimer(this.due, this.callback);

  final Duration due;
  final void Function() callback;
  bool cancelled = false;
  bool fired = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled && !fired;

  @override
  int get tick => fired ? 1 : 0;
}

/// A clock moved by hand. [advance] runs what falls due, in order.
class _Clock {
  Duration now = Duration.zero;
  final List<_FakeTimer> timers = <_FakeTimer>[];

  Timer start(Duration delay, void Function() callback) {
    final _FakeTimer timer = _FakeTimer(now + delay, callback);
    timers.add(timer);
    return timer;
  }

  void advance(Duration by) {
    final Duration end = now + by;
    while (true) {
      final List<_FakeTimer> due =
          timers.where((_FakeTimer t) => t.isActive && t.due <= end).toList()
            ..sort((_FakeTimer a, _FakeTimer b) => a.due.compareTo(b.due));
      if (due.isEmpty) break;
      final _FakeTimer next = due.first;
      now = next.due;
      next.fired = true;
      next.callback();
    }
    now = end;
  }

  int get active => timers.where((_FakeTimer t) => t.isActive).length;
}

NativeErrorReport _report(
  String where, {
  String summary = 'boom',
  int ms = 0,
}) => NativeErrorReport(
  when: DateTime.fromMillisecondsSinceEpoch(ms),
  where: where,
  summary: summary,
  logPath: '/logs/x.log',
);

void main() {
  late _Clock clock;
  late List<NativeErrorReport> emitted;
  late NativeErrorCoalescer coalescer;

  List<String> lines() =>
      emitted.map((NativeErrorReport r) => '${r.where}: ${r.summary}').toList();

  setUp(() {
    clock = _Clock();
    emitted = <NativeErrorReport>[];
    coalescer = NativeErrorCoalescer(
      emit: emitted.add,
      startTimer: clock.start,
    );
  });

  test('a single report is emitted at once, and nothing follows it', () {
    coalescer.add(_report('a'));
    expect(lines(), <String>['a: boom']);

    clock.advance(const Duration(seconds: 10));
    expect(lines(), <String>['a: boom']);
    expect(clock.active, 0);
  });

  test('two then quiet: the second is counted when the quiet gap ends', () {
    coalescer.add(_report('a'));
    clock.advance(const Duration(milliseconds: 100));
    coalescer.add(_report('a', ms: 100));
    expect(lines(), <String>['a: boom']);

    clock.advance(const Duration(milliseconds: 499));
    expect(lines(), <String>['a: boom']);
    clock.advance(const Duration(milliseconds: 1));
    expect(lines(), <String>['a: boom', 'a: boom (repeated x1)']);
    expect(emitted.last.when, DateTime.fromMillisecondsSinceEpoch(100));
    expect(emitted.last.logPath, '/logs/x.log');
    expect(clock.active, 0);
  });

  test('a burst that never goes quiet is still counted every max wait', () {
    coalescer.add(_report('a'));
    for (int i = 0; i < 25; i++) {
      clock.advance(const Duration(milliseconds: 100));
      coalescer.add(_report('a'));
    }
    // Twenty repeats arrived up to the 2,000 ms after the first of them; the rest wait.
    expect(lines(), <String>['a: boom', 'a: boom (repeated x20)']);

    clock.advance(const Duration(milliseconds: 500));
    expect(lines(), <String>[
      'a: boom',
      'a: boom (repeated x20)',
      'a: boom (repeated x5)',
    ]);
    expect(clock.active, 0);
  });

  test('A A A B: the count is flushed before B, whose line comes at once', () {
    coalescer
      ..add(_report('a'))
      ..add(_report('a'))
      ..add(_report('a'))
      ..add(_report('b'));

    expect(lines(), <String>['a: boom', 'a: boom (repeated x2)', 'b: boom']);
  });

  test('A B A: nothing is merged across a different report', () {
    coalescer
      ..add(_report('a'))
      ..add(_report('b'))
      ..add(_report('a'));

    expect(lines(), <String>['a: boom', 'b: boom', 'a: boom']);
    clock.advance(const Duration(seconds: 10));
    expect(lines(), hasLength(3));
  });

  test('the same where with another summary is another report', () {
    coalescer
      ..add(_report('a', summary: 'one'))
      ..add(_report('a', summary: 'two'));

    expect(lines(), <String>['a: one', 'a: two']);
  });

  test('A, quiet, A: the second starts over rather than counting', () {
    coalescer.add(_report('a'));
    clock.advance(const Duration(milliseconds: 500));
    coalescer.add(_report('a'));

    expect(lines(), <String>['a: boom', 'a: boom']);
  });

  test('a timer of the old key does nothing once the key has changed', () {
    coalescer
      ..add(_report('a'))
      ..add(_report('a'));
    final List<_FakeTimer> old = clock.timers.toList();
    coalescer
      ..add(_report('b'))
      ..add(_report('b'));

    expect(old.every((_FakeTimer t) => t.cancelled), isTrue);
    clock.advance(const Duration(seconds: 10));
    expect(lines(), <String>[
      'a: boom',
      'a: boom (repeated x1)',
      'b: boom',
      'b: boom (repeated x1)',
    ]);
  });

  test(
    'dispose flushes the count, cancels the timers, and ignores later reports',
    () {
      coalescer
        ..add(_report('a'))
        ..add(_report('a'));
      coalescer.dispose();

      expect(lines(), <String>['a: boom', 'a: boom (repeated x1)']);
      expect(clock.active, 0);
      coalescer.add(_report('late'));
      expect(lines(), hasLength(2));
    },
  );
}
