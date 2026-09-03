import 'package:flutter/material.dart';
import 'package:gbm_flutter/data/repositories/panel_tabs_repository.dart';
import 'package:gbm_flutter/features/panels/panel_storage_id.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/commit_meta.dart';
import '../../data/models/ref_snapshot.dart';
import '../../data/models/worktree_info.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../data/services/desktop_launcher.dart';
import '../../routing/app_router.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_banner.dart';
import '../../widgets/gbm_button.dart';
import '../../widgets/lucide_icon.dart';
import 'panel_filter_field.dart';
import 'panel_status_line.dart';
import 'panel_toolbar_spec.dart';
import 'gbm_panel_tab_shell.dart';
import 'panel_widgets.dart';

/// `manage-worktrees` as a tab, and spec page 19's **reference instance**:
/// the other eleven panels "只換欄位不換造型", so this is the one to copy.
///
/// P19's `PANELSPEC` row for this panel:
/// - list: worktree 名稱 + 分支 + 狀態
/// - detail: 路徑、HEAD、待提交數、鎖定原因
/// - toolbar: Add、Prune、Open、Remove
///
/// **Both halves of the old 「待提交數 is absent」 note are now false, and the
/// note is struck rather than deleted** (the #45/#50/#51/#60 precedent): it
/// said `WorktreeInfo` carried no count and `gbm_capi.h` had no per-worktree
/// status call, because a status read was scoped to the session's own work
/// dir. `gbm_worktree_request_pending_counts()` is that call, and
/// `WorktreeInfo.pendingChanges` is that count. Leaving the note standing
/// would invite a later round to re-file the field as unimplementable on
/// grounds already overruled.
class WorktreesPanel extends ConsumerStatefulWidget {
  const WorktreesPanel({super.key, required this.identity});

  final RepoIdentity identity;

  @override
  ConsumerState<WorktreesPanel> createState() => _WorktreesPanelState();
}

/// One worktree's answer to "how many uncommitted changes?", as cached by
/// the panel. [count] is null unless [state] is
/// [WorktreePendingCountState.measured].
typedef _CountAnswer = ({int? count, WorktreePendingCountState state});

class _WorktreesPanelState extends ConsumerState<WorktreesPanel> {
  /// Which `path@headOid` keys have already been asked about.
  ///
  /// **This, not "which counts are still null", is the request gate**, and
  /// the difference is the whole of this cache's loop safety. A measurement
  /// that fails leaves no count, so a null-based gate re-asks on every
  /// republish -- including the one the failed request itself triggers --
  /// for as long as the panel stays open. A key is asked about once and
  /// then never again, whichever of the four answers comes back, and a
  /// request that produces no reply at all still leaves its key here.
  final Set<String> _askedCountKeys = <String>{};

  /// The answers, so a republish that says `unmeasured` does not blank a
  /// number the user is looking at.
  ///
  /// [CULT-cache-documents-three-things]:
  /// - **Key**: `path@headOid`. A worktree moved to a new commit is exactly
  ///   when its count must be re-measured; lock/unlock change neither, so
  ///   the count survives them, which is the point.
  /// - **Invalidated by**: *no event at all*. The key is the invalidation --
  ///   the same shape as `UntrackedLineCountCache` in the core, and for the
  ///   same reason: nothing emits an event when the answer goes stale.
  /// - **Symptom if missed**: the count blinks back to 「未量測」 every time
  ///   anything republishes the worktree list, which the focus sweep does
  ///   at most every 2 seconds while the user alt-tabs.
  final Map<String, _CountAnswer> _countAnswers = <String, _CountAnswer>{};

  String? _selectedPath;
  String _query = '';

  /// Rule 6's 耗時. Measures **mount to the first frame that has the list**
  /// -- i.e. how long the user waited to see data, which in production is
  /// dominated by the `git worktree list` round trip the panel dispatches in
  /// initState. Stopped exactly once; a later republish is a refresh of a
  /// list already on screen, not a scan the user is waiting on.
  final Stopwatch _scanWatch = Stopwatch();
  int? _scanMs;

