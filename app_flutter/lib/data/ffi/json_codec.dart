import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart' show malloc;

import 'gbm_bindings.dart';

/// Drains the thread-local staging buffer gbm_capi.h documents
/// (`gbm_last_result_json_len`/`gbm_last_result_json_copy`) into a Dart
/// string. Must be called on the same (Dart) thread immediately after the
/// call that populated it -- see gbm_capi.h's "synchronous-result staging
/// buffer" section. Every FFI call in this app runs on the Dart isolate's
/// own thread (dart:ffi calls are synchronous from the calling isolate), so
/// "same thread" is automatic here; it would not be if this were ever
/// called from a background native thread.
String readLastResultJson(GbmBindings bindings) {
  final int len = bindings.lastResultJsonLen();
  if (len <= 0) {
    return '';
  }
  final Pointer<Uint8> buffer = malloc<Uint8>(len);
  try {
    bindings.lastResultJsonCopy(buffer, len);
    return utf8.decode(buffer.asTypedList(len));
  } finally {
    malloc.free(buffer);
  }
}

/// Decodes an event payload (already copied out by [GbmSessionEvents]) as
/// JSON. Returns `null` for an empty/absent payload (e.g. REFS_UPDATED,
/// which carries none).
Object? decodeEventPayload(Uint8List? payload) {
  if (payload == null || payload.isEmpty) {
    return null;
  }
  return jsonDecode(utf8.decode(payload));
}
