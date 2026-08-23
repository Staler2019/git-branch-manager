// Shared fake RepoSessionController/GbmBindings/RecentsRepository for
// widget and integration tests that need a RepoSessionState without a real
// FFI session. Extracted from what working_copy_view_test.dart and
// conflict_resolve_window_test.dart each hand-rolled separately.
//
// The seam this relies on: RepoSessionController._open() (see
// repo_session_repository.dart) treats a null `sessionOpen()` return as
// "open failed" and returns immediately, before touching `_bindings` or
// `_recents` again -- so [FakeGbmBindings] only needs to implement the two
// methods `_open()` itself calls (`sessionOpen`, `lastResultJsonLen`);
// every other command method on RepoSessionController then hits its own
// `if (_session == nullptr) return;` guard and safely no-ops unless
// overridden here. Overridden methods do the opposite of a no-op: they
// record the call so a test can assert on it.
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/operation_choice.dart';
import 'package:gbm_flutter/data/models/parsed_conflict_file.dart';
import 'package:gbm_flutter/data/repositories/recents_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/models/rebase_todo_entry.dart';
import 'package:gbm_flutter/data/repositories/open_repo_sessions.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

/// One recorded call into [FakeRepoSessionController] -- a name plus
/// whatever arguments the test cares about, for integration tests that
/// just need to assert "did this action reach the controller" without a
/// bespoke bool field per method. See the typed fields on
/// [FakeRepoSessionController] for the handful of methods an existing test
/// already asserts on more specifically (kept for source compatibility).
class FakeCommand {
  const FakeCommand(this.name, [this.args = const <String, Object?>{}]);

  final String name;
  final Map<String, Object?> args;

  @override
  String toString() => 'FakeCommand($name, $args)';
}

/// Fake [RepoSessionController] for widget/integration tests.
///
/// [state] starts at [initialState] (bypassing the real `_open()`, which
/// [FakeGbmBindings] makes fail immediately by returning a null session).
/// Call [emit] to simulate an FFI event arriving and publishing a new
/// state -- exactly what a real event would do via `_onEvent`'s
/// `copyWith()`, just driven by the test instead of a native callback.
class FakeRepoSessionController extends RepoSessionController {
  FakeRepoSessionController(
    RepoIdentity identity,
    RepoSessionState initialState, {
    ParsedConflictFile? parsedFile,
    int maxOperationLogEntries = 2000,
    OpenRepoSessions? openSessions,
  }) : super(
         FakeGbmBindings(),
         identity,
         FakeRecentsRepository(),
         maxOperationLogEntries: maxOperationLogEntries,
         openSessions: openSessions,
       ) {
    _parsedFile = parsedFile;
    state = initialState;
  }

  ParsedConflictFile? _parsedFile;

  /// Lets a test simulate a fresh conflict occurrence on an already-seen
  /// path (e.g. Abort followed by a new merge) supplying different markers
  /// than the ones parsed the first time.
  set parsedFile(ParsedConflictFile value) => _parsedFile = value;

  /// Every call recorded here, in order -- see [FakeCommand]. Use
  /// `fake.commandLog.any((c) => c.name == 'fetchRemote')` style
  /// assertions for commands with no bespoke field below.
  final List<FakeCommand> commandLog = <FakeCommand>[];

  // Bespoke recording fields kept for source compatibility with the two
  // tests this was extracted from (conflict_resolve_window_test.dart).
  final List<({String path, dynamic resolution})> resolveConflictCalls =
      <({String path, dynamic resolution})>[];
  bool mergeAbortCalled = false;
  bool cherryPickAbortCalled = false;
  bool cherryPickContinueCalled = false;
  bool continueRebaseCalled = false;
  bool abortRebaseCalled = false;
  bool cherryPickContinueWithMessageCalled = false;
  bool continueRebaseWithMessageCalled = false;
  String? lastContinueMessage;

  /// Simulates an FFI event publishing a new state, exactly as a real
  /// native callback would -- tests drive transitions with this instead of
  /// firing native events.
  void emit(RepoSessionState next) => state = next;

