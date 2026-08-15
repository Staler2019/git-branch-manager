import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_tree_item.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

void main() {
  testWidgets('checkout is disabled when conflictActive is true', (
    tester,
  ) async {
    int checkoutCount = 0;
    final testRef = RefInfo(
      fullName: 'refs/heads/feature',
      shortName: 'feature',
      kind: RefKind.localBranch,
      target: 'abc123',
      isHead: false,
      isGone: false,
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isSymbolic: false,
      worktreePath: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: BranchTreeItem(
            ref: testRef,
            onCheckout: () => checkoutCount++,
            conflictActive: true,
          ),
        ),
      ),
    );

    // Try to tap the branch item
    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    // Checkout should not have been called
    expect(checkoutCount, 0);
  });

  testWidgets('checkout is enabled when conflictActive is false', (
    tester,
  ) async {
    int checkoutCount = 0;
    final testRef = RefInfo(
      fullName: 'refs/heads/feature',
      shortName: 'feature',
      kind: RefKind.localBranch,
      target: 'abc123',
      isHead: false,
      isGone: false,
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isSymbolic: false,
      worktreePath: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: BranchTreeItem(
            ref: testRef,
            onCheckout: () => checkoutCount++,
            conflictActive: false,
          ),
        ),
      ),
    );

    // Tap the branch item
    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    // Checkout should have been called
    expect(checkoutCount, 1);
  });

  testWidgets('checkout is always disabled for HEAD branch', (tester) async {
    int checkoutCount = 0;
    final testRef = RefInfo(
      fullName: 'refs/heads/main',
      shortName: 'main',
      kind: RefKind.localBranch,
      target: 'abc123',
      isHead: true,
      isGone: false,
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isSymbolic: false,
      worktreePath: '',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: BranchTreeItem(
            ref: testRef,
            onCheckout: () => checkoutCount++,
            conflictActive: false,
          ),
        ),
      ),
    );

    // Try to tap the branch item (which is HEAD)
    await tester.tap(find.byType(InkWell));
    await tester.pumpAndSettle();

    // Checkout should not have been called
    expect(checkoutCount, 0);
  });
}
