// Diff fixtures for the full-file view: one file diffed at -U3 and at full
// context, built the way git builds hunks.
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';

/// A [total]-line file whose lines in [edited] are each replaced, diffed at
/// [context] lines of context the way git builds hunks. Line `n` reads
/// `L$n` (`edited L$n` once replaced), so a row's text never collides with a
/// gutter number. A line in [long] runs on for [longBy] more characters.
DiffFile replacementsDiff(
  int total,
  Set<int> edited, {
  required int context,
  Set<int> long = const <int>{},
  int longBy = 300,
}) {
  final List<(int, int)> windows = <(int, int)>[];
  for (final int e in edited.toList()..sort()) {
    final int from = e - context < 1 ? 1 : e - context;
    final int to = e + context > total ? total : e + context;
    if (windows.isNotEmpty && from <= windows.last.$2 + 1) {
      windows.last = (windows.last.$1, to);
    } else {
      windows.add((from, to));
    }
  }
  return DiffFile(
    oldPath: 'a.dart',
    newPath: 'a.dart',
    kind: FileChangeKind.modified,
    oldMode: '',
    newMode: '',
    oldBlob: '',
    newBlob: '',
    binary: false,
    similarity: 0,
    addedLines: 0,
    removedLines: 0,
    displayPath: 'a.dart',
    hunks: <DiffHunk>[
      for (final (int from, int to) in windows)
        DiffHunk(
          oldStart: from,
          oldCount: to - from + 1,
          newStart: from,
          newCount: to - from + 1,
          heading: '',
          lines: <DiffLine>[
            for (int n = from; n <= to; n++)
              if (edited.contains(n)) ...<DiffLine>[
                DiffLine(
                  kind: DiffLineKind.removed,
                  oldLine: n,
                  newLine: 0,
                  text: long.contains(n) ? 'L$n${'x' * longBy}' : 'L$n',
                ),
                DiffLine(
                  kind: DiffLineKind.added,
                  oldLine: 0,
                  newLine: n,
                  text: 'edited L$n',
                ),
              ] else
                DiffLine(
                  kind: DiffLineKind.context,
                  oldLine: n,
                  newLine: n,
                  text: long.contains(n) ? 'L$n${'x' * longBy}' : 'L$n',
                ),
          ],
        ),
    ],
  );
}

/// A context length longer than any fixture: a full-context diff.
const int kAllContext = 1 << 30;