  /// Recorded rather than left to the base class: an unoverridden method
  /// hits the real `_session == nullptr` guard and silently no-ops, so a
  /// test could not tell a dead dispatch path from a working one.
  @override
  void setHistoryFilter({
    required List<String> includeRefs,
    bool firstParentOnly = false,
    bool noMerges = false,
  }) {
    commandLog.add(
      FakeCommand('setHistoryFilter', <String, Object?>{
        'includeRefs': includeRefs,
        'firstParentOnly': firstParentOnly,
        'noMerges': noMerges,
      }),
    );
  }

  @override
  void resolveConflict(
    String path,
    dynamic resolution, {
    bool oursBlobMissing = false,
    bool theirsBlobMissing = false,
    String? resolvedContent,
  }) {
    resolveConflictCalls.add((path: path, resolution: resolution));
    commandLog.add(
      FakeCommand('resolveConflict', <String, Object?>{
        'path': path,
        'resolution': resolution,
      }),
    );
  }

  // Real requestWorkingTreeContent() is async and always publishes a fresh
  // WorkingTreeContentReply object once the read completes -- this fake
  // must do the same (not a no-op) so tests can distinguish "content
  // already applied for this selection" from "content just arrived",
  // matching _applyParsedContentIfNeeded's identity guard in the window.
  @override
  void requestWorkingTreeContent(String path) {
    commandLog.add(
      FakeCommand('requestWorkingTreeContent', <String, Object?>{'path': path}),
    );
    state = state.copyWith(
      lastWorkingTreeContent: WorkingTreeContentReply(
        path: path,
        editable: true,
        content: state.lastWorkingTreeContent?.content ?? '',
      ),
    );
  }

  /// Records the call and, unless [failFileAtRevisionExport] is set,
  /// publishes a successful export echoing the request back -- the real
  /// capi's own contract. Tests that need the failure branch flip the flag
  /// before invoking the action.
  bool failFileAtRevisionExport = false;

  @override
  void exportFileAtRevision({
    required String revision,
    required String path,
    required String destPath,
  }) {
    commandLog.add(
      FakeCommand('exportFileAtRevision', <String, Object?>{
        'revision': revision,
        'path': path,
        'destPath': destPath,
      }),
    );
    state = state.copyWith(
      lastFileAtRevisionExport: FileAtRevisionExport(
        revision: revision,
        path: path,
        destPath: destPath,
        succeeded: !failFileAtRevisionExport,
        error: failFileAtRevisionExport
            ? const GitError(
                code: 1,
                codeName: 'NotFound',
                message: 'nope',
                detail: '',
                argv: <String>[],
                exitCode: 128,
              )
            : null,
      ),
    );
  }

  @override
  void restorePaths(
    List<String> paths, {
    String source = '',
    bool staged = false,
  }) {
    commandLog.add(
      FakeCommand('restorePaths', <String, Object?>{
        'paths': paths,
        'staged': staged,
      }),
    );
  }

  @override
  void exportPatches(List<String> commitHexes, String outputDir) {
    commandLog.add(
      FakeCommand('exportPatches', <String, Object?>{
        'commitHexes': commitHexes,
        'outputDir': outputDir,
      }),
    );
  }

  @override
  void discardLines(String path, int hunkIndex, List<int> lineIndices) {
    commandLog.add(
      FakeCommand('discardLines', <String, Object?>{
        'path': path,
        'hunkIndex': hunkIndex,
        'lineIndices': lineIndices,
      }),
    );
  }

  @override
  ParsedConflictFile parseConflictMarkers(String content) {
    final ParsedConflictFile? parsed = _parsedFile;
    if (parsed == null) {
      throw StateError(
        'FakeRepoSessionController.parseConflictMarkers called with no '
        'parsedFile set -- pass one to the constructor or its setter.',
      );
    }
    return parsed;
  }

  @override
  void mergeAbort() {
    mergeAbortCalled = true;
    commandLog.add(const FakeCommand('mergeAbort'));
  }

