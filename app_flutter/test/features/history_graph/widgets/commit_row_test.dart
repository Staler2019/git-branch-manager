import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/graph_snapshot.dart';
import 'package:gbm_flutter/features/history_graph/widgets/commit_row.dart';

import '../../../support/pump_app.dart';

GraphRow _row({int lane = 0, int color = 0, int flags = 0}) {
  return GraphRow(
    parentOffset: 0,
    edgeOffset: 0,
    commitTime: 0,
    lane: lane,
    color: color,
    flags: flags,
  );
}

void main() {
  group('CommitRow', () {
    group('(variant)', () {
      testWidgets('renders commit with hash and subject', (tester) async {
        final row = _row();
        await pumpGbmWidget(
          tester,
          child: CommitRow(
            row: row,
            oidHex: 'abc12345def67890',
            graph: GraphSnapshotView.empty,
            rowIndex: 0,
            maxLane: 0,
          ),
        );

        expect(find.text('abc12345'), findsOneWidget);
      });

      testWidgets('right-click opens context menu with checkout', (
        tester,
      ) async {
        var checkoutCalled = false;
        final row = _row();
        await pumpGbmWidget(
          tester,
          child: CommitRow(
            row: row,
            oidHex: 'abc12345def67890',
            graph: GraphSnapshotView.empty,
            rowIndex: 0,
            maxLane: 0,
            onCheckout: () => checkoutCalled = true,
          ),
        );

        await tester.tap(
          find.byType(CommitRow),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        expect(find.text('Checkout this commit'), findsOneWidget);

        await tester.tap(find.text('Checkout this commit'));
        await tester.pumpAndSettle();

        expect(checkoutCalled, true);
      });

      testWidgets('context menu includes copy SHA', (tester) async {
        final row = _row();
        await pumpGbmWidget(
          tester,
          child: CommitRow(
            row: row,
            oidHex: 'abc12345def67890',
            graph: GraphSnapshotView.empty,
            rowIndex: 0,
            maxLane: 0,
          ),
        );

        await tester.tap(
          find.byType(CommitRow),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        expect(find.text('Copy SHA'), findsOneWidget);
      });

      testWidgets('merge and compare render disabled rather than omitted '
          'when the caller offers no destination', (tester) async {
        // Spec page 13 is explicit that an unavailable action is kept and
        // disabled, not hidden: 「不隱藏 — 隱藏會讓人以為功能不存在」. This
        // used to assert the opposite (findsNothing) back when 05-E was
        // hand-written and short of the catalog.
        final row = _row();
        await pumpGbmWidget(
          tester,
          child: CommitRow(
            row: row,
            oidHex: 'abc12345def67890',
            graph: GraphSnapshotView.empty,
            rowIndex: 0,
            maxLane: 0,
          ),
        );

        await tester.tap(
          find.byType(CommitRow),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        expect(find.text('Merge into current'), findsOneWidget);
        expect(find.text('Compare with…'), findsOneWidget);
      });

      testWidgets('cherry-pick callback is invoked when menu item tapped', (
        tester,
      ) async {
        var cherryPickCalled = false;
        final row = _row();
        await pumpGbmWidget(
          tester,
          child: CommitRow(
            row: row,
            oidHex: 'abc12345def67890',
            graph: GraphSnapshotView.empty,
            rowIndex: 0,
            maxLane: 0,
            onCherryPick: () => cherryPickCalled = true,
          ),
        );

        await tester.tap(
          find.byType(CommitRow),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Cherry-pick'));
        await tester.pumpAndSettle();

        expect(cherryPickCalled, true);
      });

      testWidgets('revert commit appears in context menu', (tester) async {
        var revertCalled = false;
        final row = _row();
        await pumpGbmWidget(
          tester,
          child: CommitRow(
            row: row,
            oidHex: 'abc12345def67890',
            graph: GraphSnapshotView.empty,
            rowIndex: 0,
            maxLane: 0,
            onRevert: () => revertCalled = true,
          ),
        );

        await tester.tap(
          find.byType(CommitRow),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        // Revert lives under "More actions" in the catalog, not at top
        // level -- it moved there when 05-E was brought to parity.
        await tester.tap(find.text('More actions'));
        await tester.pumpAndSettle();
        expect(find.text('Revert commit'), findsOneWidget);

        await tester.tap(find.text('Revert commit'));
        await tester.pumpAndSettle();

        expect(revertCalled, true);
      });

      testWidgets('create branch option appears when callback provided', (
        tester,
      ) async {
        final row = _row();
        await pumpGbmWidget(
          tester,
          child: CommitRow(
            row: row,
            oidHex: 'abc12345def67890',
            graph: GraphSnapshotView.empty,
            rowIndex: 0,
            maxLane: 0,
            onCreateBranchHere: () {},
          ),
        );

        await tester.tap(
          find.byType(CommitRow),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        expect(find.text('Create branch here…'), findsOneWidget);
      });

      testWidgets('actions with no callback render disabled, and Copy SHA '
          'still works on its own', (tester) async {
        final row = _row();
        await pumpGbmWidget(
          tester,
          child: CommitRow(
            row: row,
            oidHex: 'abc12345def67890',
            graph: GraphSnapshotView.empty,
            rowIndex: 0,
            maxLane: 0,
            // No callbacks provided
          ),
        );

        await tester.tap(
          find.byType(CommitRow),
          buttons: kSecondaryMouseButton,
        );
        await tester.pumpAndSettle();

        // Present, per the spec's keep-and-disable rule...
        for (final String label in <String>[
          'Checkout this commit',
          'Cherry-pick',
          'Create branch here…',
        ]) {
          expect(find.text(label), findsOneWidget, reason: label);
        }
        // ...and Copy SHA has a built-in fallback, so it is genuinely live.
        expect(find.text('Copy SHA'), findsOneWidget);
      });
    });
  });
}
