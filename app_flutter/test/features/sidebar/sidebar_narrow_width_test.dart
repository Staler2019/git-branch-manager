// Narrow-sidebar regression coverage. The sidebar splitter's own minimum is
// 180 logical px (GbmLayout.sidebarMinWidth), so every row in it has to
// survive that width -- but four independent things in the panel had no
// guard at all:
//
//   B1  the folder row's Text carried neither `overflow` nor `maxLines`, so
//       a long folder name wrapped to a second line inside a fixed-height
//       rowHeightCompact (26px) Container and overflowed *vertically*;
//   B2  BranchTreeItem's `gone` / "up N down M" label was a non-flex Text
//       with no upper bound, so it pushed the row horizontally and squeezed
//       the branch name's Expanded toward zero;
//   B3  the selection action bar's "N selected" Text had no ellipsis and sat
//       beside two non-flex TextButtons;
//   B4  every folder level added an unbounded 12px indent, so a deep tree
//       ate the name entirely.
//
// Assertions are relational (no exception / non-zero width / rect inside the
// panel), never pixel constants: widget tests render in the Ahem test font,
// where every glyph is one em wide, so text measures wider here than on a
// real device and a hardcoded threshold would encode the harness instead of
// the behaviour.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/repositories/branch_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/sidebar/sidebar_panel.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');
final String _repoIdParam = Uri.encodeComponent(_identity.workDir);

RefInfo _branch(
  String name, {
  bool isHead = false,
  String upstream = '',
  int ahead = 0,
  int behind = 0,
  bool isGone = false,
}) {
  return RefInfo(
    fullName: 'refs/heads/$name',
    shortName: name,
    kind: RefKind.localBranch,
    target: 'a' * 40,
    upstream: upstream,
    ahead: ahead,
    behind: behind,
    // Not derived from `upstream` -- see CLAUDE.md's Tier 0c note: a fixture
    // that computes one field from another cannot falsify the derivation.
    hasTrackingInfo: upstream.isNotEmpty,
    isGone: isGone,
    isHead: isHead,
    isSymbolic: isHead,
    worktreePath: '',
  );
}

RefSnapshot _refs(List<RefInfo> refs) => RefSnapshot(
  head: HeadInfo(
    kind: HeadKind.branch,
    branchName: 'main',
    fullRef: 'refs/heads/main',
    target: 'a' * 40,
  ),
  refs: refs,
  refCountGuardTripped: false,
  totalRefCount: refs.length,
);

const String _longSegment = 'an-extremely-long-name-that-will-not-fit-at-all';

// A leaf under folders prints only its last segment (P02 item 12), so the
// finders below match the segment, not the whole path. This comment used to
// say the opposite and called the last-segment reading "wrong" -- it was
// describing the bug, which the spec's own BRANCH_TREE mock contradicts.
//
// The last segment is deliberately *not* `_longSegment`: that is also the
// root folder's name, and an exact-text finder would then match two rows.
const String _deepLeafLabel =
    'a-second-extremely-long-name-that-also-will-not-fit';
const String _deepLeaf = '$_longSegment/team/subsystem/$_deepLeafLabel';
const String _siblingLeaf = '$_longSegment/team/subsystem/sibling';
const String _siblingLabel = 'sibling';

/// A four-level tree whose deepest leaf also carries a long name and a
/// tracking label -- B1, B2 and B4 all at once. Two children per folder so
/// nothing is collapsed away.
final RefSnapshot _deepRefs = _refs(<RefInfo>[
  _branch('main', isHead: true, upstream: 'refs/remotes/origin/main'),
  _branch(
    _deepLeaf,
    upstream: 'refs/remotes/origin/x',
    ahead: 1234,
    behind: 5678,
  ),
  _branch('$_longSegment/team/subsystem/sibling'),
  _branch('$_longSegment/team/other'),
  _branch('$_longSegment/second'),
]);

/// Two plain branches, for the selection action bar (B3).
final RefSnapshot _flatRefs = _refs(<RefInfo>[
  _branch('main', isHead: true),
  _branch('feature-one'),
  _branch('feature-two'),
]);