  @override
  void cherryPickAbort() {
    cherryPickAbortCalled = true;
    commandLog.add(const FakeCommand('cherryPickAbort'));
  }

  @override
  void cherryPickContinue() {
    cherryPickContinueCalled = true;
    commandLog.add(const FakeCommand('cherryPickContinue'));
  }

  @override
  void continueRebase() {
    continueRebaseCalled = true;
    commandLog.add(const FakeCommand('continueRebase'));
  }

  @override
  void abortRebase() {
    abortRebaseCalled = true;
    commandLog.add(const FakeCommand('abortRebase'));
  }

  @override
  void cherryPickSkip() {
    commandLog.add(const FakeCommand('cherryPickSkip'));
  }

  @override
  void skipRebase() {
    commandLog.add(const FakeCommand('skipRebase'));
  }

  @override
  void requestOriginalOperationMessage() {
    // Simulates the async gbm_request_original_operation_message() round
    // trip completing synchronously -- the window's ref.listen picks up
    // the null -> non-null transition and opens the MSGS dialog.
    commandLog.add(const FakeCommand('requestOriginalOperationMessage'));
    state = state.copyWith(
      originalOperationMessage: 'Original summary\n\nOriginal body',
    );
  }

  @override
  void cherryPickContinueWithMessage(String message) {
    cherryPickContinueWithMessageCalled = true;
    lastContinueMessage = message;
    commandLog.add(
      FakeCommand('cherryPickContinueWithMessage', <String, Object?>{
        'message': message,
      }),
    );
  }

  @override
  void continueRebaseWithMessage(String message) {
    continueRebaseWithMessageCalled = true;
    lastContinueMessage = message;
    commandLog.add(
      FakeCommand('continueRebaseWithMessage', <String, Object?>{
        'message': message,
      }),
    );
  }

  /// Recorded rather than left to the null-session no-op because the status
  /// bar's Cancel button dispatches through here: `_cancelTask('history-scan')`
  /// (workspace_screen.dart) cancels the incremental scan by re-requesting
  /// the current snapshot, there being no separate cancel entry point in the
  /// capi. Without this override a test could not tell a dead Cancel button
  /// apart from a dispatched one.
  @override
  void refreshHistory() {
    commandLog.add(const FakeCommand('refreshHistory'));
  }

  @override
  void fetchRemote({
    String remoteName = '',
    List<String> refs = const <String>[],
    bool prune = false,
    bool tags = false,
  }) {
    commandLog.add(
      FakeCommand('fetchRemote', <String, Object?>{
        'remoteName': remoteName,
        'refs': refs,
      }),
    );
  }

  @override
  void pullChanges({
    String remoteName = '',
    String branch = '',
    bool rebase = false,
    bool stashFirst = false,
  }) {
    commandLog.add(
      FakeCommand('pullChanges', <String, Object?>{
        'remoteName': remoteName,
        'branch': branch,
      }),
    );
  }

  @override
  void pushChanges({
    String remoteName = '',
    List<String> branches = const <String>[],
    bool setUpstream = false,
    bool pushTags = false,
    bool forceWithLease = false,
  }) {
    commandLog.add(
      FakeCommand('pushChanges', <String, Object?>{
        'remoteName': remoteName,
        'branches': branches,
        'setUpstream': setUpstream,
        'forceWithLease': forceWithLease,
      }),
    );
  }

  @override
  void stageFiles(List<String> paths) {
    commandLog.add(
      FakeCommand('stageFiles', <String, Object?>{'paths': paths}),
    );
  }

  @override
  void deleteBranch({
    required List<String> names,
    bool force = false,
    bool isRemote = false,
    String remoteName = '',
  }) {
    commandLog.add(
      FakeCommand('deleteBranch', <String, Object?>{
        'names': names,
        'force': force,
        'isRemote': isRemote,
        'remoteName': remoteName,
      }),
    );
  }

