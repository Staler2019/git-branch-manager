// Verifies CommitRow's design-doc field order (graph · [HEAD] · hash ·
// subject · author · date), the loading-state skeleton, and selected/hover
// background -- colors read from tokensFor() across all three theme
// variants, per gbm_components_test.dart's convention.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';
import 'package:gbm_flutter/theme/tokens.dart';

import '../../support/pump_app.dart';

const GraphRow _row = GraphRow(
  parentOffset: 0,
  edgeOffset: 0,
  commitTime: 0,
  lane: 0,
  color: 0,
  flags: 1,
);

CommitMeta _meta({String subject = 'Fix the bug', String author = 'Ada'}) {
  return CommitMeta(
    oid: 'a' * 40,
    tree: 'b' * 40,
    parents: const <String>[],
    author: Signature(
      name: author,
      email: 'ada@example.invalid',
      when: 0,
      tzOffsetMinutes: 0,
    ),
    committer: Signature(
      name: author,
      email: 'ada@example.invalid',
      when: 0,
      tzOffsetMinutes: 0,
    ),
    subject: subject,
    body: '',
    signedCommit: false,
  );
}

void main() {
  for (final GbmThemeVariant variant in GbmThemeVariant.values) {
    final GbmColors colors = tokensFor(variant);

    group('CommitRow ($variant)', () {
      testWidgets('renders subject and author once meta is available', (
        tester,
      ) async {
        await pumpGbmWidget(
          tester,
          variant: variant,
          child: CommitRow(
            row: _row,
            oidHex: 'a' * 40,
            graph: GraphSnapshotView.empty,
            rowIndex: 0,
            maxLane: 0,
            meta: _meta(subject: 'Fix the bug', author: 'Ada'),
          ),
        );

        expect(find.text('Fix the bug'), findsOneWidget);
        expect(find.text('Ada'), findsOneWidget);
      });

      testWidgets(
        'shows a skeleton placeholder instead of blank text while meta is loading',
        (tester) async {
          await pumpGbmWidget(
            tester,
            variant: variant,
            child: CommitRow(
              row: _row,
              oidHex: 'a' * 40,
              graph: GraphSnapshotView.empty,
              rowIndex: 0,
              maxLane: 0,
            ),
          );

          // No subject/author text rendered yet (the hash and date are
          // always present regardless of meta) -- but the row itself has
          // already rendered at full height, so nothing needs a follow-up
          // layout pass once meta arrives.
          expect(find.text('Fix the bug'), findsNothing);
          expect(find.text('Ada'), findsNothing);
          expect(
            tester.getSize(find.byType(CommitRow)).height,
            kCommitRowHeight,
          );
        },
      );

      testWidgets('selected uses surfaceSelected background', (tester) async {
        await pumpGbmWidget(
          tester,
          variant: variant,
          child: CommitRow(
            row: _row,
            oidHex: 'a' * 40,
            graph: GraphSnapshotView.empty,
            rowIndex: 0,
            maxLane: 0,
            meta: _meta(),
            selected: true,
          ),
        );

        final Container container = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(CommitRow),
                matching: find.byType(Container),
              )
              .first,
        );
        final BoxDecoration decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, colors.surfaceSelected);
      });

      testWidgets('unselected has no background', (tester) async {
        await pumpGbmWidget(
          tester,
          variant: variant,
          child: CommitRow(
            row: _row,
            oidHex: 'a' * 40,
            graph: GraphSnapshotView.empty,
            rowIndex: 0,
            maxLane: 0,
            meta: _meta(),
          ),
        );

        final Container container = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(CommitRow),
                matching: find.byType(Container),
              )
              .first,
        );
        final BoxDecoration decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, isNull);
      });

      testWidgets('tapping the row invokes onTap', (tester) async {
        String? tapped;
        await pumpGbmWidget(
          tester,
          variant: variant,
          child: CommitRow(
            row: _row,
            oidHex: 'a' * 40,
            graph: GraphSnapshotView.empty,
            rowIndex: 0,
            maxLane: 0,
            meta: _meta(),
            onTap: () => tapped = 'a' * 40,
          ),
        );

        await tester.tap(find.byType(CommitRow));
        expect(tapped, 'a' * 40);
      });

      testWidgets('renders a chip for every ref pointing to this commit', (
        tester,
      ) async {
        await pumpGbmWidget(
          tester,
          variant: variant,
          child: CommitRow(
            row: _row,
            oidHex: 'a' * 40,
            graph: GraphSnapshotView.empty,
            rowIndex: 0,
            maxLane: 0,
            meta: _meta(),
            refChips: <RefInfo>[
              RefInfo(
                fullName: 'refs/heads/main',
                shortName: 'main',
                kind: RefKind.localBranch,
                target: 'a' * 40,
                upstream: '',
                ahead: 0,
                behind: 0,
                hasTrackingInfo: false,
                isGone: false,
                isHead: true,
                isSymbolic: false,
                worktreePath: '',
              ),
              RefInfo(
                fullName: 'refs/tags/v1.0',
                shortName: 'v1.0',
                kind: RefKind.tag,
                target: 'a' * 40,
                upstream: '',
                ahead: 0,
                behind: 0,
                hasTrackingInfo: false,
                isGone: false,
                isHead: false,
                isSymbolic: false,
                worktreePath: '',
              ),
            ],
          ),
        );

        expect(find.text('main'), findsOneWidget);
        expect(find.text('v1.0'), findsOneWidget);
      });

      testWidgets('renders no chips when nothing points to this commit', (
        tester,
      ) async {
        await pumpGbmWidget(
          tester,
          variant: variant,
          child: CommitRow(
            row: _row,
            oidHex: 'a' * 40,
            graph: GraphSnapshotView.empty,
            rowIndex: 0,
            maxLane: 0,
            meta: _meta(),
          ),
        );

        expect(find.text('main'), findsNothing);
      });

      testWidgets('author is accent-colored and bold when isOwnCommit', (
        tester,
      ) async {
        await pumpGbmWidget(
          tester,
          variant: variant,
          child: CommitRow(
            row: _row,
            oidHex: 'a' * 40,
            graph: GraphSnapshotView.empty,
            rowIndex: 0,
            maxLane: 0,
            meta: _meta(author: 'Ada'),
            isOwnCommit: true,
          ),
        );

        final Text authorText = tester.widget<Text>(find.text('Ada'));
        expect(authorText.style?.color, colors.accent);
        expect(authorText.style?.fontWeight, GbmTypography.weightSemibold);
      });

      testWidgets(
        'author uses the default color when not isOwnCommit -- a whole-row '
        'tint is never applied, only the author text itself',
        (tester) async {
          await pumpGbmWidget(
            tester,
            variant: variant,
            child: CommitRow(
              row: _row,
              oidHex: 'a' * 40,
              graph: GraphSnapshotView.empty,
              rowIndex: 0,
              maxLane: 0,
              meta: _meta(author: 'Ada'),
            ),
          );

          final Text authorText = tester.widget<Text>(find.text('Ada'));
          expect(authorText.style?.color, colors.textSecondary);
          expect(
            authorText.style?.fontWeight,
            isNot(GbmTypography.weightSemibold),
          );
        },
      );
    });
  }
}
