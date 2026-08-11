// Verifies the Dart-side models parse exactly the JSON shape
// src/capi/JsonCodec.cpp emits -- the direct counterpart of
// tests/capi/JsonCodecTest.cpp on the C++ side. No FFI involved: these are
// plain JSON-decoding unit tests.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/operation_outcome.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/repo_record.dart';
import 'package:gbm_flutter/data/models/repo_state.dart' as model;

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
}