  @override
  void checkout({
    required String target,
    bool detach = false,
    bool createBranch = false,
    String newBranchName = '',
    bool force = false,
    bool stashFirst = false,
    bool recurseSubmodules = false,
  }) {
    commandLog.add(
      FakeCommand('checkout', <String, Object?>{
        'target': target,
        // `detach` matters to the reflog panel, whose targets are bare oids
        // with no branch to land on -- recording it is what lets a test
        // tell "checked out detached" from "tried to check out a branch".
        'detach': detach,
        'createBranch': createBranch,
        'newBranchName': newBranchName,
      }),
    );
  }

  @override
  void requestRemotePrunePreview(String remoteName) {
    commandLog.add(
      FakeCommand('requestRemotePrunePreview', <String, Object?>{
        'remoteName': remoteName,
      }),
    );
  }

  @override
  void pruneRemote(String remoteName, List<String> refs) {
    commandLog.add(
      FakeCommand('pruneRemote', <String, Object?>{
        'remoteName': remoteName,
        'refs': refs,
      }),
    );
  }

  @override
  void addRemote(String name, String url) {
    commandLog.add(
      FakeCommand('addRemote', <String, Object?>{'name': name, 'url': url}),
    );
  }

  @override
  void removeRemote(String name) {
    commandLog.add(
      FakeCommand('removeRemote', <String, Object?>{'name': name}),
    );
  }

  @override
  void renameBranch({
    required String from,
    required String to,
    bool force = false,
    bool renameRemote = false,
    String remoteName = '',
  }) {
    commandLog.add(
      FakeCommand('renameBranch', <String, Object?>{
        'from': from,
        'to': to,
        'force': force,
        'renameRemote': renameRemote,
        'remoteName': remoteName,
      }),
    );
  }

  @override
  void applyStash(int index, {bool pop = false}) {
    commandLog.add(
      FakeCommand('applyStash', <String, Object?>{'index': index, 'pop': pop}),
    );
  }

  @override
  void dropStash(int index) {
    commandLog.add(FakeCommand('dropStash', <String, Object?>{'index': index}));
  }

  @override
  void branchFromStash(int index, String branchName) {
    commandLog.add(
      FakeCommand('branchFromStash', <String, Object?>{
        'index': index,
        'branchName': branchName,
      }),
    );
  }

  @override
  void requestStashDiff(int index) {
    commandLog.add(
      FakeCommand('requestStashDiff', <String, Object?>{'index': index}),
    );
  }

  @override
  void createTag(
    String name, {
    String target = '',
    String message = '',
    bool force = false,
  }) {
    commandLog.add(
      FakeCommand('createTag', <String, Object?>{
        'name': name,
        'target': target,
      }),
    );
  }

  @override
  void deleteTag(
    String name, {
    bool alsoRemote = false,
    String remoteName = '',
  }) {
    commandLog.add(
      FakeCommand('deleteTag', <String, Object?>{
        'name': name,
        'alsoRemote': alsoRemote,
      }),
    );
  }

  @override
  void pushTag(String remoteName, {String name = ''}) {
    commandLog.add(
      FakeCommand('pushTag', <String, Object?>{
        'remoteName': remoteName,
        'name': name,
      }),
    );
  }

  @override
  void provideCredential(String secret) {
    commandLog.add(const FakeCommand('provideCredential'));
  }

  @override
  void cancelCredential() {
    commandLog.add(const FakeCommand('cancelCredential'));
  }

  @override
  void retryCheckoutWithChoice(OperationChoiceKind kind) {
    commandLog.add(
      FakeCommand('retryCheckoutWithChoice', <String, Object?>{'kind': kind}),
    );
  }

  @override
  void dismissCheckoutChoices() {
    commandLog.add(const FakeCommand('dismissCheckoutChoices'));
  }

  @override
  void retryDeleteBranchWithChoice(OperationChoiceKind kind) {
    commandLog.add(
      FakeCommand('retryDeleteBranchWithChoice', <String, Object?>{
        'kind': kind,
      }),
    );
  }

  @override
  void dismissDeleteBranchChoices() {
    commandLog.add(const FakeCommand('dismissDeleteBranchChoices'));
  }

