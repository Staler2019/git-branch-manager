// BlamePanel under the two wrap modes.
//
// Blame is the one surface where this preference is not purely additive: its
// rows used to carry `maxLines: 1` + ellipsis unconditionally, so a long line
// was simply cut off with no way to reach the rest. Both new modes are an
// improvement on that, and neither is the old behaviour.
//
// Widths are test-font units -- `flutter_test` draws every glyph `fontSize`
// wide -- so the long fixture line overflows more readily here than the same
// string would on screen. That is the safe direction for a test that needs
// the overflow to exist at all.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/blame_result.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/blame_panel.dart';
import 'package:gbm_flutter/widgets/gbm_code_hscroll.dart';

import 'panel_test_support.dart';

const String _longContent =
    'final result = compute(alpha, beta, gamma, delta, epsilon, zeta, eta);';

BlameLine _line(String content) => BlameLine(
  commitOid: 'aaaaaaa',
  authorName: 'Ada',
  authorEmail: 'ada@example.com',
  authorTime: 1755000000,
  summary: 'add it',
  finalLine: 1,
  originalLine: 1,
  content: content,
  boundary: false,
);

Future<void> _pump(
  WidgetTester tester, {
  required bool softWrap,
  String content = _longContent,
}) => pumpPanel(
  tester,
  BlamePanel(identity: panelTestIdentity, path: 'lib/main.dart'),
  state: RepoSessionState(
    isOpen: true,
    lastBlame: BlameResult(
      lines: <BlameLine>[_line(content)],
      truncated: false,
    ),
  ),
  // The list column is one pane of a split shell inside a 1200px surface, so
  // the code area is a few hundred px -- narrow enough for the fixture line
  // to overflow it in test-font terms.
  initialPrefs: <String, Object>{'appPrefs.softWrapEnabled': softWrap},
);

void main() {
  testWidgets('a long blame line scrolls sideways by default', (
    WidgetTester tester,
  ) async {
    await _pump(tester, softWrap: false);

    expect(find.byType(GbmCodeHScroll), findsOneWidget);
    expect(find.byType(GbmPinnedGutter), findsOneWidget);
  });

  testWidgets('soft wrap on drops the pinned gutter entirely', (
    WidgetTester tester,
  ) async {
    await _pump(tester, softWrap: true);

    expect(find.byType(GbmPinnedGutter), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('the line is never truncated in either mode', (
    WidgetTester tester,
  ) async {
    // The regression this guards: `maxLines: 1` + `TextOverflow.ellipsis`
    // used to be hardcoded on this row, so the end of a long blame line was
    // unreachable. Neither mode may bring it back -- wrapping shows the rest
    // below, scrolling shows it to the right.
    for (final bool softWrap in const <bool>[false, true]) {
      await _pump(tester, softWrap: softWrap);
      final Text code = tester.widget<Text>(find.text(_longContent));
      expect(code.maxLines, isNull, reason: 'softWrap=$softWrap');
      expect(
        code.overflow,
        isNot(TextOverflow.ellipsis),
        reason: 'softWrap=$softWrap',
      );
    }
  });

  testWidgets('the pinned gutter paints nothing over the row background', (
    WidgetTester tester,
  ) async {
    // `opaque: false` is load-bearing here and nowhere else: a blame row's
    // background is the enclosing GbmRow's hover and selection tint, and an
    // opaque gutter strip would cover both -- at every scroll offset,
    // including zero. Diff rows paint their own full-width background, so
    // they take the opposite setting.
    await _pump(tester, softWrap: false);

    final GbmPinnedGutter gutter = tester.widget<GbmPinnedGutter>(
      find.byType(GbmPinnedGutter),
    );
    expect(gutter.opaque, isFalse);
    expect(find.byType(GbmPinnedGutterClip), findsOneWidget);
  });
}
