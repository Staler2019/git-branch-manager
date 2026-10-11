// Which refresh request a refs publish covers (prepared-commit-message
// Slice E, D3). gbm_history_refresh() numbers each request, and
// GBM_EVENT_REFS_UPDATED says the highest request its refs load began after;
// the commit box's head check waits on this, because "refs arrived after I
// asked" can still be refs read before the change it is looking for.
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

const String _refsJson =
    '{"head":{"kind":1,"branchName":"main","fullRef":"refs/heads/main",'
    '"target":"aaaa"},"refs":[],"refCountGuardTripped":false,'
    '"totalRefCount":0}';

/// Answers the refs read GBM_EVENT_REFS_UPDATED triggers, and numbers
/// history refreshes the way core does.
class _RefsBindings extends FakeGbmBindings {
  int nextRequest = 7;
  final List<int> _bytes = utf8.encode(_refsJson);

  // The staging buffer holds refs only right after a refs read; before that
  // (a failed open reads it as its error) it is empty, as in core.
  bool _staged = false;

  @override
  RefsJsonDart get refsJson => (Pointer<Void> session) {
    _staged = true;
    return 0;
  };

  @override
  LastResultJsonLenDart get lastResultJsonLen =>
      () => _staged ? _bytes.length : 0;

  @override
  LastResultJsonCopyDart get lastResultJsonCopy =>
      (Pointer<Uint8> out, int outLen) =>
          out.asTypedList(outLen).setAll(0, _bytes);

  @override
  HistoryRefreshDart get historyRefresh =>
      (Pointer<Void> session) => nextRequest;
}

/// Opens successfully, so refreshHistory() reaches the binding.
class _OpenBindings extends _RefsBindings {
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

  int metaRequestsSent = 0;

  @override
  RequestCommitMetaDart get requestCommitMeta =>
      (Pointer<Void> session, Pointer<Pointer<Utf8>> oids, int oidCount) =>
          metaRequestsSent++;

  @override
  SessionCloseDart get sessionClose => (Pointer<Void> session) {};

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

GbmEvent _refsUpdated(Object? payload) => GbmEvent(
  GbmEventType.refsUpdated,
  payload == null ? null : utf8.encode(jsonEncode(payload)),
);

RepoSessionController _real() {
  final RepoSessionController c = RepoSessionController(
    _RefsBindings(),
    _identity,
    FakeRecentsRepository(),
  );
  addTearDown(c.dispose);
  return c;
}

FakeRepoSessionController _fake() {
  final FakeRepoSessionController c = FakeRepoSessionController(
    _identity,
    const RepoSessionState(),
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('a refs update records the request it covers', () {
    final RepoSessionController c = _real();
    c.debugHandleEvent(_refsUpdated(<String, dynamic>{'coversRequest': 5}));
    expect(c.state.refsCoverRequest, 5);
    expect(c.state.refs.head.target, 'aaaa');
  });

  test('a refs update without a payload keeps the previous value', () {
    final RepoSessionController c = _real();
    c.debugHandleEvent(_refsUpdated(<String, dynamic>{'coversRequest': 5}));
    c.debugHandleEvent(_refsUpdated(null));
    expect(c.state.refsCoverRequest, 5);
    expect(c.state.refsEpoch, 2);
  });

  test('a lower value arriving after a higher one changes nothing', () {
    // A walk superseded by a filter change can report after the newer one.
    final FakeRepoSessionController c = _fake();
    c.publishRefs(RefSnapshot.empty, coversRequest: 9);
    c.publishRefs(RefSnapshot.empty, coversRequest: 4);
    expect(c.state.refsCoverRequest, 9);
  });

  test('refreshHistory returns the request number core handed out', () {
    final _OpenBindings bindings = _OpenBindings()..nextRequest = 42;
    final RepoSessionController c = RepoSessionController(
      bindings,
      _identity,
      _NoopRecents(),
    );
    addTearDown(c.dispose);
    expect(c.refreshHistory(), 42);
  });

  // Slice E D1 rides on the same open-session bindings: the commit box's
  // parent check compares commit-meta replies against requests sent.
  test('commitMetaRequestSeq counts the requests that reach core', () {
    final _OpenBindings bindings = _OpenBindings();
    final RepoSessionController c = RepoSessionController(
      bindings,
      _identity,
      _NoopRecents(),
    );
    addTearDown(c.dispose);
    c.requestCommitMeta(const <String>[]);
    expect(c.commitMetaRequestSeq, 0, reason: 'an empty list sends nothing');
    c.requestCommitMeta(const <String>['aaaa']);
    c.requestCommitMeta(const <String>['bbbb', 'cccc']);
    expect(c.commitMetaRequestSeq, 2);
    expect(bindings.metaRequestsSent, 2);
  });

  test('commitMetaRequestSeq stays 0 without a native session', () {
    final RepoSessionController c = _real();
    c.requestCommitMeta(const <String>['aaaa']);
    expect(c.commitMetaRequestSeq, 0);
  });

  test('refreshHistory without a native session sends nothing and is 0', () {
    expect(_real().refreshHistory(), 0);
  });
}
