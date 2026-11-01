// A staged rename's diff has to be asked for with both of its paths, or git
// cannot pair the two halves and draws a whole-file add. None of the callers
// holds the status entry -- only its path -- so the controller looks the old
// path up itself. These tests drive the real RepoSessionController against
// bindings that record what actually crosses the FFI, because
// FakeRepoSessionController overrides the very methods under test.
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

/// One recorded diff request: which binding, and the two paths it was given.
typedef _DiffCall = ({String binding, String path, String oldPath, int staged});

/// Opens successfully and records the working-copy diff requests.
class _DiffRecordingBindings extends FakeGbmBindings {
  final List<_DiffCall> calls = <_DiffCall>[];

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

  WorkingCopyDiffDart _recorder(String binding) =>
      (
        Pointer<Void> session,
        Pointer<Utf8> path,
        Pointer<Utf8> oldPath,
        int staged,
      ) => calls.add((
        binding: binding,
        path: path.toDartString(),
        oldPath: oldPath.toDartString(),
        staged: staged,
      ));

  @override
  WorkingCopyDiffDart get workingCopyDiff => _recorder('workingCopyDiff');

  @override
  WorkingCopyDiffDart get workingCopyFullDiff =>
      _recorder('workingCopyFullDiff');

  @override
  UnstageHunkDart get unstageHunk =>
      (
        Pointer<Void> session,
        Pointer<Utf8> path,
        Pointer<Utf8> oldPath,
        int hunkIndex,
      ) => calls.add((
        binding: 'unstageHunk',
        path: path.toDartString(),
        oldPath: oldPath.toDartString(),
        staged: 1,
      ));

  @override
  UnstageLinesDart get unstageLines =>
      (
        Pointer<Void> session,
        Pointer<Utf8> path,
        Pointer<Utf8> oldPath,
        int hunkIndex,
        Pointer<Int32> lineIndices,
        int lineIndexCount,
      ) => calls.add((
        binding: 'unstageLines',
        path: path.toDartString(),
        oldPath: oldPath.toDartString(),
        staged: 1,
      ));
}

class _NoopRecents extends FakeRecentsRepository {
  @override
  Future<void> recordOpen(String workDir) async {}
}

WorkingCopyEntry _entry({
  required String path,
  String oldPath = '',
  bool staged = false,
  FileChangeKind indexStatus = FileChangeKind.modified,
  bool hasUnstagedChange = false,
}) => WorkingCopyEntry(
  path: path,
  oldPath: oldPath,
  untracked: false,
  staged: staged,
  indexStatus: indexStatus,
  hasUnstagedChange: hasUnstagedChange,
  worktreeStatus: FileChangeKind.modified,
  unstagedAdded: 0,
  unstagedRemoved: 0,
  stagedAdded: 0,
  stagedRemoved: 0,
  conflict: ConflictKind.none,
  ancestorBlob: '',
  oursBlob: '',
  theirsBlob: '',
  similarity: staged && oldPath.isNotEmpty ? 100 : 0,
  isSubmodule: false,
  isConflicted: false,
);

void main() {
  late _DiffRecordingBindings bindings;
  late RepoSessionController controller;

  setUp(() {
    bindings = _DiffRecordingBindings();
    controller = RepoSessionController(
      bindings,
      RepoIdentity.forWorkDir('/test/repo'),
      _NoopRecents(),
    );
    controller.publishWorkingCopyStatus(
      WorkingCopyStatus(
        entries: <WorkingCopyEntry>[
          _entry(
            path: 'lib/after.dart',
            oldPath: 'lib/before.dart',
            staged: true,
            indexStatus: FileChangeKind.renamed,
            hasUnstagedChange: true,
          ),
          _entry(path: 'plain.dart', staged: true),
        ],
      ),
    );
    bindings.calls.clear();
  });

  List<_DiffCall> callsOf(String binding) => bindings.calls
      .where((_DiffCall c) => c.binding == binding)
      .toList(growable: false);

  test('a staged rename diff is asked for with its old path', () {
    controller.requestDiff('lib/after.dart', staged: true);

    final List<_DiffCall> calls = callsOf('workingCopyDiff');
    expect(calls, hasLength(1));
    expect(calls.single.path, 'lib/after.dart');
    expect(calls.single.oldPath, 'lib/before.dart');
    expect(calls.single.staged, 1);
  });

  test('a staged rename full diff is asked for with its old path', () {
    controller.requestFullDiff('lib/after.dart', staged: true);

    final List<_DiffCall> calls = callsOf('workingCopyFullDiff');
    expect(calls, hasLength(1));
    expect(calls.single.oldPath, 'lib/before.dart');
  });

  test('refetching a disagreeing staged rename carries the old path on both '
      'requests', () {
    expect(
      controller.refetchDisagreeingDiffs('lib/after.dart', staged: true),
      isTrue,
    );

    expect(callsOf('workingCopyDiff').single.oldPath, 'lib/before.dart');
    expect(callsOf('workingCopyFullDiff').single.oldPath, 'lib/before.dart');
  });

  test('the unstaged side of the same file sends no old path', () {
    // git does no rename detection between the index and the work tree, so
    // the work-tree half of a renamed-then-edited file is a plain path.
    controller.requestDiff('lib/after.dart');

    expect(callsOf('workingCopyDiff').single.oldPath, '');
  });

  test('a staged file that is not a rename sends no old path', () {
    controller.requestDiff('plain.dart', staged: true);

    expect(callsOf('workingCopyDiff').single.oldPath, '');
  });

  test('unstaging a hunk of a staged rename sends its old path', () {
    // The core rebuilds the staged diff with this pathspec; without the old
    // path the hunk index the pane showed addresses a whole-file add.
    controller.unstageHunk('lib/after.dart', 0);

    final List<_DiffCall> calls = callsOf('unstageHunk');
    expect(calls, hasLength(1));
    expect(calls.single.path, 'lib/after.dart');
    expect(calls.single.oldPath, 'lib/before.dart');
  });

  test('unstaging lines of a staged rename sends its old path', () {
    controller.unstageLines('lib/after.dart', 0, <int>[2, 4]);

    final List<_DiffCall> calls = callsOf('unstageLines');
    expect(calls, hasLength(1));
    expect(calls.single.oldPath, 'lib/before.dart');
  });

  test('unstaging lines of a staged file that is not a rename sends no old '
      'path', () {
    controller.unstageLines('plain.dart', 0, <int>[1]);

    expect(callsOf('unstageLines').single.oldPath, '');
  });
}
