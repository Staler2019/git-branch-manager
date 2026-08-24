import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_selection_gesture.dart';
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

/// Checkout is a double-click now (BRANCH_STATES 「點兩下即 checkout」), so a
/// test that still single-taps would pass for the wrong reason: a single tap
/// never checks out anything any more.
Future<void> _doubleTap(WidgetTester tester) async {
  await tester.tap(find.byType(InkWell));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(find.byType(InkWell));
  await tester.pumpAndSettle();
}

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

    await _doubleTap(tester);

    // Checkout should not have been called
    expect(checkoutCount, 0);
  });

  testWidgets('a double tap checks out when conflictActive is false', (
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

    await _doubleTap(tester);

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

    await _doubleTap(tester);

    expect(checkoutCount, 0);
  });

  testWidgets('a single tap on a local branch selects, and does not check '
      'out (MULTIKEYS 單擊)', (tester) async {
    // The behaviour this round inverted. It used to be the other way round --
    // a plain click was the checkout -- which is what P13's MULTIKEYS table
    // contradicts: 「單擊 ＝ 只選這一項，anchor 移到這一項」.
    int checkoutCount = 0;
    final List<SelectionGesture> gestures = <SelectionGesture>[];
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
            onSelect: gestures.add,
          ),
        ),
      ),
    );

    await tester.tap(find.byType(InkWell));
    await tester.pump(kDoubleTapTimeout);

    // Counted, not `any`: a row that both selected *and* checked out would
    // satisfy a truthy assertion on either one.
    expect(gestures, <SelectionGesture>[SelectionGesture.single]);
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

  group('isGonePending renders spec page 02 stage 1 and 2', () {
    RefInfo localRef({String upstream = 'refs/remotes/origin/feature'}) =>
        RefInfo(
          fullName: 'refs/heads/feature',
          shortName: 'feature',
          kind: RefKind.localBranch,
          target: 'abc123',
          isHead: false,
          isGone: false,
          upstream: upstream,
          ahead: 0,
          behind: 0,
          hasTrackingInfo: false,
          isSymbolic: false,
          worktreePath: '',
        );

    Future<void> pumpRow(
      WidgetTester tester,
      RefInfo ref, {
      required bool isGonePending,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: BranchTreeItem(
              ref: ref,
              onCheckout: () {},
              isGonePending: isGonePending,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('a pending-gone local branch gets the gone badge', (
      tester,
    ) async {
      await pumpRow(tester, localRef(), isGonePending: true);

      expect(find.text('gone'), findsOneWidget);
    });

    testWidgets('a pending-gone local branch gets the cloud-off icon', (
      tester,
    ) async {
      await pumpRow(tester, localRef(), isGonePending: true);

      expect(
        tester.widget<LucideIcon>(find.byType(LucideIcon)).name,
        'cloud-off',
      );
    });

    testWidgets('without the flag it renders as an ordinary branch', (
      tester,
    ) async {
      await pumpRow(tester, localRef(), isGonePending: false);

      expect(find.text('gone'), findsNothing);
      expect(
        tester.widget<LucideIcon>(find.byType(LucideIcon)).name,
        'git-branch',
      );
    });

    testWidgets('the accessibility label says upstream gone', (tester) async {
      // Spec page 02 stage 2. The badge is three letters in the smallest
      // type size in the app; a screen reader has to be told outright.
      // Disposed inline, not via addTearDown: flutter_test verifies that no
      // SemanticsHandle is live *before* tear-downs run, so registering the
      // dispose there fails the test with an unrelated assertion.
      final SemanticsHandle handle = tester.ensureSemantics();

      await pumpRow(tester, localRef(), isGonePending: true);

      expect(find.bySemanticsLabel(RegExp('upstream gone')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('a pending-gone remote-only row is struck through', (
      tester,
    ) async {
      // Stage 1: 「該列轉半透明、名稱加刪除線」. The remote-only row already
      // renders at .62 opacity for a different reason ("not checked out
      // here"), so the strikethrough is what distinguishes "gone from the
      // remote" from "just not local yet".
      await pumpRow(tester, _remoteOnlyRef(), isGonePending: true);

      final Text name = tester.widget<Text>(find.text('worktrees'));
      expect(name.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('a live remote-only row is not struck through', (tester) async {
      await pumpRow(tester, _remoteOnlyRef(), isGonePending: false);

      final Text name = tester.widget<Text>(find.text('worktrees'));
      expect(name.style?.decoration, isNot(TextDecoration.lineThrough));
    });

    testWidgets('a pending-gone local branch is struck through too', (
      tester,
    ) async {
      await pumpRow(tester, localRef(), isGonePending: true);

      final Text name = tester.widget<Text>(find.text('feature'));
      expect(name.style?.decoration, TextDecoration.lineThrough);
    });

    testWidgets('a pending-gone local branch is dimmed', (tester) async {
      // Stage 1's 半透明 applies to the marked row whichever shape it has;
      // only remote-only rows were dimmed before.
      await pumpRow(tester, localRef(), isGonePending: true);

      expect(find.byType(Opacity), findsOneWidget);
    });

    testWidgets('a row git already reports as gone needs no flag', (
      tester,
    ) async {
      // The existing path must keep working after a real prune, when the
      // pending entry has been dropped and RefInfo.isGone took over.
      await pumpRow(
        tester,
        RefInfo(
          fullName: 'refs/heads/feature',
          shortName: 'feature',
          kind: RefKind.localBranch,
          target: 'abc123',
          isHead: false,
          isGone: true,
          upstream: 'refs/remotes/origin/feature',
          ahead: 0,
          behind: 0,
          hasTrackingInfo: false,
          isSymbolic: false,
          worktreePath: '',
        ),
        isGonePending: false,
      );

      expect(find.text('gone'), findsOneWidget);
      expect(
        tester.widget<LucideIcon>(find.byType(LucideIcon)).name,
        'cloud-off',
      );
    });
  });
}
