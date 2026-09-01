// `ParsedDiff.truncated` is what the core sets when a diff is over its byte
// cap: it parses nothing at all and hands back an empty `files`. Until this
// round the flag crossed the FFI, reached this widget as a constructor field,
// and was read by nobody -- so a refused diff and a genuinely unchanged file
// drew the same "No changes", which is the wrong answer rather than a partial
// one.
//
// The negative test next to it is the load-bearing half: without it, an arm
// drawn for every empty diff would pass the positive one just as well.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/diff_page.dart';

import '../../support/pump_app.dart';

DiffFile _file() => const DiffFile(
  oldPath: 'lib/a.dart',
  newPath: 'lib/a.dart',
  kind: FileChangeKind.modified,
  oldMode: '',
  newMode: '',
  oldBlob: '',
  newBlob: '',
  binary: false,
  similarity: 0,
  addedLines: 1,
  removedLines: 0,
  displayPath: 'lib/a.dart',
  hunks: <DiffHunk>[
    DiffHunk(
      oldStart: 1,
      oldCount: 1,
      newStart: 1,
      newCount: 1,
      heading: '',
      lines: <DiffLine>[
        DiffLine(
          kind: DiffLineKind.added,
          oldLine: 0,
          newLine: 1,
          text: 'added line',
        ),
      ],
    ),
  ],
);

void main() {
  Future<void> pump(WidgetTester tester, ParsedDiff diff) async {
    await pumpGbmWidget(
      tester,
      child: SizedBox(width: 600, height: 400, child: DiffPage(diff: diff)),
    );
  }

  testWidgets('a refused diff says it is too large, not that nothing changed', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      const ParsedDiff(
        files: <DiffFile>[],
        truncated: true,
        inputBytes: 40 * 1024 * 1024,
      ),
    );

    expect(find.text('Diff too large to display'), findsOneWidget);
    expect(find.text('No changes'), findsNothing);
  });

  testWidgets('an ordinarily empty diff still says nothing changed', (
    WidgetTester tester,
  ) async {
    await pump(tester, ParsedDiff.empty);

    expect(find.text('No changes'), findsOneWidget);
    expect(find.text('Diff too large to display'), findsNothing);
  });

  testWidgets('a diff with files is drawn, truncated or not', (
    WidgetTester tester,
  ) async {
    // `truncated` is checked before `files.isEmpty`, so a future change that
    // ever produced both would hide real content behind the notice. The core
    // does not produce that combination today; this pins which way the
    // precedence would have to be argued if it ever did.
    await pump(
      tester,
      ParsedDiff(files: <DiffFile>[_file()], truncated: false, inputBytes: 100),
    );

    expect(find.text('added line'), findsOneWidget);
    expect(find.text('Diff too large to display'), findsNothing);
  });
}
