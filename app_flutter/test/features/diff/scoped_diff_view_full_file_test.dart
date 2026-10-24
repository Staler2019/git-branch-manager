// Full-file mode of ScopedDiffView: the unchanged rows between the -U3
// cards are drawn ([fullFileFillRows]), and every stage path must send git
// exactly what excerpt mode sends for the same cards and the same changed
// lines -- the fill rows belong to no hunk, so they can only add to what is
// framed, never to what moves. Each test runs one input in both modes and
// compares the payloads, rather than restating them, so the excerpt mode the
// rest of this directory pins is the oracle.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/diff_full_file_fill.dart';
import 'package:gbm_flutter/features/diff/diff_scopes.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:gbm_flutter/widgets/gbm_dashed.dart';

import '../../support/pump_app.dart';

/// A hunk from a sketch with real line numbers: `.` advances both sides,
/// `-` the old side only, `+` the new side only. Texts are `h<hunk> l<row>`.
DiffHunk _numbered(String sketch, {required int start, required int hunk}) {
  int oldLine = start;
  int newLine = start;
  final List<DiffLine> lines = <DiffLine>[];
  for (int i = 0; i < sketch.length; i++) {
    final String c = sketch[i];
    lines.add(
      DiffLine(
        kind: switch (c) {
          '+' => DiffLineKind.added,
          '-' => DiffLineKind.removed,
          _ => DiffLineKind.context,
        },
        oldLine: c == '+' ? 0 : oldLine++,
        newLine: c == '-' ? 0 : newLine++,
        text: 'h$hunk l$i',
      ),
    );
  }
  return DiffHunk(
    oldStart: start,
    oldCount: oldLine - start,
    newStart: start,
    newCount: newLine - start,
    heading: 'fn()',
    lines: lines,
  );
}

DiffFile _file(List<DiffHunk> hunks) => DiffFile(
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
  hunks: hunks,
);

/// Index lines 3-8 and 15-21 are drawn by the two hunks (unstaged, so the
/// old side); the index file has 23 lines.
final DiffFile _unstaged = _file(<DiffHunk>[
  _numbered('...+...', start: 3, hunk: 0),
  _numbered('...-...', start: 15, hunk: 1),
]);

List<DiffFillRow> _fill(Iterable<int> lines, {int sourceIndex = 0}) =>
    <DiffFillRow>[
      for (final int l in lines)
        (
          sourceIndex: sourceIndex,
          indexLine: l,
          line: DiffLine(
            kind: DiffLineKind.context,
            oldLine: l,
            newLine: l,
            text: 'fill $l',
          ),
        ),
    ];

final List<DiffFillRow> _loneFill = _fill(<int>[
  1,
  2,
  9,
  10,
  11,
  12,
  13,
  14,
  22,
  23,
]);

typedef _Staged = ({int hunkIndex, List<int> lines});

/// `hunk:lines` per call -- a record holding a list compares by identity.
List<String> _calls(List<_Staged> staged) => <String>[
  for (final _Staged s in staged) '${s.hunkIndex}:${s.lines.join(',')}',
];

