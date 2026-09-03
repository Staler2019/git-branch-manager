// WorktreesPanel is spec page 19's reference instance -- the panel the
// other eleven are meant to be copied from ("只換欄位不換造型"). So this
// asserts the P19 PANELSPEC row for manage-worktrees specifically:
//
//   list:    worktree 名稱 + 分支 + 狀態
//   detail:  路徑、HEAD、待提交數、鎖定原因
//   toolbar: Add、Prune、Open、Remove
//
// 待提交數 used to be recorded here as unobtainable; it is obtainable now
// (WorktreeInfo.pendingChanges, fed by gbm_worktree_request_pending_counts)
// and simply not rendered until this panel's P19 rewrite. WorktreesPanel's
// class doc carries the struck note.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/worktree_info.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/worktrees_panel.dart';

import 'package:flutter/material.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/features/panels/panel_filter_field.dart';
import 'package:gbm_flutter/features/panels/panel_toolbar_spec.dart';
import 'package:gbm_flutter/features/panels/panel_widgets.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_badge.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';
import 'package:gbm_flutter/widgets/lucide_icon.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_repo_session.dart';
import 'panel_test_support.dart';

const WorktreeInfo _main = WorktreeInfo(
  path: '/src/git-branch-manager',
  headOid: 'a1b2c3d',
  branch: 'main',
  isMain: true,
  isBare: false,
  isDetached: false,
  isLocked: false,
  lockReason: '',
  isPrunable: false,
  prunableReason: '',
  isPrimary: true,
  // A plain refresh leaves every count unmeasured; the panel asks for the
  // real numbers separately. The current worktree also has no
  // `worktrees/<name>/` admin directory, so git records no creation time
  // for it -- null here is the production value, not a fixture shortcut.
  pendingChanges: null,
  pendingCountState: WorktreePendingCountState.unmeasured,
  createdAt: null,
);

const WorktreeInfo _locked = WorktreeInfo(
  path: '/src/wt/gbm-lfs',
  headOid: '9d02f4e',
  branch: 'feature/lfs',
  isMain: false,
  isBare: false,
  isDetached: false,
  isLocked: true,
  lockReason: 'on the USB drive',
  isPrunable: false,
  prunableReason: '',
  isPrimary: false,
  pendingChanges: null,
  pendingCountState: WorktreePendingCountState.unmeasured,
  createdAt: null,
);

/// A worktree fixture whose count fields are the only thing a caller varies.
/// Everything else is held identical across a transition, which is
/// [TEST-fixture-cannot-disagree] shape 10: if the untouched halves are
/// rebuilt per call, an unrelated rebuild can answer the assertion.
WorktreeInfo _wt({
  String path = '/src/wt/gbm-lfs',
  String headOid = '9d02f4e',
  bool detached = false,
  bool prunable = false,
  DateTime? createdAt,
  int? pendingChanges,
  WorktreePendingCountState pendingCountState =
      WorktreePendingCountState.unmeasured,
}) => WorktreeInfo(
  path: path,
  headOid: headOid,
  branch: 'feature/lfs',
  isMain: false,
  isBare: false,
  isDetached: detached,
  isLocked: false,
  lockReason: '',
  isPrunable: prunable,
  prunableReason: '',
  isPrimary: false,
  pendingChanges: pendingChanges,
  pendingCountState: pendingCountState,
  createdAt: createdAt,
);

/// A ref snapshot holding one local branch for `_wt()`'s branch, so the
/// 分支 row has something to resolve ahead/behind against.
RefSnapshot _refsWith({required String upstream, required int ahead}) =>
    RefSnapshot(
      head: const HeadInfo(
        kind: HeadKind.branch,
        branchName: 'main',
        fullRef: 'refs/heads/main',
        target: 'a1b2c3d',
      ),
      refs: <RefInfo>[
        RefInfo(
          fullName: 'refs/heads/feature/lfs',
          shortName: 'feature/lfs',
          kind: RefKind.localBranch,
          target: '9d02f4e',
          upstream: upstream,
          ahead: ahead,
          behind: 0,
          hasTrackingInfo: upstream.isNotEmpty,
          isGone: false,
          isHead: false,
          isSymbolic: false,
          worktreePath: '',
        ),
      ],
      refCountGuardTripped: false,
      totalRefCount: 1,
    );

