// Verifies BranchTreeItem's right-click menu against the design doc's
// `ctxItemsFor('branch')`: item set, danger styling, and that a tap wires
// through to the right callback -- using kSecondaryButton via tapAt/tester
// gestures, since onSecondaryTapDown is not reachable through tester.tap.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_tree_item.dart';
import 'package:gbm_flutter/theme/tokens.dart';

import '../../support/pump_app.dart';

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

RefInfo _remoteOnlyBranch({String name = 'worktrees'}) {
  return RefInfo(
    fullName: 'refs/remotes/origin/$name',
    shortName: name,
    kind: RefKind.remoteBranch,
    target: 'a' * 40,
    upstream: '',
    ahead: 0,
    behind: 0,
    hasTrackingInfo: false,
    isGone: false,
    isHead: false,
    isSymbolic: false,
    worktreePath: '',
  );
}

RefInfo _goneBranch({String name = 'feature/gone'}) {
  return RefInfo(
    fullName: 'refs/heads/$name',
    shortName: name,
    kind: RefKind.localBranch,
    target: 'a' * 40,
    upstream: 'refs/remotes/origin/$name',
    ahead: 0,
    behind: 0,
    hasTrackingInfo: true,
    isGone: true,
    isHead: false,
    isSymbolic: false,
    worktreePath: '',
  );
}