Future<FakeRepoSessionController> _pump(
  WidgetTester tester, {
  required RefSnapshot refs,
  double width = GbmLayout.sidebarMinWidth,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();

  final FakeRepoSessionController fake = FakeRepoSessionController(
    _identity,
    const RepoSessionState(isOpen: true),
  );

  final GoRouter router = GoRouter(
    initialLocation: '/repo/$_repoIdParam/history',
    routes: <RouteBase>[
      GoRoute(
        path: '/repo/:repoId/history',
        builder: (context, state) => Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            // A SizedBox rather than tester.view.physicalSize: the sidebar's
            // real width comes from GbmSplitPane, not from the window, so
            // constraining the panel directly is what the production tree
            // actually does to it.
            child: SizedBox(
              width: width,
              height: 600,
              child: SidebarPanel(identity: _identity, filterFocusNode: null),
            ),
          ),
        ),
      ),
    ],
  );

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoRefsProvider(_identity).overrideWithValue(refs),
      repoSessionProvider(_identity).overrideWith((ref) => fake),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: router,
      ),
    ),
  );
  await tester.pump();
  return fake;
}

/// Every folder row is collapsed on first build, so the deep leaf is only
/// reachable after walking down. Taps the folder label, which
/// `_toggleFolderExpandedSingleLevel` is wired to.
Future<void> _expand(WidgetTester tester, String folderName) async {
  await tester.tap(find.text(folderName));
  await tester.pump();
}

void main() {
  // Deliberately NOT a `takeException()` test. B1's wrap is a *cross-axis*
  // overflow -- the Text grew taller than its row, not wider -- and
  // RenderFlex only reports main-axis overflow, so the broken version threw
  // nothing at all and a no-exception assertion here passed before the fix
  // as readily as after it. The two assertions below are the ones that bite.
  group('folder row (B1)', () {
    testWidgets('the folder name stays on one line and ellipsizes', (
      tester,
    ) async {
      await _pump(tester, refs: _deepRefs);

      final Text folder = tester.widget<Text>(find.text(_longSegment));
      expect(folder.maxLines, 1);
      expect(folder.overflow, TextOverflow.ellipsis);
    });

    testWidgets('the folder label renders one line tall, not two', (
      tester,
    ) async {
      await _pump(tester, refs: _deepRefs);

      // The rendered consequence, independent of how it was achieved: a
      // wrapped label was two lines tall and painted over its neighbours
      // inside the 26px rowHeightCompact container.
      final double labelHeight = tester.getSize(find.text(_longSegment)).height;
      expect(labelHeight, lessThan(GbmSpacing.rowHeightCompact));
    });
  });

  group('branch row (B2)', () {
    testWidgets('a long branch name with ahead/behind does not overflow', (
      tester,
    ) async {
      await _pump(tester, refs: _deepRefs);
      await _expand(tester, _longSegment);
      await _expand(tester, 'team');
      await _expand(tester, 'subsystem');

      expect(tester.takeException(), isNull);
    });

    testWidgets('the branch name keeps a non-zero width', (tester) async {
      await _pump(tester, refs: _deepRefs);
      await _expand(tester, _longSegment);
      await _expand(tester, 'team');
      await _expand(tester, 'subsystem');

      // "No overflow" alone would pass with the name's Expanded collapsed to
      // zero by the non-flex tracking label beside it -- which is exactly
      // the failure this row had.
      // Deliberately the leaf's own label, not `find.text(_longSegment)` --
      // that matches the root folder row (exact-text finder), so it would
      // have asserted the wrong widget's width entirely.
      expect(tester.getSize(find.text(_deepLeafLabel)).width, greaterThan(0));
    });
  });

  group('tree indent (B4)', () {
    testWidgets('a deep leaf still starts inside the panel', (tester) async {
      await _pump(tester, refs: _deepRefs);
      await _expand(tester, _longSegment);
      await _expand(tester, 'team');
      await _expand(tester, 'subsystem');

      final Rect leaf = tester.getRect(find.text(_siblingLabel));
      expect(leaf.left, lessThan(GbmLayout.sidebarMinWidth));
      expect(leaf.width, greaterThan(0));
    });
  });

  group('selection action bar (B3)', () {
    testWidgets('does not overflow with a selection at 180px', (tester) async {
      await _pump(tester, refs: _flatRefs);

      // A plain click is the selection gesture now (MULTIKEYS 單擊); the
      // row no longer carries a checkbox to tick.
      await tester.tap(find.text('feature-one'));
      // Lets the double-tap window close so the recognizer's timer does not
      // outlive the test. The selection itself already landed on pointer-down.
      await tester.pump(kDoubleTapTimeout);

      expect(find.textContaining('selected'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('control: a wide sidebar degrades nothing', () {
    testWidgets('every row renders at 400px', (tester) async {
      await _pump(tester, refs: _deepRefs, width: 400);
      await _expand(tester, _longSegment);
      await _expand(tester, 'team');
      await _expand(tester, 'subsystem');

      expect(tester.takeException(), isNull);
      expect(find.text(_siblingLabel), findsOneWidget);
      expect(find.text('main'), findsOneWidget);
    });
  });
}
