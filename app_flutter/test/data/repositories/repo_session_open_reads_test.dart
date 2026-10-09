// Identity is read once when the repository opens, not on every refresh
// sweep. `effectiveIdentity.email` is what the commit graph marks "my
// commits" with, and nothing on screen re-reads it on its own -- so if the
// open does not read it, the graph has no email until the Repository
// Settings dialog happens to be opened.
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

/// Opens successfully and records every per-session read the open starts.
class _OpenRecordingBindings extends FakeGbmBindings {
  final List<String> calls = <String>[];

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
      (Pointer<Void> session) => calls.add('historyRefresh');

  @override
  WorkingCopyRefreshDart get workingCopyRefresh =>
      (Pointer<Void> session) => calls.add('workingCopyRefresh');

  @override
  LocalIdentityRefreshDart get localIdentityRefresh =>
      (Pointer<Void> session) => calls.add('localIdentityRefresh');

  @override
  EffectiveIdentityRefreshDart get effectiveIdentityRefresh =>
      (Pointer<Void> session) => calls.add('effectiveIdentityRefresh');
}

/// This open succeeds, so `_open()` does reach `recordOpen()` -- which the
/// shared [FakeRecentsRepository] deliberately throws on.
class _NoopRecents extends FakeRecentsRepository {
  @override
  Future<void> recordOpen(String workDir) async {}
}

void main() {
  test('opening a repository reads both identities exactly once', () {
    final _OpenRecordingBindings bindings = _OpenRecordingBindings();

    RepoSessionController(
      bindings,
      RepoIdentity.forWorkDir('/test/repo'),
      _NoopRecents(),
    );

    expect(
      bindings.calls.where((String c) => c == 'localIdentityRefresh').length,
      1,
    );
    expect(
      bindings.calls
          .where((String c) => c == 'effectiveIdentityRefresh')
          .length,
      1,
      reason: 'the commit graph marks "my commits" by this email',
    );
  });
}
