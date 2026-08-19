import 'package:flutter/foundation.dart';

/// What a `/repo/:repoId/dialogs/discard-changes` URL is asking to discard.
///
/// The dialog serves two context menus with very different blast radii --
/// 05-F's whole-file "Discard changes…" (`restorePaths`) and 05-G's
/// line-level "Discard N lines…" (`gbm_discard_lines`) -- and both arrive
/// through the same route, distinguished only by query parameters. Parsing
/// them was previously inline in `app_router.dart`, where an incomplete
/// line selection (a `line` with no `hunk`, an index that would not parse)
/// quietly cancelled itself down to *whole-file* mode: the user asked to
/// discard two lines and the identical danger button would have discarded
/// the whole file, unrecoverably.
///
/// So a request that carries any line-mode marker it cannot honour is
/// [isMalformed] rather than silently something else, and the dialog
/// refuses it instead of falling back. There is no reachable in-app URL
/// that produces one -- [RoutePaths.discardLinesDialogFor] always emits a
/// complete set -- but this route is deep-linkable, so a hand-typed or
/// truncated URL has to land somewhere safe.
@immutable
class DiscardChangesRequest {
  const DiscardChangesRequest._({
    required this.paths,
    required this.hunkIndex,
    required this.lineIndices,
    required this.isMalformed,
  });

  /// 05-F: replace these files' uncommitted changes with their staged
  /// contents.
  const DiscardChangesRequest.wholeFiles(List<String> paths)
    : this._(
        paths: paths,
        hunkIndex: null,
        lineIndices: const <int>[],
        isMalformed: false,
      );

  /// 05-G: revert just [lineIndices] of [hunkIndex] in [path]'s working
  /// copy. Not `const` -- it wraps [path] in a list, which a const
  /// initializer cannot do.
  DiscardChangesRequest.lines({
    required String path,
    required int hunkIndex,
    required List<int> lineIndices,
  }) : this._(
         paths: <String>[path],
         hunkIndex: hunkIndex,
         lineIndices: lineIndices,
         isMalformed: false,
       );

  /// A request that asked for line mode but cannot be executed as written.
  /// [paths] is kept only so the dialog can name what was *not* touched.
  const DiscardChangesRequest.malformed(List<String> paths)
    : this._(
        paths: paths,
        hunkIndex: null,
        lineIndices: const <int>[],
        isMalformed: true,
      );

  /// Parses `state.uri.queryParametersAll` -- the `All` matters: the plain
  /// map collapses a repeated key to its last value, which would drop every
  /// file of a multi-file selection but one (and every line but one).
  factory DiscardChangesRequest.fromQuery(Map<String, List<String>> query) {
    final List<String> paths = query['path'] ?? const <String>[];
    final List<String> rawHunks = query['hunk'] ?? const <String>[];
    final List<String> rawLines = query['line'] ?? const <String>[];

    // Any marker at all commits the request to line mode; whether it can be
    // honoured is a separate question, answered just below.
    if (rawHunks.isEmpty && rawLines.isEmpty) {
      return DiscardChangesRequest.wholeFiles(paths);
    }

    final int? hunkIndex = rawHunks.length == 1
        ? int.tryParse(rawHunks.single)
        : null;
    final List<int> lineIndices = <int>[
      for (final String raw in rawLines)
        if (int.tryParse(raw) case final int index) index,
    ];

    final bool executable =
        paths.length == 1 &&
        hunkIndex != null &&
        hunkIndex >= 0 &&
        rawLines.isNotEmpty &&
        // An index that failed to parse is dropped by the comprehension
        // above; discarding the remaining ones would hit the wrong lines.
        lineIndices.length == rawLines.length &&
        lineIndices.every((int index) => index >= 0);

    if (!executable) return DiscardChangesRequest.malformed(paths);
    return DiscardChangesRequest.lines(
      path: paths.single,
      hunkIndex: hunkIndex,
      lineIndices: lineIndices,
    );
  }

  /// One entry in whole-file mode per selected file; exactly one in line
  /// mode (the file [lineIndices] belong to).
  final List<String> paths;

  /// The hunk [lineIndices] index into; null outside line mode.
  final int? hunkIndex;

  /// Line indices within [hunkIndex]'s `lines` array; empty outside line
  /// mode.
  final List<int> lineIndices;

  /// True when line mode was asked for but cannot be executed. Mutually
  /// exclusive with [isLineMode].
  final bool isMalformed;

  bool get isLineMode =>
      !isMalformed && hunkIndex != null && lineIndices.isNotEmpty;
}
