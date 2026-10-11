// The order RepoSessionController.dispose() releases its two native halves.
//
// Closing the session is what drains core: `~Session` waits out every read
// still running on the shared pool, and any of them may emit one last event
// while it does -- `requestWorktreePendingCounts` runs a git command per
// worktree, so it is often still running when a test or a repo switch ends.
// That event goes to whatever callback is registered. If the
// NativeCallable behind it was closed first, the Dart VM aborts the whole
// app (`DLRT_GetFfiCallbackMetadata`); six crash reports of
// `worktree_add_refresh_test.dart` were exactly that.
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

typedef _EmitDart = void Function(
  Pointer<Void> session,
  int eventType,
  Pointer<Uint8> payload,
  int payloadLen,
  Pointer<Void> userData,
);

/// Opens a session, and emits once from inside `sessionClose` -- the read
/// that finishes while core drains.
class _DrainingBindings extends FakeGbmBindings {
  Pointer<NativeFunction<GbmEventCallbackNative>> registered = nullptr;
  bool emittedWhileClosing = false;
  int payloadsSent = 0;
  int payloadsFreed = 0;

  @override
  FreeEventPayloadDart get freeEventPayload => (Pointer<Uint8> payload) {
    payloadsFreed++;
    malloc.free(payload);
  };

  @override
  SessionOpenDart get sessionOpen =>
      (Pointer<Utf8> workDir, Pointer<Utf8> gitDir, Pointer<Utf8> commonDir) =>
          Pointer<Void>.fromAddress(1);

  @override
  RegisterCallbackDart get registerCallback =>
      (
        Pointer<Void> session,
        Pointer<NativeFunction<GbmEventCallbackNative>> callback,
        Pointer<Void> userData,
      ) {
        registered = callback;
      };

  @override
  SessionCloseDart get sessionClose => (Pointer<Void> session) {
    // A closed NativeCallable aborts the test process right here.
    // Carries a payload, as core's error event does: the receiver owns it
    // and frees it with gbm_free_event_payload.
    final Pointer<Uint8> payload = malloc<Uint8>(2)
      ..[0] = 0x7b
      ..[1] = 0x7d;
    payloadsSent++;
    registered.asFunction<_EmitDart>()(
      session,
      GbmEventType.errorOccurred,
      payload,
      2,
      nullptr,
    );
    emittedWhileClosing = true;
  };

  @override
  HistoryRefreshDart get historyRefresh =>
      (Pointer<Void> session) => 1;

  @override
  WorkingCopyRefreshDart get workingCopyRefresh => (Pointer<Void> session) {};

  @override
  LocalIdentityRefreshDart get localIdentityRefresh =>
      (Pointer<Void> session) {};

  @override
  EffectiveIdentityRefreshDart get effectiveIdentityRefresh =>
      (Pointer<Void> session) {};
}

class _NoopRecents extends FakeRecentsRepository {
  @override
  Future<void> recordOpen(String workDir) async {}
}

void main() {
  test('an event core emits while the session closes still has a receiver', () {
    final _DrainingBindings bindings = _DrainingBindings();
    final RepoSessionController controller = RepoSessionController(
      bindings,
      RepoIdentity.forWorkDir('/test/repo'),
      _NoopRecents(),
    );
    expect(bindings.registered, isNot(nullptr));

    controller.dispose();

    expect(bindings.emittedWhileClosing, isTrue);
  });

  // The callback is a NativeCallable.listener: an emit during sessionClose is
  // queued for the isolate, which is busy in dispose() until it returns. The
  // queued event still has to be received, or its payload is never freed.
  test(
    'an event queued while the session closes still has its payload freed',
    () async {
      final _DrainingBindings bindings = _DrainingBindings();
      final RepoSessionController controller = RepoSessionController(
        bindings,
        RepoIdentity.forWorkDir('/test/repo'),
        _NoopRecents(),
      );

      controller.dispose();
      for (int i = 0; i < 20 && bindings.payloadsFreed < 1; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }

      expect(bindings.payloadsSent, 1);
      expect(bindings.payloadsFreed, 1);
    },
  );
}
