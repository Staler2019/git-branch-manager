// ScopedDiffView as a lazily built list: it must paint every row exactly
// where the eager Column painted it (the frame drawn per item has to add up
// to the one frame it replaced), and a long file must build only what is on
// screen. The rects below were recorded from the eager version at commit
// 8a01713e and are the oracle; they are not derived from the code under
// test. One deliberate change since: code text widths (63.8 -> 62.5,
// 76.5 -> 75.0) lost Material's ambient `letterSpacing: 0.25` when
// `GbmCodeText` pinned it to 0, which KIT `.gbm-diffline` has (user ruling
// 2026-10-25, Slice W). Every position is unchanged.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/features/diff/diff_full_file_fill.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/diff/widgets/diff_line.dart';

import '../../support/pump_app.dart';

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

ScopedDiffSource _source(DiffFile? file, {required bool staged}) =>
    ScopedDiffSource(
      title: staged ? 'Staged' : 'Unstaged',
      file: file,
      staged: staged,
      onStageScope: (int h, List<int> l) {},
    );

Future<void> _pump(
  WidgetTester tester,
  List<ScopedDiffSource> sources, {
  List<DiffFillRow>? fill,
  bool showColumnHeads = true,
}) => pumpGbmWidget(
  tester,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox(
      width: 500,
      height: 600,
      child: ScopedDiffView(
        softWrap: false,
        fill: fill,
        showColumnHeads: showColumnHeads,
        sources: sources,
      ),
    ),
  ),
);

/// Every painted row and every text, as `label@rect`, relative to the view.
List<String> _layout(WidgetTester tester) {
  final Offset origin = tester.getTopLeft(find.byType(ScopedDiffView));
  String r(Rect rect) {
    final Rect s = rect.shift(-origin);
    return '${s.left.toStringAsFixed(1)},${s.top.toStringAsFixed(1)},'
        '${s.width.toStringAsFixed(1)}x${s.height.toStringAsFixed(1)}';
  }

  return <String>[
    for (final Element e in find.byType(DiffLineView).evaluate())
      'row ${(e.widget as DiffLineView).line.text}@'
          '${r(tester.getRect(find.byWidget(e.widget)))}',
    for (final Element e in find.byType(RichText).evaluate())
      'text ${(e.widget as RichText).text.toPlainText()}@'
          '${r(tester.getRect(find.byWidget(e.widget)))}',
  ];
}

/// [eager] as full-file mode draws it once the overview ruler is beside the
/// rows: the well's right padding is 22, not 8 (G1 design §04 #4), so every
/// row is 14 narrower and what a card head right-aligns sits 14 further
/// left. Nothing else moves -- the eager baselines above were measured
/// before the ruler existed, and they stay as measured.
List<String> _withRulerGutter(List<String> eager) => <String>[
  for (final String entry in eager)
    if (RegExp(r'^(row .*@[\d.]+,[\d.]+,)([\d.]+)(x.*)$').firstMatch(entry)
        case final RegExpMatch m)
      '${m[1]}${(double.parse(m[2]!) - 14).toStringAsFixed(1)}${m[3]}'
    else if (RegExp(r'^(text Stage .*@)([\d.]+)(,.*)$').firstMatch(entry)
        case final RegExpMatch m)
      '${m[1]}${(double.parse(m[2]!) - 14).toStringAsFixed(1)}${m[3]}'
    else
      entry,
];

final DiffFile _excerpt = _file(<DiffHunk>[
  _numbered('...+...', start: 3, hunk: 0),
  _numbered('...-...', start: 15, hunk: 1),
]);

