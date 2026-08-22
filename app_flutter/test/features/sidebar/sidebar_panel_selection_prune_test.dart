// `_pruneSelection` drops selected branch names that no longer exist. It ran
// straight from `SidebarPanel.build()` and wrote `branchSelectionProvider`
// there, which Riverpod forbids: `StateNotifier.state=` reaches
// `_debugCanModifyProviders` and throws
// `Tried to modify a provider while the widget tree was building`.
//
// **The throw is `assert`-guarded** (`riverpod/src/framework/element.dart`
// wraps `debugCanModifyProviders?.call()` in `assert(() { ... }(), '')`), so
// only debug and profile builds see it -- a release build strips the assert
// and lets the write land mid-build, which is the inconsistent-state risk the
// message describes rather than a crash. Both halves are bad; the debug half
// is what a manual pass hits.
//
// **Pre-existing, not a regression of this branch**: the call has been in
// `build()` since `4474d550` (2026-08-12, the multi-select round), and
// nothing at any tier covered pruning at all.
//
// Why no earlier fixture could have caught it: every existing sidebar test
// overrides `repoRefsProvider(...).overrideWithValue(...)` with one fixed
// snapshot, and a snapshot that cannot shrink cannot make a selected branch
// vanish. These tests deliberately leave that provider un-overridden so it
// derives from the session (`branch_repository.dart:11`) and `emit()` really
// does shrink it -- the same fixture-falsifiability rule CLAUDE.md already
// records for `hasTrackingInfo` and the borrowed `_mergeState()`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/list_selection.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/branch_selection_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/sidebar/sidebar_panel.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

RefInfo _local(String name, {bool isHead = false}) => RefInfo(
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

/// Flat names, no `/`: a slash would group the row under a folder and this
/// file has no business depending on tree rendering.
RefSnapshot _refs(List<String> names) => RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'a' * 40,
  ),
  refs: <RefInfo>[
    _local('main', isHead: true),
    for (final String n in names) _local(n),
  ],
  refCountGuardTripped: false,
  totalRefCount: names.length + 1,
);

class _Harness {
  _Harness(this.fake, this.container);

  final FakeRepoSessionController fake;
  final ProviderContainer container;

  ListSelection<String> get selection =>
      container.read(branchSelectionProvider(_identity));

  set selection(ListSelection<String> value) =>
      container.read(branchSelectionProvider(_identity).notifier).state = value;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  required List<String> branches,
  ListSelection<String>? seedSelection,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    RepoSessionState(refs: _refs(branches)),
  );

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      // repoRefsProvider deliberately NOT overridden -- see the header.
      repoSessionProvider(_identity).overrideWith((Ref ref) => fake),
    ],
  );
  addTearDown(container.dispose);

  if (seedSelection != null) {
    container.read(branchSelectionProvider(_identity).notifier).state =
        seedSelection;
  }

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: SidebarPanel(identity: _identity, filterFocusNode: null),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(fake, container);
}

void main() {
  group('pruning a selection whose branch vanished', () {
    testWidgets('a refs update that drops a selected branch does not throw', (
      WidgetTester tester,
    ) async {
      final _Harness h = await _pump(
        tester,
        branches: <String>['alpha', 'beta'],
      );
      h.selection = const ListSelection<String>(
        items: <String>['alpha', 'beta'],
        anchor: 'beta',
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'setup must be clean');

      // beta is deleted under the selection.
      h.fake.emit(RepoSessionState(refs: _refs(<String>['alpha'])));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(h.selection.items, <String>['alpha']);
    });

    testWidgets('the anchor moves when the anchored branch is the one that '
        'vanished', (WidgetTester tester) async {
      final _Harness h = await _pump(
        tester,
        branches: <String>['alpha', 'beta'],
      );
      h.selection = const ListSelection<String>(
        items: <String>['alpha', 'beta'],
        anchor: 'beta',
      );
      await tester.pumpAndSettle();

      h.fake.emit(RepoSessionState(refs: _refs(<String>['alpha'])));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(h.selection.anchor, 'alpha');
    });

    // The arm a listener-only fix fails. `branchSelectionProvider` is not
    // autoDispose, so a selection outlives the repository it was made in --
    // and `ref.listen` never fires for the value already present when it
    // registers (CLAUDE.md, "A retained query outliving its session"). The
    // stale name is therefore present at the very first build, with no
    // change event to hang a prune on.
    testWidgets('a selection that is already stale at mount is pruned', (
      WidgetTester tester,
    ) async {
      final _Harness h = await _pump(
        tester,
        branches: <String>['alpha'],
        seedSelection: const ListSelection<String>(
          items: <String>['alpha', 'ghost'],
          anchor: 'ghost',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(h.selection.items, <String>['alpha']);
      expect(h.selection.anchor, 'alpha');
    });

    testWidgets('a selection with nothing left becomes empty with no anchor', (
      WidgetTester tester,
    ) async {
      final _Harness h = await _pump(
        tester,
        branches: <String>['alpha'],
        seedSelection: const ListSelection<String>(
          items: <String>['ghost'],
          anchor: 'ghost',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(h.selection.items, isEmpty);
      expect(h.selection.anchor, isNull);
    });

    // The early return matters as much as the write: without it every build
    // would write an equal value and rebuild forever.
    testWidgets('a selection that is entirely live is left alone', (
      WidgetTester tester,
    ) async {
      final _Harness h = await _pump(
        tester,
        branches: <String>['alpha', 'beta'],
        seedSelection: const ListSelection<String>(
          items: <String>['alpha', 'beta'],
          anchor: 'alpha',
        ),
      );

      expect(tester.takeException(), isNull);
      expect(h.selection.items, <String>['alpha', 'beta']);
      expect(h.selection.anchor, 'alpha');
    });
  });
}