const Signature _who = Signature(
  name: 'a',
  email: 'a@b.c',
  when: 0,
  tzOffsetMinutes: 0,
);

/// The value of one labelled detail row. Read through [PanelDetailField]
/// rather than `find.text`, because a list row's subtitle carries the same
/// branch name and oid the detail does -- a bare text finder is ambiguous in
/// exactly the cases these assertions are about.
String _detailValue(WidgetTester tester, String label) => tester
    .widgetList<PanelDetailField>(find.byType(PanelDetailField))
    .firstWhere((PanelDetailField f) => f.label == label)
    .value;

/// 'enabled'/'disabled' rather than a raw null check, so a failure message
/// names the state instead of printing `<null>`.
String _removeGate(WidgetTester tester) =>
    panelButton(tester, 'Remove worktree…').onPressed == null
    ? 'disabled'
    : 'enabled';

Future<void> _type(WidgetTester tester, String query) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(PanelFilterField),
      matching: find.byType(TextField),
    ),
    query,
  );
  await tester.pumpAndSettle();
}

int _requests(PumpedPanel pumped) => pumped.fake.commandLog
    .where((FakeCommand c) => c.name == 'requestWorktreePendingCounts')
    .length;

/// Counts, rather than `.any`, because a selection that dispatched twice is
/// exactly the regression these tests exist to catch ([TEST-count-dont-any]).
int _metaRequests(PumpedPanel pumped, String oid) => pumped.fake.commandLog
    .where(
      (FakeCommand c) =>
          c.name == 'requestCommitMeta' &&
          (c.args['oids']! as List<String>).contains(oid),
    )
    .length;

Future<PumpedPanel> _pump(
  WidgetTester tester, {
  List<WorktreeInfo> worktrees = const <WorktreeInfo>[_main, _locked],
  RefSnapshot? refs,
  List<RouteBase> extraRoutes = const <RouteBase>[],
}) => pumpPanel(
  tester,
  WorktreesPanel(identity: panelTestIdentity),
  state: RepoSessionState(
    isOpen: true,
    worktrees: worktrees,
    refs: refs ?? RefSnapshot.empty,
  ),
  extraRoutes: extraRoutes,
);