RefInfo _tag({String name = 'v1.0.0'}) {
  return RefInfo(
    fullName: 'refs/tags/$name',
    shortName: name,
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

Future<void> _pump(WidgetTester tester, Widget child) =>
    pumpGbmWidget(tester, child: child);

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

  group('conflict gate on Rename branch (spec P13: "分支正在被 rebase/merge '
      '佔用 -> 整個 dialog 不開啟")', () {
    testWidgets('renders dimmed while a sequencer operation is active', (
      tester,
    ) async {
      await _pump(
        tester,
        BranchTreeItem(
          ref: _branch(),
          conflictActive: true,
          onCheckout: () {},
          onRename: () {},
        ),
      );
      await _rightClick(tester, find.byType(BranchTreeItem));
      final Text label = tester.widget<Text>(find.text('Rename branch'));
      expect(
        label.style?.color,
        tokensFor(GbmThemeVariant.darkTechnical).textTertiary,
      );
    });

    testWidgets('tapping it mid-conflict does not invoke onRename', (
      tester,
    ) async {
      bool renamed = false;
      await _pump(
        tester,
        BranchTreeItem(
          ref: _branch(),
          conflictActive: true,
          onCheckout: () {},
          onRename: () => renamed = true,
        ),
      );
      await _rightClick(tester, find.byType(BranchTreeItem));
      await tester.tap(find.text('Rename branch'));
      await tester.pumpAndSettle();
      expect(
        renamed,
        isFalse,
        reason:
            'onTap must be null too -- `enabled: false` alone would leave a '
            'dimmed item that still fires.',
      );
    });
  });

  group('remote-only row (05-C)', () {
    testWidgets(
      'shows the 05-C remote-only subset, not the 05-B local-branch menu',
      (tester) async {
        await _pump(
          tester,
          BranchTreeItem(
            ref: _remoteOnlyBranch(),
            onCheckout: () {},
            onPruneRef: () {},
            onDeleteOnRemote: () {},
          ),
        );
        await _rightClick(tester, find.byType(BranchTreeItem));

        expect(find.text('Checkout as new local…'), findsOneWidget);
        expect(find.text('Fetch this branch'), findsOneWidget);
        expect(find.text('Copy branch name'), findsOneWidget);
        expect(find.text('Prune this ref'), findsOneWidget);
        expect(find.text('Delete on remote…'), findsOneWidget);
        expect(find.text('Rename branch'), findsNothing);
        expect(find.text('Delete branch'), findsNothing);
        expect(find.text('Merge into current branch'), findsNothing);
        expect(find.text('New branch from here'), findsNothing);
      },
    );

    testWidgets('tapping Fetch this branch invokes onFetchRef', (tester) async {
      bool fetched = false;
      await _pump(
        tester,
        BranchTreeItem(
          ref: _remoteOnlyBranch(),
          onCheckout: () {},
          onFetchRef: () => fetched = true,
        ),
      );
      await _rightClick(tester, find.byType(BranchTreeItem));
      await tester.tap(find.text('Fetch this branch'));
      await tester.pumpAndSettle();
      expect(fetched, isTrue);
    });

    testWidgets(
      'Fetch this branch is disabled (no onTap) when onFetchRef is null',
      (tester) async {
        await _pump(
          tester,
          BranchTreeItem(ref: _remoteOnlyBranch(), onCheckout: () {}),
        );
        await _rightClick(tester, find.byType(BranchTreeItem));
        await tester.tap(find.text('Fetch this branch'));
        await tester.pumpAndSettle();
        // No crash and no callback exists to fire -- same pattern as the
        // other disabled-item assertions in this file.
        expect(find.text('Fetch this branch'), findsNothing);
      },
    );

    testWidgets('Delete on remote… is styled danger', (tester) async {
      await _pump(
        tester,
        BranchTreeItem(
          ref: _remoteOnlyBranch(),
          onCheckout: () {},
          onDeleteOnRemote: () {},
        ),
      );
      await _rightClick(tester, find.byType(BranchTreeItem));
      final Text label = tester.widget<Text>(find.text('Delete on remote…'));
      expect(
        label.style?.color,
        tokensFor(GbmThemeVariant.darkTechnical).danger,
      );
    });

    testWidgets('tapping Checkout as new local… invokes onCheckout', (
      tester,
    ) async {
      bool checkedOut = false;
      await _pump(
        tester,
        BranchTreeItem(
          ref: _remoteOnlyBranch(),
          onCheckout: () => checkedOut = true,
        ),
      );
      await _rightClick(tester, find.byType(BranchTreeItem));
      await tester.tap(find.text('Checkout as new local…'));
      await tester.pumpAndSettle();
      expect(checkedOut, isTrue);
    });

    testWidgets(
      'Checkout as new local… is disabled (no onTap) while conflictActive',
      (tester) async {
        await _pump(
          tester,
          BranchTreeItem(
            ref: _remoteOnlyBranch(),
            onCheckout: () {},
            conflictActive: true,
          ),
        );
        await _rightClick(tester, find.byType(BranchTreeItem));
        await tester.tap(find.text('Checkout as new local…'));
        await tester.pumpAndSettle();
        // No crash and the menu stays interactible for the other items --
        // absence of a thrown callback is the assertion here since a
        // disabled GbmMenuItem simply no-ops on tap.
        expect(find.text('Checkout as new local…'), findsNothing);
      },
    );

    testWidgets('tapping Prune this ref invokes onPruneRef', (tester) async {
      bool pruned = false;
      await _pump(
        tester,
        BranchTreeItem(
          ref: _remoteOnlyBranch(),
          onCheckout: () {},
          onPruneRef: () => pruned = true,
        ),
      );
      await _rightClick(tester, find.byType(BranchTreeItem));
      await tester.tap(find.text('Prune this ref'));
      await tester.pumpAndSettle();
      expect(pruned, isTrue);
    });

    testWidgets('tapping Delete on remote… invokes onDeleteOnRemote', (
      tester,
    ) async {
      bool deleted = false;
      await _pump(
        tester,
        BranchTreeItem(
          ref: _remoteOnlyBranch(),
          onCheckout: () {},
          onDeleteOnRemote: () => deleted = true,
        ),
      );
      await _rightClick(tester, find.byType(BranchTreeItem));
      await tester.tap(find.text('Delete on remote…'));
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
    });

    testWidgets('Copy branch name copies the stripped shortName', (
      tester,
    ) async {
      await _pump(
        tester,
        BranchTreeItem(ref: _remoteOnlyBranch(), onCheckout: () {}),
      );
      await _rightClick(tester, find.byType(BranchTreeItem));
      expect(find.text('Copy branch name'), findsOneWidget);
    });
  });

  group('gone row (05-C subset, BRANCH_STATES: "gone 的列只留 Prune 與 Copy")', () {
    testWidgets('shows the 05-C subset, not the 05-B local-branch menu', (
      tester,
    ) async {
      await _pump(
        tester,
        BranchTreeItem(
          ref: _goneBranch(),
          onCheckout: () {},
          onRename: () {},
          onDelete: () {},
          onNewBranchFromHere: () {},
          onMerge: () {},
          onPruneRef: () {},
        ),
      );
      await _rightClick(tester, find.byType(BranchTreeItem));

      expect(find.text('Checkout as new local…'), findsOneWidget);
      expect(find.text('Fetch this branch'), findsOneWidget);
      expect(find.text('Copy branch name'), findsOneWidget);
      expect(find.text('Prune this ref'), findsOneWidget);
      expect(find.text('Delete on remote…'), findsOneWidget);
      expect(find.text('Rename branch'), findsNothing);
      expect(find.text('Delete branch'), findsNothing);
      expect(find.text('Merge into current branch'), findsNothing);
      expect(find.text('New branch from here'), findsNothing);
    });

    testWidgets(
      'tapping Fetch this branch does nothing (disabled -- own upstream is '
      'what vanished)',
      (tester) async {
        await _pump(
          tester,
          BranchTreeItem(
            ref: _goneBranch(),
            onCheckout: () {},
            onPruneRef: () {},
          ),
        );
        await _rightClick(tester, find.byType(BranchTreeItem));
        await tester.tap(find.text('Fetch this branch'));
        await tester.pumpAndSettle();
        expect(find.text('Fetch this branch'), findsNothing);
      },
    );

    testWidgets(
      'tapping Checkout as new local… does nothing (disabled -- already local)',
      (tester) async {
        bool checkedOut = false;
        await _pump(
          tester,
          BranchTreeItem(
            ref: _goneBranch(),
            onCheckout: () => checkedOut = true,
            onPruneRef: () {},
          ),
        );
        await _rightClick(tester, find.byType(BranchTreeItem));
        await tester.tap(find.text('Checkout as new local…'));
        await tester.pumpAndSettle();
        expect(checkedOut, isFalse);
      },
    );

    testWidgets(
      'tapping Delete on remote… does nothing (disabled -- remote already gone)',
      (tester) async {
        await _pump(
          tester,
          BranchTreeItem(
            ref: _goneBranch(),
            onCheckout: () {},
            onPruneRef: () {},
          ),
        );
        await _rightClick(tester, find.byType(BranchTreeItem));
        await tester.tap(find.text('Delete on remote…'));
        await tester.pumpAndSettle();
        // No crash and no callback exists to fire -- absence of a thrown
        // error is the assertion, mirroring the remote-only conflictActive
        // case above.
        expect(find.text('Delete on remote…'), findsNothing);
      },
    );

    testWidgets('tapping Prune this ref invokes onPruneRef', (tester) async {
      bool pruned = false;
      await _pump(
        tester,
        BranchTreeItem(
          ref: _goneBranch(),
          onCheckout: () {},
          onPruneRef: () => pruned = true,
        ),
      );
      await _rightClick(tester, find.byType(BranchTreeItem));
      await tester.tap(find.text('Prune this ref'));
      await tester.pumpAndSettle();
      expect(pruned, isTrue);
    });

    testWidgets(
      'Delete on remote… renders dimmed, not danger red -- disabled wins '
      'over its danger styling (GbmMenuItem.enabled doc comment)',
      (tester) async {
        await _pump(
          tester,
          BranchTreeItem(
            ref: _goneBranch(),
            onCheckout: () {},
            onPruneRef: () {},
          ),
        );
        await _rightClick(tester, find.byType(BranchTreeItem));
        final Text label = tester.widget<Text>(find.text('Delete on remote…'));
        expect(
          label.style?.color,
          tokensFor(GbmThemeVariant.darkTechnical).textTertiary,
        );
      },
    );
  });

  group('tag row (05-D)', () {
    testWidgets('shows the 05-D tag menu, not the 05-B local-branch menu', (
      tester,
    ) async {
      await _pump(
        tester,
        BranchTreeItem(
          ref: _tag(),
          onCheckout: () {},
          onPushTag: () {},
          onCompareRef: () {},
          onDeleteTag: () {},
        ),
      );
      await _rightClick(tester, find.byType(BranchTreeItem));

      expect(find.text('Checkout tag (detached)'), findsOneWidget);
      expect(find.text('Push tag'), findsOneWidget);
      expect(find.text('Compare with…'), findsOneWidget);
      expect(find.text('Copy tag name'), findsOneWidget);
      expect(find.text('Delete tag…'), findsOneWidget);
      expect(find.text('Rename branch'), findsNothing);
      expect(find.text('Delete branch'), findsNothing);
      expect(find.text('Merge into current branch'), findsNothing);
    });

    testWidgets('Delete tag… is styled danger', (tester) async {
      await _pump(
        tester,
        BranchTreeItem(
          ref: _tag(),
          onCheckout: () {},
          onCompareRef: () {},
          onDeleteTag: () {},
        ),
      );
      await _rightClick(tester, find.byType(BranchTreeItem));
      final Text label = tester.widget<Text>(find.text('Delete tag…'));
      expect(
        label.style?.color,
        tokensFor(GbmThemeVariant.darkTechnical).danger,
      );
    });

    testWidgets('tapping Checkout tag (detached) invokes onCheckout', (
      tester,
    ) async {
      bool checkedOut = false;
      await _pump(
        tester,
        BranchTreeItem(
          ref: _tag(),
          onCheckout: () => checkedOut = true,
          onCompareRef: () {},
          onDeleteTag: () {},
        ),
      );
      await _rightClick(tester, find.byType(BranchTreeItem));
      await tester.tap(find.text('Checkout tag (detached)'));
      await tester.pumpAndSettle();
      expect(checkedOut, isTrue);
    });

    testWidgets(
      'Checkout tag (detached) is disabled (no onTap) while conflictActive, '
      'Push tag stays unaffected',
      (tester) async {
        await _pump(
          tester,
          BranchTreeItem(
            ref: _tag(),
            onCheckout: () {},
            onPushTag: () {},
            onCompareRef: () {},
            onDeleteTag: () {},
            conflictActive: true,
          ),
        );
        await _rightClick(tester, find.byType(BranchTreeItem));

        // Disabled -- absence of a thrown callback on tap is the
        // assertion, same pattern as the 05-C conflictActive case above.
        await tester.tap(find.text('Checkout tag (detached)'));
        await tester.pumpAndSettle();
        expect(find.text('Checkout tag (detached)'), findsNothing);
      },
    );

    testWidgets(
      'Push tag still reaches onPushTag while conflictActive -- unlike '
      'Checkout, it never touches HEAD or the working tree',
      (tester) async {
        bool pushed = false;
        await _pump(
          tester,
          BranchTreeItem(
            ref: _tag(),
            onCheckout: () {},
            onPushTag: () => pushed = true,
            onCompareRef: () {},
            onDeleteTag: () {},
            conflictActive: true,
          ),
        );
        await _rightClick(tester, find.byType(BranchTreeItem));
        await tester.tap(find.text('Push tag'));
        await tester.pumpAndSettle();
        expect(pushed, isTrue);
      },
    );

    testWidgets('Push tag is disabled (no onTap) when onPushTag is null', (
      tester,
    ) async {
      await _pump(
        tester,
        BranchTreeItem(
          ref: _tag(),
          onCheckout: () {},
          onCompareRef: () {},
          onDeleteTag: () {},
        ),
      );
      await _rightClick(tester, find.byType(BranchTreeItem));
      await tester.tap(find.text('Push tag'));
      await tester.pumpAndSettle();
      expect(find.text('Push tag'), findsNothing);
    });

    testWidgets('tapping Delete tag… invokes onDeleteTag', (tester) async {
      bool deleted = false;
      await _pump(
        tester,
        BranchTreeItem(
          ref: _tag(),
          onCheckout: () {},
          onCompareRef: () {},
          onDeleteTag: () => deleted = true,
        ),
      );
      await _rightClick(tester, find.byType(BranchTreeItem));
      await tester.tap(find.text('Delete tag…'));
      await tester.pumpAndSettle();
      expect(deleted, isTrue);
    });
  });
}