const List<String> _eagerExcerpt = <String>[
  'row h0 l0@20.0,70.0,463.0x22.0',
  'row h0 l1@20.0,92.0,463.0x22.0',
  'row h0 l2@20.0,114.0,463.0x22.0',
  'row h0 l3@20.0,178.0,462.0x22.0',
  'row h0 l4@20.0,211.0,463.0x22.0',
  'row h0 l5@20.0,233.0,463.0x22.0',
  'row h0 l6@20.0,255.0,463.0x22.0',
  'row h1 l0@20.0,303.0,463.0x22.0',
  'row h1 l1@20.0,325.0,463.0x22.0',
  'row h1 l2@20.0,347.0,463.0x22.0',
  'row h1 l3@20.0,411.0,462.0x22.0',
  'row h1 l4@20.0,444.0,463.0x22.0',
  'row h1 l5@20.0,466.0,463.0x22.0',
  'row h1 l6@20.0,488.0,463.0x22.0',
  'text Unstaged@24.0,6.0,234.0x17.0',
  'text 2 個 scope@267.0,6.0,101.3x17.0',
  'text @@ -3,6 +3,7 @@ fn()@17.0,48.5,225.0x17.0',
  'text h0 l0@116.0,71.0,62.5x20.0',
  'text 3@30.0,71.0,36.0x17.0',
  'text 3@66.0,71.0,36.0x17.0',
  'text  @102.0,71.0,14.0x19.0',
  'text h0 l1@116.0,93.0,62.5x20.0',
  'text 4@30.0,93.0,36.0x17.0',
  'text 4@66.0,93.0,36.0x17.0',
  'text  @102.0,93.0,14.0x19.0',
  'text h0 l2@116.0,115.0,62.5x20.0',
  'text 5@30.0,115.0,36.0x17.0',
  'text 5@66.0,115.0,36.0x17.0',
  'text  @102.0,115.0,14.0x19.0',
  'text 變更 1@28.0,153.5,45.0x17.0',
  'text +1@86.0,154.0,21.5x16.0',
  'text Stage 1 line@332.8,154.0,133.2x16.0',
  'text h0 l3@116.0,179.0,62.5x20.0',
  'text @30.0,179.0,36.0x17.0',
  'text 6@66.0,179.0,36.0x17.0',
  'text +@102.0,179.0,14.0x19.0',
  'text h0 l4@116.0,212.0,62.5x20.0',
  'text 6@30.0,212.0,36.0x17.0',
  'text 7@66.0,212.0,36.0x17.0',
  'text  @102.0,212.0,14.0x19.0',
  'text h0 l5@116.0,234.0,62.5x20.0',
  'text 7@30.0,234.0,36.0x17.0',
  'text 8@66.0,234.0,36.0x17.0',
  'text  @102.0,234.0,14.0x19.0',
  'text h0 l6@116.0,256.0,62.5x20.0',
  'text 8@30.0,256.0,36.0x17.0',
  'text 9@66.0,256.0,36.0x17.0',
  'text  @102.0,256.0,14.0x19.0',
  'text @@ -15,7 +15,6 @@ fn()@17.0,281.5,229.0x17.0',
  'text h1 l0@116.0,304.0,62.5x20.0',
  'text 15@30.0,304.0,36.0x17.0',
  'text 15@66.0,304.0,36.0x17.0',
  'text  @102.0,304.0,14.0x19.0',
  'text h1 l1@116.0,326.0,62.5x20.0',
  'text 16@30.0,326.0,36.0x17.0',
  'text 16@66.0,326.0,36.0x17.0',
  'text  @102.0,326.0,14.0x19.0',
  'text h1 l2@116.0,348.0,62.5x20.0',
  'text 17@30.0,348.0,36.0x17.0',
  'text 17@66.0,348.0,36.0x17.0',
  'text  @102.0,348.0,14.0x19.0',
  'text 變更 2@28.0,386.5,45.0x17.0',
  'text −1@82.0,387.0,21.5x16.0',
  'text Stage 1 line@332.8,387.0,133.2x16.0',
  'text h1 l3@116.0,412.0,62.5x20.0',
  'text 18@30.0,412.0,36.0x17.0',
  'text @66.0,412.0,36.0x17.0',
  'text -@102.0,412.0,14.0x19.0',
  'text h1 l4@116.0,445.0,62.5x20.0',
  'text 19@30.0,445.0,36.0x17.0',
  'text 18@66.0,445.0,36.0x17.0',
  'text  @102.0,445.0,14.0x19.0',
  'text h1 l5@116.0,467.0,62.5x20.0',
  'text 20@30.0,467.0,36.0x17.0',
  'text 19@66.0,467.0,36.0x17.0',
  'text  @102.0,467.0,14.0x19.0',
  'text h1 l6@116.0,489.0,62.5x20.0',
  'text 21@30.0,489.0,36.0x17.0',
  'text 20@66.0,489.0,36.0x17.0',
  'text  @102.0,489.0,14.0x19.0',
];

