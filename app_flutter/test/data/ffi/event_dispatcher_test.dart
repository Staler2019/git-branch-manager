// GbmSessionEvents.dispose() closes its NativeCallable only after every event
// already queued for it has been received -- and then does close it: a
// listener left open keeps the isolate alive.
import 'dart:ffi';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';

import '../../support/fake_repo_session.dart';

class _RegisterOnly extends FakeGbmBindings {
  @override
  RegisterCallbackDart get registerCallback => (
    Pointer<Void> session,
    Pointer<NativeFunction<GbmEventCallbackNative>> callback,
    Pointer<Void> userData,
  ) {};
}

void main() {
  test('dispose closes the native callback once its queue drains', () async {
    final GbmSessionEvents events = GbmSessionEvents(
      _RegisterOnly(),
      Pointer<Void>.fromAddress(1),
    );

    events.dispose();
    for (int i = 0; i < 20 && !events.isNativeCallbackClosed; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }

    expect(events.isNativeCallbackClosed, isTrue);
  });
}
