import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/app_lifecycle/dart_error_handlers.dart';

typedef _Sent = ({String where, String summary, String detail});

/// Installs the handlers over whatever the test binding set, and restores both.
List<_Sent> _install({void Function()? throwing}) {
  final List<_Sent> sent = <_Sent>[];
  final void Function() restore = installDartErrorHandlers(
    report: (String where, String summary, String detail) {
      throwing?.call();
      sent.add((where: where, summary: summary, detail: detail));
    },
  );
  addTearDown(restore);
  return sent;
}

void main() {
  test(
    'a framework error is reported and still reaches the previous handler',
    () {
      final List<FlutterErrorDetails> previous = <FlutterErrorDetails>[];
      final FlutterExceptionHandler? original = FlutterError.onError;
      FlutterError.onError = previous.add;
      addTearDown(() => FlutterError.onError = original);
      final List<_Sent> sent = _install();

      FlutterError.reportError(
        FlutterErrorDetails(
          exception: StateError('in build'),
          stack: StackTrace.fromString('#0 build (w.dart:1)'),
        ),
      );

      expect(sent, hasLength(1));
      expect(sent.single.where, 'FlutterError');
      expect(sent.single.summary, 'StateError: Bad state: in build');
      expect(sent.single.detail, contains('#0 build (w.dart:1)'));
      expect(previous, hasLength(1));
    },
  );

  test(
    'an uncaught async error is reported and left to the previous handler',
    () {
      final List<Object> previous = <Object>[];
      final ErrorCallback? original = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        previous.add(error);
        return true;
      };
      addTearDown(() => PlatformDispatcher.instance.onError = original);
      final List<_Sent> sent = _install();

      final bool handled = PlatformDispatcher.instance.onError!(
        const FormatException('late'),
        StackTrace.empty,
      );

      expect(sent.single.where, 'PlatformDispatcher');
      expect(sent.single.summary, 'FormatException: FormatException: late');
      expect(previous, hasLength(1));
      expect(handled, isTrue, reason: "the previous handler's answer stands");
    },
  );

  test(
    'with no previous dispatcher handler the engine keeps its default printing',
    () {
      final ErrorCallback? original = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = null;
      addTearDown(() => PlatformDispatcher.instance.onError = original);
      _install();

      expect(
        PlatformDispatcher.instance.onError!(StateError('x'), StackTrace.empty),
        isFalse,
      );
    },
  );

  test('a report that throws is swallowed and never reported again', () {
    final List<FlutterErrorDetails> previous = <FlutterErrorDetails>[];
    final FlutterExceptionHandler? original = FlutterError.onError;
    FlutterError.onError = previous.add;
    addTearDown(() => FlutterError.onError = original);
    int calls = 0;
    _install(
      throwing: () {
        calls++;
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: const FormatException('from the reporter'),
          ),
        );
        throw StateError('reporter broke');
      },
    );

    FlutterError.reportError(
      FlutterErrorDetails(exception: StateError('first')),
    );

    expect(calls, 1);
    expect(
      previous,
      hasLength(2),
      reason: 'both still reach the previous handler',
    );
  });

  test('restoring puts both previous handlers back', () {
    final FlutterExceptionHandler? flutterBefore = FlutterError.onError;
    final ErrorCallback? dispatcherBefore = PlatformDispatcher.instance.onError;
    final void Function() restore = installDartErrorHandlers(
      report: (String w, String s, String d) {},
    );
    expect(FlutterError.onError, isNot(same(flutterBefore)));

    restore();

    expect(FlutterError.onError, same(flutterBefore));
    expect(PlatformDispatcher.instance.onError, same(dispatcherBefore));
  });

  test('repeats are limited before they are reported', () {
    final FlutterExceptionHandler? original = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails _) {};
    addTearDown(() => FlutterError.onError = original);
    final List<_Sent> sent = _install();

    for (int i = 0; i < 50; i++) {
      FlutterError.reportError(
        FlutterErrorDetails(exception: StateError('$i')),
      );
    }

    expect(sent, hasLength(1));
  });
}