const List<String> _eagerFull = <String>[
  'row fill 1@20.0,48.0,463.0x22.0',
  'row fill 2@20.0,70.0,463.0x22.0',
  'row h0 l0@20.0,96.0,463.0x22.0',
  'row h0 l1@20.0,118.0,463.0x22.0',
  'row h0 l2@20.0,140.0,463.0x22.0',
  'row h0 l3@20.0,204.0,462.0x22.0',
  'row h0 l4@20.0,237.0,463.0x22.0',
  'row h0 l5@20.0,259.0,463.0x22.0',
  'row h0 l6@20.0,281.0,463.0x22.0',
  'row fill 9@20.0,307.0,463.0x22.0',
  'row h1 l0@20.0,333.0,463.0x22.0',
  'row h1 l1@20.0,355.0,463.0x22.0',
  'row h1 l2@20.0,377.0,463.0x22.0',
  'row h1 l3@20.0,441.0,462.0x22.0',
  'row h1 l4@20.0,474.0,463.0x22.0',
  'row h1 l5@20.0,496.0,463.0x22.0',
  'row h1 l6@20.0,518.0,463.0x22.0',
  'text Unstaged@24.0,6.0,234.0x17.0',
  'text 2 個 scope@267.0,6.0,101.3x17.0',
  'text fill 1@116.0,49.0,75.0x20.0',
  'text 1@30.0,49.0,36.0x17.0',
  'text 1@66.0,49.0,36.0x17.0',
  'text  @102.0,49.0,14.0x19.0',
  'text fill 2@116.0,71.0,75.0x20.0',
  'text 2@30.0,71.0,36.0x17.0',
  'text 2@66.0,71.0,36.0x17.0',
  'text  @102.0,71.0,14.0x19.0',
  'text h0 l0@116.0,97.0,62.5x20.0',
  'text 3@30.0,97.0,36.0x17.0',
  'text 3@66.0,97.0,36.0x17.0',
  'text  @102.0,97.0,14.0x19.0',
  'text h0 l1@116.0,119.0,62.5x20.0',
  'text 4@30.0,119.0,36.0x17.0',
  'text 4@66.0,119.0,36.0x17.0',
  'text  @102.0,119.0,14.0x19.0',
  'text h0 l2@116.0,141.0,62.5x20.0',
  'text 5@30.0,141.0,36.0x17.0',
  'text 5@66.0,141.0,36.0x17.0',
  'text  @102.0,141.0,14.0x19.0',
  'text 變更 1@28.0,179.5,45.0x17.0',
  'text +1@86.0,180.0,21.5x16.0',
  'text Stage 1 line@332.8,180.0,133.2x16.0',
  'text h0 l3@116.0,205.0,62.5x20.0',
  'text @30.0,205.0,36.0x17.0',
  'text 6@66.0,205.0,36.0x17.0',
  'text +@102.0,205.0,14.0x19.0',
  'text h0 l4@116.0,238.0,62.5x20.0',
  'text 6@30.0,238.0,36.0x17.0',
  'text 7@66.0,238.0,36.0x17.0',
  'text  @102.0,238.0,14.0x19.0',
  'text h0 l5@116.0,260.0,62.5x20.0',
  'text 7@30.0,260.0,36.0x17.0',
  'text 8@66.0,260.0,36.0x17.0',
  'text  @102.0,260.0,14.0x19.0',
  'text h0 l6@116.0,282.0,62.5x20.0',
  'text 8@30.0,282.0,36.0x17.0',
  'text 9@66.0,282.0,36.0x17.0',
  'text  @102.0,282.0,14.0x19.0',
  'text fill 9@116.0,308.0,75.0x20.0',
  'text 9@30.0,308.0,36.0x17.0',
  'text 9@66.0,308.0,36.0x17.0',
  'text  @102.0,308.0,14.0x19.0',
  'text h1 l0@116.0,334.0,62.5x20.0',
  'text 15@30.0,334.0,36.0x17.0',
  'text 15@66.0,334.0,36.0x17.0',
  'text  @102.0,334.0,14.0x19.0',
  'text h1 l1@116.0,356.0,62.5x20.0',
  'text 16@30.0,356.0,36.0x17.0',
  'text 16@66.0,356.0,36.0x17.0',
  'text  @102.0,356.0,14.0x19.0',
  'text h1 l2@116.0,378.0,62.5x20.0',
  'text 17@30.0,378.0,36.0x17.0',
  'text 17@66.0,378.0,36.0x17.0',
  'text  @102.0,378.0,14.0x19.0',
  'text 變更 2@28.0,416.5,45.0x17.0',
  'text −1@82.0,417.0,21.5x16.0',
  'text Stage 1 line@332.8,417.0,133.2x16.0',
  'text h1 l3@116.0,442.0,62.5x20.0',
  'text 18@30.0,442.0,36.0x17.0',
  'text @66.0,442.0,36.0x17.0',
  'text -@102.0,442.0,14.0x19.0',
  'text h1 l4@116.0,475.0,62.5x20.0',
  'text 19@30.0,475.0,36.0x17.0',
  'text 18@66.0,475.0,36.0x17.0',
  'text  @102.0,475.0,14.0x19.0',
  'text h1 l5@116.0,497.0,62.5x20.0',
  'text 20@30.0,497.0,36.0x17.0',
  'text 19@66.0,497.0,36.0x17.0',
  'text  @102.0,497.0,14.0x19.0',
  'text h1 l6@116.0,519.0,62.5x20.0',
  'text 21@30.0,519.0,36.0x17.0',
  'text 20@66.0,519.0,36.0x17.0',
  'text  @102.0,519.0,14.0x19.0',
];

