// A session whose callback registration failed emits nothing, ever: every
// spinner waiting on it would spin for good. `gbm_register_callback` says so
// by returning 0 and leaving the error in the staging buffer, and the open is
// then a failed open, exactly like a null session handle.
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

class _RegisterFailsBindings extends FakeGbmBindings {
  final List<String> calls = <String>[];
  final Uint8List _error = utf8.encode(
    jsonEncode(<String, Object?>{
      'code': 0,
      'codeName': 'Unknown',
      'message': 'Native error in gbm_register_callback',
      'detail': '',
      'argv': <String>[],
      'exitCode': -1,
    }),
  );

  @override
  SessionOpenDart get sessionOpen =>
      (Pointer<Utf8> workDir, Pointer<Utf8> gitDir, Pointer<Utf8> commonDir) =>
          Pointer<Void>.fromAddress(1);

  @override
  SessionCloseDart get sessionClose =>
      (Pointer<Void> session) => calls.add('sessionClose');

  @override
  RegisterCallbackDart get registerCallback =>
      (
        Pointer<Void> session,
        Pointer<NativeFunction<GbmEventCallbackNative>> callback,
        Pointer<Void> userData,
      ) => 0;

  @override
  LastResultJsonLenDart get lastResultJsonLen =>
      () => _error.length;

  @override
  LastResultJsonCopyDart get lastResultJsonCopy =>
      (Pointer<Uint8> buffer, int capacity) {
        buffer.asTypedList(capacity).setRange(0, _error.length, _error);
      };

  @override
  HistoryRefreshDart get historyRefresh => (Pointer<Void> session) {
    calls.add('historyRefresh');
    return 1;
  };
}

class _NoopRecents extends FakeRecentsRepository {
  @override
  Future<void> recordOpen(String workDir) async {}
}

void main() {
  test('a callback registration that fails is a failed open', () {
    final _RegisterFailsBindings bindings = _RegisterFailsBindings();

    final RepoSessionController controller = RepoSessionController(
      bindings,
      RepoIdentity.forWorkDir('/test/repo'),
      _NoopRecents(),
    );
    addTearDown(controller.dispose);

    expect(controller.state.isOpen, isFalse);
    expect(
      controller.state.lastError?.message,
      'Native error in gbm_register_callback',
    );
    expect(
      bindings.calls.where((String c) => c == 'sessionClose').length,
      1,
      reason: 'a session nobody can hear from is closed, not leaked',
    );
    expect(
      bindings.calls.where((String c) => c == 'historyRefresh'),
      isEmpty,
      reason: 'nothing is started on a session whose replies cannot arrive',
    );
  });
}
