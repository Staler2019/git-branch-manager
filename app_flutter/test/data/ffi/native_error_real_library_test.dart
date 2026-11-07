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
typedef _SetFilter = Pointer<Void> Function(Pointer<Void> filter);
typedef _ModuleFromAddressNative = Int32 Function(
  Uint32 flags,
  Pointer<Void> address,
  Pointer<IntPtr> module,
);
typedef _ModuleFromAddressDart = int Function(
  int flags,
  Pointer<Void> address,
  Pointer<IntPtr> module,
);
typedef _ModuleFileNameNative = Uint32 Function(
  IntPtr module,
  Pointer<Utf16> name,
  Uint32 size,
);
typedef _ModuleFileNameDart = int Function(
  int module,
  Pointer<Utf16> name,
  int size,
);

/// The file name of the module whose code [address] is in, or null.
String? _moduleOf(DynamicLibrary kernel32, Pointer<Void> address) {
  const int fromAddress = 0x4; // GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS
  const int unchangedRefcount = 0x2;
  final _ModuleFromAddressDart moduleFromAddress = kernel32
      .lookupFunction<_ModuleFromAddressNative, _ModuleFromAddressDart>(
        'GetModuleHandleExW',
      );
  final _ModuleFileNameDart moduleFileName = kernel32
      .lookupFunction<_ModuleFileNameNative, _ModuleFileNameDart>(
        'GetModuleFileNameW',
      );
  return using((Arena arena) {
    final Pointer<IntPtr> module = arena<IntPtr>();
    if (moduleFromAddress(fromAddress | unchangedRefcount, address, module) ==
        0) {
      return null;
    }
    final Pointer<Utf16> name = arena<Uint16>(32768).cast<Utf16>();
    if (moduleFileName(module.value, name, 32768) == 0) return null;
    return name.toDartString().split(RegExp(r'[\\/]')).last;
  });
}

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

  // Only the topmost unhandled-exception filter runs, so the library's is worth nothing if
  // the engine, the Dart VM or a plugin installs one after it. This process is a Flutter
  // engine with the Dart VM started, as the app is.
  test(
    "in a Flutter process the top-level crash filter is the library's",
    () {
      openGbmCapiLibrary();
      final DynamicLibrary kernel32 = DynamicLibrary.open('kernel32.dll');
      final _SetFilter setFilter = kernel32
          .lookupFunction<_SetFilter, _SetFilter>(
            'SetUnhandledExceptionFilter',
          );
      final Pointer<Void> current = setFilter(nullptr);
      setFilter(current);

      expect(
        _moduleOf(kernel32, current)?.toLowerCase(),
        libraryPath!.split(RegExp(r'[\\/]')).last.toLowerCase(),
      );
    },
    skip: libraryPath == null
        ? 'GBM_CAPI_LIBRARY_PATH is not set'
        : !Platform.isWindows
        ? 'SetUnhandledExceptionFilter is Windows only'
        : false,
  );
}
