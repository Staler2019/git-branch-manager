// Verifies the Dart-side models parse exactly the JSON shape
// src/capi/JsonCodec.cpp emits -- the direct counterpart of
// tests/capi/JsonCodecTest.cpp on the C++ side. No FFI involved: these are
// plain JSON-decoding unit tests.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/base_folder_record.dart';
import 'package:gbm_flutter/data/models/blame_result.dart';
import 'package:gbm_flutter/data/models/file_history_entry.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/line_history_chunk.dart';
import 'package:gbm_flutter/data/models/operation_outcome.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/reflog_entry.dart';
import 'package:gbm_flutter/data/models/remote_info.dart';
import 'package:gbm_flutter/data/models/repo_record.dart';
import 'package:gbm_flutter/data/models/repo_state.dart' as model;
import 'package:gbm_flutter/data/models/stash_entry.dart';
import 'package:gbm_flutter/data/models/undo_entry.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/models/worktree_info.dart';

void main() {
  test('GitError.fromJson round-trips every field', () {
    final Map<String, dynamic> json = jsonDecode(
      '{"code":3,"codeName":"Conflict","message":"merge conflict",'
      '"detail":"stderr","argv":["git","merge"],"exitCode":1}',
    );
    final GitError error = GitError.fromJson(json);

    expect(error.code, 3);
    expect(error.codeName, 'Conflict');
    expect(error.message, 'merge conflict');
    expect(error.argv, <String>['git', 'merge']);
    expect(error.exitCode, 1);
  });

  test('RepoState.fromJson handles a null indexLockAgeSeconds', () {
    final Map<String, dynamic> json = jsonDecode(
      '{"flags":0,"isClean":true,"isSequencerOperation":false,"rebaseStep":0,'
      '"rebaseTotal":0,"rebaseOntoLabel":"","indexLocked":false,'
      '"indexLockAgeSeconds":null,"describe":"Clean"}',
    );
    final model.RepoState state = model.RepoState.fromJson(json);

    expect(state.isClean, isTrue);
    expect(state.indexLockAgeSeconds, isNull);
  });

  test('RepoRecord.listFromJson decodes an array and exposes isMissing', () {
    final List<dynamic> json = jsonDecode(
      '[{"id":1,"baseFolderId":1,"workDir":"/a","gitDir":"/a/.git","commonDir":"/a/.git",'
      '"kind":0,"name":"a","parentRepoId":null,"depth":0,"discoveredAt":0,"missingSince":null},'
      '{"id":2,"baseFolderId":1,"workDir":"/b","gitDir":"/b/.git","commonDir":"/b/.git",'
      '"kind":0,"name":"b","parentRepoId":null,"depth":0,"discoveredAt":0,"missingSince":123}]',
    );
    final List<RepoRecord> records = RepoRecord.listFromJson(json);

    expect(records, hasLength(2));
    expect(records[0].isMissing, isFalse);
    expect(records[1].isMissing, isTrue);
    expect(records[1].kind, RepoKind.normal);
  });

  test('RefSnapshot.fromJson filters localBranches by kind', () {
    final Map<String, dynamic> json = jsonDecode(
      '{"head":{"kind":0,"branchName":"main","fullRef":"refs/heads/main","target":"aa"},'
      '"refCountGuardTripped":false,"totalRefCount":2,'
      '"refs":['
      '{"fullName":"refs/heads/main","shortName":"main","kind":0,"target":"aa","upstream":"",'
      '"ahead":0,"behind":0,"hasTrackingInfo":false,"isGone":false,"isHead":true,'
      '"isSymbolic":false,"worktreePath":""},'
      '{"fullName":"refs/remotes/origin/main","shortName":"origin/main","kind":1,"target":"aa",'
      '"upstream":"","ahead":0,"behind":0,"hasTrackingInfo":false,"isGone":false,"isHead":false,'
      '"isSymbolic":false,"worktreePath":""}'
      ']}',
    );
    final RefSnapshot snapshot = RefSnapshot.fromJson(json);

    expect(snapshot.refs, hasLength(2));
    expect(snapshot.localBranches, hasLength(1));
    expect(snapshot.localBranches.single.shortName, 'main');
    expect(snapshot.head.branchName, 'main');
  });

  test('OperationOutcome.fromJson decodes a null error on success', () {
    final Map<String, dynamic> json = jsonDecode('{"succeeded":true,"error":null,"summary":"Switched to main"}');
    final OperationOutcome outcome = OperationOutcome.fromJson(json);

    expect(outcome.succeeded, isTrue);
    expect(outcome.error, isNull);
    expect(outcome.summary, 'Switched to main');
  });

  test('GraphRow decodes RowMeta flag bits', () {
    // flags = parentCount(2) | IsMerge(0x08) | IsHead(0x20) = 0x2A
    const GraphRow row = GraphRow(parentOffset: 0, edgeOffset: 0, commitTime: 0, lane: 0, color: 0, flags: 0x2A);

    expect(row.parentCount, 2);
    expect(row.isMerge, isTrue);
    expect(row.isHead, isTrue);
    expect(row.isBoundary, isFalse);
    expect(row.isOverflow, isFalse);
  });

  test('GraphSnapshotView.parentsOf skips boundary parents', () {
    const GraphSnapshotView view = GraphSnapshotView(
      rows: <GraphRow>[GraphRow(parentOffset: 0, edgeOffset: 0, commitTime: 0, lane: 0, color: 0, flags: 2)],
      oidsHex: <String>['aa', 'bb'],
      parentPool: <int>[1, kRowBoundary],
      laneCount: 1,
      complete: true,
      truncated: false,
    );

    expect(view.parentsOf(0), <String>['bb']);
  });

  test('WorkingCopyStatus.fromJson splits entries by staged/unstaged/untracked', () {
    final Map<String, dynamic> json = jsonDecode(
      '{"entries":['
      '{"path":"a.txt","oldPath":"","untracked":false,"staged":true,"indexStatus":0,'
      '"hasUnstagedChange":false,"worktreeStatus":0,"conflict":0,"ancestorBlob":"",'
      '"oursBlob":"","theirsBlob":"","similarity":0,"isSubmodule":false,"isConflicted":false},'
      '{"path":"b.txt","oldPath":"","untracked":true,"staged":false,"indexStatus":0,'
      '"hasUnstagedChange":false,"worktreeStatus":0,"conflict":0,"ancestorBlob":"",'
      '"oursBlob":"","theirsBlob":"","similarity":0,"isSubmodule":false,"isConflicted":false}'
      ']}',
    );
    final WorkingCopyStatus status = WorkingCopyStatus.fromJson(json);

    expect(status.isClean, isFalse);
    expect(status.staged.map((e) => e.path), <String>['a.txt']);
    expect(status.untrackedFiles.map((e) => e.path), <String>['b.txt']);
  });

  test('ParsedDiff.fromJson decodes nested files/hunks/lines', () {
    final Map<String, dynamic> json = jsonDecode(
      '{"files":[{"oldPath":"a.txt","newPath":"a.txt","kind":0,"oldMode":"","newMode":"",'
      '"oldBlob":"","newBlob":"","binary":false,"similarity":0,"addedLines":1,"removedLines":0,'
      '"displayPath":"a.txt","hunks":[{"oldStart":1,"oldCount":1,"newStart":1,"newCount":2,'
      '"heading":"","lines":[{"kind":0,"oldLine":1,"newLine":1,"text":"line1"},'
      '{"kind":1,"oldLine":0,"newLine":2,"text":"line2"}]}]}],"truncated":false,"inputBytes":42}',
    );
    final ParsedDiff diff = ParsedDiff.fromJson(json);

    expect(diff.files, hasLength(1));
    expect(diff.files.single.hunks.single.lines, hasLength(2));
    expect(diff.files.single.hunks.single.lines[1].kind, DiffLineKind.added);
    expect(diff.files.single.hunks.single.lines[1].text, 'line2');
  });

  test('BaseFolderRecord.listFromJson decodes an array', () {
    final List<dynamic> json = jsonDecode(
      '[{"id":1,"path":"/code","enabled":true,"maxDepth":3,"followLinks":false,'
      '"lastScanStarted":0,"lastScanFinished":0,"lastScanDirs":0,"lastScanMs":0}]',
    );
    final List<BaseFolderRecord> folders = BaseFolderRecord.listFromJson(json);

    expect(folders, hasLength(1));
    expect(folders.single.path, '/code');
    expect(folders.single.enabled, isTrue);
    expect(folders.single.maxDepth, 3);
  });

  test('StashEntry.listFromJson decodes an array', () {
    final List<dynamic> json = jsonDecode('[{"index":0,"message":"WIP","oid":"aa","timestamp":123}]');
    final List<StashEntry> stashes = StashEntry.listFromJson(json);

    expect(stashes, hasLength(1));
    expect(stashes.single.index, 0);
    expect(stashes.single.message, 'WIP');
  });

  test('WorktreeInfo.listFromJson decodes an array', () {
    final List<dynamic> json = jsonDecode(
      '[{"path":"/repo","headOid":"aa","branch":"main","isMain":true,"isBare":false,'
      '"isDetached":false,"isLocked":false,"lockReason":"","isPrunable":false,"prunableReason":""}]',
    );
    final List<WorktreeInfo> worktrees = WorktreeInfo.listFromJson(json);

    expect(worktrees, hasLength(1));
    expect(worktrees.single.isMain, isTrue);
    expect(worktrees.single.branch, 'main');
  });

  test('RemoteInfo.listFromJson decodes an array', () {
    final List<dynamic> json = jsonDecode(
      '[{"name":"origin","fetchUrl":"https://example.invalid/a.git","pushUrl":"https://example.invalid/a.git"}]',
    );
    final List<RemoteInfo> remotes = RemoteInfo.listFromJson(json);

    expect(remotes, hasLength(1));
    expect(remotes.single.name, 'origin');
  });

  test('OperationRecord.fromJson decodes argv and exposes failed', () {
    final Map<String, dynamic> json = jsonDecode(
      '{"whenEpochMs":1000,"repoDir":"/repo","argv":["git","status"],"commandLine":"git status",'
      '"exitCode":1,"durationMs":5,"stderrText":"error","cancelled":false,"timedOut":false}',
    );
    final OperationRecord record = OperationRecord.fromJson(json);

    expect(record.argv, <String>['git', 'status']);
    expect(record.failed, isTrue);
  });

  test('BlameResult.fromJson decodes lines and the truncated flag', () {
    final Map<String, dynamic> json = jsonDecode(
      '{"lines":[{"commitOid":"aa","authorName":"A","authorEmail":"a@x","authorTime":1,'
      '"summary":"init","finalLine":1,"originalLine":1,"content":"hi","boundary":true}],'
      '"truncated":false}',
    );
    final BlameResult result = BlameResult.fromJson(json);

    expect(result.lines, hasLength(1));
    expect(result.lines.single.boundary, isTrue);
    expect(result.truncated, isFalse);
  });

  test('FileHistoryEntry.listFromJson decodes an array', () {
    final List<dynamic> json = jsonDecode(
      '[{"oid":"aa","author":{"name":"A","email":"a@x","when":1,"tzOffsetMinutes":0},'
      '"subject":"init","status":"A","renamedFrom":""}]',
    );
    final List<FileHistoryEntry> entries = FileHistoryEntry.listFromJson(json);

    expect(entries, hasLength(1));
    expect(entries.single.status, 'A');
    expect(entries.single.author.name, 'A');
  });

  test('LineHistoryChunk.listFromJson decodes an array', () {
    final List<dynamic> json = jsonDecode(
      '[{"oid":"aa","author":{"name":"A","email":"a@x","when":1,"tzOffsetMinutes":0},'
      '"subject":"init","diffText":"@@ -1 +1 @@"}]',
    );
    final List<LineHistoryChunk> chunks = LineHistoryChunk.listFromJson(json);

    expect(chunks, hasLength(1));
    expect(chunks.single.diffText, '@@ -1 +1 @@');
  });

  test('ReflogEntry.listFromJson decodes an array newest-first', () {
    final List<dynamic> json = jsonDecode(
      '[{"index":0,"oid":"aa","message":"commit: init",'
      '"who":{"name":"A","email":"a@x","when":1,"tzOffsetMinutes":0}}]',
    );
    final List<ReflogEntry> entries = ReflogEntry.listFromJson(json);

    expect(entries, hasLength(1));
    expect(entries.single.index, 0);
    expect(entries.single.who.name, 'A');
  });

  test('UndoEntry.listFromJson decodes an array', () {
    final List<dynamic> json = jsonDecode(
      '[{"id":1,"description":"Commit","headBefore":"aa","branchBefore":"main","timestamp":123}]',
    );
    final List<UndoEntry> entries = UndoEntry.listFromJson(json);

    expect(entries, hasLength(1));
    expect(entries.single.branchBefore, 'main');
  });
}