const List<String> _eagerMerged = <String>[
  'row h2 l0@20.0,79.0,462.0x22.0',
  'row h2 l1@20.0,112.0,463.0x22.0',
  'row h2 l2@20.0,134.0,463.0x22.0',
  'row h2 l3@20.0,156.0,463.0x22.0',
  'row h0 l0@20.0,204.0,463.0x22.0',
  'row h0 l1@20.0,226.0,463.0x22.0',
  'row h0 l2@20.0,290.0,462.0x22.0',
  'row h0 l3@20.0,323.0,463.0x22.0',
  'row h0 l4@20.0,345.0,463.0x22.0',
  'text @@ -1,3 +1,4 @@ fn()@17.0,19.5,225.0x17.0',
  'text 變更 1@44.0,54.5,45.0x17.0',
  'text +1@102.0,55.0,21.5x16.0',
  'text Unstage 1 line@310.6,55.0,155.4x16.0',
  'text h2 l0@116.0,80.0,62.5x20.0',
  'text @30.0,80.0,36.0x17.0',
  'text 1@66.0,80.0,36.0x17.0',
  'text +@102.0,80.0,14.0x19.0',
  'text h2 l1@116.0,113.0,62.5x20.0',
  'text 1@30.0,113.0,36.0x17.0',
  'text 2@66.0,113.0,36.0x17.0',
  'text  @102.0,113.0,14.0x19.0',
  'text h2 l2@116.0,135.0,62.5x20.0',
  'text 2@30.0,135.0,36.0x17.0',
  'text 3@66.0,135.0,36.0x17.0',
  'text  @102.0,135.0,14.0x19.0',
  'text h2 l3@116.0,157.0,62.5x20.0',
  'text 3@30.0,157.0,36.0x17.0',
  'text 4@66.0,157.0,36.0x17.0',
  'text  @102.0,157.0,14.0x19.0',
  'text @@ -6,4 +6,5 @@ fn()@17.0,182.5,225.0x17.0',
  'text h0 l0@116.0,205.0,62.5x20.0',
  'text 6@30.0,205.0,36.0x17.0',
  'text 6@66.0,205.0,36.0x17.0',
  'text  @102.0,205.0,14.0x19.0',
  'text h0 l1@116.0,227.0,62.5x20.0',
  'text 7@30.0,227.0,36.0x17.0',
  'text 7@66.0,227.0,36.0x17.0',
  'text  @102.0,227.0,14.0x19.0',
  'text 變更 2@44.0,265.5,45.0x17.0',
  'text +1@102.0,266.0,21.5x16.0',
  'text Stage 1 line@332.8,266.0,133.2x16.0',
  'text h0 l2@116.0,291.0,62.5x20.0',
  'text @30.0,291.0,36.0x17.0',
  'text 8@66.0,291.0,36.0x17.0',
  'text +@102.0,291.0,14.0x19.0',
  'text h0 l3@116.0,324.0,62.5x20.0',
  'text 8@30.0,324.0,36.0x17.0',
  'text 9@66.0,324.0,36.0x17.0',
  'text  @102.0,324.0,14.0x19.0',
  'text h0 l4@116.0,346.0,62.5x20.0',
  'text 9@30.0,346.0,36.0x17.0',
  'text 10@66.0,346.0,36.0x17.0',
  'text  @102.0,346.0,14.0x19.0',
];