Future<void> shiftArrow(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

/// Drags from the start of [from]'s text to the end of [to]'s, the same
/// idiom `scoped_diff_view_test.dart` documents.
Future<void> dragSelect(WidgetTester tester, String from, String to) async {
  final Rect fromRect = tester.getRect(find.text(from));
  final Rect toRect = tester.getRect(find.text(to));
  final TestGesture gesture = await tester.startGesture(
    Offset(fromRect.left + 1, fromRect.center.dy),
    kind: PointerDeviceKind.mouse,
  );
  addTearDown(gesture.removePointer);
  await tester.pump();
  await gesture.moveTo(Offset(toRect.right - 1, toRect.center.dy));
  await tester.pump();
  await gesture.up();
  await tester.pump();
  await tester.pump();
}

void main() {
  late List<_Staged> staged;
  late List<void Function()?> submitters;

  setUp(() {
    staged = <_Staged>[];
    submitters = <void Function()?>[];
  });

  Future<void> pump(
    WidgetTester tester, {
    required List<DiffFillRow>? fill,
    List<ScopedDiffSource>? sources,
  }) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpGbmWidget(
      tester,
      child: SingleChildScrollView(
        child: SizedBox(
          width: 800,
          child: ScopedDiffView(
            softWrap: false,
            fill: fill,
            showColumnHeads: sources == null,
            sources:
                sources ??
                <ScopedDiffSource>[
                  ScopedDiffSource(
                    title: 'Unstaged',
                    file: _unstaged,
                    staged: false,
                    onStageScope: (int h, List<int> l) =>
                        staged.add((hunkIndex: h, lines: l)),
                  ),
                ],
            onTemporaryScopeChanged: submitters.add,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// Runs [act] in excerpt mode, then in full-file mode, and returns what
  /// each sent to `onStageScope`.
  Future<(List<_Staged>, List<_Staged>)> bothModes(
    WidgetTester tester,
    Future<void> Function({required bool full}) act,
  ) async {
    await pump(tester, fill: null);
    await act(full: false);
    final List<_Staged> excerpt = List<_Staged>.of(staged);
    staged.clear();
    // A different key, so the full-file view is a new State with no
    // selection carried over from the excerpt run.
    await tester.pumpWidget(const SizedBox());
    await pump(tester, fill: _loneFill);
    await act(full: true);
    return (excerpt, List<_Staged>.of(staged));
  }

  double top(WidgetTester tester, String text) =>
      tester.getRect(find.text(text)).top;

  group('ScopedDiffView -- full-file mode draws', () {
    testWidgets('no @@ heading, while excerpt mode draws one per hunk', (
      WidgetTester tester,
    ) async {
      await pump(tester, fill: null);
      expect(find.textContaining('@@'), findsNWidgets(2));

      await pump(tester, fill: _loneFill);
      expect(find.textContaining('@@'), findsNothing);
    });

    testWidgets('every fill row, between the hunks it sits between', (
      WidgetTester tester,
    ) async {
      await pump(tester, fill: _loneFill);

      final List<String> painted = <String>[
        'fill 1',
        'fill 2',
        'h0 l0',
        'h0 l6',
        'fill 9',
        'fill 14',
        'h1 l0',
        'h1 l6',
        'fill 22',
        'fill 23',
      ];
      for (int i = 1; i < painted.length; i++) {
        expect(
          top(tester, painted[i - 1]),
          lessThan(top(tester, painted[i])),
          reason: '${painted[i - 1]} above ${painted[i]}',
        );
      }
      for (final DiffFillRow row in _loneFill) {
        expect(find.text(row.line.text), findsOneWidget);
      }
    });

    testWidgets('fill rows the way a gap is drawn: a dashed rule, no button', (
      WidgetTester tester,
    ) async {
      await pump(tester, fill: null);
      final int excerptButtons = find.byType(GbmButton).evaluate().length;
      final int excerptRules = find.byType(GbmDashedLine).evaluate().length;

      await pump(tester, fill: _loneFill);
      expect(find.byType(GbmButton), findsNWidgets(excerptButtons));
      // Three fill runs: above, between and below the two hunks.
      expect(find.byType(GbmDashedLine), findsNWidgets(excerptRules + 3));
      expect(
        find.ancestor(
          of: find.text('fill 9'),
          matching: find.byType(GbmButton),
        ),
        findsNothing,
      );
    });
  });

  group('ScopedDiffView -- full-file mode stages what excerpt mode stages', () {
    testWidgets('a card button', (WidgetTester tester) async {
      final (List<_Staged> excerpt, List<_Staged> full) = await bothModes(
        tester,
        ({required bool full}) async {
          await tester.tap(find.byType(GbmButton).last);
          await tester.pump();
        },
      );
      expect(excerpt, hasLength(1));
      expect(_calls(full), _calls(excerpt));
    });

    testWidgets('a drag across both cards, from a fill row in full mode', (
      WidgetTester tester,
    ) async {
      final (List<_Staged> excerpt, List<_Staged> full) = await bothModes(
        tester,
        ({required bool full}) async {
          await dragSelect(tester, full ? 'fill 2' : 'h0 l0', 'h1 l3');
          submitters.last!();
          await tester.pump();
        },
      );
      expect(_calls(excerpt), <String>['0:3', '1:3']);
      expect(_calls(full), _calls(excerpt));
    });

    testWidgets('Shift+Down across the fill rows between two cards', (
      WidgetTester tester,
    ) async {
      final (
        List<_Staged> excerpt,
        List<_Staged> full,
      ) = await bothModes(tester, ({required bool full}) async {
        await tester.tap(find.text('h0 l0'));
        await tester.pump();
        // The first press seeds on h0 l3; from there h0 l4-l6 and h1 l0-l3
        // are seven rows, plus the six fill rows 9-14 in full mode.
        for (int i = 0; i < (full ? 14 : 8); i++) {
          await shiftArrow(tester, LogicalKeyboardKey.arrowDown);
        }
        // The range walks the fill rows too: one per press, ending on
        // h1 l3 in both modes.
        expect(
          find.text(
            scopeButtonLabel(staged: false, spanned: full ? 14 : 8, changed: 2),
          ),
          findsOneWidget,
        );
        submitters.last!();
        await tester.pump();
      });
      expect(_calls(excerpt), <String>['0:3', '1:3']);
      expect(_calls(full), _calls(excerpt));
    });

    testWidgets('the one-shot label counts the fill rows a drag framed', (
      WidgetTester tester,
    ) async {
      await pump(tester, fill: _loneFill);
      await dragSelect(tester, 'fill 2', 'h1 l3');

      // fill 2, h0 l0-l6, fill 9-14, h1 l0-l3: 1 + 7 + 6 + 4 rows framed.
      expect(
        find.text(scopeButtonLabel(staged: false, spanned: 18, changed: 2)),
        findsOneWidget,
      );
    });
  });

  group('ScopedDiffView -- full-file mode in a merged list', () {
    testWidgets('paints fill, unstaged and staged rows on one index ruler', (
      WidgetTester tester,
    ) async {
      // Unstaged changes inside index 3-8, staged inside index 15-21 (its
      // index is the new side; '...+...' from 15 puts index 15-21 there).
      final DiffFile stagedFile = _file(<DiffHunk>[
        _numbered('...+...', start: 15, hunk: 9),
      ]);
      final DiffFile unstagedFile = _file(<DiffHunk>[
        _numbered('...+...', start: 3, hunk: 0),
      ]);
      await pump(
        tester,
        fill: _fill(<int>[1, 2, 9, 10, 11, 12, 13, 14, 22, 23]),
        sources: <ScopedDiffSource>[
          ScopedDiffSource(
            title: 'Unstaged',
            file: unstagedFile,
            staged: false,
            onStageScope: (int h, List<int> l) {},
          ),
          ScopedDiffSource(
            title: 'Staged',
            file: stagedFile,
            staged: true,
            onStageScope: (int h, List<int> l) {},
          ),
        ],
      );

      final List<String> painted = <String>[
        'fill 2',
        'h0 l6',
        'fill 9',
        'fill 14',
        'h9 l0',
        'h9 l6',
        'fill 22',
      ];
      for (int i = 1; i < painted.length; i++) {
        expect(
          top(tester, painted[i - 1]),
          lessThan(top(tester, painted[i])),
          reason: '${painted[i - 1]} above ${painted[i]}',
        );
      }
    });
  });
}
