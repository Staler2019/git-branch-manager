// The status bar's Cancel reaches core through
// RepoSessionController.cancelOperation(): one gbm_cancel_operation() call
// with the record's queued id, and core's answer handed back unchanged
// (1 cancelled, 0 not found, -1 refused -- the refusal itself arrives as
// GBM_EVENT_ERROR_OCCURRED, not through this return value).
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

class _CancelRecordingBindings extends FakeGbmBindings {
  _CancelRecordingBindings(this.answer);

  final int answer;
  final List<(int, int)> cancels = <(int, int)>[];

  @override
  SessionOpenDart get sessionOpen =>
      (Pointer<Utf8> workDir, Pointer<Utf8> gitDir, Pointer<Utf8> commonDir) =>
          Pointer<Void>.fromAddress(1);

  @override
  RegisterCallbackDart get registerCallback => (
    Pointer<Void> session,
    Pointer<NativeFunction<GbmEventCallbackNative>> callback,
    Pointer<Void> userData,
  ) {};

  @override
  HistoryRefreshDart get historyRefresh =>
      (Pointer<Void> session) => 0;

  @override
  WorkingCopyRefreshDart get workingCopyRefresh => (Pointer<Void> session) {};

  @override
  LocalIdentityRefreshDart get localIdentityRefresh =>
      (Pointer<Void> session) {};

  @override
  EffectiveIdentityRefreshDart get effectiveIdentityRefresh =>
      (Pointer<Void> session) {};

  @override
  CancelOperationDart get cancelOperation => (Pointer<Void> session, int id) {
    cancels.add((session.address, id));
    return answer;
  };
}

class _NoopRecents extends FakeRecentsRepository {
  @override
  Future<void> recordOpen(String workDir) async {}
}

void main() {
  for (final int answer in <int>[1, 0, -1]) {
    test('cancelOperation passes the id once and returns core\'s $answer', () {
      final _CancelRecordingBindings bindings = _CancelRecordingBindings(
        answer,
      );
      final RepoSessionController controller = RepoSessionController(
        bindings,
        RepoIdentity.forWorkDir('/test/repo'),
        _NoopRecents(),
      );

      expect(controller.cancelOperation(41), answer);
      expect(bindings.cancels, <(int, int)>[(1, 41)]);
    });
  }

  test(
    'id 0 sends nothing: it would cancel every operation in the session',
    () {
      final _CancelRecordingBindings bindings = _CancelRecordingBindings(1);
      final RepoSessionController controller = RepoSessionController(
        bindings,
        RepoIdentity.forWorkDir('/test/repo'),
        _NoopRecents(),
      );

      expect(controller.cancelOperation(0), 0);
      expect(bindings.cancels, isEmpty);
    },
  );
}
