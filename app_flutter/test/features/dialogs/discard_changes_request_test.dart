// Unit tests for the URL -> dialog-arguments half of the discard chain.
//
// This is the seam 05-G's own tests could not reach: `diff_line_test.dart`
// proves the menu item dispatches, and `WorkingCopyApiTest` proves
// `gbm_discard_lines` edits the right lines, but between them sits a URL
// round-trip whose failure mode is silent and destructive -- a line
// selection that only half-parses used to fall back to *whole-file* discard
// of the same path, behind the same danger button.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/dialogs/discard_changes/discard_changes_request.dart';
import 'package:gbm_flutter/routing/route_paths.dart';

DiscardChangesRequest _fromUrl(String url) =>
    DiscardChangesRequest.fromQuery(Uri.parse(url).queryParametersAll);

void main() {
  group('the URLs RoutePaths builds round-trip', () {
    test('discardLinesDialogFor gives line mode with every index kept', () {
      final DiscardChangesRequest request = _fromUrl(
        RoutePaths.discardLinesDialogFor(
          'repo-id',
          path: 'lib/main.dart',
          hunkIndex: 2,
          lineIndices: <int>[4, 5, 9],
        ),
      );

      expect(request.isLineMode, isTrue);
      expect(request.isMalformed, isFalse);
      expect(request.paths, <String>['lib/main.dart']);
      expect(request.hunkIndex, 2);
      expect(
        request.lineIndices,
        <int>[4, 5, 9],
        reason:
            'queryParametersAll, not queryParameters -- the latter collapses '
            'the repeated `line` key to its last value',
      );
    });

    test('discardChangesDialogFor gives whole-file mode for every path', () {
      final DiscardChangesRequest request = _fromUrl(
        RoutePaths.discardChangesDialogFor(
          'repo-id',
          paths: <String>['a.dart', 'b/c.dart'],
        ),
      );

      expect(request.isLineMode, isFalse);
      expect(request.isMalformed, isFalse);
      expect(request.paths, <String>['a.dart', 'b/c.dart']);
      expect(request.hunkIndex, isNull);
      expect(request.lineIndices, isEmpty);
    });

    test('hunk index 0 is a real hunk, not a missing one', () {
      final DiscardChangesRequest request = _fromUrl(
        RoutePaths.discardLinesDialogFor(
          'repo-id',
          path: 'a.dart',
          hunkIndex: 0,
          lineIndices: <int>[0],
        ),
      );

      expect(request.isLineMode, isTrue);
      expect(request.hunkIndex, 0);
      expect(request.lineIndices, <int>[0]);
    });
  });

  group('a half-parsed line selection is malformed, never a whole-file '
      'discard', () {
    // Each case below is one where the request carries *some* line-mode
    // marker but cannot be honoured as written. The assertion that matters
    // in every one is `isLineMode == false && isMalformed == true`: falling
    // through to whole-file mode would discard the entire file instead of
    // the handful of lines the user picked.
    void expectMalformed(String url, {required String reason}) {
      final DiscardChangesRequest request = _fromUrl(url);
      expect(request.isMalformed, isTrue, reason: reason);
      expect(
        request.isLineMode,
        isFalse,
        reason: 'a malformed request is never executable',
      );
    }

    const String base = '/repo/r/dialogs/discard-changes?path=a.dart';

    test('line indices with no hunk to index into', () {
      expectMalformed('$base&line=3&line=4', reason: 'no `hunk` parameter');
    });

    test('a hunk that is not a number', () {
      expectMalformed('$base&hunk=abc&line=3', reason: '`hunk` is not an int');
    });

    test('a hunk with no lines selected', () {
      expectMalformed(
        '$base&hunk=1',
        reason:
            'discarding a whole hunk is not something any menu offers, so '
            'this is a truncated request rather than a valid one',
      );
    });

    test('a line index that is not a number', () {
      expectMalformed(
        '$base&hunk=1&line=3&line=oops',
        reason: 'dropping the unparsable index would discard the wrong lines',
      );
    });

    test('a negative hunk index', () {
      expectMalformed('$base&hunk=-1&line=3', reason: 'no such hunk');
    });

    test('a negative line index', () {
      expectMalformed('$base&hunk=1&line=-3', reason: 'no such line');
    });

    test('more than one path alongside a line selection', () {
      expectMalformed(
        '/repo/r/dialogs/discard-changes?path=a.dart&path=b.dart&hunk=1&line=3',
        reason:
            'the line indices belong to one file\'s hunk; picking the first '
            'path would silently apply them to an arbitrary file',
      );
    });

    test('a line selection with no path at all', () {
      expectMalformed(
        '/repo/r/dialogs/discard-changes?hunk=1&line=3',
        reason: 'nothing to discard from',
      );
    });
  });

  group('direct construction', () {
    test('wholeFiles is never line mode', () {
      const DiscardChangesRequest request = DiscardChangesRequest.wholeFiles(
        <String>['a.dart'],
      );

      expect(request.isLineMode, isFalse);
      expect(request.isMalformed, isFalse);
      expect(request.hunkIndex, isNull);
    });

    test('lines carries exactly the one path it targets', () {
      final DiscardChangesRequest request = DiscardChangesRequest.lines(
        path: 'a.dart',
        hunkIndex: 3,
        lineIndices: <int>[7],
      );

      expect(request.isLineMode, isTrue);
      expect(request.paths, <String>['a.dart']);
      expect(request.hunkIndex, 3);
      expect(request.lineIndices, <int>[7]);
    });
  });
}