  // Spec page 19 management panels (Tier 6c). Each records into
  // [commandLog] so a panel test can assert the toolbar reached the
  // session; without an override they would hit the null-session guard and
  // silently no-op, which a test cannot tell apart from a dead button.
  @override
  void addSubmodule(String url, {String path = '', String branch = ''}) {
    commandLog.add(
      FakeCommand('addSubmodule', <String, Object?>{
        'url': url,
        'path': path,
        'branch': branch,
      }),
    );
  }

  @override
  void initSubmodules({
    List<String> paths = const <String>[],
    bool recursive = false,
  }) {
    commandLog.add(
      FakeCommand('initSubmodules', <String, Object?>{
        'paths': paths,
        'recursive': recursive,
      }),
    );
  }

  @override
  void updateSubmodules({
    List<String> paths = const <String>[],
    bool recursive = false,
    bool init = false,
    bool remote = false,
  }) {
    commandLog.add(
      FakeCommand('updateSubmodules', <String, Object?>{
        'paths': paths,
        'recursive': recursive,
        'init': init,
        'remote': remote,
      }),
    );
  }

  @override
  void syncSubmodules({
    List<String> paths = const <String>[],
    bool recursive = false,
  }) {
    commandLog.add(
      FakeCommand('syncSubmodules', <String, Object?>{
        'paths': paths,
        'recursive': recursive,
      }),
    );
  }

  @override
  void deinitSubmodules({
    List<String> paths = const <String>[],
    bool force = false,
  }) {
    commandLog.add(
      FakeCommand('deinitSubmodules', <String, Object?>{
        'paths': paths,
        'force': force,
      }),
    );
  }

  @override
  void installLfs() {
    commandLog.add(const FakeCommand('installLfs'));
  }

  @override
  void trackLfsPattern(String pattern) {
    commandLog.add(
      FakeCommand('trackLfsPattern', <String, Object?>{'pattern': pattern}),
    );
  }

  @override
  void untrackLfsPattern(String pattern) {
    commandLog.add(
      FakeCommand('untrackLfsPattern', <String, Object?>{'pattern': pattern}),
    );
  }

  @override
  void pullLfs({String remoteName = ''}) {
    commandLog.add(
      FakeCommand('pullLfs', <String, Object?>{'remoteName': remoteName}),
    );
  }

  @override
  void fetchLfs({String remoteName = ''}) {
    commandLog.add(
      FakeCommand('fetchLfs', <String, Object?>{'remoteName': remoteName}),
    );
  }

  @override
  void pruneLfs({bool dryRun = false}) {
    commandLog.add(
      FakeCommand('pruneLfs', <String, Object?>{'dryRun': dryRun}),
    );
  }

  @override
  void requestReflog({String ref = ''}) {
    commandLog.add(FakeCommand('requestReflog', <String, Object?>{'ref': ref}));
  }

  @override
  void requestCommitMeta(List<String> oids) {
    commandLog.add(
      FakeCommand('requestCommitMeta', <String, Object?>{'oids': oids}),
    );
  }

  /// Recorded, not no-opped: without this override the real method hits its
  /// own `_session == nullptr` guard and silently returns, so `commandLog`
  /// could not tell "correctly gated off by an invisible column" from "never
  /// wired up at all" -- which is exactly the distinction the Changed files
  /// column's visible-gate test turns on.
  @override
  void requestCommitFileCounts(List<String> oids) {
    commandLog.add(
      FakeCommand('requestCommitFileCounts', <String, Object?>{'oids': oids}),
    );
  }

  @override
  void startBisect({
    String badRef = '',
    List<String> goodRefs = const <String>[],
    List<String> paths = const <String>[],
    bool noCheckout = false,
  }) {
    commandLog.add(
      FakeCommand('startBisect', <String, Object?>{
        'badRef': badRef,
        'goodRefs': goodRefs,
        'paths': paths,
        'noCheckout': noCheckout,
      }),
    );
  }

  @override
  void markBisect({required bool good, String ref = ''}) {
    commandLog.add(
      FakeCommand('markBisect', <String, Object?>{'good': good, 'ref': ref}),
    );
  }

