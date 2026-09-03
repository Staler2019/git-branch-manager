// The one searchable branch / tag / commit list, shared by Checkout, New
// branch and Add worktree.
//
// Spec page 06's Checkout row words it 「可搜尋的分支 / tag / commit 清單」 and
// P17's New branch row reuses that wording for its 從哪裡分出 field, so the
// two are one control by the spec's own text rather than by our convenience.
//
// The commit row is the half that never existed: Checkout's list was built
// from `localBranches` + `remoteBranches` + `tags` only, so its hint promised
// a granularity nothing in the widget could reach
// ([SPEC-how-column-is-a-requirement] -- a `how` cell names the input, and a
// capability is not evidence for one).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_ref_picker.dart';
import 'package:gbm_flutter/widgets/gbm_row.dart';

const List<GbmRefPickerEntry> _entries = <GbmRefPickerEntry>[
  GbmRefPickerEntry(name: 'main', kind: GbmRefKind.localBranch),
  GbmRefPickerEntry(name: 'release/0.5', kind: GbmRefKind.localBranch),
  GbmRefPickerEntry(name: 'origin/main', kind: GbmRefKind.remoteBranch),
  GbmRefPickerEntry(name: 'v0.5.0', kind: GbmRefKind.tag),
];

Future<GbmRefPickerEntry?> _pump(
  WidgetTester tester, {
  List<GbmRefPickerEntry> entries = _entries,
  String? selected,
  bool allowCommitHash = false,
}) async {
  GbmRefPickerEntry? picked;
  await tester.pumpWidget(
    MaterialApp(
      theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
      home: Scaffold(
        body: SizedBox(
          width: 420,
          child: GbmRefPicker(
            entries: entries,
            selected: selected,
            allowCommitHash: allowCommitHash,
            onSelected: (GbmRefPickerEntry entry) => picked = entry,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  // Returned as a getter would be, except a closure cannot be one: the caller
  // reads it *after* driving a tap, so it has to be re-read each time.
  return picked;
}

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(find.byType(TextField), query);
  await tester.pumpAndSettle();
}

/// Scoped to the list on purpose: the search field's own [EditableText]
/// carries the typed query as text, so a bare `find.text('deadbeef')` matches
/// twice and `findsOneWidget` fails on a *correct* widget.
Finder _inList(String text) =>
    find.descendant(of: find.byType(ListView), matching: find.text(text));

void main() {
  group('GbmRefPicker grouping', () {
    testWidgets('one heading per kind, in the spec mockup\'s order', (
      tester,
    ) async {
      await _pump(tester);

      final List<String> headings = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => t.data ?? '')
          .where(
            (String s) => <String>[
              'LOCAL BRANCHES',
              'REMOTE BRANCHES',
              'TAGS',
            ].contains(s),
          )
          .toList();

      expect(headings, <String>['LOCAL BRANCHES', 'REMOTE BRANCHES', 'TAGS']);
    });

    // The picker sorts by kind rather than trusting the caller to hand
    // entries over pre-grouped. The heading is emitted when the *previous*
    // entry's kind differs, so an interleaved list would print
    // 'LOCAL BRANCHES' twice -- a footgun the three call sites would each
    // have to remember not to trip.
    testWidgets('an interleaved list still gets one heading per kind', (
      tester,
    ) async {
      await _pump(
        tester,
        entries: const <GbmRefPickerEntry>[
          GbmRefPickerEntry(name: 'v0.5.0', kind: GbmRefKind.tag),
          GbmRefPickerEntry(name: 'main', kind: GbmRefKind.localBranch),
          GbmRefPickerEntry(name: 'origin/main', kind: GbmRefKind.remoteBranch),
          GbmRefPickerEntry(name: 'release/0.5', kind: GbmRefKind.localBranch),
        ],
      );

      expect(find.text('LOCAL BRANCHES'), findsOneWidget);
      expect(find.text('REMOTE BRANCHES'), findsOneWidget);
      expect(find.text('TAGS'), findsOneWidget);
    });

    testWidgets('a filtered-out kind leaves no orphan heading', (tester) async {
      await _pump(tester);
      await _type(tester, 'origin');

      expect(find.text('REMOTE BRANCHES'), findsOneWidget);
      expect(find.text('LOCAL BRANCHES'), findsNothing);
      expect(find.text('TAGS'), findsNothing);
    });
  });

  group('GbmRefPicker search', () {
    testWidgets('matches a case-insensitive substring', (tester) async {
      await _pump(tester);
      await _type(tester, 'RELEASE');

      expect(find.text('release/0.5'), findsOneWidget);
      expect(find.text('main'), findsNothing);
    });

    testWidgets('a query that matches nothing says what was searched for', (
      tester,
    ) async {
      await _pump(tester);
      await _type(tester, 'nope');

      expect(
        find.text('No branch, tag or commit matches "nope".'),
        findsOneWidget,
      );
    });
  });

  group('GbmRefPicker selection', () {
    testWidgets('tapping a row reports the whole entry, not just its name', (
      tester,
    ) async {
      GbmRefPickerEntry? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: GbmRefPicker(
                entries: _entries,
                selected: null,
                onSelected: (GbmRefPickerEntry e) => picked = e,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('origin/main'));
      await tester.pumpAndSettle();

      // The kind is why this is an entry and not a String: `origin/main`
      // checks out as a *new local branch*, and only the kind says so.
      expect(picked?.name, 'origin/main');
      expect(picked?.kind, GbmRefKind.remoteBranch);
    });

    testWidgets('the selected row carries the selected tint', (tester) async {
      await _pump(tester, selected: 'release/0.5');

      final Iterable<GbmRow> rows = tester.widgetList<GbmRow>(
        find.byType(GbmRow),
      );
      expect(rows.where((GbmRow r) => r.selected).length, 1);
    });
  });

  group('GbmRefPicker disabled entries', () {
    // 「已在 gbm-0.5」 on a branch another worktree has checked out. git
    // refuses that add anyway; saying so before the button is pressed beats
    // an error banner afterwards.
    testWidgets('a disabled entry draws its annotation and refuses taps', (
      tester,
    ) async {
      GbmRefPickerEntry? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: GbmRefPicker(
                entries: const <GbmRefPickerEntry>[
                  GbmRefPickerEntry(
                    name: 'main',
                    kind: GbmRefKind.localBranch,
                    annotation: '已在 gbm',
                    enabled: false,
                  ),
                ],
                selected: null,
                onSelected: (GbmRefPickerEntry e) => picked = e,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('已在 gbm'), findsOneWidget);

      await tester.tap(find.text('main'));
      await tester.pumpAndSettle();
      expect(picked, isNull, reason: 'git would refuse this one');
    });

    testWidgets('an enabled entry may still carry an annotation', (
      tester,
    ) async {
      GbmRefPickerEntry? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: GbmRefPicker(
                entries: const <GbmRefPickerEntry>[
                  GbmRefPickerEntry(
                    name: 'main',
                    kind: GbmRefKind.localBranch,
                    annotation: '目前分支',
                  ),
                ],
                selected: null,
                onSelected: (GbmRefPickerEntry e) => picked = e,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('main'));
      await tester.pumpAndSettle();
      expect(picked?.name, 'main');
    });
  });

  group('GbmRefPicker commit hashes', () {
    testWidgets('a hash-shaped query with no match offers itself', (
      tester,
    ) async {
      await _pump(tester, allowCommitHash: true);
      await _type(tester, 'a1b2c3d');

      expect(find.text('COMMIT'), findsOneWidget);
      expect(_inList('a1b2c3d'), findsOneWidget);
    });

    testWidgets('the commit row reports kind commit', (tester) async {
      GbmRefPickerEntry? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: SizedBox(
              width: 420,
              child: GbmRefPicker(
                entries: _entries,
                selected: null,
                allowCommitHash: true,
                onSelected: (GbmRefPickerEntry e) => picked = e,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _type(tester, 'deadbeef');
      await tester.tap(_inList('deadbeef'));
      await tester.pumpAndSettle();

      expect(picked?.name, 'deadbeef');
      expect(picked?.kind, GbmRefKind.commit);
    });

    // 「打得像 hash 才出現」. `release` is four-plus characters and matches no
    // ref once typed in full, but it is not hex, so offering it as a commit
    // would be offering something `git rev-parse` will refuse.
    testWidgets('a non-hex query is never offered as a commit', (tester) async {
      await _pump(tester, allowCommitHash: true);
      await _type(tester, 'zzzz');

      expect(find.text('COMMIT'), findsNothing);
    });

    testWidgets('a hash shorter than four characters is not offered', (
      tester,
    ) async {
      await _pump(tester, allowCommitHash: true);
      await _type(tester, 'abc');

      expect(find.text('COMMIT'), findsNothing);
    });

    // The flag is what tells Checkout ("可搜尋的分支 / tag / commit") from a
    // caller that only accepts a ref, so it has to actually gate something.
    testWidgets('allowCommitHash off means no commit row, ever', (
      tester,
    ) async {
      await _pump(tester);
      await _type(tester, 'a1b2c3d');

      expect(find.text('COMMIT'), findsNothing);
    });

    // A query that *is* a ref's name is a ref, not a hash -- `abcdef` as a
    // branch name is unusual but legal, and offering it twice would ask the
    // user to pick between two identical-looking rows.
    testWidgets('a hex query that names a real ref is not doubled', (
      tester,
    ) async {
      await _pump(
        tester,
        entries: const <GbmRefPickerEntry>[
          GbmRefPickerEntry(name: 'abcdef', kind: GbmRefKind.localBranch),
        ],
        allowCommitHash: true,
      );
      await _type(tester, 'abcdef');

      expect(_inList('abcdef'), findsOneWidget);
      expect(find.text('COMMIT'), findsNothing);
    });
  });
}
