// gbm_branch_checkout / gbm_branch_delete / gbm_remote_fetch / gbm_remote_prune
// return 0 when nothing was queued, and then no outcome ever comes for that
// call. The controller records a pending entry before each call and pairs
// outcomes with entries in order (PendingOperationTracker), so an entry left
// behind for a call that returned 0 would take the next call's outcome.
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/branch_deletion_probe.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

/// Opens a session; each of the four calls answers the next value of its
/// queue (1 when the queue is empty), as the export would.
class _QueueingBindings extends FakeGbmBindings {
  final List<int> checkoutAnswers = <int>[];
  final List<int> fetchAnswers = <int>[];
  final List<int> deleteAnswers = <int>[];
  final List<int> pruneAnswers = <int>[];
  int deleteCalls = 0;
  Uint8List _staged = Uint8List(0);

  /// Answers the RepoState read every working-copy outcome triggers
  /// (repo_session_cancelled_outcome_test.dart's shape).
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
  BranchCheckoutDart get branchCheckout =>
      (
        Pointer<Void> session,
        Pointer<Utf8> target,
        int detach,
        int createBranch,
        Pointer<Utf8> newBranchName,
        int force,
        int stashFirst,
        int recurseSubmodules,
      ) => checkoutAnswers.isEmpty ? 1 : checkoutAnswers.removeAt(0);

  @override
  RemoteFetchDart get remoteFetch =>
      (
        Pointer<Void> session,
        Pointer<Utf8> remoteName,
        Pointer<Pointer<Utf8>> refs,
        int refCount,
        int prune,
        int tags,
        int background,
      ) => fetchAnswers.isEmpty ? 1 : fetchAnswers.removeAt(0);

  @override
  BranchDeleteDart get branchDelete =>
      (
        Pointer<Void> session,
        Pointer<Pointer<Utf8>> names,
        int nameCount,
        Pointer<Int32> forces,
        Pointer<Pointer<Utf8>> expectedTips,
        int isRemote,
        Pointer<Utf8> remoteName,
      ) {
        deleteCalls++;
        return deleteAnswers.isEmpty ? 1 : deleteAnswers.removeAt(0);
      };

  @override
  RemotePruneDart get remotePrune =>
      (
        Pointer<Void> session,
        Pointer<Utf8> remoteName,
        Pointer<Pointer<Utf8>> refs,
        int refCount,
      ) => pruneAnswers.isEmpty ? 1 : pruneAnswers.removeAt(0);
}

class _NoopRecents extends FakeRecentsRepository {
  @override
  Future<void> recordOpen(String workDir) async {}
}

GbmEvent _outcome(int type, String kind) => GbmEvent(
  type,
  utf8.encode(
    jsonEncode(<String, dynamic>{
      'succeeded': true,
      'choices': <dynamic>[],
      'summary': '',
      'kind': kind,
    }),
  ),
);

void main() {
  late _QueueingBindings bindings;
  late RepoSessionController controller;

  setUp(() {
    bindings = _QueueingBindings();
    controller = RepoSessionController(
      bindings,
      RepoIdentity.forWorkDir('/test/repo'),
      _NoopRecents(),
    );
    addTearDown(controller.dispose);
  });

  test('a checkout that was not queued does not take the next '
      "checkout's outcome", () {
    bindings.checkoutAnswers.add(0);
    controller.checkout(target: 'never-queued');
    controller.checkout(target: 'queued');

    controller.debugHandleEvent(
      _outcome(GbmEventType.operationFinished, 'checkout'),
    );

    expect(
      controller.state.operationLog
          .whereType<AppLogEntry>()
          .map((AppLogEntry e) => e.message)
          // 「Opened repository」 is always there; only checkouts are the subject.
          .where((String m) => m.startsWith('Checked out')),
      <String>['Checked out queued'],
    );
  });

  test('a fetch that was not queued does not take the next '
      "fetch's outcome", () {
    final List<FetchFinished> seen = <FetchFinished>[];
    controller.fetchFinished.listen(seen.add);
    bindings.fetchAnswers.add(0);
    controller.fetchRemote(background: true);
    controller.fetchRemote();

    controller.debugHandleEvent(
      _outcome(GbmEventType.workingCopyOperationFinished, 'fetch'),
    );

    expect(seen.map((FetchFinished f) => f.background), <bool>[false]);
  });

  // A delete that succeeds goes on to delete the remote branches its request
  // names, so the request it is paired with shows in how many calls follow.
  test('a branch delete that was not queued does not take the next '
      "delete's outcome", () {
    bindings.deleteAnswers.add(0);
    controller.deleteBranch(
      entries: <DeleteBranchEntry>[DeleteBranchEntry.plain('never-queued')],
      thenDeleteRemote: <RemoteBranchDeletion>[
        RemoteBranchDeletion(
          remoteName: 'origin',
          names: <String>['never-queued'],
        ),
      ],
    );
    controller.deleteBranch(
      entries: <DeleteBranchEntry>[DeleteBranchEntry.plain('queued')],
    );
    expect(bindings.deleteCalls, 2);

    controller.debugHandleEvent(
      _outcome(GbmEventType.operationFinished, 'delete-branch'),
    );

    expect(bindings.deleteCalls, 2);
  });

  test('a prune that was not queued does not take the next '
      "prune's outcome", () {
    bindings.pruneAnswers.add(0);
    controller.pruneRemote('upstream', <String>['upstream/never-queued']);
    controller.pruneRemote('origin', <String>['origin/queued']);

    controller.debugHandleEvent(
      _outcome(GbmEventType.operationFinished, 'prune-remote'),
    );

    expect(
      controller.state.operationLog
          .whereType<AppLogEntry>()
          .map((AppLogEntry e) => e.message)
          .where((String m) => m.startsWith('Pruned')),
      <String>['Pruned 1 remote-tracking ref on origin: origin/queued'],
    );
  });
}