void main() {
  group('WorktreesPanel (spec P19 reference instance)', () {
    // P19 rule 2's four segments, with the mockup's own labels. `Remove` is
    // NOT among them: PANELSPEC's toolbar cell says 「Add、Prune、Open、
    // Remove」, rule 2 says 破壞性動作不放工具列, and the mockup draws
    // 「Remove worktree…」 in the detail action row. Two against one, and the
    // four-word cell is a summary of the panel's *actions* rather than a
    // claim about where they sit -- see docs/reports' P19 section.
    testWidgets(
      'the toolbar carries rule 2\'s segments, and no danger action',
      (tester) async {
        await _pump(tester);

        // The shared assertion the other eleven panels state the same way.
        // It checks more than the block it replaced: segment membership is
        // positional (「Prune」 being *on* the toolbar never said it was in
        // the maintenance segment) and each segment's button kind is
        // checked, so a primary-styled maintenance button now fails.
        expectPanelTemplate(
          tester,
          primary: const <String>['Add worktree…'],
          maintenance: const <String>['Prune'],
          external: const <String>['Open in terminal'],
          notOnToolbar: const <String>['Remove'],
          listHeader: 'Worktrees · 2',
          statusBar: RegExp(r'^2 worktrees · 掃描 \d+ ms$'),
        );
      },
    );

    // 「右端固定是 filter」 -- asserted against the toolbar's own right edge
    // rather than a pixel constant ([FLU-finder-proves-existence-not-position]).
    testWidgets('the filter is pinned to the toolbar\'s right end', (
      tester,
    ) async {
      await _pump(tester);

      final Rect filter = tester.getRect(find.byType(PanelFilterField));
      final Rect row = tester.getRect(find.byType(PanelToolbarRow));
      expect(filter.right, closeTo(row.right - GbmSpacing.space3, 0.5));
    });

    testWidgets('the list shows name, branch and status per row', (
      tester,
    ) async {
      await _pump(tester);

      // 名稱 (base name, not the full path -- the path is detail-column
      // content), 分支, 狀態. The name appears twice once a row is selected
      // (row + detail title), so this asserts on the list column only.
      expect(
        find.descendant(
          of: find.byType(PanelListRow),
          matching: find.text('git-branch-manager'),
        ),
        findsOneWidget,
      );
      // 'current', not 'main': the flag says which worktree the session is
      // open on, and P19's mockup badges it `current` for that reason.
      expect(find.text('main · current'), findsOneWidget);
      expect(find.text('gbm-lfs'), findsOneWidget);
      expect(find.text('feature/lfs · locked'), findsOneWidget);
    });

    testWidgets('the list column carries the mockup\'s counted header', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Worktrees · 2'), findsOneWidget);
    });

    // P19 rule 2 pins a filter to the toolbar's right end, and 「接了卻不篩
    // 的 filter 是會說謊的控制項」 -- so the predicate, the header count and
    // the status line's 命中 clause are asserted together. Without these the
    // whole filter mutates to `return true` with the file staying green,
    // which is what it did until this test existed.
    testWidgets('the filter narrows the list, the header and the status line', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.byType(PanelListRow), findsNWidgets(2));

      await _type(tester, 'lfs');

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('gbm-lfs'), findsOneWidget);
      expect(find.text('Worktrees · 1'), findsOneWidget);
      // 命中 sits between the count and the scan time, and appears only
      // because shown != total -- an unfiltered list must not print it.
      expect(
        find.textContaining(RegExp(r'^2 worktrees · 命中 1 · 掃描 \d+ ms$')),
        findsOneWidget,
      );
    });

    // The branch is matched as well as the path, and this is the case that
    // tells the two apart: the row's *title* is 「gbm-lfs」, so a filter
    // reading only what the row draws would drop this worktree entirely.
    testWidgets('the filter matches a branch name the row never draws', (
      tester,
    ) async {
      await _pump(tester);

      await _type(tester, 'feature');

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('gbm-lfs'), findsOneWidget);
    });

    // Two different empty states, and they must not be confused: 「no
    // worktrees」 tells the user this repository has none, which is a lie
    // while a filter is hiding two.
    testWidgets('a query that matches nothing says so as a filter miss', (
      tester,
    ) async {
      await _pump(tester);

      await _type(tester, 'zzzz');

      expect(find.byType(PanelListRow), findsNothing);
      expect(find.text('No worktree matches the filter'), findsOneWidget);
      expect(find.text('No worktrees'), findsNothing);
      expect(find.text('Worktrees · 0'), findsOneWidget);
    });

    // The mockup names exactly three glyphs, and only for this panel.
    testWidgets('each row carries the glyph its state calls for', (
      tester,
    ) async {
      await _pump(
        tester,
        worktrees: <WorktreeInfo>[
          _wt(path: '/a/plain'),
          _wt(path: '/a/detached', detached: true),
          _wt(path: '/a/gone', prunable: true),
        ],
      );

      String glyphAt(int index) => tester
          .widgetList<LucideIcon>(
            find.descendant(
              of: find.byType(PanelListRow).at(index),
              matching: find.byType(LucideIcon),
            ),
          )
          .single
          .name;

      expect(glyphAt(0), 'folder-git-2');
      expect(glyphAt(1), 'git-commit-horizontal');
      expect(glyphAt(2), 'alert-triangle');
    });

    testWidgets('the warning glyph is drawn in the warning colour', (
      tester,
    ) async {
      await _pump(
        tester,
        worktrees: <WorktreeInfo>[_wt(path: '/a/gone', prunable: true)],
      );

      final LucideIcon icon = tester.widget<LucideIcon>(
        find.descendant(
          of: find.byType(PanelListRow),
          matching: find.byType(LucideIcon),
        ),
      );
      // Compared as ARGB32: Paint/Color quantise on read-back, so an
      // identity comparison prints Expected and Actual identically when it
      // fails ([FLU-paint-color-quantises]).
      expect(icon.color?.toARGB32(), gbmColorsFor(tester).warning.toARGB32());
    });

    // 「其餘不存在」 is asserted as findsNothing rather than as an empty
    // string: a badge drawn with no text still takes space and still reads
    // as a chip.
    testWidgets('badges appear only where the mockup draws one', (
      tester,
    ) async {
      await _pump(
        tester,
        worktrees: <WorktreeInfo>[
          _wt(path: '/a/plain'),
          _wt(path: '/a/gone', prunable: true),
        ],
      );

      expect(find.text('路徑不存在'), findsOneWidget);

      await _pump(tester, worktrees: <WorktreeInfo>[_main]);
      expect(find.text('current'), findsOneWidget);
    });

    // The mockup's badge slot is a bare styled span, not a chip:
    //
    //   <span style="font-size:9px;color:var(--text-tertiary);
    //                flex-shrink:0">{{ w.badge }}</span>
    //
    // A GbmBadge is a pill -- background, border radius, padding -- which is
    // the whole of the user's report 「current 沒有底色、也不是 button」.
    testWidgets('the badge is plain text, not a chip', (tester) async {
      await _pump(tester, worktrees: <WorktreeInfo>[_main]);

      expect(find.byType(GbmBadge), findsNothing);

      final Text badge = tester.widget<Text>(find.text('current'));
      expect(
        badge.style?.color?.toARGB32(),
        gbmColorsFor(tester).textTertiary.toARGB32(),
      );
      expect(badge.style?.fontSize, GbmTypography.textXs);
    });

    // `current` and `路徑不存在` share one slot and one style in the mockup
    // (`badge: w.cur ? 'current' : w.gone ? '路徑不存在' : ''`, rendered by a
    // single span), so the gone one must not be recoloured either. The
    // warning colour lives on the row's *name* and its glyph.
    testWidgets('the gone badge carries no warning colour of its own', (
      tester,
    ) async {
      await _pump(
        tester,
        worktrees: <WorktreeInfo>[_wt(path: '/a/gone', prunable: true)],
      );

      final GbmColors colors = gbmColorsFor(tester);
      final Text badge = tester.widget<Text>(find.text('路徑不存在'));
      expect(badge.style?.color?.toARGB32(), colors.textTertiary.toARGB32());

      // `color: {{ w.color }}` on the name, where
      // `w.color = w.gone ? 'var(--warning)' : 'var(--text-primary)'`.
      final Text name = tester.widget<Text>(find.text('gone'));
      expect(name.style?.color?.toARGB32(), colors.warning.toARGB32());
    });

    testWidgets('a healthy row keeps its ordinary name colour', (tester) async {
      await _pump(tester, worktrees: <WorktreeInfo>[_wt(path: '/a/plain')]);

      final Text name = tester.widget<Text>(find.text('plain'));
      expect(
        name.style?.color?.toARGB32(),
        gbmColorsFor(tester).textPrimary.toARGB32(),
      );
    });

    testWidgets('the detail pane is empty until a row is selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(find.text('Select a worktree to see its details'), findsOneWidget);
    });

    // The mockup's five rows, in its order. Asserted as an ordered list
    // rather than five findsOneWidget calls, because rule 4 makes the detail
    // a definition list and a definition list's order is part of it.
    testWidgets('the detail is the mockup\'s five labelled rows, in order', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();

      final List<String> labels = tester
          .widgetList<PanelDetailField>(find.byType(PanelDetailField))
          .map((PanelDetailField f) => f.label)
          .toList();
      expect(
        labels.take(5),
        <String>['路徑', '分支', 'HEAD', '狀態', '建立於'],
        reason: 'the five unconditional rows come first, in this order',
      );
      expect(
        labels,
        contains('Lock reason'),
        reason: 'and the conditional ones follow rather than interleave',
      );
      expect(find.text('/src/wt/gbm-lfs'), findsOneWidget);
      expect(find.text('on the USB drive'), findsOneWidget);
    });

    // 「main ↑2」. RefInfo.ahead means nothing when upstream is empty
    // ([REF-ahead-meaningless-without-upstream]) -- a branch that never had
    // one reports 0, and rendering that literally claims the opposite of the
    // truth -- so the arrow is gated on the upstream, not on the number.
    testWidgets('分支 shows ahead only when there is an upstream', (
      tester,
    ) async {
      await _pump(
        tester,
        worktrees: <WorktreeInfo>[_wt()],
        refs: _refsWith(upstream: 'refs/remotes/origin/feature/lfs', ahead: 2),
      );
      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();
      expect(_detailValue(tester, '分支'), 'feature/lfs ↑2');

      await _pump(
        tester,
        worktrees: <WorktreeInfo>[_wt()],
        refs: _refsWith(upstream: '', ahead: 2),
      );
      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();
      expect(_detailValue(tester, '分支'), 'feature/lfs');
    });

    // 「a1b2c3d · Fix lane allocator overflow」. Both fixtures are pumped,
    // because the cache-miss frame is the normal one: the subject is
    // requested when the selection changes, so the first frame after every
    // click has only the oid.
    testWidgets('HEAD gains its subject once the commit meta arrives', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[_wt()],
      );
      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();
      expect(_detailValue(tester, 'HEAD'), '9d02f4e');

      pumped.fake.emit(
        pumped.fake.state.copyWith(
          commitMetaCache: <String, CommitMeta>{
            '9d02f4e': const CommitMeta(
              oid: '9d02f4e',
              tree: 'tree',
              parents: <String>[],
              author: _who,
              committer: _who,
              subject: 'Fix lane allocator overflow',
              body: '',
              signedCommit: false,
            ),
          },
        ),
      );
      await tester.pumpAndSettle();
      expect(
        _detailValue(tester, 'HEAD'),
        '9d02f4e · Fix lane allocator overflow',
      );
    });

    // The test above emits the meta by hand, which is a fixture supplying
    // what production must *ask* for -- [CULT-scrutinise-the-comment] applied
    // to this file's own earlier comment, which claimed the subject was
    // requested on selection while nothing in the panel requested anything.
    // Without this dispatch a linked worktree on an old branch tip shows a
    // bare oid forever, because the only other filler of `commitMetaCache`
    // is History's viewport happening to scroll past that commit.
    testWidgets('selecting a worktree asks for its HEAD commit meta', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[_wt()],
      );
      expect(
        _metaRequests(pumped, '9d02f4e'),
        0,
        reason: 'nothing is selected on mount',
      );

      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();

      expect(_metaRequests(pumped, '9d02f4e'), 1);
    });

    // The gate is the cache, not the tap: re-selecting a worktree whose
    // subject is already on screen must not re-ask. Dispatching from `onTap`
    // (a user action) rather than from `build` is what keeps this bounded --
    // a build-driven request would re-fire on every republish.
    testWidgets('a HEAD whose meta is already cached is not re-requested', (
      tester,
    ) async {
      final PumpedPanel pumped = await pumpPanel(
        tester,
        WorktreesPanel(identity: panelTestIdentity),
        state: RepoSessionState(
          isOpen: true,
          worktrees: <WorktreeInfo>[_wt()],
          refs: RefSnapshot.empty,
          commitMetaCache: <String, CommitMeta>{
            '9d02f4e': const CommitMeta(
              oid: '9d02f4e',
              tree: 'tree',
              parents: <String>[],
              author: _who,
              committer: _who,
              subject: 'Fix lane allocator overflow',
              body: '',
              signedCommit: false,
            ),
          },
        ),
      );

      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();

      expect(
        _detailValue(tester, 'HEAD'),
        '9d02f4e · Fix lane allocator overflow',
      );
      expect(_metaRequests(pumped, '9d02f4e'), 0);
    });

    testWidgets('狀態 joins the count and the lock state', (tester) async {
      await _pump(
        tester,
        worktrees: <WorktreeInfo>[
          _wt(
            pendingChanges: 9,
            pendingCountState: WorktreePendingCountState.measured,
          ),
        ],
      );
      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();

      expect(find.text('9 個未提交變更 · 未鎖定'), findsOneWidget);
    });

    // Rule 4 says the detail is 一律 a 78px definition list, so a row that
    // vanishes when git has no answer would make the panel's shape depend on
    // the item. The row stays and says git did not record it.
    testWidgets('建立於 draws git\'s silence rather than disappearing', (
      tester,
    ) async {
      await _pump(tester, worktrees: <WorktreeInfo>[_wt()]);
      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();
      expect(find.text('git 未記錄'), findsOneWidget);

      await _pump(
        tester,
        worktrees: <WorktreeInfo>[_wt(createdAt: DateTime(2026, 6, 2, 14, 41))],
      );
      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();
      expect(find.text('2026-06-02 14:41'), findsOneWidget);
    });

    testWidgets('the jump-out action is disabled with nothing selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(panelButton(tester, 'Open in terminal').onPressed, isNull);
      expect(
        find.text('Remove worktree…'),
        findsNothing,
        reason: 'the detail action row has no subject yet',
      );
    });

    // Rule 4's action row: the mockup's four slots, with danger last and
    // hard against the row's right edge. Asserted as an *equality* of right
    // edges: 「danger is to the right」 is true under spaceBetween and under
    // start alike, so it cannot fail ([TEST-fixture-cannot-disagree] #8).
    testWidgets('the detail action row puts danger against its right edge', (
      tester,
    ) async {
      // A non-locked worktree: the button reads Unlock for a locked one,
      // and the mockup's row is the unlocked case.
      await _pump(tester, worktrees: <WorktreeInfo>[_main, _wt()]);
      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();

      for (final String label in const <String>[
        'Switch to',
        'Lock',
        'Remove worktree…',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
      expectDangerPinnedRight(tester, 'Remove worktree…');
    });

    // Two `context.go` calls are indistinguishable by `onPressed != null`
    // ([TEST-fixture-cannot-disagree] #5), so the destination is what is
    // asserted, via a sentinel route.
    testWidgets('Switch to opens that worktree as the repository', (
      tester,
    ) async {
      await _pump(
        tester,
        extraRoutes: <RouteBase>[
          // The real destination is RoutePaths.workspaceFor(), which is
          // historyFor() -- '/repo/:repoId/history'. Spelled out rather than
          // built from the helper, so a change to the helper reddens here
          // instead of quietly agreeing with itself.
          GoRoute(
            path: '/repo/:repoId/history',
            builder: (_, _) => const Text('SWITCHED'),
          ),
        ],
      );
      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Switch to'));
      await tester.pumpAndSettle();

      expect(find.text('SWITCHED'), findsOneWidget);
    });

    // Rule 5. The banner is about a row in the *list*, so it is drawn
    // whenever the exception exists -- not only while that row is selected.
    testWidgets('a gone path raises the mockup\'s banner, verbatim', (
      tester,
    ) async {
      await _pump(tester, worktrees: <WorktreeInfo>[_main, _locked]);
      expect(find.byType(GbmWarningBanner), findsNothing);

      await _pump(
        tester,
        worktrees: <WorktreeInfo>[
          _main,
          _wt(path: '/src/wt/gbm-lfs', prunable: true),
        ],
      );
      expect(
        find.text(
          'gbm-lfs 的路徑已不存在。Prune 會把它從 git 的紀錄中移除，'
          '不會刪任何檔案。',
        ),
        findsOneWidget,
      );
    });

    // Rule 6: 實際數量與耗時. The duration is matched as a pattern, not a
    // number -- it is a real elapsed measurement, so pinning a value would
    // pin the test machine.
    testWidgets('the status bar writes real counts and a real duration', (
      tester,
    ) async {
      await _pump(
        tester,
        worktrees: <WorktreeInfo>[
          _main,
          _locked,
          _wt(path: '/src/wt/gbm-lfs', prunable: true),
        ],
      );

      expect(
        find.textContaining(RegExp(r'^3 worktrees · 1 個路徑失效 · 掃描 \d+ ms$')),
        findsOneWidget,
      );
    });

    // ...and the 路徑失效 clause is dropped rather than written as 0, which
    // is what makes the number above a real count instead of a template.
    testWidgets('the status bar omits the failure clause when there is none', (
      tester,
    ) async {
      await _pump(tester, worktrees: <WorktreeInfo>[_main, _locked]);

      expect(
        find.textContaining(RegExp(r'^2 worktrees · 掃描 \d+ ms$')),
        findsOneWidget,
      );
    });

    // git refuses to remove the repository's *primary* worktree, so the
    // button must not offer to.
    testWidgets('Remove stays disabled for the primary worktree', (
      tester,
    ) async {
      await _pump(tester);

      await tester.tap(find.text('git-branch-manager'));
      await tester.pumpAndSettle();

      expect(panelButton(tester, 'Open in terminal').onPressed, isNotNull);
      expect(_removeGate(tester), 'disabled');
    });

    // The case the gate used to get backwards, and the one no fixture here
    // could express while `isMain` was doing both jobs: gbm opened on a
    // *linked* worktree. `isMain` marks the linked one (it is "current"),
    // `isPrimary` marks the repository's main one, and they are different
    // rows. Gating on `isMain` blocked the row the user is standing in --
    // which git removes happily -- and offered the primary one, which git
    // refuses.
    testWidgets(
      'opened on a linked worktree, Remove follows primary and not current',
      (tester) async {
        const WorktreeInfo primaryNotCurrent = WorktreeInfo(
          path: '/src/git-branch-manager',
          headOid: 'a1b2c3d',
          branch: 'main',
          isMain: false,
          isBare: false,
          isDetached: false,
          isLocked: false,
          lockReason: '',
          isPrunable: false,
          prunableReason: '',
          isPrimary: true,
          pendingChanges: null,
          pendingCountState: WorktreePendingCountState.unmeasured,
          createdAt: null,
        );
        const WorktreeInfo currentNotPrimary = WorktreeInfo(
          path: '/src/wt/gbm-lfs',
          headOid: '9d02f4e',
          branch: 'feature/lfs',
          isMain: true,
          isBare: false,
          isDetached: false,
          isLocked: false,
          lockReason: '',
          isPrunable: false,
          prunableReason: '',
          isPrimary: false,
          pendingChanges: null,
          pendingCountState: WorktreePendingCountState.unmeasured,
          createdAt: null,
        );
        await _pump(
          tester,
          worktrees: const <WorktreeInfo>[primaryNotCurrent, currentNotPrimary],
        );

        await tester.tap(find.text('gbm-lfs'));
        await tester.pumpAndSettle();
        expect(
          _removeGate(tester),
          'enabled',
          reason: 'the worktree the session is open on is removable',
        );

        await tester.tap(find.text('git-branch-manager'));
        await tester.pumpAndSettle();
        expect(
          _removeGate(tester),
          'disabled',
          reason: 'the primary worktree is not, whoever is standing where',
        );
      },
    );

    testWidgets('Remove worktree… dispatches for a non-primary worktree', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester);

      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove worktree…'));
      await tester.pumpAndSettle();

      expect(
        pumped.fake.commandLog
            .where((FakeCommand c) => c.name == 'removeWorktree')
            .length,
        1,
      );
    });

    testWidgets('an empty repository shows an empty-list message', (
      tester,
    ) async {
      await _pump(tester, worktrees: const <WorktreeInfo>[]);

      expect(find.text('No worktrees'), findsOneWidget);
    });
  });

  // P19's PANELSPEC detail cell for this panel lists 待提交數, and it now has
  // a source: gbm_worktree_request_pending_counts(). The panel asks for it
  // itself, because the count is NOT part of refreshRepoStatus()'s sweep --
  // see [STATE-refresh-entry-point] and the controller's doc comment.
  //
  // Every test below counts dispatches rather than inspecting the cache.
  // [CULT-cache-documents-three-things] requires counting precisely because
  // "a cache that recomputed every time and answered correctly is
  // indistinguishable from a working one by its output" -- and here the
  // recomputation *is* the dispatch, so the dispatch count is the instrument.
  group('WorktreesPanel pending-change counts', () {
    testWidgets('mounting asks for the counts exactly once', (tester) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[_wt()],
      );

      expect(_requests(pumped), 1);
    });

    testWidgets('a republish of the same path@headOid does not re-ask', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[_wt()],
      );

      pumped.fake.emit(
        pumped.fake.state.copyWith(
          worktrees: <WorktreeInfo>[
            _wt(
              pendingChanges: 9,
              pendingCountState: WorktreePendingCountState.measured,
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(_requests(pumped), 1);
    });

    // The loop case, on its own because it is the one that spins. A failed
    // measurement leaves no count, so a gate reading "some count is null"
    // re-asks forever -- every republish, every focus refresh, for as long
    // as the panel is open. The gate reads "some key was never asked".
    testWidgets('a failed measurement is an answer, and is not re-asked', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[_wt()],
      );

      for (int i = 0; i < 3; i++) {
        pumped.fake.emit(
          pumped.fake.state.copyWith(
            worktrees: <WorktreeInfo>[
              _wt(pendingCountState: WorktreePendingCountState.failed),
            ],
          ),
        );
        await tester.pumpAndSettle();
      }

      expect(_requests(pumped), 1);
    });

    // add / remove / prune all change a path, and a checkout changes the
    // oid, so a key that is genuinely new is exactly when the count can have
    // changed -- and exactly when one more request is owed.
    testWidgets('a worktree at a new path is asked for once', (tester) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[_wt()],
      );

      pumped.fake.emit(
        pumped.fake.state.copyWith(
          worktrees: <WorktreeInfo>[
            _wt(),
            _wt(path: '/src/wt/gbm-docs'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(_requests(pumped), 2);
    });

    // The other half of the key, and the half no other test here varies:
    // a checkout inside a worktree keeps its path and changes its oid, and
    // the count can change with it. Without this case a key of `path` alone
    // would be indistinguishable from `path@headOid`.
    testWidgets('a worktree moved to a new commit is asked about again', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[_wt()],
      );

      pumped.fake.emit(
        pumped.fake.state.copyWith(
          worktrees: <WorktreeInfo>[_wt(headOid: 'ff17a20')],
        ),
      );
      await tester.pumpAndSettle();

      expect(_requests(pumped), 2);
    });

    testWidgets('a measured count is shown in the detail column', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[
          _wt(
            pendingChanges: 9,
            pendingCountState: WorktreePendingCountState.measured,
          ),
        ],
      );
      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();

      expect(_detailValue(tester, '狀態'), '9 個未提交變更 · 未鎖定');
      expect(_requests(pumped), 1);
    });

    // The symptom the cache exists to prevent, and the only test that can
    // see it: a plain refreshWorktrees() (the focus sweep runs one every
    // 2 seconds of alt-tabbing) republishes every worktree as `unmeasured`,
    // because measuring is a separate request. Without the cache the number
    // in front of the user blinks back to 「未量測」 on a timer.
    testWidgets('a measured count survives a republish that says unmeasured', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[
          _wt(
            pendingChanges: 9,
            pendingCountState: WorktreePendingCountState.measured,
          ),
        ],
      );
      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();

      pumped.fake.emit(
        pumped.fake.state.copyWith(worktrees: <WorktreeInfo>[_wt()]),
      );
      await tester.pumpAndSettle();

      expect(_detailValue(tester, '狀態'), '9 個未提交變更 · 未鎖定');
    });
  });

  // 使用者裁定推翻本輪原本的「沒有面板內重試入口」。原本的理由是「規則 2 的
  // 四段工具列沒有位置放它」——那個理由本身沒錯，錯在停在那裡：規則 4 給了
  // 明細動作列，而那正是每一列自己的動作該待的地方，也剛好就在寫著
  //「量測失敗」的那一格底下。
  group('P19 rule 4: a failed pending count can be retried in the panel', () {
    testWidgets('the retry dispatches a second measurement', (tester) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[
          _wt(pendingCountState: WorktreePendingCountState.failed),
        ],
      );
      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();
      expect(_detailValue(tester, '狀態'), '量測失敗 · 未鎖定');

      final int before = _requests(pumped);
      await tester.tap(find.widgetWithText(GbmButton, '重新量測'));
      await tester.pumpAndSettle();

      // Count, never `.any` -- a retry that dispatched twice per tap is the
      // shape [TEST-count-dont-any] exists for.
      expect(_requests(pumped), before + 1);
    });

    // The other half of「不是隱藏」。A button that is simply absent whenever
    // it would not work teaches the user the feature does not exist
    // ([FLU-menu-enabled-is-visual-only]), and `onTap: null` has to come with
    // the grey or a 「disabled」 button still fires.
    testWidgets('it is present but disabled when the count is measured', (
      tester,
    ) async {
      await _pump(
        tester,
        worktrees: <WorktreeInfo>[
          _wt(
            pendingChanges: 9,
            pendingCountState: WorktreePendingCountState.measured,
          ),
        ],
      );
      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();

      final GbmButton retry = tester.widget<GbmButton>(
        find.widgetWithText(GbmButton, '重新量測'),
      );
      expect(
        retry.onPressed,
        isNull,
        reason: 'nothing failed, nothing to redo',
      );
    });

    testWidgets('an unmeasured worktree can also be asked again', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(
        tester,
        worktrees: <WorktreeInfo>[
          _wt(pendingCountState: WorktreePendingCountState.unmeasured),
        ],
      );
      await tester.tap(find.text('gbm-lfs'));
      await tester.pumpAndSettle();

      final int before = _requests(pumped);
      await tester.tap(find.widgetWithText(GbmButton, '重新量測'));
      await tester.pumpAndSettle();
      expect(_requests(pumped), before + 1);
    });
  });
}
