import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'gbm_bindings.dart';

/// One event delivered from `gbm_capi` for a session: the `eventType`
/// ordinal from [GbmEventType] and its decoded payload bytes, if any.
class GbmEvent {
  const GbmEvent(this.type, this.payload);

  final int type;
  final Uint8List? payload;
}

/// Bridges one open session's native events into a broadcast [Stream].
///
/// Registers a [NativeCallable.listener] with `gbm_capi` -- the only
/// `NativeCallable` variant safe to invoke from a thread other than the one
/// that created it, which matters here because `gbm_capi` calls back from a
/// `ThreadPool` worker or the operation runner's serial thread, never from
/// the Dart isolate that opened the session (see gbm_capi.h's doc comment
/// and the plan's "async/callback design" section).
class GbmSessionEvents {
  GbmSessionEvents(this._bindings, this._session) {
    _callable = NativeCallable<GbmEventCallbackNative>.listener(_onEvent);
    _bindings.registerCallback(_session, _callable.nativeFunction, nullptr);
  }

  final GbmBindings _bindings;
  final Pointer<Void> _session;
  late final NativeCallable<GbmEventCallbackNative> _callable;
  final StreamController<GbmEvent> _controller =
      StreamController<GbmEvent>.broadcast();

  Stream<GbmEvent> get events => _controller.stream;

  void _onEvent(
    Pointer<Void> session,
    int eventType,
    Pointer<Uint8> payload,
    int payloadLen,
    Pointer<Void> userData,
  ) {
    Uint8List? bytes;
    if (payload != nullptr) {
      // Copied out before freeing: payload.asTypedList() is a *view* over
      // native memory, which becomes dangling the instant
      // gbm_free_event_payload() runs.
      bytes = Uint8List.fromList(payload.asTypedList(payloadLen));
      _bindings.freeEventPayload(payload);
    }
    if (!_controller.isClosed) {
      _controller.add(GbmEvent(eventType, bytes));
    }
  }

  /// Closes the native callback and the stream. Must be called **after** the
  /// owning session handle is closed (`RepoSessionController.dispose`):
  /// closing the session drains core, a read still running may emit while it
  /// does, and invoking a closed NativeCallable aborts the app. Once the
  /// session is closed nothing emits. (This said "before" until 2026-10-11 --
  /// the order that crashed `worktree_add_refresh_test.dart`.)
  void dispose() {
    _callable.close();
    unawaited(_controller.close());
  }
}
