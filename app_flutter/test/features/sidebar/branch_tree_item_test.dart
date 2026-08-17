import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_tree_item.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/lucide_icon.dart';

RefInfo _remoteOnlyRef({String shortName = 'worktrees'}) => RefInfo(
  fullName: 'refs/remotes/origin/$shortName',
  shortName: shortName,
  kind: RefKind.remoteBranch,
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

  group('remote-only rows (RefKind.remoteBranch)', () {
    testWidgets('a single tap does not check out', (tester) async {
      int checkoutCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: BranchTreeItem(
              ref: _remoteOnlyRef(),
              onCheckout: () => checkoutCount++,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(checkoutCount, 0);
    });

    testWidgets('a double tap checks out (as new local)', (tester) async {
      int checkoutCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: BranchTreeItem(
              ref: _remoteOnlyRef(),
              onCheckout: () => checkoutCount++,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(InkWell));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(checkoutCount, 1);
    });

    testWidgets('a double tap is inert while conflictActive is true', (
      tester,
    ) async {
      int checkoutCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: BranchTreeItem(
              ref: _remoteOnlyRef(),
              onCheckout: () => checkoutCount++,
              conflictActive: true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(InkWell));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(InkWell));
      await tester.pumpAndSettle();

      expect(checkoutCount, 0);
    });

    testWidgets('renders dimmed (Opacity 0.62)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: BranchTreeItem(ref: _remoteOnlyRef(), onCheckout: () {}),
          ),
        ),
      );

      final Opacity opacity = tester.widget<Opacity>(find.byType(Opacity));
      expect(opacity.opacity, 0.62);
    });

    testWidgets('renders the cloud icon, not git-branch', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: BranchTreeItem(ref: _remoteOnlyRef(), onCheckout: () {}),
          ),
        ),
      );

      expect(tester.widget<LucideIcon>(find.byType(LucideIcon)).name, 'cloud');
    });

    testWidgets(
      'the "more" button shows when onPruneRef/onDeleteOnRemote are set, '
      'even though onRename/onDelete are null',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
            home: Scaffold(
              body: BranchTreeItem(
                ref: _remoteOnlyRef(),
                onCheckout: () {},
                onPruneRef: () {},
                onDeleteOnRemote: () {},
              ),
            ),
          ),
        );

        expect(find.byTooltip('Branch actions'), findsOneWidget);
      },
    );
  });

  group('gone rows use the cloud-off icon (BRANCH_STATES table)', () {
    testWidgets('renders cloud-off, not git-branch, when isGone', (
      tester,
    ) async {
      final RefInfo goneRef = RefInfo(
        fullName: 'refs/heads/feature',
        shortName: 'feature',
        kind: RefKind.localBranch,
        target: 'abc123',
        isHead: false,
        isGone: true,
        upstream: 'refs/remotes/origin/feature',
        ahead: 0,
        behind: 0,
        hasTrackingInfo: true,
        isSymbolic: false,
        worktreePath: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: BranchTreeItem(ref: goneRef, onCheckout: () {}),
          ),
        ),
      );

      expect(
        tester.widget<LucideIcon>(find.byType(LucideIcon)).name,
        'cloud-off',
      );
    });
  });
}
