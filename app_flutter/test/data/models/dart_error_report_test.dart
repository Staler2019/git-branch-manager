import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/dart_error_report.dart';

class _FakeTimers {
  final List<(Duration, void Function())> started =
      <(Duration, void Function())>[];

  Timer start(Duration duration, void Function() callback) {
    started.add((duration, callback));
    return _NoopTimer();
  }

  /// Fires the most recent timer started for [duration].
  void fire(Duration duration) {
    final int index = started.lastIndexWhere(
      ((Duration, void Function()) t) => t.$1 == duration,
    );
    started.removeAt(index).$2();
  }
}

class _NoopTimer implements Timer {
  @override
  void cancel() {}
  @override
  bool get isActive => true;
  @override
  int get tick => 0;
}

DartErrorReport _report(Object error, [String where = 'FlutterError']) =>
    DartErrorReport.fromError(where: where, error: error);

void main() {
  group('the summary shown in every Log', () {
    test('a filesystem error keeps its type and OS code, never its path', () {
      final DartErrorReport report = _report(
        const FileSystemException(
          'Cannot open',
          '/Users/me/private-repo/file',
          OSError('denied', 13),
        ),
      );
      expect(report.summary, 'FileSystemException (os error 13)');
      expect(report.detail, contains('private-repo'));
    });

    test('a socket error keeps its type and OS code, never its address', () {
      final DartErrorReport report = _report(
        const SocketException(
          'refused',
          osError: OSError('refused', 61),
          address: null,
          port: 4433,
        ),
      );
      expect(report.summary, 'SocketException (os error 61)');
    });

    test('a process error keeps its type and code, never its arguments', () {
      final DartErrorReport report = _report(
        const ProcessException('git', <String>['clone', 'secret-url'], 'x', 2),
      );
      expect(report.summary, 'ProcessException (os error 2)');
    });

    test('an HTTP error keeps only its type', () {
      expect(
        _report(const HttpException('bad', uri: null)).summary,
        'HttpException',
      );
    });

    test('an argument error keeps its type and name, never its value', () {
      final DartErrorReport report = _report(
        ArgumentError.value('the-secret', 'token'),
      );
      expect(report.summary, 'ArgumentError (token)');
      expect(report.summary, isNot(contains('the-secret')));
    });

    test('a range error keeps its type and name, never its value', () {
      final DartErrorReport report = _report(RangeError.value(99, 'index'));
      expect(report.summary, 'RangeError (index)');
      expect(report.summary, isNot(contains('99')));
    });

    test(
      'anything else is its type and first line, with URL credentials masked',
      () {
        final DartErrorReport report = _report(
          StateError('clone https://user:secret@host/x failed\nsecond line'),
        );
        expect(
          report.summary,
          'StateError: Bad state: clone https://user:••••@host/x failed',
        );
      },
    );

    test('the type is recorded for the limiter', () {
      expect(_report(StateError('x')).type, 'StateError');
    });
  });

  group('the detail written to the file', () {
    test('has the whole text and the stack, with URL credentials masked', () {
      final DartErrorReport report = DartErrorReport.fromError(
        where: 'PlatformDispatcher',
        error: StateError('https://user:secret@host/x\nline two'),
        stack: StackTrace.fromString('#0 main (file.dart:1)'),
      );
      expect(report.detail, contains('line two'));
      expect(report.detail, contains('#0 main (file.dart:1)'));
      expect(report.detail, contains('user:••••@host'));
      expect(report.detail, isNot(contains('secret')));
    });

    test('is capped at 16 KiB on a character boundary', () {
      final DartErrorReport report = _report(StateError('工' * 10000));
      final int bytes = utf8.encode(report.detail).length;
      expect(bytes, lessThanOrEqualTo(DartErrorReport.maxDetailBytes));
      expect(bytes, greaterThan(DartErrorReport.maxDetailBytes - 64));
      expect(report.detail, endsWith(DartErrorReport.truncatedMarker));
      expect(report.detail, isNot(contains('�')));
    });

    test('a short detail is not marked', () {
      expect(
        _report(StateError('short')).detail,
        isNot(contains(DartErrorReport.truncatedMarker)),
      );
    });
  });

  group('DartErrorLimiter', () {
    late List<DartErrorReport> sent;
    late _FakeTimers timers;
    late DateTime now;
    late DartErrorLimiter limiter;

    setUp(() {
      sent = <DartErrorReport>[];
      timers = _FakeTimers();
      now = DateTime(2026, 11, 7, 10);
      limiter = DartErrorLimiter(
        emit: sent.add,
        now: () => now,
        startTimer: timers.start,
      );
    });

    test('the first report goes out at once', () {
      limiter.add(_report(StateError('a')));
      expect(sent.map((DartErrorReport r) => r.summary), <String>[
        'StateError: Bad state: a',
      ]);
    });

    test(
      'repeats of one type in one place become a count, whatever the text',
      () {
        limiter.add(_report(StateError('overflowed by 1 pixels')));
        for (int i = 2; i <= 50; i++) {
          limiter.add(_report(StateError('overflowed by $i pixels')));
        }
        expect(sent, hasLength(1));
        timers.fire(DartErrorLimiter.repeatWindow);
        expect(sent, hasLength(2));
        expect(
          sent.last.summary,
          'StateError: Bad state: overflowed by 50 pixels (repeated x49)',
        );
      },
    );

    test('a different type ends the run and sends its count first', () {
      limiter.add(_report(StateError('a')));
      limiter.add(_report(StateError('a')));
      limiter.add(_report(FormatException('b')));
      expect(sent.map((DartErrorReport r) => r.summary), <String>[
        'StateError: Bad state: a',
        'StateError: Bad state: a (repeated x1)',
        'FormatException: FormatException: b',
      ]);
    });

    test('the same type somewhere else is not a repeat', () {
      limiter.add(_report(StateError('a')));
      limiter.add(_report(StateError('a'), 'PlatformDispatcher'));
      expect(sent, hasLength(2));
    });

    test('the same type after the window is a new report', () {
      limiter.add(_report(StateError('a')));
      now = now.add(DartErrorLimiter.repeatWindow + const Duration(seconds: 1));
      limiter.add(_report(StateError('a')));
      expect(sent, hasLength(2));
      expect(sent.last.summary, 'StateError: Bad state: a');
    });

    test('at most maxPerWindow reports a minute, then one line says how many were held back', () {
      final List<Object> errors = <Object>[
        StateError('s'),
        FormatException('f'),
        ArgumentError('a'),
        UnsupportedError('u'),
        TimeoutException('t'),
      ];
      for (int i = 0; i < 30; i++) {
        limiter.add(_report(errors[i % errors.length]));
      }
      final int beforeEnd = sent.length;
      expect(beforeEnd, DartErrorLimiter.maxPerWindow);
      timers.fire(DartErrorLimiter.capWindow);
      expect(sent, hasLength(beforeEnd + 1));
      now = now.add(DartErrorLimiter.capWindow);
      limiter.add(_report(StateError('after')));
      expect(sent[beforeEnd].summary, '10 more errors suppressed');
      expect(sent.last.summary, 'StateError: Bad state: after');
    });

    test('after dispose nothing is sent', () {
      limiter.dispose();
      limiter.add(_report(StateError('a')));
      expect(sent, isEmpty);
    });
  });
}
