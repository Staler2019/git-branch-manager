// A branch deletion probe completes when its reply event arrives. Once the
// controller is disposed no event ever arrives, so a probe still in flight
// would leave the delete dialog awaiting a Future that never completes. It
// completes with an error instead, which the dialog already renders.
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/branch_deletion_probe.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

/// Opens a session whose probe requests are sent and never answered.
class _SilentProbeBindings extends FakeGbmBindings {
  int probesSent = 0;
  Uint8List _staged = Uint8List(0);

  @override
  RepoStateJsonDart get repoStateJson => (Pointer<Void> session) {
    _staged = utf8.encode(
      jsonEncode(<String, dynamic>{
        'flags': 0,
        'isClean': true,
        'isSequencerOperation': false,
        'rebaseStep': 0,
        'rebaseTotal': 0,
        'rebaseOntoLabel': '',
        'indexLocked': false,
        'indexLockAgeSeconds': null,
        'preparedMessagePending': false,
        'describe': '',
      }),
    );
    return 0;
  };

  @override
  LastResultJsonLenDart get lastResultJsonLen =>
      () => _staged.length;

  @override
  LastResultJsonCopyDart get lastResultJsonCopy =>
      (Pointer<Uint8> out, int outLen) {
        out.asTypedList(outLen).setAll(0, _staged);
      };

  @override
  SessionOpenDart get sessionOpen =>
      (Pointer<Utf8> workDir, Pointer<Utf8> gitDir, Pointer<Utf8> commonDir) =>
          Pointer<Void>.fromAddress(1);

  @override
  SessionCloseDart get sessionClose => (Pointer<Void> session) {};

  @override
  RegisterCallbackDart get registerCallback =>
      (
        Pointer<Void> session,
        Pointer<NativeFunction<GbmEventCallbackNative>> callback,
        Pointer<Void> userData,
      ) => 1;

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
  RequestBranchDeletionProbeDart get requestBranchDeletionProbe =>
      (
        Pointer<Void> session,
        int requestId,
        Pointer<Pointer<Utf8>> names,
        int nameCount,
      ) => probesSent++;
}

class _NoopRecents extends FakeRecentsRepository {
  @override
  Future<void> recordOpen(String workDir) async {}
}

void main() {
  test('a probe still in flight when the controller is disposed completes '
      'with an error', () async {
    final _SilentProbeBindings bindings = _SilentProbeBindings();
    final RepoSessionController controller = RepoSessionController(
      bindings,
      RepoIdentity.forWorkDir('/test/repo'),
      _NoopRecents(),
    );

    final Future<BranchDeletionProbeReply> reply = controller
        .probeBranchDeletion(<String>['feature']);
    expect(bindings.probesSent, 1);
    controller.dispose();

    final BranchDeletionProbeReply answered = await reply.timeout(
      const Duration(seconds: 2),
    );
    expect(answered.error, isNotNull);
    expect(answered.probes, isEmpty);
  });
}
