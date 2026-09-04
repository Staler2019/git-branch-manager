import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/panel_tabs_repository.dart';

/// The tabs a test actually opened, with D7's seeded pinned tab filtered
/// out. Every assertion in the first group predates the seed and is about
/// what `open`/`close` did to the *caller's* tabs -- filtering keeps each
/// one pinning that, rather than silently becoming an assertion about how
/// many tabs are seeded.
List<PanelTabSpec> _opened(PanelTabsNotifier n) =>
    n.state.where((PanelTabSpec t) => !t.kind.isPinned).toList();

void main() {
  group('PanelTabsNotifier', () {
    late PanelTabsNotifier notifier;

    setUp(() => notifier = PanelTabsNotifier());
    tearDown(() => notifier.dispose());

    test('open adds a tab and returns its id', () {
      final String id = notifier.open(GbmPanelKind.manageStashes);

      expect(_opened(notifier), hasLength(1));
      expect(_opened(notifier).single.id, id);
      expect(_opened(notifier).single.kind, GbmPanelKind.manageStashes);
      expect(_opened(notifier).single.subject, isNull);
    });

    // The behaviour that differs from compareTabsProvider on purpose: two
    // Compare tabs hold two genuinely different ref pairs, but a second
    // Worktrees tab would be the same panel twice. Spec's "同一功能不留兩條路"
    // is about entry points, but stacking duplicate tabs is the same problem
    // wearing a different hat.
    test('re-opening the same panel focuses it instead of duplicating', () {
      final String first = notifier.open(GbmPanelKind.manageStashes);
      final String second = notifier.open(GbmPanelKind.manageStashes);

      expect(second, first);
      expect(_opened(notifier), hasLength(1));
    });

    test('different kinds open as separate tabs', () {
      notifier.open(GbmPanelKind.manageStashes);
      notifier.open(GbmPanelKind.bisect);

      expect(_opened(notifier).map((PanelTabSpec t) => t.kind), <GbmPanelKind>[
        GbmPanelKind.manageStashes,
        GbmPanelKind.bisect,
      ]);
    });

    test('a per-subject panel opens one tab per file', () {
      final String a = notifier.open(
        GbmPanelKind.blame,
        subject: 'lib/main.dart',
      );
      final String b = notifier.open(
        GbmPanelKind.blame,
        subject: 'lib/app.dart',
      );
      final String aAgain = notifier.open(
        GbmPanelKind.blame,
        subject: 'lib/main.dart',
      );

      expect(b, isNot(a));
      expect(aAgain, a);
      expect(_opened(notifier), hasLength(2));
    });

    // A repository-wide panel is a singleton regardless of what a caller
    // passes, so a stray subject can never split it into two tabs.
    test('a repository-wide panel ignores subject', () {
      final String a = notifier.open(
        GbmPanelKind.manageRemotes,
        subject: 'lib/main.dart',
      );
      final String b = notifier.open(GbmPanelKind.manageRemotes);

      expect(b, a);
      expect(_opened(notifier).single.subject, isNull);
    });

    test('close removes only the named tab', () {
      final String stashes = notifier.open(GbmPanelKind.manageStashes);
      final String bisect = notifier.open(GbmPanelKind.bisect);

      notifier.close(stashes);

      expect(_opened(notifier).single.id, bisect);
    });

    test('closing an unknown id is a no-op', () {
      notifier.open(GbmPanelKind.reflog);
      notifier.close('not-a-real-id');
      expect(_opened(notifier), hasLength(1));
    });
  });

  // D7. The mechanism is a *seeded, close-refusing tab*, deliberately not a
  // third fixed tab: doing it this way reuses the whole P19 round (route,
  // panel shell, panelStorageId(), scroll memory) with no change to the
  // route tree, where a fixed tab would need a second copy of PanelPage.
  group('a pinned panel', () {
    late PanelTabsNotifier notifier;

    setUp(() => notifier = PanelTabsNotifier());
    tearDown(() => notifier.dispose());

    test('is already open before anything asks for it', () {
      expect(notifier.state.map((PanelTabSpec t) => t.kind), <GbmPanelKind>[
        GbmPanelKind.manageWorktrees,
      ]);
    });

    // Tools > Worktrees… still works, and lands on the seeded tab rather
    // than stacking a second one -- `open`'s existing singleton dedupe does
    // this for free, which is why the seed goes through `open` rather than
    // pushing a spec onto the list itself.
    test('opening it again focuses the seeded tab', () {
      final String id = notifier.open(GbmPanelKind.manageWorktrees);

      expect(id, notifier.state.single.id);
      expect(notifier.state, hasLength(1));
    });

    test('close refuses it', () {
      final String id = notifier.state.single.id;

      notifier.close(id);

      expect(
        notifier.state.single.id,
        id,
        reason: 'a pinned tab survives an explicit close',
      );
    });

    // The refusal is scoped to the pinned tab, not to closing in general --
    // a guard that returned early for the wrong reason would make every
    // panel unclosable and this is what tells the two apart.
    test('close still removes an ordinary tab while a pinned one is open', () {
      final String reflog = notifier.open(GbmPanelKind.reflog);

      notifier.close(reflog);

      expect(notifier.state.map((PanelTabSpec t) => t.kind), <GbmPanelKind>[
        GbmPanelKind.manageWorktrees,
      ]);
    });
  });

  group('GbmPanelKind', () {
    test('covers exactly the twelve panels IAMAP routes to tabs', () {
      // Spec page 14's IAMAP: "大型管理面板（12）". clean-untracked is
      // deliberately absent -- it shares the Rewrite history submenu but
      // belongs to IAMAP's "中型表單 / 確認框" group and stays a dialog.
      expect(GbmPanelKind.values, hasLength(12));
      expect(
        GbmPanelKind.values.map((GbmPanelKind k) => k.slug).toSet(),
        <String>{
          'stashes',
          'worktrees',
          'remotes',
          'submodules',
          'lfs',
          'patches',
          'interactive-rebase',
          'bisect',
          'reflog',
          'blame',
          'file-history',
          'line-history',
        },
      );
    });

    test('only the three per-file panels are per-subject', () {
      expect(
        GbmPanelKind.values.where((GbmPanelKind k) => k.isPerSubject).toSet(),
        <GbmPanelKind>{
          GbmPanelKind.blame,
          GbmPanelKind.fileHistory,
          GbmPanelKind.lineHistory,
        },
      );
    });

    // 待裁定 4: only worktrees. Eleven pinned tabs would fill the strip,
    // and #62's TabRow overflow menu is still open.
    test('only Worktrees is pinned', () {
      expect(
        GbmPanelKind.values.where((GbmPanelKind k) => k.isPinned).toSet(),
        <GbmPanelKind>{GbmPanelKind.manageWorktrees},
      );
    });

    // The two properties are not independent: seeding needs one canonical
    // instance to seed, and a per-subject panel is *about* a file that no
    // seed can know. Asserted rather than left implicit, because the seed
    // loop would otherwise open a Blame tab with a null subject -- which
    // `_buildPanel` renders by asking git to blame the empty path.
    test('a pinned panel is never per-subject', () {
      for (final GbmPanelKind kind in GbmPanelKind.values) {
        expect(kind.isPinned && kind.isPerSubject, isFalse, reason: kind.name);
      }
    });

    test('labels are sentence case per spec page 14', () {
      for (final GbmPanelKind kind in GbmPanelKind.values) {
        expect(kind.label, isNotEmpty);
        expect(
          kind.label,
          isNot(endsWith('…')),
          reason:
              'a tab label names a thing; the ellipsis belongs on the '
              'menu item that opens it',
        );
      }
    });
  });

  group('PanelTabSpec.label', () {
    test('a repository-wide panel uses the kind label alone', () {
      const PanelTabSpec spec = PanelTabSpec(
        id: 'worktrees-0',
        kind: GbmPanelKind.manageWorktrees,
      );
      expect(spec.label, 'Worktrees');
    });

    // Two Blame tabs must be tellable apart without reading the route.
    test('a per-subject panel appends the file base name', () {
      const PanelTabSpec spec = PanelTabSpec(
        id: 'blame-0',
        kind: GbmPanelKind.blame,
        subject: 'lib/features/workspace/workspace_screen.dart',
      );
      expect(spec.label, 'Blame: workspace_screen.dart');
    });
  });
}
