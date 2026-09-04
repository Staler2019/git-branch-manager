// Spec page 19 樣板規則 1: 「可同時開多個、各自記憶捲動位置與 **splitter**」.
//
// The scroll half is `test/integration/panel_tab_scroll_memory_test.dart`.
// This is the splitter half, and it only has teeth for the three per-subject
// panel kinds (blame, file-history, line-history): those are the ones that
// can legitimately be open twice at once, so those are the ones a per-kind
// storage id would make share a position.
//
// **Corrected**: an earlier version of this header said the nine singleton
// kinds' ids were 「deliberately left alone」, and the test below was named
// 「a singleton kind keeps its unsuffixed id」 -- which read as a blessed
// exception to the rule rather than as the rule applied. 使用者裁定推翻了它。
// Every id now comes from `panelStorageId()`, whose suffix is derived from
// `GbmPanelKind.isPerSubject` -- the same property `open()` dedupes on, so
// 「can two of these exist」 and 「does the key tell them apart」 are one fact.
// See `panel_storage_id_test.dart` for the rule itself; this file stays as
// the behavioural half, proving a seeded width actually reaches the pane.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/blame_result.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/blame_panel.dart';
import 'package:gbm_flutter/features/panels/file_history_panel.dart';
import 'package:gbm_flutter/features/panels/line_history_panel.dart';
import 'package:gbm_flutter/features/panels/reflog_panel.dart';
import 'package:gbm_flutter/features/panels/panel_widgets.dart';
import 'package:gbm_flutter/theme/tokens.dart';

import 'panel_test_support.dart';

const BlameLine _line = BlameLine(
  commitOid: 'aaaaaaa',
  authorName: 'Ada',
  authorEmail: 'ada@example.com',
  authorTime: 1755000000,
  summary: 'add the header',
  finalLine: 1,
  originalLine: 1,
  content: 'import foo;',
  boundary: false,
);

const String _pathA = 'lib/a.dart';
const String _pathB = 'lib/b.dart';

/// A width nothing else in the layout would produce, so a pane measured at
/// this value can only have come from the seeded entry.
const double _seeded = 340.0;

/// The list column's width, read off the header, which is
/// `width: double.infinity` inside that column and so spans it exactly.
double _listWidth(WidgetTester tester) =>
    tester.getRect(find.byType(PanelListHeaderText)).width;

double get _default => GbmLayout.splitterPanelList.defaultExtent!;

void main() {
  group('P19 rule 1: two tabs of one kind keep separate splitter sizes', () {
    testWidgets('a saved size applies to the subject it was saved for', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        BlamePanel(identity: panelTestIdentity, path: _pathA),
        state: const RepoSessionState(
          isOpen: true,
          lastBlame: BlameResult(lines: <BlameLine>[_line], truncated: false),
        ),
        initialPrefs: const <String, Object>{
          'panelLayout.panel.blame:$_pathA': '[$_seeded]',
        },
      );

      expect(_listWidth(tester), closeTo(_seeded, 1.0));
    });

    // The point of the whole commit. With a per-*kind* id both blame tabs
    // read `panel.blame`, so resizing one silently resizes the other -- the
    // failure 「各自」 names.
    testWidgets('a second subject does not inherit the first\'s size', (
      tester,
    ) async {
      await pumpPanel(
        tester,
        BlamePanel(identity: panelTestIdentity, path: _pathB),
        state: const RepoSessionState(
          isOpen: true,
          lastBlame: BlameResult(lines: <BlameLine>[_line], truncated: false),
        ),
        initialPrefs: const <String, Object>{
          'panelLayout.panel.blame:$_pathA': '[$_seeded]',
        },
      );

      expect(_listWidth(tester), closeTo(_default, 1.0));
      expect(_listWidth(tester), isNot(closeTo(_seeded, 1.0)));
    });

    testWidgets('file-history keys on its path too', (tester) async {
      await pumpPanel(
        tester,
        FileHistoryPanel(identity: panelTestIdentity, path: _pathA),
        state: const RepoSessionState(isOpen: true),
        initialPrefs: const <String, Object>{
          'panelLayout.panel.file-history:$_pathA': '[$_seeded]',
        },
      );

      expect(_listWidth(tester), closeTo(_seeded, 1.0));
    });

    testWidgets('line-history keys on its path too', (tester) async {
      await pumpPanel(
        tester,
        LineHistoryPanel(
          identity: panelTestIdentity,
          path: _pathA,
          initialStartLine: 1,
          initialEndLine: 2,
        ),
        state: const RepoSessionState(isOpen: true),
        initialPrefs: const <String, Object>{
          'panelLayout.panel.line-history:$_pathA': '[$_seeded]',
        },
      );

      expect(_listWidth(tester), closeTo(_seeded, 1.0));
    });

    // A singleton kind carries no suffix because it can never have a second
    // tab to be told apart from -- the rule applied, not an exception to it.
    // Nine of the twelve keep the exact string they had, so nine users' saved
    // widths survive; `interactive-rebase` re-keys and is the round's one
    // orphan (a read-miss falling back to the default, never a wrong number).
    testWidgets('a singleton kind carries no subject suffix', (tester) async {
      await pumpPanel(
        tester,
        ReflogPanel(identity: panelTestIdentity),
        state: const RepoSessionState(isOpen: true),
        initialPrefs: const <String, Object>{
          'panelLayout.panel.reflog': '[$_seeded]',
        },
      );

      expect(_listWidth(tester), closeTo(_seeded, 1.0));
    });
  });
}
