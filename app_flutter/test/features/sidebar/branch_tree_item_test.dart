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

/// The row's own tappable area. Every row now carries a trailing actions
/// button, and that button has an InkWell of its own, so `find.byType(InkWell)`
/// is ambiguous. The row centre is inside the body, which is the half that
/// selects and double-clicks.
final Finder _rowBody = find.byType(BranchTreeItem);

/// Checkout is a double-click now (BRANCH_STATES 「點兩下即 checkout」), so a
/// test that still single-taps would pass for the wrong reason: a single tap
/// never checks out anything any more.
Future<void> _doubleTap(WidgetTester tester) async {
  await tester.tap(_rowBody);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.tap(_rowBody);
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

    await tester.tap(_rowBody);
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

      await tester.tap(_rowBody);
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

      await tester.tap(_rowBody);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(_rowBody);
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

      await tester.tap(_rowBody);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(_rowBody);
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

    testWidgets('the "more" button shows when onDeleteOnRemote is set, '
        'even though onRename/onDelete are null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: BranchTreeItem(
              ref: _remoteOnlyRef(),
              onCheckout: () {},
              onDeleteOnRemote: () {},
            ),
          ),
        ),
      );

      expect(find.byTooltip('Branch actions'), findsOneWidget);
    });
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
      String remoteCounterpart = 'refs/remotes/origin/feature',
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: BranchTreeItem(
              ref: ref,
              onCheckout: () {},
              isGonePending: isGonePending,
              remoteCounterpart: remoteCounterpart,
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

    testWidgets('a pending-gone local branch is NOT dimmed', (tester) async {
      // 使用者裁定 + BRANCH_TREE's own mock, which marks `dim: true` on its
      // two `state: 'remote'` rows and on nothing else -- including its
      // `state: 'gone'` row. This test asserted the opposite until this
      // round, on a reading of stage 1's 半透明 that took it to cover every
      // marked row. Dimming a gone *local* branch made the row the user most
      // needs to act on the hardest to read; the strikethrough and the
      // cloud-off icon (asserted above) are what carry gone.
      await pumpRow(tester, localRef(), isGonePending: true);

      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('a pending-gone remote-only row stays dimmed', (tester) async {
      // The other half of the same rule: this row really is one the machine
      // does not have, so it keeps 「半透明」 whether or not it is also gone.
      await pumpRow(
        tester,
        _remoteOnlyRef(),
        isGonePending: true,
        remoteCounterpart: '',
      );

      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        closeTo(0.62, 0.001),
      );
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

  // BRANCH_STATES, one test per row of the user's own icon table:
  //
  //   local, no remote copy      git-branch                 local
  //   local + remote             git-branch                 ↑2 ↓1 (only if any)
  //   local, remote deleted      cloud-off (warning)        gone   + strikethrough
  //   remote-only, still there   cloud (tertiary)           --     + 62% dim
  //   remote-only, deleted       cloud-off (warning) + gone + 62% dim  [transient]
  //
  // The last row is the window between a fetch and the automatic prune that
  // clears it -- and where that prune fails, it persists. It is drawn either
  // way, so what it looks like is pinned here rather than left to chance.
  group('BRANCH_STATES icon and badge table', () {
    RefInfo local({
      String upstream = '',
      bool isGone = false,
      int ahead = 0,
      int behind = 0,
      bool hasTrackingInfo = false,
    }) => RefInfo(
      fullName: 'refs/heads/feature',
      shortName: 'feature',
      kind: RefKind.localBranch,
      target: 'abc123',
      upstream: upstream,
      ahead: ahead,
      behind: behind,
      // Never derived from `upstream`: %(upstream:track) is empty for a
      // branch exactly in sync, so the two are independent inputs.
      hasTrackingInfo: hasTrackingInfo,
      isGone: isGone,
      isHead: false,
      isSymbolic: false,
      worktreePath: '',
    );

    Future<void> pump(
      WidgetTester tester,
      RefInfo ref, {
      required String remoteCounterpart,
      bool isGonePending = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
          home: Scaffold(
            body: BranchTreeItem(
              ref: ref,
              onCheckout: () {},
              remoteCounterpart: remoteCounterpart,
              isGonePending: isGonePending,
            ),
          ),
        ),
      );
      await tester.pump();
    }

    String iconOf(WidgetTester tester) =>
        tester.widget<LucideIcon>(find.byType(LucideIcon)).name;

    testWidgets('local with no remote copy: git-branch + local badge', (
      tester,
    ) async {
      await pump(tester, local(), remoteCounterpart: '');

      expect(iconOf(tester), 'git-branch');
      expect(find.text('local'), findsOneWidget);
      expect(find.text('gone'), findsNothing);
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('local pushed without -u carries no local badge', (
      tester,
    ) async {
      // The badge means 「還沒 push 過」 and the spec says 「Push 後 badge
      // 自動消失」. `git push origin HEAD` leaves `upstream` empty, so
      // reading that field would keep the badge on a branch that is on the
      // remote right now -- the counterpart is what answers.
      await pump(
        tester,
        local(),
        remoteCounterpart: 'refs/remotes/origin/feature',
      );

      expect(iconOf(tester), 'git-branch');
      expect(find.text('local'), findsNothing);
    });

    testWidgets('local + remote, diverged: git-branch + the real numbers', (
      tester,
    ) async {
      await pump(
        tester,
        local(
          upstream: 'refs/remotes/origin/feature',
          hasTrackingInfo: true,
          ahead: 2,
          behind: 1,
        ),
        remoteCounterpart: 'refs/remotes/origin/feature',
      );

      expect(iconOf(tester), 'git-branch');
      expect(find.text('↑2 ↓1'), findsOneWidget);
      expect(find.text('local'), findsNothing);
    });

    testWidgets('local + remote, in sync: git-branch and no badge at all', (
      tester,
    ) async {
      // The commonest row in any repository. It must not pick up `local`
      // (it has a remote) and must not print ↑0 ↓0.
      await pump(
        tester,
        local(upstream: 'refs/remotes/origin/feature'),
        remoteCounterpart: 'refs/remotes/origin/feature',
      );

      expect(iconOf(tester), 'git-branch');
      expect(find.text('local'), findsNothing);
      expect(find.text('gone'), findsNothing);
      expect(find.textContaining('↑'), findsNothing);
      expect(find.textContaining('↓'), findsNothing);
    });

    testWidgets('local whose remote was deleted: cloud-off + gone, undimmed', (
      tester,
    ) async {
      await pump(
        tester,
        local(upstream: 'refs/remotes/origin/feature', isGone: true),
        remoteCounterpart: 'refs/remotes/origin/feature',
      );

      expect(iconOf(tester), 'cloud-off');
      expect(find.text('gone'), findsOneWidget);
      expect(find.text('local'), findsNothing);
      final Text name = tester.widget<Text>(find.text('feature'));
      expect(name.style?.decoration, TextDecoration.lineThrough);
      // 本機還在 -- this is a row the user can still act on.
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('remote-only, still on the remote: cloud + 62% dim', (
      tester,
    ) async {
      await pump(tester, _remoteOnlyRef(), remoteCounterpart: '');

      expect(iconOf(tester), 'cloud');
      // A remote-only row is never `local`: it is nothing *but* remote.
      expect(find.text('local'), findsNothing);
      expect(find.text('gone'), findsNothing);
      expect(
        tester.widget<Opacity>(find.byType(Opacity)).opacity,
        closeTo(0.62, 0.001),
      );
    });

    testWidgets(
      'remote-only and deleted: cloud-off + gone + 62% dim (the transient '
      'window before the automatic prune)',
      (tester) async {
        await pump(
          tester,
          _remoteOnlyRef(),
          remoteCounterpart: '',
          isGonePending: true,
        );

        expect(iconOf(tester), 'cloud-off');
        expect(find.text('gone'), findsOneWidget);
        expect(find.text('local'), findsNothing);
        expect(
          tester.widget<Opacity>(find.byType(Opacity)).opacity,
          closeTo(0.62, 0.001),
        );
      },
    );

    testWidgets('the icon colours come from the theme tokens', (tester) async {
      // Compared by identity against the token, not against a literal:
      // a hard-coded ARGB would pass in one theme variant and lie in the
      // other.
      final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);

      await pump(
        tester,
        local(upstream: 'refs/remotes/origin/feature', isGone: true),
        remoteCounterpart: 'refs/remotes/origin/feature',
      );
      expect(
        tester.widget<LucideIcon>(find.byType(LucideIcon)).color?.toARGB32(),
        colors.warning.toARGB32(),
      );

      await pump(tester, _remoteOnlyRef(), remoteCounterpart: '');
      expect(
        tester.widget<LucideIcon>(find.byType(LucideIcon)).color?.toARGB32(),
        colors.textTertiary.toARGB32(),
      );
    });
  });
}
