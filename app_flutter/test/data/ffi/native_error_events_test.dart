// GbmNativeErrorEvents fed exactly what NativeErrorApiTest.cpp pins on the C++ side, through
// the native function pointer it registers -- the same entry a real report takes. The
// library itself is not loaded in this tier; the JSON literal is the seam.
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/ffi/native_error_events.dart';
import 'package:gbm_flutter/data/models/native_error_report.dart';

import '../../support/fake_repo_session.dart';

typedef _CallbackDart = void Function(
  Pointer<Uint8> payload,
  int payloadLen,
  Pointer<Void> userData,
);

class _RecordingBindings extends FakeGbmBindings {
  final List<Pointer<NativeFunction<GbmNativeErrorCallbackNative>>> registered =
      <Pointer<NativeFunction<GbmNativeErrorCallbackNative>>>[];
  final List<int> freed = <int>[];
  int _lastLength = 0;

  @override
  SetNativeErrorCallbackDart get setNativeErrorCallback =>
      (
        Pointer<NativeFunction<GbmNativeErrorCallbackNative>> callback,
        Pointer<Void> userData,
      ) => registered.add(callback);

  @override
  FreeEventPayloadDart get freeEventPayload => (Pointer<Uint8> payload) {
    freed.add(payload.address);
    // So that reading it after this point shows.
    payload.asTypedList(_lastLength).fillRange(0, _lastLength, 0xff);
    malloc.free(payload);
  };

  /// As the library does: a malloc'ed buffer the receiver frees.
  int fire(List<int> bytes) {
    final Pointer<Uint8> buffer = malloc<Uint8>(
      bytes.isEmpty ? 1 : bytes.length,
    );
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    _lastLength = bytes.length;
    registered.first.asFunction<_CallbackDart>()(buffer, bytes.length, nullptr);
    return buffer.address;
  }
}

String _literal({
  String where = 'gbm_x',
  String summary = 'std::runtime_error: boom',
  String logPath = '/logs/gbm-native-errors.log',
}) =>
    '{"whenEpochMs":1793889351496,"where":${jsonEncode(where)},'
    '"summary":${jsonEncode(summary)},"logPath":${jsonEncode(logPath)}}';

void main() {
  late _RecordingBindings bindings;
  late GbmNativeErrorEvents events;

  setUp(() {
    bindings = _RecordingBindings();
    events = GbmNativeErrorEvents(bindings);
  });

  tearDown(() => events.dispose());

  test('a report arrives with every field of the agreed JSON', () async {
    final Future<NativeErrorReport> next = events.reports.first;
    bindings.fire(utf8.encode(_literal()));
    final NativeErrorReport report = await next;

    expect(report.when, DateTime.fromMillisecondsSinceEpoch(1793889351496));
    expect(report.where, 'gbm_x');
    expect(report.summary, 'std::runtime_error: boom');
    expect(report.logPath, '/logs/gbm-native-errors.log');
  });

  test('the payload is freed once, after it was copied', () async {
    final Future<NativeErrorReport> next = events.reports.first;
    final int address = bindings.fire(utf8.encode(_literal(summary: '工作樹')));
    final NativeErrorReport report = await next;

    expect(bindings.freed, <int>[address]);
    expect(report.summary, '工作樹');
  });

  test('a credential in where or summary is masked', () async {
    final Future<NativeErrorReport> next = events.reports.first;
    bindings.fire(
      utf8.encode(
        _literal(
          where: 'clone https://user:secret@host/x',
          summary: 'failed: https://user:secret@host/x',
        ),
      ),
    );
    final NativeErrorReport report = await next;

    expect(report.where, isNot(contains('secret')));
    expect(report.summary, isNot(contains('secret')));
    expect(report.where, contains('user:••••@host'));
    expect(report.summary, contains('user:••••@host'));
  });

  test('control characters cannot reach the Log as themselves', () async {
    final Future<NativeErrorReport> next = events.reports.first;
    bindings.fire(
      utf8.encode(
        _literal(where: 'w\nhere', summary: 's\x1b[2J', logPath: 'p\rath'),
      ),
    );
    final NativeErrorReport report = await next;

    expect(report.where, r'w\nhere');
    expect(report.summary, r's\x1b[2J');
    expect(report.logPath, r'p\rath');
  });

  group('a payload that cannot be read', () {
    final Map<String, List<int>> cases = <String, List<int>>{
      'is not UTF-8': <int>[0x7b, 0xa4, 0x7d],
      'is not JSON': utf8.encode('raw-text-that-must-not-show'),
      'is not an object': utf8.encode('["raw-text-that-must-not-show"]'),
      'has a field of the wrong type': utf8.encode(
        '{"whenEpochMs":1,"where":"raw-text-that-must-not-show","summary":7,"logPath":""}',
      ),
      'has a time out of range': utf8.encode(
        '{"whenEpochMs":9007199254740991,"where":"raw-text-that-must-not-show","summary":"","logPath":""}',
      ),
      'lacks a field': utf8.encode('{"where":"raw-text-that-must-not-show"}'),
    };
    for (final MapEntry<String, List<int>> entry in cases.entries) {
      test(
        '${entry.key}: a generic report, freed, with none of its text',
        () async {
          final Future<NativeErrorReport> next = events.reports.first;
          final int address = bindings.fire(entry.value);
          final NativeErrorReport report = await next;

          expect(report.where, 'native error channel');
          expect(report.summary, 'a report could not be read');
          expect(report.summary, isNot(contains('raw-text')));
          expect(report.where, isNot(contains('raw-text')));
          expect(bindings.freed, <int>[address]);
        },
      );
    }
  });

  test('a null payload is reported without being freed', () async {
    final Future<NativeErrorReport> next = events.reports.first;
    bindings.registered.first.asFunction<_CallbackDart>()(nullptr, 0, nullptr);
    final NativeErrorReport report = await next;

    expect(report.where, 'native error channel');
    expect(bindings.freed, isEmpty);
  });

  test(
    'dispose clears the native callback, then closes the callable',
    () async {
      expect(bindings.registered.single, isNot(nullptr));

      events.dispose();
      expect(bindings.registered, hasLength(2));
      expect(bindings.registered.last, nullptr);

      for (int i = 0; i < 20 && !events.isNativeCallbackClosed; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(events.isNativeCallbackClosed, isTrue);
    },
  );

  test('a second dispose does nothing', () async {
    events.dispose();
    events.dispose();

    expect(bindings.registered, hasLength(2));
    await Future<void>.delayed(const Duration(milliseconds: 20));
  });

  test('a report queued when dispose runs is still freed', () async {
    final int address = bindings.fire(utf8.encode(_literal()));
    events.dispose();

    for (int i = 0; i < 20 && !events.isNativeCallbackClosed; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    expect(events.isNativeCallbackClosed, isTrue);
    expect(bindings.freed, <int>[address]);
  });
}
