import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/data/repositories/diff_view_mode_repository.dart';
import 'package:gbm_flutter/features/diff/diff_page.dart';
import 'package:gbm_flutter/features/diff/side_by_side_diff_view.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_detail_panel.dart';
import 'package:gbm_flutter/widgets/gbm_segmented_control.dart';

import '../../../support/pump_app.dart';

const CommitMeta _meta = CommitMeta(
  oid: 'abc123',
  tree: 'tree1',
  parents: <String>['parent1'],
  author: Signature(
    name: 'Alice',
    email: 'alice@example.com',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  committer: Signature(
    name: 'Alice',
    email: 'alice@example.com',
    when: 0,
    tzOffsetMinutes: 0,
  ),
  subject: 'Fix the thing',
  body: 'Full description body.',
  signedCommit: false,
);

/// A diff with one real hunk. [ParsedDiff.empty] renders 'No changes' in
/// either mode, so a test telling the two renderers apart needs content.
ParsedDiff _diff() => const ParsedDiff(
  files: <DiffFile>[
    DiffFile(
      oldPath: 'a.dart',
      newPath: 'a.dart',
      kind: FileChangeKind.modified,
      oldMode: '100644',
      newMode: '100644',
      oldBlob: 'aaa',
      newBlob: 'bbb',
      binary: false,
      similarity: 0,
      addedLines: 1,
      removedLines: 1,
      displayPath: 'a.dart',
      hunks: <DiffHunk>[
        DiffHunk(
          oldStart: 1,
          oldCount: 1,
          newStart: 1,
          newCount: 1,
          heading: '',
          lines: <DiffLine>[
            DiffLine(
              kind: DiffLineKind.removed,
              oldLine: 1,
              newLine: 0,
              text: 'old',
            ),
            DiffLine(
              kind: DiffLineKind.added,
              oldLine: 0,
              newLine: 1,
              text: 'new',
            ),
          ],
        ),
      ],
    ),
  ],
  truncated: false,
  inputBytes: 0,
);

/// Records what the switch reported, so a test can assert the panel delegates
/// rather than holding the mode itself.
DiffViewMode? _lastReported;

Widget _panel({
  required String? selectedFilePath,
  required bool hasSelectedCommit,
  required CommitMeta? meta,
  required ParsedDiff? diff,
  DiffViewMode mode = DiffViewMode.unified,
}) => CommitDetailPanelCore(
  selectedFilePath: selectedFilePath,
  hasSelectedCommit: hasSelectedCommit,
  meta: meta,
  diff: diff,
  diffViewMode: mode,
  onDiffViewModeChanged: (DiffViewMode m) => _lastReported = m,
);

void main() {
  setUp(() => _lastReported = null);

  testWidgets('prompts to select a commit when nothing is selected', (
    tester,
  ) async {
    await pumpGbmWidget(
      tester,
      child: _panel(
        selectedFilePath: null,
        hasSelectedCommit: false,
        meta: null,
        diff: null,
      ),
    );

    expect(find.text('Select a commit to view details'), findsOneWidget);
  });

  testWidgets('shows a spinner while a selected commit\'s meta is loading', (
    tester,
  ) async {
    await pumpGbmWidget(
      tester,
      child: _panel(
        selectedFilePath: null,
        hasSelectedCommit: true,
        meta: null,
        diff: null,
      ),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows commit subject and body once meta has loaded', (
    tester,
  ) async {
    await pumpGbmWidget(
      tester,
      child: _panel(
        selectedFilePath: null,
        hasSelectedCommit: true,
        meta: _meta,
        diff: null,
      ),
    );

    expect(find.text('Fix the thing'), findsOneWidget);
    expect(find.text('Full description body.'), findsOneWidget);
  });

  testWidgets(
    'shows a spinner instead of metadata once a file is selected but its '
    'diff has not arrived yet',
    (tester) async {
      await pumpGbmWidget(
        tester,
        child: _panel(
          selectedFilePath: 'a.dart',
          hasSelectedCommit: true,
          meta: _meta,
          diff: null,
        ),
      );

      expect(find.text('Fix the thing'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    },
  );

  testWidgets(
    'shows the file diff instead of metadata once a file is selected and '
    'its diff has arrived -- mutually exclusive with the metadata view',
    (tester) async {
      await pumpGbmWidget(
        tester,
        child: _panel(
          selectedFilePath: 'a.dart',
          hasSelectedCommit: true,
          meta: _meta,
          diff: ParsedDiff.empty,
        ),
      );

      expect(find.text('Fix the thing'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  // --- The 並排 / unified switch ------------------------------------------
  //
  // The panel stays presentational: the mode arrives as a param and the
  // switch reports back through a callback, so these pump no ProviderScope
  // of their own. The round trip through the real provider (and its
  // persistence) is `history_diff_view_mode_test.dart`'s job -- neither test
  // proves the other's half.

  group('diff view mode switch', () {
    testWidgets('the metadata face does not offer it', (tester) async {
      // Nothing to switch when no diff is on screen, and a control that
      // changes nothing visible is worse than absent.
      await pumpGbmWidget(
        tester,
        child: _panel(
          selectedFilePath: null,
          hasSelectedCommit: true,
          meta: _meta,
          diff: null,
        ),
      );

      expect(find.byType(GbmSegmentedControl<DiffViewMode>), findsNothing);
    });

    testWidgets('a selected file whose diff has not arrived does not offer '
        'it either', (tester) async {
      // It would be inert -- there is nothing to lay out either way -- and a
      // control that does nothing when pressed reads as broken, not pending.
      await pumpGbmWidget(
        tester,
        child: _panel(
          selectedFilePath: 'a.dart',
          hasSelectedCommit: true,
          meta: _meta,
          diff: null,
        ),
      );

      expect(find.byType(GbmSegmentedControl<DiffViewMode>), findsNothing);
    });

    testWidgets('the diff face names the file and offers the switch', (
      tester,
    ) async {
      await pumpGbmWidget(
        tester,
        child: _panel(
          selectedFilePath: 'a.dart',
          hasSelectedCommit: true,
          meta: _meta,
          diff: _diff(),
        ),
      );

      expect(find.text('a.dart'), findsOneWidget);
      expect(find.byType(GbmSegmentedControl<DiffViewMode>), findsOneWidget);
    });

    testWidgets('unified renders DiffPage and not the side-by-side view', (
      tester,
    ) async {
      await pumpGbmWidget(
        tester,
        child: _panel(
          selectedFilePath: 'a.dart',
          hasSelectedCommit: true,
          meta: _meta,
          diff: _diff(),
          mode: DiffViewMode.unified,
        ),
      );

      expect(find.byType(DiffPage), findsOneWidget);
      expect(find.byType(SideBySideDiffView), findsNothing);
    });

    testWidgets('side-by-side renders SideBySideDiffView and not DiffPage', (
      tester,
    ) async {
      await pumpGbmWidget(
        tester,
        child: _panel(
          selectedFilePath: 'a.dart',
          hasSelectedCommit: true,
          meta: _meta,
          diff: _diff(),
          mode: DiffViewMode.sideBySide,
        ),
      );

      expect(find.byType(SideBySideDiffView), findsOneWidget);
      expect(find.byType(DiffPage), findsNothing);
    });

    testWidgets('tapping the other key reports the mode it switches to', (
      tester,
    ) async {
      await pumpGbmWidget(
        tester,
        child: _panel(
          selectedFilePath: 'a.dart',
          hasSelectedCommit: true,
          meta: _meta,
          diff: _diff(),
          mode: DiffViewMode.unified,
        ),
      );

      await tester.tap(find.text('side by side'));
      await tester.pump();

      expect(_lastReported, DiffViewMode.sideBySide);
    });

    testWidgets('the titlebar sits above the diff rather than over it', (
      tester,
    ) async {
      // A finder proves the switch exists; it cannot prove the diff is not
      // underneath it. Assert against the neighbour's rect, not a constant.
      await pumpGbmWidget(
        tester,
        child: _panel(
          selectedFilePath: 'a.dart',
          hasSelectedCommit: true,
          meta: _meta,
          diff: _diff(),
        ),
      );

      final Rect switchRect = tester.getRect(
        find.byType(GbmSegmentedControl<DiffViewMode>),
      );
      final Rect diffRect = tester.getRect(find.byType(DiffPage));

      expect(switchRect.bottom, lessThanOrEqualTo(diffRect.top));
    });
  });
}
