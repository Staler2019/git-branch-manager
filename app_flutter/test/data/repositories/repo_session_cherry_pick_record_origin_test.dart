// cherryPick must reach gbm_cherry_pick's `recordOrigin` argument: on the C
// side it is what adds `-x`, the "(cherry picked from commit …)" line of
// spec page 07's MSGS table (CherryPickRevertApiTest).
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

/// Opens a session and records each gbm_cherry_pick call's `recordOrigin`.
class _CherryPickRecordingBindings extends FakeGbmBindings {
  final List<int> recordOriginArgs = <int>[];

  @override
  SessionOpenDart get sessionOpen =>
      (Pointer<Utf8> workDir, Pointer<Utf8> gitDir, Pointer<Utf8> commonDir) =>
          Pointer<Void>.fromAddress(1);

  @override
  SessionCloseDart get sessionClose => (Pointer<Void> session) {};

  @override
  RegisterCallbackDart get registerCallback => (
    Pointer<Void> session,
    Pointer<NativeFunction<GbmEventCallbackNative>> callback,
    Pointer<Void> userData,
  ) {};

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

  @override
  CherryPickDart get cherryPick =>
      (
        Pointer<Void> session,
        Pointer<Pointer<Utf8>> commitHexes,
        int commitCount,
        int mainline,
        int noCommit,
        int stashFirst,
        int recordOrigin,
      ) {
        recordOriginArgs.add(recordOrigin);
      };
}

class _NoopRecents extends FakeRecentsRepository {
  @override
  Future<void> recordOpen(String workDir) async {}
}

void main() {
  test('cherryPickRecordsOrigin reaches gbm_cherry_pick as 1, false as 0; '
      'on by default like the Preferences switch', () {
    final _CherryPickRecordingBindings bindings =
        _CherryPickRecordingBindings();
    final RepoSessionController controller = RepoSessionController(
      bindings,
      RepoIdentity.forWorkDir('/test/repo'),
      _NoopRecents(),
    );
    addTearDown(controller.dispose);

    controller.cherryPick(<String>['abc123']);
    controller.cherryPickRecordsOrigin = false;
    controller.cherryPick(<String>['abc123']);

    expect(bindings.recordOriginArgs, <int>[1, 0]);
  });
}
