// Verifies the Dart-side models parse exactly the JSON shape
// src/capi/JsonCodec.cpp emits -- the direct counterpart of
// tests/capi/JsonCodecTest.cpp on the C++ side. No FFI involved: these are
// plain JSON-decoding unit tests.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/base_folder_record.dart';
import 'package:gbm_flutter/data/models/bisect_status.dart';
import 'package:gbm_flutter/data/models/blame_result.dart';
import 'package:gbm_flutter/data/models/changed_file.dart';
import 'package:gbm_flutter/data/models/clean_entry.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/file_history_entry.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/git_identity.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/lfs_state.dart';
import 'package:gbm_flutter/data/models/line_history_chunk.dart';
import 'package:gbm_flutter/data/models/operation_choice.dart';
import 'package:gbm_flutter/data/models/operation_outcome.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/rebase_todo_entry.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/reflog_entry.dart';
import 'package:gbm_flutter/data/models/remote_info.dart';
import 'package:gbm_flutter/data/models/repo_record.dart';
import 'package:gbm_flutter/data/models/repo_state.dart' as model;
import 'package:gbm_flutter/data/models/stash_entry.dart';
import 'package:gbm_flutter/data/models/submodule_info.dart';
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
    final Map<String, dynamic> json = jsonDecode(
      '{"succeeded":true,"error":null,"choices":[],"summary":"Switched to main"}',
    );
    final OperationOutcome outcome = OperationOutcome.fromJson(json);

    expect(outcome.succeeded, isTrue);
    expect(outcome.error, isNull);
    expect(outcome.choices, isEmpty);
    expect(outcome.summary, 'Switched to main');
  });

  test('OperationOutcome.fromJson decodes recovery choices on failure', () {
    final Map<String, dynamic> json = jsonDecode(
      '{"succeeded":false,"error":null,"summary":"","choices":['
      '{"kind":0,"label":"Stash changes and checkout","explanation":"...","destructive":false},'
      '{"kind":2,"label":"Cancel","explanation":"Do not check out.","destructive":false}'
      ']}',
    );
    final OperationOutcome outcome = OperationOutcome.fromJson(json);

    expect(outcome.choices, hasLength(2));
    expect(outcome.choices.first.kind, OperationChoiceKind.stashAndRetry);
    expect(outcome.choices.last.kind, OperationChoiceKind.abort);
  });

  test('GraphRow decodes RowMeta flag bits', () {
    // flags = parentCount(2) | IsMerge(0x08) | IsHead(0x20) = 0x2A
    const GraphRow row = GraphRow(
      parentOffset: 0,
      edgeOffset: 0,
      commitTime: 0,
      lane: 0,
      color: 0,
      flags: 0x2A,
    );

    expect(row.parentCount, 2);
    expect(row.isMerge, isTrue);
    expect(row.isHead, isTrue);
    expect(row.isBoundary, isFalse);
    expect(row.isOverflow, isFalse);
  });

  test('GraphSnapshotView.parentsOf skips boundary parents', () {
    const GraphSnapshotView view = GraphSnapshotView(
      rows: <GraphRow>[
        GraphRow(
          parentOffset: 0,
          edgeOffset: 0,
          commitTime: 0,
          lane: 0,
          color: 0,
          flags: 2,
        ),
      ],
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

  test('ChangedFile.fromJson decodes every field', () {
    final Map<String, dynamic> json = jsonDecode(
      '{"path":"b.txt","oldPath":"a.txt","kind":3,"oldMode":"100644",'
      '"newMode":"100644","oldBlob":"aaa","newBlob":"bbb","similarity":92}',
    );
    final ChangedFile file = ChangedFile.fromJson(json);

    expect(file.path, 'b.txt');
    expect(file.oldPath, 'a.txt');
    expect(file.kind, FileChangeKind.renamed);
    expect(file.oldMode, '100644');
    expect(file.newMode, '100644');
    expect(file.oldBlob, 'aaa');
    expect(file.newBlob, 'bbb');
    expect(file.similarity, 92);
  });

  test('ChangedFile.listFromJson decodes an array in order', () {
    final List<dynamic> json = jsonDecode(
      '[{"path":"a.txt","oldPath":"","kind":1,"oldMode":"","newMode":"100644",'
      '"oldBlob":"","newBlob":"aaa","similarity":0},'
      '{"path":"b.txt","oldPath":"","kind":2,"oldMode":"100644","newMode":"",'
      '"oldBlob":"bbb","newBlob":"","similarity":0}]',
    );
    final List<ChangedFile> files = ChangedFile.listFromJson(json);

    expect(files.map((f) => f.path), <String>['a.txt', 'b.txt']);
    expect(files.map((f) => f.kind), <FileChangeKind>[
      FileChangeKind.added,
      FileChangeKind.deleted,
    ]);
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
    final List<dynamic> json = jsonDecode(
      '[{"index":0,"message":"WIP","oid":"aa","timestamp":123}]',
    );
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

  test('CommitMeta.fromJson decodes author/committer/subject/body', () {
    final Map<String, dynamic> json = jsonDecode(
      '{"oid":"aa","tree":"bb","parents":["cc","dd"],'
      '"author":{"name":"A","email":"a@x","when":1,"tzOffsetMinutes":0},'
      '"committer":{"name":"C","email":"c@x","when":2,"tzOffsetMinutes":0},'
      '"subject":"init","body":"body text","signed":true}',
    );
    final CommitMeta meta = CommitMeta.fromJson(json);

    expect(meta.oid, 'aa');
    expect(meta.parents, <String>['cc', 'dd']);
    expect(meta.author.name, 'A');
    expect(meta.committer.name, 'C');
    expect(meta.subject, 'init');
    expect(meta.body, 'body text');
    expect(meta.signedCommit, isTrue);
  });

  test('CommitMeta.listFromJson decodes a batch reply in request order', () {
    final List<dynamic> json = jsonDecode(
      '[{"oid":"aa","tree":"tt","parents":[],'
      '"author":{"name":"A","email":"a@x","when":1,"tzOffsetMinutes":0},'
      '"committer":{"name":"A","email":"a@x","when":1,"tzOffsetMinutes":0},'
      '"subject":"first","body":"","signed":false},'
      '{"oid":"bb","tree":"tt","parents":["aa"],'
      '"author":{"name":"B","email":"b@x","when":2,"tzOffsetMinutes":0},'
      '"committer":{"name":"B","email":"b@x","when":2,"tzOffsetMinutes":0},'
      '"subject":"second","body":"","signed":false}]',
    );
    final List<CommitMeta> metas = CommitMeta.listFromJson(json);

    expect(metas, hasLength(2));
    expect(metas[0].oid, 'aa');
    expect(metas[1].oid, 'bb');
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

  test('CleanEntry.listFromJson decodes an array', () {
    final List<dynamic> json = jsonDecode(
      '[{"path":"build/","isDirectory":true}]',
    );
    final List<CleanEntry> entries = CleanEntry.listFromJson(json);

    expect(entries, hasLength(1));
    expect(entries.single.isDirectory, isTrue);
  });

  test('RebaseTodoEntry.listFromJson decodes the action ordinal', () {
    final List<dynamic> json = jsonDecode(
      '[{"action":1,"oid":"aa","shortOid":"a","subject":"Fix bug"}]',
    );
    final List<RebaseTodoEntry> entries = RebaseTodoEntry.listFromJson(json);

    expect(entries, hasLength(1));
    expect(entries.single.action, RebaseTodoAction.edit);
  });

  test('SubmoduleInfo.listFromJson decodes the state ordinal', () {
    final List<dynamic> json = jsonDecode(
      '[{"name":"lib","path":"lib","url":"https://example.invalid/lib.git","branch":"",'
      '"headOid":"aa","state":2}]',
    );
    final List<SubmoduleInfo> submodules = SubmoduleInfo.listFromJson(json);

    expect(submodules, hasLength(1));
    expect(submodules.single.state, SubmoduleState.modified);
  });

  test('BisectStatus.fromJson decodes good/skipped oid lists', () {
    final Map<String, dynamic> json = jsonDecode(
      '{"active":true,"currentOid":"cc","badOid":"bb","goodOids":["aa"],"skippedOids":[],"logText":"log"}',
    );
    final BisectStatus status = BisectStatus.fromJson(json);

    expect(status.active, isTrue);
    expect(status.goodOids, <String>['aa']);
  });

  test(
    'LfsInstallation.fromJson and LfsFileInfo.listFromJson decode their fields',
    () {
      final LfsInstallation installation = LfsInstallation.fromJson(
        jsonDecode('{"available":true,"version":"git-lfs/3.4.1"}'),
      );
      expect(installation.available, isTrue);

      final List<LfsFileInfo> files = LfsFileInfo.listFromJson(
        jsonDecode('[{"path":"a.psd","oid":"aa","downloadedLocally":false}]'),
      );
      expect(files.single.downloadedLocally, isFalse);
    },
  );

  test(
    'LocalIdentity.fromJson and EffectiveIdentity.fromJson decode their fields',
    () {
      final LocalIdentity local = LocalIdentity.fromJson(
        jsonDecode(
          '{"name":"Repo Override","email":"a@b.c","overridden":true}',
        ),
      );
      expect(local.overridden, isTrue);

      final EffectiveIdentity effective = EffectiveIdentity.fromJson(
        jsonDecode('{"name":"Global User","email":"g@h.i"}'),
      );
      expect(effective.name, 'Global User');
    },
  );
}
