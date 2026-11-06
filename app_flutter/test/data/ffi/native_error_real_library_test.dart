// The native error channel with nothing faked: a real gbm_capi raises and reports on its own
// side, and the report crosses dart:ffi into GbmNativeErrorEvents. Every other test stops at
// the JSON literal on one side of that crossing or the other, and Windows is where a
// crossing has actually gone wrong (#207).
//
// Needs a library built with tests, since gbm_test_raise_native_error exists only there,
// so `capi-build` in ci.yml runs this file right after building one. A plain `flutter test`
// names no library and skips. To run it by hand:
//
//   GBM_CAPI_LIBRARY_PATH=$PWD/../build/capi-only/src/capi/libgbm_capi.dylib \
//   GBM_NATIVE_ERROR_LOG_DIR=$(mktemp -d) \
//   flutter test test/data/ffi/native_error_real_library_test.dart
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/ffi/native_error_events.dart';
import 'package:gbm_flutter/data/ffi/native_library.dart';
import 'package:gbm_flutter/data/models/native_error_report.dart';

typedef _RaiseNative = Void Function(Pointer<Utf8> message);
typedef _RaiseDart = void Function(Pointer<Utf8> message);

void main() {
  final String? libraryPath = Platform.environment['GBM_CAPI_LIBRARY_PATH'];

  test('a report raised inside the library arrives in Dart, masked', () async {
    // Required rather than defaulted, so that this never writes to the user's real log.
    final String logDirectory =
        Platform.environment['GBM_NATIVE_ERROR_LOG_DIR']!;
    final DynamicLibrary library = openGbmCapiLibrary();
    final _RaiseDart raise = library.lookupFunction<_RaiseNative, _RaiseDart>(
      'gbm_test_raise_native_error',
    );
    final GbmNativeErrorEvents events = GbmNativeErrorEvents(
      GbmBindings(library),
    );
    addTearDown(events.dispose);
    final Future<NativeErrorReport> next = events.reports.first;

    using((Arena arena) {
      raise(
        'clone https://user:secret@host/x failed'.toNativeUtf8(
          allocator: arena,
        ),
      );
    });
    final NativeErrorReport report = await next.timeout(
      const Duration(seconds: 10),
    );

    expect(report.where, 'gbm_test_raise_native_error');
    expect(report.summary, contains('clone https://user:••••@host/x failed'));
    expect(report.summary, isNot(contains('secret')));
    expect(report.logPath, startsWith(logDirectory));
    expect(File(report.logPath).existsSync(), isTrue);
  }, skip: libraryPath == null ? 'GBM_CAPI_LIBRARY_PATH is not set' : false);

  // The Dart error reporter's fake hand-builds this payload; this is what the library sends.
  test('an external error keeps the summary it was given, and its detail goes to the file', () async {
    final GbmBindings bindings = GbmBindings(openGbmCapiLibrary());
    final GbmNativeErrorEvents events = GbmNativeErrorEvents(bindings);
    addTearDown(events.dispose);
    final Future<NativeErrorReport> next = events.reports.first;

    using((Arena arena) {
      bindings.reportExternalError(
        'FlutterError'.toNativeUtf8(allocator: arena),
        'StateError: on screen'.toNativeUtf8(allocator: arena),
        'only in the file'.toNativeUtf8(allocator: arena),
      );
    });
    final NativeErrorReport report = await next.timeout(
      const Duration(seconds: 10),
    );

    expect(report.where, 'FlutterError');
    expect(report.summary, 'StateError: on screen');
    expect(
      File(report.logPath).readAsStringSync(),
      contains('FlutterError: only in the file'),
    );
  }, skip: libraryPath == null ? 'GBM_CAPI_LIBRARY_PATH is not set' : false);
}