  @override
  void initState() {
    super.initState();
    _scanWatch.start();
    Future.microtask(
      () => ref
          .read(repoSessionProvider(widget.identity).notifier)
          .refreshWorktrees(),
    );
  }

  RepoSessionController get _session =>
      ref.read(repoSessionProvider(widget.identity).notifier);

  static String _countKey(WorktreeInfo w) => '${w.path}@${w.headOid}';

  /// Files every answer that arrived, then asks once for any key never
  /// asked about. Called from `build`, which is why the *request* is
  /// deferred: dispatching to the controller from inside a build is the
  /// provider write [FLU-never-write-provider-in-build] forbids, and its
  /// guard is `assert`-wrapped, so release would let it land mid-frame.
  ///
  /// The bookkeeping is not deferred: `_askedCountKeys` is written
  /// synchronously so a second build in the same frame cannot queue a
  /// second request for the same keys.
  void _harvestAndRequestCounts(List<WorktreeInfo> worktrees) {
    for (final WorktreeInfo w in worktrees) {
      if (w.pendingCountState == WorktreePendingCountState.unmeasured) {
        continue;
      }
      _countAnswers[_countKey(w)] = (
        count: w.pendingChanges,
        state: w.pendingCountState,
      );
    }

    final Iterable<String> keys = worktrees.map(_countKey);
    if (keys.every(_askedCountKeys.contains)) return;
    _askedCountKeys.addAll(keys);

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _session.requestWorktreePendingCounts();
    });
    // addPostFrameCallback does not itself ask for a frame
    // ([FLU-postframe-no-frame]): it registers for the end of the *next*
    // one, and if nothing else schedules one it simply never runs.
    SchedulerBinding.instance.ensureVisualUpdate();
  }

  void _stopScanTimer(List<WorktreeInfo> worktrees) {
    if (!_scanWatch.isRunning || worktrees.isEmpty) return;
    _scanWatch.stop();
    _scanMs = _scanWatch.elapsedMilliseconds;
  }

  /// The cached answer for [w], falling back to whatever the live snapshot
  /// says. Reading the cache first is what survives an `unmeasured`
  /// republish.
  _CountAnswer _answerFor(WorktreeInfo w) =>
      _countAnswers[_countKey(w)] ??
      (count: w.pendingChanges, state: w.pendingCountState);

  /// Whether 「重新量測」 can do anything for [w].
  ///
  /// `failed` is the case this exists for: the cache deliberately files a
  /// failure so the automatic gate does not re-ask forever, which without a
  /// manual way back means one failed measurement stays failed until the tab
  /// is closed and reopened. `unmeasured` is included because a reply that
  /// never arrived is the same dead end from the user's side.
  ///
  /// `notApplicable` is **not** retryable, and that is not a shortcut: it
  /// means bare-or-prunable, where the command cannot run at all rather than
  /// having run and lost ([STATE-never-guess-what-git-would-say]'s LFS
  /// exemption). Offering a retry there would promise something no number of
  /// presses can deliver. `measured` has nothing to redo.
  bool _canRemeasure(WorktreeInfo w) => switch (_answerFor(w).state) {
    WorktreePendingCountState.failed ||
    WorktreePendingCountState.unmeasured => true,
    WorktreePendingCountState.measured ||
    WorktreePendingCountState.notApplicable => false,
  };

  /// Forgets what is known about [w]'s count and asks again.
  ///
  /// The eviction is **not** redundant with `_harvestAndRequestCounts`
  /// overwriting the entry when the reply lands. That overwrite is
  /// unconditional today, so dropping these two lines leaves every test
  /// green — but 「retry」 means *forget and re-ask*, and expressing it as
  /// "dispatch, and rely on a distant unconditional write" makes this button
  /// depend on a policy nothing here owns. `_askedCountKeys` has to go too or
  /// the automatic gate still counts this key as asked.
  void _remeasure(WorktreeInfo w) {
    final String key = _countKey(w);
    _countAnswers.remove(key);
    _askedCountKeys.remove(key);
    _session.requestWorktreePendingCounts();
  }

  /// P19's 待提交數 value. All four states read differently to a user, so
  /// this switches on the state rather than on `count == null`.
  static String _describePendingCount(_CountAnswer answer) =>
      switch (answer.state) {
        WorktreePendingCountState.measured => '${answer.count} 個未提交變更',
        WorktreePendingCountState.unmeasured => '未量測',
        WorktreePendingCountState.notApplicable => '不適用',
        WorktreePendingCountState.failed => '量測失敗',
      };

  /// The 分支 + 狀態 half of P19's list row (the 名稱 half is the path's base
  /// name). Every flag git reports is shown rather than only the first, so a
  /// worktree that is both locked and prunable does not look like one that
  /// is merely locked.
  String _describe(WorktreeInfo w) {
    final String status = <String>[
      if (w.isMain) 'current',
      if (w.isLocked) 'locked',
      if (w.isPrunable) 'prunable',
      if (w.isBare) 'bare',
    ].join(' · ');
    return <String>[
      w.isDetached ? 'detached' : w.branch,
      if (status.isNotEmpty) status,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    // Watches a record of exactly the three fields this panel renders, not
    // the whole session ([FLU-watch-a-record-not-the-state]). `refs` and
    // `commitMetaCache` are here because the 分支 and HEAD rows read them:
    // watching only `worktrees` left the commit subject frozen on whatever
    // frame it happened to arrive on, since nothing else republishes the
    // worktree list when a meta lands.
    final (
      List<WorktreeInfo> worktrees,
      RefSnapshot refSnapshot,
      Map<String, CommitMeta> metas,
    ) = ref.watch(
      repoSessionProvider(
        widget.identity,
      ).select((state) => (state.worktrees, state.refs, state.commitMetaCache)),
    );
    _harvestAndRequestCounts(worktrees);
    _stopScanTimer(worktrees);

    // Computed once and read by the header, the status bar and the list, so
    // the three cannot disagree about how many worktrees there are
    // ([CULT-single-source-of-truth]).
    final List<WorktreeInfo> visible = worktrees
        .where(_matchesQuery)
        .toList(growable: false);
    final int goneCount = worktrees.where((w) => w.isPrunable).length;

    // Selection is held by path rather than index so a refresh that reorders
    // or removes rows can't silently point the detail pane at a different
    // worktree than the one the user clicked.
    final WorktreeInfo? selected = worktrees
        .where((WorktreeInfo w) => w.path == _selectedPath)
        .firstOrNull;

    return GbmPanelTabShell(
      storageId: panelStorageId(GbmPanelKind.manageWorktrees),
      detailIsEmpty: selected == null,
      emptyDetailMessage: 'Select a worktree to see its details',
      toolbar: PanelToolbarSpec(
        primary: <Widget>[
          GbmButton(
            label: 'Add worktree…',
            kind: GbmButtonKind.primary,
            onPressed: () => context.push(
              RoutePaths.addWorktreeDialogFor(
                repoIdFor(widget.identity.workDir),
              ),
            ),
          ),
        ],
        maintenance: <Widget>[
          GbmButton(
            label: 'Prune',
            kind: GbmButtonKind.ghost,
            onPressed: _session.pruneWorktrees,
          ),
        ],
        external: <Widget>[
          // 'Open in terminal', per the mockup, and it reaches the terminal
          // chain that already exists for Repository → Open in terminal --
          // this used to call openInFileManager(), which is a different
          // application.
          GbmButton(
            label: 'Open in terminal',
            kind: GbmButtonKind.ghost,
            onPressed: selected == null
                ? null
                : () => ref
                      .read(desktopLauncherProvider)
                      .openTerminal(selected.path),
          ),
        ],
        filter: PanelFilterField(
          query: _query,
          onChanged: (String value) => setState(() => _query = value),
        ),
      ),
      banner: goneCount == 0
          ? null
          : GbmWarningBanner(message: _goneBannerMessage(worktrees)),
      listHeader: PanelListHeaderText(text: 'Worktrees · ${visible.length}'),
      statusBar: PanelStatusBarText(
        text: _statusLine(
          total: worktrees.length,
          shown: visible.length,
          gone: goneCount,
        ),
      ),
      list: visible.isEmpty
          ? PanelEmptyList(
              message: worktrees.isEmpty
                  ? 'No worktrees'
                  : 'No worktree matches the filter',
            )
          : ListView.builder(
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final WorktreeInfo w = visible[index];
                return PanelListRow(
                  title: w.path.split('/').last,
                  subtitle: _describe(w),
                  selected: w.path == _selectedPath,
                  onTap: () => _select(w, metas),
                  icon: _glyphFor(context, w),
                  badge: _badgeFor(w),
                  titleColor: _titleColorFor(context, w),
                );
              },
            ),
      detail: selected == null
          ? const SizedBox.shrink()
          : _WorktreeDetail(
              worktree: selected,
              title: selected.path.split('/').last,
              branchLine: _branchLine(selected, refSnapshot),
              headLine: _headLine(selected, metas),
              statusLine: _detailStatusLine(selected),
              createdLine: selected.createdAt == null
                  ? 'git 未記錄'
                  : _formatCreatedAt(selected.createdAt!),
            ),
      detailActions: selected == null
          ? null
          : PanelDetailActions(
              actions: <Widget>[
                GbmButton(
                  label: 'Switch to',
                  onPressed: () => context.go(
                    RoutePaths.workspaceFor(repoIdFor(selected.path)),
                  ),
                ),
                GbmButton(
                  label: selected.isLocked ? 'Unlock' : 'Lock',
                  kind: GbmButtonKind.ghost,
                  onPressed: selected.isMain
                      ? null
                      : () => selected.isLocked
                            ? _session.unlockWorktree(selected.path)
                            : _session.lockWorktree(selected.path),
                ),
                GbmButton(
                  label: '重新量測',
                  kind: GbmButtonKind.ghost,
                  onPressed: _canRemeasure(selected)
                      ? () => _remeasure(selected)
                      : null,
                ),
              ],
              dangerActions: <Widget>[
                // Gated on isPrimary, not isMain. isMain means "the worktree
                // this session is open on" -- open gbm on a linked worktree
                // and this button used to refuse the row you are standing in
                // (git removes it happily) while offering the repository's
                // main one (git refuses).
                //
                // Also gated on !isPrunable -- D2's own "notApplicable ->
                // 路徑本來就不在，改走 Prune，這張不會開". Measured: git
                // itself accepts `worktree remove` on a path that is
                // already gone (it just drops the administrative entry,
                // exit 0), so this is a UI consistency choice, not
                // something git refuses -- Prune already does exactly
                // that, in the background, without asking.
                GbmButton(
                  label: 'Remove worktree…',
                  kind: GbmButtonKind.danger,
                  onPressed: selected.isPrimary || selected.isPrunable
                      ? null
                      : () => context.push(
                          RoutePaths.removeWorktreeDialogFor(
                            repoIdFor(widget.identity.workDir),
                            path: selected.path,
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  bool _matchesQuery(WorktreeInfo w) {
    if (_query.trim().isEmpty) return true;
    final String needle = _query.trim().toLowerCase();
    return w.path.toLowerCase().contains(needle) ||
        w.branch.toLowerCase().contains(needle);
  }

  /// The mockup's 「4 worktrees · 1 個路徑失效 · 掃描 118 ms」.
  ///
  /// Rule 6 asks for 實際數量, so a clause whose number is zero is *dropped*
  /// rather than written as 「0 個路徑失效」 -- a template that always prints
  /// every clause is not reporting a count, it is decorating one.
  /// This is the one panel that passes [panelStatusLine]'s `timing` slot, and
  /// the reason is that it is the one panel that measures anything per row --
  /// one `git status` per linked worktree. The other eleven run a single
  /// command, so a 耗時 clause there would be invented rather than reported.
  String _statusLine({
    required int total,
    required int shown,
    required int gone,
  }) => panelStatusLine(
    total: total,
    shown: shown,
    noun: 'worktree',
    setFacts: <String>[if (gone > 0) '$gone 個路徑失效'],
    timing: <String>[if (_scanMs != null) '掃描 $_scanMs ms'],
  );

  /// Names the gone worktrees rather than counting them: the user's next
  /// action is deciding whether to Prune, and 「一個路徑失效」 does not say
  /// which one.
  String _goneBannerMessage(List<WorktreeInfo> worktrees) {
    final String names = worktrees
        .where((WorktreeInfo w) => w.isPrunable)
        .map((WorktreeInfo w) => w.path.split('/').last)
        .join('、');
    return '$names 的路徑已不存在。Prune 會把它從 git 的紀錄中移除，'
        '不會刪任何檔案。';
  }

  /// The mockup's three glyphs, and only these three -- P19 names no icon
  /// for any of the other eleven panels.
  Widget _glyphFor(BuildContext context, WorktreeInfo w) {
    final GbmColors colors = context.gbmColors;
    if (w.isPrunable) {
      return LucideIcon('alert-triangle', size: 12, color: colors.warning);
    }
    return LucideIcon(
      w.isDetached ? 'git-commit-horizontal' : 'folder-git-2',
      size: 12,
      color: colors.textTertiary,
    );
  }

  /// `current` / `路徑不存在`, and **nothing at all** otherwise -- an empty
  /// badge still takes the gap before it.
  ///
  /// One expression, one slot, one style, exactly as the mockup writes it:
  /// `badge: w.cur ? 'current' : w.gone ? '路徑不存在' : ''`. It used to be
  /// two `GbmBadge`s, the second one recoloured `removed` -- a pill with a
  /// background, which is what the user reported as 「current 沒有底色、也不
  /// 是 button」. The alert colour was never the badge's job: it belongs to
  /// the row's name and its `alert-triangle` glyph, both of which say it
  /// already.
  String? _badgeFor(WorktreeInfo w) {
    if (w.isMain) return 'current';
    if (w.isPrunable) return '路徑不存在';
    return null;
  }

  /// `color: {{ w.color }}` on the worktree's name, which the mockup defines
  /// as `w.gone ? 'var(--warning)' : 'var(--text-primary)'`.
  Color? _titleColorFor(BuildContext context, WorktreeInfo w) =>
      w.isPrunable ? context.gbmColors.warning : null;

  /// 「main ↑2」. The arrow is gated on the *upstream*, not on the number:
  /// RefInfo.ahead is meaningless when upstream is empty
  /// ([REF-ahead-meaningless-without-upstream]), where a branch that never
  /// had one reports 0 and rendering that claims the opposite of the truth.
  String _branchLine(WorktreeInfo w, RefSnapshot refs) {
    if (w.isDetached) return 'HEAD 分離';
    final RefInfo? ref_ = refs.localBranches
        .where((RefInfo r) => r.shortName == w.branch)
        .firstOrNull;
    if (ref_ == null || ref_.upstream.isEmpty || ref_.ahead == 0) {
      return w.branch;
    }
    return '${w.branch} ↑${ref_.ahead}';
  }

  /// Selecting a row is also what asks for its HEAD's subject. Dispatching
  /// from a user action rather than from `build` is what bounds it: a
  /// build-driven request would re-fire on every republish, and every reply
  /// *is* a republish. Gated on the cache so re-selecting a row already on
  /// screen costs nothing -- `requestCommitMeta` dedups too, but relying on
  /// that would put a git process between the panel and the guarantee.
  ///
  /// Nothing else fills this cache for a linked worktree: the only other
  /// filler is History's viewport scrolling past that commit, which for an
  /// old branch tip never happens, so the row showed a bare oid forever.
  void _select(WorktreeInfo w, Map<String, CommitMeta> metas) {
    setState(() => _selectedPath = w.path);
    if (metas.containsKey(w.headOid)) return;
    _session.requestCommitMeta(<String>[w.headOid]);
  }

  /// 「a1b2c3d · Fix lane allocator overflow」, or the bare oid until the
  /// subject arrives. The cache-miss frame is the normal one, not an edge
  /// case: the subject is requested by [_select] when the selection changes.
  String _headLine(WorktreeInfo w, Map<String, CommitMeta> metas) {
    final CommitMeta? meta = metas[w.headOid];
    if (meta == null || meta.subject.isEmpty) return w.headOid;
    return '${w.headOid} · ${meta.subject}';
  }

  /// 「9 個未提交變更 · 未鎖定」.
  String _detailStatusLine(WorktreeInfo w) => <String>[
    _describePendingCount(_answerFor(w)),
    w.isLocked ? '已鎖定' : '未鎖定',
  ].join(' · ');

  static String _formatCreatedAt(DateTime when) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${when.year}-${two(when.month)}-${two(when.day)} '
        '${two(when.hour)}:${two(when.minute)}';
  }
}

/// P19 detail column: 路徑、HEAD、鎖定原因. 待提交數 is now available on
/// [WorktreeInfo] and is not drawn here **yet** -- the P19 rewrite of this
/// column is a later commit in the same round. "Not yet rendered" and "not
/// obtainable" are different claims; see the class doc on [WorktreesPanel]
/// for the one this replaces.
class _WorktreeDetail extends StatelessWidget {
  const _WorktreeDetail({
    required this.worktree,
    required this.title,
    required this.branchLine,
    required this.headLine,
    required this.statusLine,
    required this.createdLine,
  });

  final WorktreeInfo worktree;

  /// The mockup draws the selected worktree's name above the fields.
  final String title;

  /// Every value is resolved by the panel rather than derived here: the
  /// counts come from the panel's cache, and ahead/behind and the commit
  /// subject come from providers the panel already watches. A StatelessWidget
  /// that reached for them itself would be a second source for each.
  final String branchLine;
  final String headLine;
  final String statusLine;
  final String createdLine;

  @override
  Widget build(BuildContext context) {
    return PanelDetailColumn(
      title: title,
      children: <Widget>[
        PanelDetailField(label: '路徑', value: worktree.path, mono: true),
        PanelDetailField(label: '分支', value: branchLine, mono: true),
        PanelDetailField(label: 'HEAD', value: headLine, mono: true),
        PanelDetailField(label: '狀態', value: statusLine),
        // Drawn even when git recorded nothing. Rule 4 makes the detail
        // 一律 a definition list, so a row that disappears would make the
        // panel's shape depend on the item -- and 「git 未記錄」 is a true
        // statement where a missing row is silence.
        PanelDetailField(label: '建立於', value: createdLine),
        if (worktree.isLocked)
          PanelDetailField(
            label: 'Lock reason',
            value: worktree.lockReason.isEmpty
                ? 'Locked, no reason recorded'
                : worktree.lockReason,
          ),
        if (worktree.isPrunable)
          PanelDetailField(
            label: 'Prunable',
            value: worktree.prunableReason.isEmpty
                ? 'Prunable'
                : worktree.prunableReason,
          ),
      ],
    );
  }
}