  @override
  void skipBisect({List<String> refs = const <String>[]}) {
    commandLog.add(FakeCommand('skipBisect', <String, Object?>{'refs': refs}));
  }

  @override
  void resetBisect({String target = ''}) {
    commandLog.add(
      FakeCommand('resetBisect', <String, Object?>{'target': target}),
    );
  }

  @override
  void requestBlame(
    String path, {
    String revision = '',
    int startLine = 0,
    int endLine = 0,
  }) {
    commandLog.add(
      FakeCommand('requestBlame', <String, Object?>{
        'path': path,
        'revision': revision,
        'startLine': startLine,
        'endLine': endLine,
      }),
    );
  }

  @override
  void requestFileHistory(String path, {String startRevision = ''}) {
    commandLog.add(
      FakeCommand('requestFileHistory', <String, Object?>{
        'path': path,
        'startRevision': startRevision,
      }),
    );
  }

  @override
  void requestLineHistory(
    String path,
    int startLine,
    int endLine, {
    String startRevision = '',
  }) {
    commandLog.add(
      FakeCommand('requestLineHistory', <String, Object?>{
        'path': path,
        'startLine': startLine,
        'endLine': endLine,
        'startRevision': startRevision,
      }),
    );
  }

  @override
  void requestCommitFileDiff(String oid, String path) {
    commandLog.add(
      FakeCommand('requestCommitFileDiff', <String, Object?>{
        'oid': oid,
        'path': path,
      }),
    );
  }

  @override
  void requestRebasePlan(String upstream) {
    commandLog.add(
      FakeCommand('requestRebasePlan', <String, Object?>{'upstream': upstream}),
    );
  }

  @override
  void startInteractiveRebase(
    String upstream,
    List<RebaseTodoEntry> todo, {
    String onto = '',
    bool stashFirst = false,
  }) {
    commandLog.add(
      FakeCommand('startInteractiveRebase', <String, Object?>{
        'upstream': upstream,
        // The todo's *shape* is what matters to a caller test -- which
        // action landed on which commit, in what order -- so it is
        // flattened rather than stored as opaque entries a test would have
        // to reach into.
        'oids': todo.map((RebaseTodoEntry e) => e.oid).toList(),
        'actions': todo.map((RebaseTodoEntry e) => e.action.name).toList(),
        'onto': onto,
        'stashFirst': stashFirst,
      }),
    );
  }

  @override
  void applyPatchFiles(
    List<String> files, {
    bool threeWay = false,
    bool updateIndex = false,
  }) {
    commandLog.add(
      FakeCommand('applyPatchFiles', <String, Object?>{
        'files': files,
        'threeWay': threeWay,
        'updateIndex': updateIndex,
      }),
    );
  }

  @override
  void importPatches(List<String> patchFiles, {bool threeWay = false}) {
    commandLog.add(
      FakeCommand('importPatches', <String, Object?>{
        'patchFiles': patchFiles,
        'threeWay': threeWay,
      }),
    );
  }
}

/// Fake [GbmBindings] that fails session open immediately, so
/// [FakeRepoSessionController]'s `_open()` returns before touching
/// anything else. Any method beyond the two `_open()` calls throws loudly
/// via [noSuchMethod] instead of dlopen'ing the real native library --
/// deliberate: a provider this test forgot to override should fail fast,
/// not silently succeed against a real `.dylib`/`.so`.
class FakeGbmBindings implements GbmBindings {
  @override
  SessionOpenDart get sessionOpen =>
      (Pointer<Utf8> workDir, Pointer<Utf8> gitDir, Pointer<Utf8> commonDir) =>
          nullptr;

  @override
  LastResultJsonLenDart get lastResultJsonLen =>
      () => 0;

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Not implemented for testing');
}

/// Fake [RecentsRepository] -- [RepoSessionController]._open() calls
/// `recordOpen()` fire-and-forget only after a successful session open,
/// which never happens here, so no method is ever actually reached.
class FakeRecentsRepository implements RecentsRepository {
  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Not implemented for testing');
}