void main() {
  testWidgets('the well drawn one item at a time adds up to the one box the '
      'eager column drew, with no seam showing a rounded corner', (
    WidgetTester tester,
  ) async {
    await _pump(tester, <ScopedDiffSource>[_source(_excerpt, staged: false)]);
    final Offset origin = tester.getTopLeft(find.byType(ScopedDiffView));

    // Every slice of the well: the rounded box each item draws, and the clip
    // that keeps only that item's share of it.
    final List<({Rect box, Rect clip})> slices = <({Rect box, Rect clip})>[
      for (final Element e
          in find
              .byWidgetPredicate(
                (Widget w) =>
                    w is DecoratedBox &&
                    w.decoration is BoxDecoration &&
                    (w.decoration as BoxDecoration).borderRadius != null,
              )
              .evaluate()
              // The well's slices only, not a badge's pill in the head.
              .where(
                (Element e) => find
                    .ancestor(
                      of: find.byWidget(e.widget),
                      matching: find.byWidgetPredicate(
                        (Widget w) =>
                            w.runtimeType.toString() == '_FrameSegment',
                      ),
                    )
                    .evaluate()
                    .isNotEmpty,
              ))
        (
          box: tester.getRect(find.byWidget(e.widget)).shift(-origin),
          clip: tester
              .getRect(
                find
                    .ancestor(
                      of: find.byWidget(e.widget),
                      matching: find.byType(ClipRect),
                    )
                    .first,
              )
              .shift(-origin),
        ),
    ];
    expect(slices.length, greaterThan(2));

    // Recorded from the eager column's sunken Container at 8a01713e.
    const Rect eager = Rect.fromLTRB(8, 37, 492, 521);
    final Rect visible = slices
        .map((({Rect box, Rect clip}) s) => s.box.intersect(s.clip))
        .reduce((Rect a, Rect b) => a.expandToInclude(b));
    expect(visible, eager);

    for (final ({Rect box, Rect clip}) s in slices) {
      // A cut edge must have the box's rounded corner past the clip;
      // only the well's own top and bottom keep theirs.
      if (s.clip.top > eager.top) {
        expect(s.box.top, lessThan(s.clip.top - 6), reason: '$s');
      }
      if (s.clip.bottom < eager.bottom) {
        expect(s.box.bottom, greaterThan(s.clip.bottom + 6), reason: '$s');
      }
    }
  });

  testWidgets('excerpt mode paints every row and text where the eager '
      'column did', (WidgetTester tester) async {
    await _pump(tester, <ScopedDiffSource>[_source(_excerpt, staged: false)]);
    expect(_layout(tester), _eagerExcerpt);
  });

  testWidgets('full-file mode paints every row and text where the eager '
      'column did: one item per fill row adds no spacing', (
    WidgetTester tester,
  ) async {
    await _pump(tester, <ScopedDiffSource>[
      _source(_excerpt, staged: false),
    ], fill: _fill(<int>[1, 2, 9]));
    expect(_layout(tester), _withRulerGutter(_eagerFull));
  });

  testWidgets('a merged list paints every row and text where the eager '
      'column did', (WidgetTester tester) async {
    await _pump(tester, <ScopedDiffSource>[
      _source(
        _file(<DiffHunk>[_numbered('..+..', start: 6, hunk: 0)]),
        staged: false,
      ),
      _source(
        _file(<DiffHunk>[_numbered('+...', start: 1, hunk: 2)]),
        staged: true,
      ),
    ], showColumnHeads: false);
    expect(_layout(tester), _eagerMerged);
  });

  testWidgets('the column head stays out of the selection, as it was when '
      'it sat above the SelectionArea', (WidgetTester tester) async {
    await _pump(tester, <ScopedDiffSource>[_source(_excerpt, staged: false)]);

    // A text joins a selection only through the registrar this returns; null
    // is what `SelectionContainer.disabled` hands everything under it.
    SelectionRegistrar? registrarOf(String text) => SelectionContainer.maybeOf(
      tester.element(find.text(text, findRichText: true)),
    );
    expect(registrarOf('h0 l3'), isNotNull, reason: 'the rows are selectable');
    expect(registrarOf('Unstaged'), isNull);
    expect(registrarOf('2 個 scope'), isNull);
  });

  testWidgets('a 5000-line full-file view builds only the rows near the '
      'viewport', (WidgetTester tester) async {
    final DiffFile file = _file(<DiffHunk>[
      _numbered('...+...', start: 2500, hunk: 0),
    ]);
    await _pump(
      tester,
      <ScopedDiffSource>[_source(file, staged: false)],
      fill: <DiffFillRow>[
        ..._fill(<int>[for (int l = 1; l < 2500; l++) l]),
        ..._fill(<int>[for (int l = 2507; l <= 5000; l++) l]),
      ],
    );
    expect(find.byType(DiffLineView).evaluate().length, lessThan(200));
  });

  // Discarding a line refetches the diff, and while it is in flight the view
  // has nothing to draw. Its list carries GlobalKeys (the drag geometry finds
  // it by them), so if the empty state drew that same list outside the
  // SelectionArea the keyed subtree would be *moved* out and back, and a
  // SelectionListener would be sorted while inactive -- device tier,
  // `context_menu_flows_test.dart` 05-G.
  testWidgets('content -> nothing to draw -> content, with a selection, '
      'throws nothing', (WidgetTester tester) async {
    await _pump(tester, <ScopedDiffSource>[_source(_excerpt, staged: false)]);
    await tester.tap(
      find.text('h0 l3', findRichText: true),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await _pump(tester, <ScopedDiffSource>[
      ScopedDiffSource(
        title: 'Unstaged',
        file: null,
        staged: false,
        loading: true,
        onStageScope: (int h, List<int> l) {},
      ),
    ]);
    await tester.pump();
    await _pump(tester, <ScopedDiffSource>[_source(_excerpt, staged: false)]);
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
