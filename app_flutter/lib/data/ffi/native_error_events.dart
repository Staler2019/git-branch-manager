import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/native_error_report.dart';
import 'gbm_bindings.dart';

typedef _EmitDart = void Function(
  Pointer<Uint8> payload,
  int payloadLen,
  Pointer<Void> userData,
);

/// Bridges `gbm_set_native_error_callback` into a broadcast [Stream]. Process-wide, unlike
/// `GbmSessionEvents`: the library reports from any thread, for any session or none.
class GbmNativeErrorEvents {
  GbmNativeErrorEvents(this._bindings) {
    _callable = NativeCallable<GbmNativeErrorCallbackNative>.listener(
      _onReport,
    );
    _bindings.setNativeErrorCallback(_callable.nativeFunction, nullptr);
  }

  final GbmBindings _bindings;
  late final NativeCallable<GbmNativeErrorCallbackNative> _callable;
  final StreamController<NativeErrorReport> _controller =
      StreamController<NativeErrorReport>.broadcast();

  Stream<NativeErrorReport> get reports => _controller.stream;

  /// Not a length: sent by [dispose] through the callable itself.
  static const int _drained = -1;
  bool _disposed = false;

  @visibleForTesting
  bool get isNativeCallbackClosed {
    try {
      _callable.nativeFunction;
      return false;
    } on StateError {
      return true;
    }
  }

  void _onReport(
    Pointer<Uint8> payload,
    int payloadLen,
    Pointer<Void> userData,
  ) {
    if (payloadLen == _drained) {
      _callable.close();
      return;
    }
    Uint8List? bytes;
    if (payload != nullptr) {
      // Copied before freeing: asTypedList() is a view over native memory.
      bytes = Uint8List.fromList(payload.asTypedList(payloadLen));
      _bindings.freeEventPayload(payload);
    }
    if (!_controller.isClosed) {
      _controller.add(_decode(bytes));
    }
  }

  NativeErrorReport _decode(Uint8List? bytes) {
    try {
      if (bytes != null) {
        return NativeErrorReport.fromJson(
          jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>,
        );
      }
    } on FormatException {
      // Falls through.
    } on TypeError {
      // Falls through.
    } on RangeError {
      // Falls through: a time DateTime cannot hold.
    }
    return NativeErrorReport.unreadable(DateTime.now());
  }

  /// Clears the native callback, which returns only once no report is being delivered,
  /// then closes the callable after everything already queued for it has arrived: a
  /// message still queued at close is dropped with its payload unfreed. Call it after
  /// every session is closed, since closing one can still report.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _bindings.setNativeErrorCallback(nullptr, nullptr);
    unawaited(_controller.close());
    _callable.nativeFunction.asFunction<_EmitDart>()(
      nullptr,
      _drained,
      nullptr,
    );
  }
}
