import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/git_error.dart';
import '../models/git_version.dart';
import 'event_dispatcher.dart';
import 'gbm_bindings.dart';
import 'json_codec.dart';

/// What `gbm_clone_start` answered.
sealed class CloneJobStart {
  const CloneJobStart();
}

final class CloneJobStarted extends CloneJobStart {
  const CloneJobStarted(this.job);
  final CloneJobHandle job;
}

/// Refused before git ran (bad url or destination, no usable git).
final class CloneJobRefused extends CloneJobStart {
  const CloneJobRefused(this.error);
  final GitError error;
}

/// One running clone job (gbm_capi.h's "Clone job" block).
abstract interface class CloneJobHandle {
  void cancel();
  void provideCredential(String secret);
  void cancelCredential();

  /// Releases the job: after this, nothing reaches the start call's
  /// `onEvent` again -- including an event still queued, so close only once
  /// `GBM_EVENT_CLONE_FINISHED` has arrived, or to abandon the job. Safe to
  /// call twice; every other call is a no-op after.
  void close();
}

/// The seam `CloneJobController` runs clones through, so it can be tested
/// without the native library.
abstract interface class CloneJobNative {
  CloneJobStart start({
    required String url,
    required String destPath,
    required bool recurseSubmodules,
    required int depth,
    required void Function(GbmEvent event) onEvent,
  });

  /// The git every invocation runs; null when none is usable.
  GitVersion? gitVersion();
}

class GbmCloneJobNative implements CloneJobNative {
  const GbmCloneJobNative(this._bindings);

  final GbmBindings _bindings;

  @override
  CloneJobStart start({
    required String url,
    required String destPath,
    required bool recurseSubmodules,
    required int depth,
    required void Function(GbmEvent event) onEvent,
  }) {
    final GbmSessionEvents events = GbmSessionEvents.unregistered(_bindings);
    final Pointer<Utf8> urlPtr = url.toNativeUtf8();
    final Pointer<Utf8> destPtr = destPath.toNativeUtf8();
    final Pointer<Void> handle;
    try {
      handle = _bindings.cloneStart(
        urlPtr,
        destPtr,
        recurseSubmodules ? 1 : 0,
        depth,
        events.nativeFunction,
        nullptr,
      );
    } finally {
      malloc.free(urlPtr);
      malloc.free(destPtr);
    }
    if (handle == nullptr) {
      final String json = readLastResultJson(_bindings);
      events.dispose();
      return CloneJobRefused(
        json.isEmpty
            ? const GitError(
                code: 0,
                codeName: 'Unknown',
                message: 'The clone could not start.',
                detail: '',
                argv: <String>[],
                exitCode: 0,
              )
            : GitError.fromJson(jsonDecode(json) as Map<String, dynamic>),
      );
    }
    final StreamSubscription<GbmEvent> subscription = events.events.listen(
      onEvent,
    );
    return CloneJobStarted(
      GbmCloneJob._(_bindings, handle, events, subscription),
    );
  }

  @override
  GitVersion? gitVersion() {
    if (_bindings.gitVersionJson() != 0) return null;
    return GitVersion.fromJson(
      jsonDecode(readLastResultJson(_bindings)) as Map<String, dynamic>,
    );
  }
}

class GbmCloneJob implements CloneJobHandle {
  GbmCloneJob._(this._bindings, this._handle, this._events, this._subscription);

  final GbmBindings _bindings;
  final Pointer<Void> _handle;
  final GbmSessionEvents _events;
  final StreamSubscription<GbmEvent> _subscription;
  bool _closed = false;

  /// The job's event bridge, so a test can watch its callable close.
  @visibleForTesting
  GbmSessionEvents get events => _events;

  @override
  void cancel() {
    if (!_closed) _bindings.cloneCancel(_handle);
  }

  @override
  void provideCredential(String secret) {
    if (_closed) return;
    final Pointer<Utf8> secretPtr = secret.toNativeUtf8();
    try {
      _bindings.cloneProvideCredential(_handle, secretPtr);
    } finally {
      malloc.free(secretPtr);
    }
  }

  @override
  void cancelCredential() {
    if (!_closed) _bindings.cloneCancelCredential(_handle);
  }

  /// The native job first: `gbm_clone_close` joins its thread, after which
  /// nothing emits, and only then the callable
  /// ([FLU-close-session-before-callable]).
  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _bindings.cloneClose(_handle);
    unawaited(_subscription.cancel());
    _events.dispose();
  }
}
