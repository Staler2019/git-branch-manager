// Epoch 4.1's S1 list: an action is name + log + cancellation token (R4);
// the runner writes exactly one Log line per run, never swallows an Error
// (F6), never reports a cancellation the body could not honour (F8), and
// keeps its sink after the widget that started it is gone (R4, A3).
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/app_action.dart';
import 'package:gbm_flutter/data/models/app_action_cancel_token.dart';
import 'package:gbm_flutter/data/models/app_action_outcome.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/services/app_action_runner.dart';

final class _Boom implements Exception {
  const _Boom();
}

AppAction<int> _action(
  Future<int> Function(AppActionCancelToken token) body, {
  bool cancellable = false,
}) => AppAction<int>(
  name: 'probe',
  cancellable: cancellable,
  body: body,
  describeSuccess: (int v) => 'did $v',
  describeFailure: (Exception e) => 'failed: ${e.runtimeType}',
  describeCancelled: () => 'cancelled',
);

void main() {
  final DateTime t0 = DateTime.utc(2026, 10, 19, 12);
  late List<AppLogEntry> lines;
  late List<DateTime> ticks;
  late AppActionRunner runner;

  setUp(() {
    lines = <AppLogEntry>[];
    ticks = <DateTime>[t0, t0.add(const Duration(milliseconds: 250))];
    int i = 0;
    runner = AppActionRunner(
      clock: () => ticks[i < ticks.length - 1 ? i++ : i],
    );
  });

  void expectOneLine(OperationLogLevel level, String message) {
    expect(lines.length, 1);
    expect(lines.single.level, level);
    expect(lines.single.message, message);
  }

  test('a success is Succeeded and one info line', () async {
    final AppActionOutcome<int> outcome = await runner.run(
      _action((_) async => 7),
      sink: lines.add,
    );
    expect(outcome, isA<AppActionSucceeded<int>>());
    expect((outcome as AppActionSucceeded<int>).value, 7);
    expectOneLine(OperationLogLevel.info, 'did 7');
  });

  test('an Exception is Failed and one error line, not rethrown', () async {
    final AppActionOutcome<int> outcome = await runner.run(
      _action((_) async => throw const _Boom()),
      sink: lines.add,
    );
    expect(outcome, isA<AppActionFailed<int>>());
    expect(outcome.message, 'failed: _Boom');
    expectOneLine(OperationLogLevel.error, 'failed: _Boom');
  });

  test('cancelled before it starts: the body never runs', () async {
    int calls = 0;
    final AppActionCancelToken token = AppActionCancelToken()..cancel();
    final AppActionOutcome<int> outcome = await runner.run(
      _action((_) async => ++calls, cancellable: true),
      sink: lines.add,
      token: token,
    );
    expect(outcome, isA<AppActionCancelled<int>>());
    expect(calls, 0);
    expectOneLine(OperationLogLevel.warning, 'cancelled');
  });

  test('a cancellable body cancelled mid-run is Cancelled', () async {
    final AppActionCancelToken token = AppActionCancelToken();
    final Completer<void> gate = Completer<void>();
    final Future<AppActionOutcome<int>> running = runner.run(
      _action((AppActionCancelToken t) async {
        await gate.future;
        t.throwIfCancelled();
        return 1;
      }, cancellable: true),
      sink: lines.add,
      token: token,
    );
    token.cancel();
    gate.complete();
    expect(await running, isA<AppActionCancelled<int>>());
    expectOneLine(OperationLogLevel.warning, 'cancelled');
  });

  group('a body that cannot be cancelled reports what it actually did', () {
    test('success', () async {
      final AppActionCancelToken token = AppActionCancelToken();
      final Completer<void> gate = Completer<void>();
      final Future<AppActionOutcome<int>> running = runner.run(
        _action((AppActionCancelToken t) async {
          await gate.future;
          t.throwIfCancelled();
          return 3;
        }),
        sink: lines.add,
        token: token,
      );
      token.cancel();
      gate.complete();
      expect(await running, isA<AppActionSucceeded<int>>());
      expectOneLine(OperationLogLevel.info, 'did 3');
    });

    test('failure', () async {
      final AppActionCancelToken token = AppActionCancelToken();
      final Completer<void> gate = Completer<void>();
      final Future<AppActionOutcome<int>> running = runner.run(
        _action((AppActionCancelToken t) async {
          await gate.future;
          t.throwIfCancelled();
          throw const _Boom();
        }),
        sink: lines.add,
        token: token,
      );
      token.cancel();
      gate.complete();
      expect(await running, isA<AppActionFailed<int>>());
      expectOneLine(OperationLogLevel.error, 'failed: _Boom');
    });
  });

  test('an Error escapes and writes nothing', () async {
    await expectLater(
      runner.run(
        _action((_) async => throw StateError('bug')),
        sink: lines.add,
      ),
      throwsA(isA<StateError>()),
    );
    expect(lines, isEmpty);
  });

  test('startedAt and duration come from the injected clock', () async {
    final AppActionOutcome<int> outcome = await runner.run(
      _action((_) async => 1),
      sink: lines.add,
    );
    expect(outcome.actionName, 'probe');
    expect(outcome.startedAt, t0);
    expect(outcome.duration, const Duration(milliseconds: 250));
    expect(lines.single.whenEpochMs, t0.millisecondsSinceEpoch + 250);
  });

  test('no sink still returns the outcome', () async {
    final AppActionOutcome<int> outcome = await runner.run(
      _action((_) async => 2),
      sink: null,
    );
    expect(outcome, isA<AppActionSucceeded<int>>());
  });

  testWidgets('the line is written after the starting widget is gone', (
    tester,
  ) async {
    final Completer<int> gate = Completer<int>();
    late Future<AppActionOutcome<int>> running;
    await tester.pumpWidget(
      _Starter(
        onStart: (AppLogSink sink) {
          running = runner.run(_action((_) => gate.future), sink: sink);
        },
        sink: lines.add,
      ),
    );
    await tester.pumpWidget(const SizedBox());
    gate.complete(5);
    await tester.runAsync(() => running);
    expectOneLine(OperationLogLevel.info, 'did 5');
  });
}

class _Starter extends StatefulWidget {
  const _Starter({required this.onStart, required this.sink});

  final void Function(AppLogSink sink) onStart;
  final AppLogSink sink;

  @override
  State<_Starter> createState() => _StarterState();
}

class _StarterState extends State<_Starter> {
  @override
  void initState() {
    super.initState();
    widget.onStart(widget.sink);
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}
