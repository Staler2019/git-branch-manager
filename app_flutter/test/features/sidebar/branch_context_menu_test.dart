// Verifies BranchTreeItem's right-click menu against the design doc's
// `ctxItemsFor('branch')`: item set, danger styling, and that a tap wires
// through to the right callback -- using kSecondaryButton via tapAt/tester
// gestures, since onSecondaryTapDown is not reachable through tester.tap.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_tree_item.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

RefInfo _branch({String name = 'feature/x', bool isHead = false}) {
  return RefInfo(
    fullName: 'refs/heads/$name',
    shortName: name,
    kind: RefKind.localBranch,
    target: 'a' * 40,
    upstream: '',
    ahead: 0,
    behind: 0,
    hasTrackingInfo: false,
    isGone: false,
    isHead: isHead,
    isSymbolic: false,
    worktreePath: '',
  );
}

Future<void> _rightClick(WidgetTester tester, Finder finder) async {
  final TestGesture gesture = await tester.createGesture(
    kind: PointerDeviceKind.mouse,
    buttons: kSecondaryMouseButton,
  );
  addTearDown(gesture.removePointer);
  await gesture.down(tester.getCenter(finder));
  await gesture.up();
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets(
    'right-click shows Checkout/Rename/Merge/Copy/Delete for a non-HEAD branch',
    (tester) async {
      await _pump(
        tester,
        BranchTreeItem(
          ref: _branch(),
          onCheckout: () {},
          onRename: () {},
          onDelete: () {},
          onNewBranchFromHere: () {},
          onMerge: () {},
        ),
      );
      await _rightClick(tester, find.byType(BranchTreeItem));

      expect(find.text('Checkout feature/x'), findsOneWidget);
      expect(find.text('New branch from here'), findsOneWidget);
      expect(find.text('Rename branch'), findsOneWidget);
      expect(find.text('Merge into current branch'), findsOneWidget);
      expect(find.text('Copy branch name'), findsOneWidget);
      expect(find.text('Delete branch'), findsOneWidget);
    },
  );

  testWidgets('the HEAD branch has no Checkout entry', (tester) async {
    await _pump(
      tester,
      BranchTreeItem(
        ref: _branch(isHead: true),
        onCheckout: () {},
        onDelete: () {},
      ),
    );
    await _rightClick(tester, find.byType(BranchTreeItem));
    expect(find.textContaining('Checkout'), findsNothing);
  });

  testWidgets('Delete branch is styled danger', (tester) async {
    await _pump(
      tester,
      BranchTreeItem(ref: _branch(), onCheckout: () {}, onDelete: () {}),
    );
    await _rightClick(tester, find.byType(BranchTreeItem));
    final Text label = tester.widget<Text>(find.text('Delete branch'));
    expect(label.style?.color, tokensFor(GbmThemeVariant.darkTechnical).danger);
  });

  testWidgets('tapping Rename branch invokes onRename and closes the menu', (
    tester,
  ) async {
    bool renamed = false;
    await _pump(
      tester,
      BranchTreeItem(
        ref: _branch(),
        onCheckout: () {},
        onRename: () => renamed = true,
      ),
    );
    await _rightClick(tester, find.byType(BranchTreeItem));
    await tester.tap(find.text('Rename branch'));
    await tester.pumpAndSettle();
    expect(renamed, isTrue);
    expect(find.text('Rename branch'), findsNothing);
  });
}
