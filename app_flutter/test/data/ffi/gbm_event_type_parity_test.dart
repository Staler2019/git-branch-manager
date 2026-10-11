// Event-number parity between `enum GbmEventType` in `src/capi/gbm_capi.h`
// and `GbmEventType` in `gbm_bindings.dart`.
//
// `gbm_capi_signature_parity_test.dart` checks function signatures only. An
// event constant off by one analyzes, unit-tests and capi-tests clean -- every
// tier below the device tier feeds the Dart constant to itself -- and then
// routes a real event into the wrong handler. This file reads both sources as
// text and compares every value by name.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `GBM_EVENT_ORIGINAL_OPERATION_MESSAGE_READY` -> `originalOperationMessageReady`.
String _dartName(String cName) {
  final List<String> words = cName
      .substring('GBM_EVENT_'.length)
      .toLowerCase()
      .split('_');
  return words.first +
      words
          .skip(1)
          .map((String w) => w[0].toUpperCase() + w.substring(1))
          .join();
}

Map<String, int> _headerEvents(String header) {
  final int start = header.indexOf('enum GbmEventType');
  final int end = header.indexOf('};', start);
  final String body = header.substring(start, end);
  return <String, int>{
    for (final RegExpMatch m in RegExp(
      r'^\s*(GBM_EVENT_[A-Z0-9_]+)\s*=\s*(\d+)',
      multiLine: true,
    ).allMatches(body))
      _dartName(m.group(1)!): int.parse(m.group(2)!),
  };
}

Map<String, int> _dartEvents(String bindings) {
  final int start = bindings.indexOf('abstract final class GbmEventType');
  final int end = bindings.indexOf('}', start);
  final String body = bindings.substring(start, end);
  return <String, int>{
    for (final RegExpMatch m in RegExp(
      r'static const int (\w+) = (\d+);',
    ).allMatches(body))
      m.group(1)!: int.parse(m.group(2)!),
  };
}

void main() {
  test('every GBM_EVENT_* value matches its GbmEventType constant', () {
    // Arrange
    final Map<String, int> header = _headerEvents(
      File('../src/capi/gbm_capi.h').readAsStringSync(),
    );
    final Map<String, int> dart = _dartEvents(
      File('lib/data/ffi/gbm_bindings.dart').readAsStringSync(),
    );

    // Assert: the parse found the enum at all, then name-for-name equality.
    expect(header, isNotEmpty);
    expect(dart, equals(header));
  });
}
