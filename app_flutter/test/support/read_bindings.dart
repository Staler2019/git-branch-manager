// A real RepoSessionController over an open fake session, for the reads a
// surface waits on (read-failure-states-spec.html). The request exports record
// their arguments and answer [ReadBindings.answer] -- 1 = queued, 0 = nothing
// queued with the native error staged, as the library does -- so the real
// controller's reset, key check and 0 branch all run. Replies go in through
// `debugHandleEvent` as wire bytes.
//
// Built on the same overrides as `repo_session_auto_prune_worktrees_test.dart`'s
// `_PruneBindings`: the ones the controller's constructor reaches.
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';

import 'fake_repo_session.dart';

/// The GitError JSON the library stages when an export catches a throw
/// (`reportNativeException`, capi/Handle.h).
Map<String, dynamic> nativeErrorJson(String function) => <String, dynamic>{
  'code': 1,
  'codeName': 'Unknown',
  'message': 'Native error in $function',
  'detail': 'std::bad_alloc',
  'argv': <String>[],
  'exitCode': -1,
};

Map<String, dynamic> gitErrorJson(String message) => <String, dynamic>{
  'code': 2,
  'codeName': 'CommandFailed',
  'message': message,
  'detail': '',
  'argv': <String>['git', 'blame'],
  'exitCode': 128,
};

GbmEvent readyEvent(int type, Map<String, dynamic> payload) =>
    GbmEvent(type, utf8.encode(jsonEncode(payload)));

class ReadBindings extends FakeGbmBindings {
  /// What each request export returns.
  int answer = 1;

  final List<Map<String, Object?>> blameRequests = <Map<String, Object?>>[];
  final List<Map<String, Object?>> fileHistoryRequests =
      <Map<String, Object?>>[];
  final List<Map<String, Object?>> lineHistoryRequests =
      <Map<String, Object?>>[];
  final List<String> reflogRequests = <String>[];
  final List<String> rebasePlanRequests = <String>[];

  Uint8List _staged = Uint8List(0);

  void _stage(Object json) => _staged = utf8.encode(jsonEncode(json));

  /// Refreshed lists (R class): each refresh export counts its calls, and
  /// each list getter the re-read path calls counts its reads and stages the
  /// list set here -- so a test can tell a re-read from none.
  int stashRefreshes = 0;
  int stashesReads = 0;
  List<Map<String, dynamic>> stashesList = <Map<String, dynamic>>[];

  @override
  StashRefreshDart get stashRefresh => (Pointer<Void> session) {
    stashRefreshes++;
    if (answer == 0) _stage(nativeErrorJson('gbm_stash_refresh'));
    return answer;
  };

  final List<int> stashDiffRequests = <int>[];

  @override
  StashRequestDiffDart get stashRequestDiff =>
      (Pointer<Void> session, int index) {
        stashDiffRequests.add(index);
        if (answer == 0) _stage(nativeErrorJson('gbm_stash_request_diff'));
        return answer;
      };

  @override
  StashesJsonDart get stashesJson => (Pointer<Void> session) {
    stashesReads++;
    _stage(stashesList);
    return 0;
  };

  int worktreeRefreshes = 0;
  int worktreePendingCountRequests = 0;
  int worktreesReads = 0;

  /// No prunable row by default, so `publishWorktrees`' auto-prune reaches
  /// no `worktreePrune` binding.
  List<Map<String, dynamic>> worktreesList = <Map<String, dynamic>>[];

  @override
  WorktreeRefreshDart get worktreeRefresh => (Pointer<Void> session) {
    worktreeRefreshes++;
    if (answer == 0) _stage(nativeErrorJson('gbm_worktree_refresh'));
    return answer;
  };

  @override
  WorktreeRequestPendingCountsDart get worktreeRequestPendingCounts =>
      (Pointer<Void> session) {
        worktreePendingCountRequests++;
        if (answer == 0) {
          _stage(nativeErrorJson('gbm_worktree_request_pending_counts'));
        }
        return answer;
      };

  @override
  WorktreesJsonDart get worktreesJson => (Pointer<Void> session) {
    worktreesReads++;
    _stage(worktreesList);
    return 0;
  };

  int remoteRefreshes = 0;
  int remotesReads = 0;
  List<Map<String, dynamic>> remotesList = <Map<String, dynamic>>[];

  @override
  RemoteRefreshDart get remoteRefresh => (Pointer<Void> session) {
    remoteRefreshes++;
    if (answer == 0) _stage(nativeErrorJson('gbm_remote_refresh'));
    return answer;
  };

  @override
  RemotesJsonDart get remotesJson => (Pointer<Void> session) {
    remotesReads++;
    _stage(remotesList);
    return 0;
  };

  int submoduleRefreshes = 0;
  int submodulesReads = 0;
  List<Map<String, dynamic>> submodulesList = <Map<String, dynamic>>[];

  @override
  SubmoduleRefreshDart get submoduleRefresh => (Pointer<Void> session) {
    submoduleRefreshes++;
    if (answer == 0) _stage(nativeErrorJson('gbm_submodule_refresh'));
    return answer;
  };

  @override
  SubmodulesJsonDart get submodulesJson => (Pointer<Void> session) {
    submodulesReads++;
    _stage(submodulesList);
    return 0;
  };

  @override
  RequestBlameDart get requestBlame =>
      (
        Pointer<Void> session,
        Pointer<Utf8> path,
        Pointer<Utf8> revision,
        int startLine,
        int endLine,
      ) {
        blameRequests.add(<String, Object?>{
          'path': path.toDartString(),
          'revision': revision.toDartString(),
          'startLine': startLine,
          'endLine': endLine,
        });
        if (answer == 0) _stage(nativeErrorJson('gbm_request_blame'));
        return answer;
      };

  @override
  RequestFileHistoryDart get requestFileHistory =>
      (Pointer<Void> session, Pointer<Utf8> path, Pointer<Utf8> startRevision) {
        fileHistoryRequests.add(<String, Object?>{
          'path': path.toDartString(),
          'startRevision': startRevision.toDartString(),
        });
        if (answer == 0) _stage(nativeErrorJson('gbm_request_file_history'));
        return answer;
      };

  @override
  RequestLineHistoryDart get requestLineHistory =>
      (
        Pointer<Void> session,
        Pointer<Utf8> path,
        int startLine,
        int endLine,
        Pointer<Utf8> startRevision,
      ) {
        lineHistoryRequests.add(<String, Object?>{
          'path': path.toDartString(),
          'startLine': startLine,
          'endLine': endLine,
          'startRevision': startRevision.toDartString(),
        });
        if (answer == 0) _stage(nativeErrorJson('gbm_request_line_history'));
        return answer;
      };

  @override
  RequestReflogDart get requestReflog =>
      (Pointer<Void> session, Pointer<Utf8> ref) {
        reflogRequests.add(ref.toDartString());
        if (answer == 0) _stage(nativeErrorJson('gbm_request_reflog'));
        return answer;
      };

  @override
  RequestRebasePlanDart get requestRebasePlan =>
      (Pointer<Void> session, Pointer<Utf8> upstream) {
        rebasePlanRequests.add(upstream.toDartString());
        if (answer == 0) _stage(nativeErrorJson('gbm_request_rebase_plan'));
        return answer;
      };

  @override
  RepoStateJsonDart get repoStateJson => (Pointer<Void> session) {
    _stage(<String, dynamic>{
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
    });
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
}
