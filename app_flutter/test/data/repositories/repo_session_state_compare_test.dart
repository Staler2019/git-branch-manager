// Verifies the M6 Compare/Prune reply-wrapper types parse exactly the JSON
// shape src/capi/gbm_capi.h's GBM_EVENT_COMPARE_READY /
// GBM_EVENT_COMPARE_FILE_DIFF_READY / GBM_EVENT_REMOTE_PRUNE_PREVIEW_READY
// doc comments describe, mirroring model_parsing_test.dart's convention for
// the plain data/models/ DTOs. No FFI involved.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

void main() {
  group('CompareResult', () {
    test('fromJson decodes merge base, commits and files', () {
      final Map<String, dynamic> json = jsonDecode(
        '{"left":"main","right":"feature","threeDot":true,'
        '"mergeBase":"aa","commits":[{"oid":"bb","onRightOnly":true,'
        '"authorName":"A","authorDate":1000,"subject":"Feature commit"}],'
        '"files":[{"oldPath":"a.txt","newPath":"a.txt","kind":0,"oldMode":"",'
        '"newMode":"","oldBlob":"","newBlob":"","binary":false,"similarity":0,'
        '"addedLines":1,"removedLines":0,"displayPath":"a.txt","hunks":[]}]}',
      );

      final CompareResult result = CompareResult.fromJson(json);

      expect(result.left, 'main');
      expect(result.right, 'feature');
      expect(result.threeDot, isTrue);
      expect(result.mergeBase, 'aa');
      expect(result.commits, hasLength(1));
      expect(result.commits.single.oid, 'bb');
      expect(result.files, hasLength(1));
      expect(result.files.single.displayPath, 'a.txt');
    });

    test('fromJson accepts an empty mergeBase (unrelated histories)', () {
      final Map<String, dynamic> json = jsonDecode(
        '{"left":"main","right":"orphan","threeDot":false,"mergeBase":"",'
        '"commits":[],"files":[]}',
      );

      final CompareResult result = CompareResult.fromJson(json);

      expect(result.mergeBase, isEmpty);
      expect(result.commits, isEmpty);
      expect(result.files, isEmpty);
    });

    test('key() combines left/right/threeDot into a stable composite key', () {
      final String a = CompareResult.key('main', 'feature', true);
      final String b = CompareResult.key('main', 'feature', true);
      final String c = CompareResult.key('main', 'feature', false);

      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('CompareFileDiffResult', () {
    test('fromJson decodes the echoed request plus the diff', () {
      final Map<String, dynamic> json = jsonDecode(
        '{"left":"main","right":"feature","threeDot":true,"path":"a.txt",'
        '"diff":{"files":[],"truncated":false,"inputBytes":0}}',
      );

      final CompareFileDiffResult result = CompareFileDiffResult.fromJson(json);

      expect(result.left, 'main');
      expect(result.right, 'feature');
      expect(result.threeDot, isTrue);
      expect(result.path, 'a.txt');
      expect(result.diff.inputBytes, 0);
    });

    test('key() includes the path so two files in one pair stay distinct', () {
      final String a = CompareFileDiffResult.key(
        'main',
        'feature',
        true,
        'a.txt',
      );
      final String b = CompareFileDiffResult.key(
        'main',
        'feature',
        true,
        'b.txt',
      );

      expect(a, isNot(b));
    });
  });

  group('RemotePrunePreview', () {
    test('fromJson decodes the remote name and preview entries', () {
      final Map<String, dynamic> json = jsonDecode(
        '{"remote":"origin","refs":[{"ref":"origin/feature/old-branch"}]}',
      );

      final RemotePrunePreview preview = RemotePrunePreview.fromJson(json);

      expect(preview.remote, 'origin');
      expect(preview.refs, hasLength(1));
      expect(preview.refs.single.ref, 'origin/feature/old-branch');
    });
  });

  group('CompareWithWorkingCopyResult', () {
    test('fromJson decodes the echoed ref plus the diff', () {
      final Map<String, dynamic> json = jsonDecode(
        '{"ref":"main","diff":{"files":[],"truncated":false,"inputBytes":0}}',
      );

      final CompareWithWorkingCopyResult result =
          CompareWithWorkingCopyResult.fromJson(json);

      expect(result.ref, 'main');
      expect(result.diff.inputBytes, 0);
    });

    test('key() is just the ref -- only one working copy per tab', () {
      final String a = CompareWithWorkingCopyResult.key('main');
      final String b = CompareWithWorkingCopyResult.key('feature');

      expect(a, isNot(b));
      expect(CompareWithWorkingCopyResult.key('main'), a);
    });
  });
}
