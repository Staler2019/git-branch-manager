// The soft-wrap preference across the seam no widget test crosses.
//
// Every other wrap test in the suite *seeds* the preference and then pumps,
// so each mode is proven only on a freshly built tree. Two things live in
// the gap between those tests and the running app:
//
//  1. The provider -> surface path. A surface that reads
//     `appPreferencesProvider` in `build()` and one that reads it once in
//     `initState` are indistinguishable to a seeded test, and only the
//     second is wrong. Flipping the notifier while the diff is on screen is
//     what tells them apart.
//  2. The rebuild itself. Turning wrap off restructures every code row from
//     a `Row` into a `Stack`, and in `ScopedDiffView` those rows carry the
//     `GlobalKey`s their `SelectionListener`s hang off -- CLAUDE.md records
//     that reparenting that subtree is the hazardous move. A fresh
//     `pumpWidget` per mode never reparents anything; only a `setState` on
//     the *same* element does.
//
// The two halves are not equally load-bearing, and saying so is the point.
// Replacing `ref.watch` with `ref.read` in `PanelDiffText` reddens the first
// test and *nothing else in the suite* -- the seeded tests next door read the
// right value on their one and only build, so the seam is genuinely
// unguarded without this. Breaking the row-key memo, by contrast, reddens
// this file's second test and around twenty in `scoped_diff_view_test.dart`
// as well: that red is broad, so the second test is a guard on a path
// nothing else walks rather than the sole detector of a key regression.
//
// Widths are test-font units (`flutter_test` draws every glyph `fontSize`
// wide), so the fixture lines overflow far more readily here than the same
// strings would in JetBrains Mono. That is the safe direction for a test
// that needs the overflow to exist.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/app_preferences_repository.dart';
import 'package:gbm_flutter/features/diff/scoped_diff_view.dart';
import 'package:gbm_flutter/features/panels/panel_diff_text.dart';
import 'package:gbm_flutter/widgets/gbm_code_hscroll.dart';

import '../support/pump_app.dart';

const String _longLine =
    'const result = compute(alpha, beta, gamma, delta, epsilon, zeta, eta);';

const String _diff =
    '@@ -1,2 +1,2 @@\n'
    '-const before = oldValue(alpha, beta, gamma, delta, epsilon, zeta);\n'
    '+const after = newValue(alpha, beta, gamma, delta, epsilon, zeta, eta);';

DiffFile _file() => DiffFile(
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
      oldCount: 2,
      newStart: 1,
      newCount: 2,
      heading: '',
      lines: <DiffLine>[
        DiffLine(
          kind: DiffLineKind.context,
          oldLine: 1,
          newLine: 1,
          text: 'previously(existing, code, that, was, already, here, ok);',
        ),
        DiffLine(
          kind: DiffLineKind.added,
          oldLine: 0,
          newLine: 2,
          text: _longLine,
        ),
      ],
    ),
  ],
);

void main() {
  testWidgets(
    'flipping the preference restyles a diff that is already on screen',
    (WidgetTester tester) async {
      // PanelDiffText is the surface that reads the provider itself rather
      // than taking a parameter, so it is the one where a stale read would
      // actually ship.
      final ProviderContainer container = await pumpGbmWidget(
        tester,
        child: const SizedBox(
          width: 300,
          height: 200,
          child: PanelDiffText(text: _diff),
        ),
      );

      expect(
        find.byType(SingleChildScrollView),
        findsOneWidget,
        reason: 'off is the shipped default, so the scroller is there first',
      );

      await container
          .read(appPreferencesProvider.notifier)
          .update((AppPreferences p) => p.copyWith(softWrapEnabled: true));
      await tester.pump();

      expect(find.byType(SingleChildScrollView), findsNothing);
      for (final Text t in tester.widgetList<Text>(find.byType(Text))) {
        expect(t.softWrap, isTrue);
      }

      await container
          .read(appPreferencesProvider.notifier)
          .update((AppPreferences p) => p.copyWith(softWrapEnabled: false));
      await tester.pump();

      expect(
        find.byType(SingleChildScrollView),
        findsOneWidget,
        reason: 'and back -- the read is per build, not once per mount',
      );
    },
  );

  testWidgets('a live flip reparents the keyed selection rows without error', (
    WidgetTester tester,
  ) async {
    // The same `DiffFile` instance throughout: what changes is only the
    // flag, so every row keeps its GlobalKey and Flutter must *move* each
    // element into its new parent rather than build a second one. A
    // duplicate-key or double-listener failure surfaces as a framework
    // exception on the pump that follows setState.
    final DiffFile file = _file();
    late void Function(void Function()) rebuild;
    bool softWrap = false;

    await pumpGbmWidget(
      tester,
      child: StatefulBuilder(
        builder: (BuildContext context, void Function(void Function()) setS) {
          rebuild = setS;
          return SizedBox(
            width: 420,
            child: ScopedDiffView(
              softWrap: softWrap,
              title: 'Unstaged',
              file: file,
              staged: false,
              onStageScope: (int h, List<int> l) {},
            ),
          );
        },
      ),
    );

    expect(find.byType(GbmPinnedGutter), findsWidgets);

    rebuild(() => softWrap = true);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      find.byType(GbmPinnedGutter),
      findsNothing,
      reason: 'wrapping on, there is nothing to pin against',
    );

    rebuild(() => softWrap = false);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(GbmPinnedGutter), findsWidgets);
  });
}
