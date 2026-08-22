import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../actions/gbm_action_availability.dart';
import '../../actions/gbm_action_id.dart';
import '../../actions/gbm_menu_model.dart';
import '../../actions/gbm_selection_gesture.dart';
import '../../actions/gbm_sequencer_operation.dart';
import '../../data/models/ref_snapshot.dart';
import '../../data/models/repo_state.dart';
import '../../data/models/working_copy_status.dart';
import '../../data/repositories/app_preferences_repository.dart';
import '../../data/repositories/chrome_visibility_repository.dart';
import '../../data/repositories/compare_tabs_repository.dart';
import '../../data/repositories/panel_tabs_repository.dart';
import '../../data/repositories/file_list_view_mode_repository.dart';
import '../../data/repositories/history_repository.dart';
import '../../data/repositories/panel_layout_repository.dart';
import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';
import '../../data/services/desktop_launcher.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/theme_mode_provider.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_banner.dart';
import '../../widgets/split_pane.dart';
import '../history_graph/commit_search.dart';
import '../history_graph/graph_filter_convergence.dart';
import '../history_graph/commit_selection_summary.dart';
import '../history_graph/widgets/graph_columns_selector.dart';
import '../log_drawer/log_drawer.dart';
import '../repo_switcher/repo_switcher_popover.dart';
import '../panels/add_remote_prompt.dart';
import '../sidebar/sidebar_panel.dart';
import '../status_bar/background_task.dart';
import '../status_bar/status_bar.dart';
import 'widgets/menu_bar_row.dart';
import 'widgets/platform_menu_bar_host.dart';
import 'widgets/tab_row.dart';
import 'widgets/top_bar.dart';
import 'widgets/workspace_action_shortcuts.dart';
import 'widgets/workspace_tab.dart';

/// The repository shell: menu bar + top bar + tab switcher + sidebar, with
/// `child` (History or Working Copy, see routing/app_router.dart's
/// ShellRoute) as the main pane. The Dart analog of `MainWindow`
/// (src/app/views/MainWindow.cpp). Owns the session's lifetime: opening any
/// child route lazily opens the `gbm_capi` session (see
/// data/repositories/repo_session_repository.dart), and Riverpod's
/// family provider is torn down (closing the session) once nothing is
/// watching it anymore, i.e. once every child route under this shell is
/// popped.
///
/// `ConsumerStatefulWidget` rather than `ConsumerWidget` solely to hold
/// [_sidebarVisible] -- the menu bar's "Toggle sidebar" item
/// (menu_bar_row.dart) needs somewhere to flip a bool, and this is pure
/// transient UI state scoped to one open workspace, not app/session state
/// worth a provider of its own.
class WorkspaceScreen extends ConsumerStatefulWidget {
  const WorkspaceScreen({
    super.key,
    required this.identity,
    required this.child,
    this.isMacOS,
  });

  final RepoIdentity identity;
  final Widget child;

  /// Platform override for the in-window vs system menu bar branch (spec
  /// page 01: menus live in the system bar on macOS, in-window elsewhere)
  /// and for [WorkspaceActionShortcuts]' Cmd/Ctrl binding. `null` (the
  /// default) falls back to [Platform.isMacOS] -- production behavior is
  /// unchanged -- but a non-null value lets a test force either branch
  /// regardless of the host running the test (`dart:io`'s
  /// `Platform.isMacOS` is not affected by
  /// `debugDefaultTargetPlatformOverride`, so it can't be forced any other
  /// way). Same nullable-override shape as [PlatformMenuBarHost]'s
  /// `isMacOSOverride`.
  final bool? isMacOS;

  @override
  ConsumerState<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends ConsumerState<WorkspaceScreen> {
  bool _sidebarVisible = true;
  int _lastSeenOperationLogIndex = 0;
  final GbmSplitPaneController _logDrawerController = GbmSplitPaneController();
  final FocusNode _branchFilterFocusNode = FocusNode();
  final RepoSwitcherController _switcherController = RepoSwitcherController();

  /// Wall-clock time the last history scan took, for the status bar's
  /// "掃描耗時" figure (spec page 02 item 11). Measured here rather than
  /// reported by the core, which does not time its own scan -- so it is the
  /// UI-observed duration, which is what the number claims to be.
  DateTime? _scanStartedAt;
  Duration? _lastScanDuration;

  /// The last filter actually handed to the core, so an unrelated rebuild
  /// cannot restart a history walk. Null until the first dispatch, which is
  /// deliberately *not* the same as [HistoryFilterRequest.none]: the session
  /// opens unfiltered already, so there is nothing to send for that state.
  HistoryFilterRequest? _lastSentHistoryFilter;
  Timer? _historyFilterDebounce;

  @override
  void dispose() {
    _historyFilterDebounce?.cancel();
    _branchFilterFocusNode.dispose();
    super.dispose();
  }

  /// Typing in the sidebar's filter box changes this on every keystroke, and
  /// each dispatch is a full `git rev-list`. Debounced so "graph-lanes" is
  /// one walk rather than eleven; compared against the last one *sent* so a
  /// query that lands back on a filter already in force costs nothing.
  void _dispatchHistoryFilter(
    RepoIdentity identity,
    HistoryFilterRequest next,
  ) {
    _historyFilterDebounce?.cancel();
    _historyFilterDebounce = Timer(kHistoryFilterDebounce, () {
      if (!mounted || next == _lastSentHistoryFilter) return;
      _lastSentHistoryFilter = next;
      ref
          .read(repoSessionProvider(identity).notifier)
          .setHistoryFilter(
            includeRefs: next.includeRefs,
            firstParentOnly: next.firstParentOnly,
            noMerges: next.noMerges,
          );
    });
  }

  void _showGraphColumnsDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(GbmSpacing.space3),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Graph Columns',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: GbmSpacing.space2),
              const GraphColumnsSelector(),
              const SizedBox(height: GbmSpacing.space3),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Done'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final RepoIdentity identity = widget.identity;
    final RepoSessionState session = ref.watch(repoSessionProvider(identity));
    final String repoId = repoIdForRoute(identity);
    final ChromeVisibility chrome = ref.watch(chromeVisibilityProvider);
    // Resolved once per build so every branch below (in-window menu bar
    // visibility, WorkspaceActionShortcuts' Cmd/Ctrl binding,
    // PlatformMenuBarHost's own platform check) agrees -- see
    // widget.isMacOS's doc comment for why this can't just be
    // Platform.isMacOS directly.
    final bool isMacOS = widget.isMacOS ?? Platform.isMacOS;

    // Times the history scan for the status bar's elapsed figure. Recorded
    // on the false -> true edge and closed on true -> false, so a rebuild
    // in the middle of a scan does not restart the clock.
    ref.listen<bool>(
      repoSessionProvider(identity).select((state) => state.isRefreshing),
      (bool? previous, bool next) {
        if (next && previous != true) {
          _scanStartedAt = DateTime.now();
        } else if (!next && previous == true && _scanStartedAt != null) {
          setState(() {
            _lastScanDuration = DateTime.now().difference(_scanStartedAt!);
            _scanStartedAt = null;
          });
        }
      },
    );

    // The graph converges on the sidebar's branch filter: exactly one match
    // collapses it to a single line with no merge rows (see
    // historyFilterFor). Listened here rather than in SidebarPanel because
    // the sidebar is hideable and the graph is not.
    ref.listen<HistoryFilterRequest>(
      historyFilterRequestProvider(identity),
      (HistoryFilterRequest? previous, HistoryFilterRequest next) =>
          _dispatchHistoryFilter(identity, next),
    );

    // Pushed automatically -- a credential prompt is not something the user
    // chose to open, unlike every other dialog route. See
    // CredentialDialogContent's doc comment for the reverse direction
    // (answering pops it back here without waiting for this to go null).
    ref.listen(
      repoSessionProvider(identity).select((state) => state.credentialPrompt),
      (previous, next) {
        if (next != null && previous == null) {
          context.push(RoutePaths.credentialDialogFor(repoId));
        }
      },
    );

    // Same auto-push pattern as credentialPrompt above -- a checkout
    // refused on a dirty work tree is not something the user chose to open
    // a dialog for either.
    ref.listen(
      repoSessionProvider(identity).select((state) => state.checkoutChoices),
      (previous, next) {
        if (next.isNotEmpty && (previous?.isEmpty ?? true)) {
          context.push(RoutePaths.checkoutRecoveryDialogFor(repoId));
        }
      },
    );

    // Same auto-push pattern, for the "not fully merged" -> "Force delete"
    // recovery flow (see DeleteBranchRecoveryDialogContent's doc comment).
    ref.listen(
      repoSessionProvider(
        identity,
      ).select((state) => state.deleteBranchChoices),
      (previous, next) {
        if (next.isNotEmpty && (previous?.isEmpty ?? true)) {
          context.push(RoutePaths.deleteBranchRecoveryDialogFor(repoId));
        }
      },
    );

    if (!session.isOpen) {
      return Scaffold(
        appBar: AppBar(
          leading: BackButton(onPressed: () => context.go(RoutePaths.welcome)),
        ),
        body: Center(
          child: Text(
            session.lastError?.message ?? 'Opening repository…',
            style: TextStyle(color: context.gbmColors.textSecondary),
          ),
        ),
      );
    }

    // Build the handlers map for actions and menu items
    final Map<GbmActionId, VoidCallback?> actionHandlers = _buildActionHandlers(
      context,
      ref,
      identity,
      repoId,
      session,
    );

    // Track whether log has unread entries (newest entry > lastSeen index)
    final bool hasUnreadLog =
        session.operationLog.isNotEmpty &&
        (session.operationLog.length > _lastSeenOperationLogIndex);

    // Build the main scaffold content
    final Widget scaffoldContent = Scaffold(
      body: Column(
        children: <Widget>[
          // Spec page 01: "只有 menu bar 位置與標題列跟隨系統" -- on macOS the
          // menus live in the system bar (PlatformMenuBarHost below wraps
          // this whole scaffold), so drawing this in-window row there too
          // would show the same menus twice.
          //
          // onFetch/onPull/onPush/onToggleSidebar are read back out of
          // actionHandlers (computed once, above) rather than recomputed
          // here -- the same callback instance is what
          // WorkspaceActionShortcuts (keyboard) and PlatformMenuBarHost
          // (macOS system menu) dispatch through, so a keyboard shortcut
          // and a menu click for the same action can no longer disagree.
          // See _buildActionHandlers' doc comment for the bug this fixes.
          if (!isMacOS)
            MenuBarRow(
              repoId: repoId,
              sidebarVisible: _sidebarVisible,
              // Always non-null: viewToggleSidebar has no state-dependent
              // gate (see gbm_action_availability.dart), so
              // _buildActionHandlers always populates it.
              onToggleSidebar: actionHandlers[GbmActionId.viewToggleSidebar]!,
              onFetch: actionHandlers[GbmActionId.repositoryFetch],
              onPull: actionHandlers[GbmActionId.repositoryPull],
              onPush: actionHandlers[GbmActionId.repositoryPush],
              // Purely visual (GbmMenuItem.enabled) -- see MenuBarRow's doc
              // comment. Same map as WorkspaceActionShortcuts/
              // PlatformMenuBarHost below, so the in-window menu's grey
              // state agrees with what those two paths will actually do.
              actionHandlers: actionHandlers,
            ),
          TopBar(
            repoName: _displayName(identity.workDir),
            repoState: session.repoState,
            isRefreshing: session.isRefreshing,
            onRefresh: () => refreshRepoHistory(ref, identity),
            onBack: () => context.go(RoutePaths.welcome),
          ),
          TabRow(
            repoId: repoId,
            pendingChangeCount: session.workingCopyStatus.entries.length,
            compareTabs: ref.watch(compareTabsProvider(identity)),
            onCloseCompareTab: (String tabId) =>
                _closeCompareTab(context, ref, identity, repoId, tabId),
            panelTabs: ref.watch(panelTabsProvider(identity)),
            onClosePanelTab: (String tabId) =>
                _closePanelTab(context, ref, identity, repoId, tabId),
            // Sourced from isActionEnabled(), not session.conflictActive
            // directly -- single source of truth, same pattern as
            // BranchTreeItem/CommitGraphView. Cherry-pick/Reset have no
            // GbmActionId of their own yet, so they share Merge's gate --
            // see TabRow.conflictActive's doc comment.
            conflictActive: !isActionEnabled(
              GbmActionId.branchMergeIntoCurrent,
              session,
            ),
          ),
          if (session.conflictActive)
            ConflictBanner(
              repoId: repoId,
              session: session,
              onAbort: () => _handleConflictAbort(ref, identity, session),
              onSkip: () => _handleConflictSkip(ref, identity, session),
              onContinue: () => _handleConflictContinue(ref, identity, session),
            ),
          // Independent of conflictActive -- an error unrelated to the
          // conflict itself (auth failure, lock held, ...) must stay
          // visible instead of being swallowed by conflictActive still
          // being true. codeName == 'Conflict' is excluded here
          // specifically: MergeOps.cpp/RebaseOps.cpp/CherryPickOps.cpp/
          // RevertOps.cpp all classify "operation stopped because of a
          // conflict" (both the initial stop, and typically a premature
          // Continue/Skip while conflicts remain unresolved) under that one
          // GitError::Code, worded as "The operation stopped with
          // conflicts" -- content ConflictBanner's own status line ("Merge
          // in progress: N files conflicted") already states, and which
          // otherwise lingers indefinitely after the fact (no success path
          // clears lastError, only refreshHistory() does) and would
          // reappear the moment conflictActive later flips false. The
          // detailed reason for a rejected Continue/Skip is available
          // inside ConflictResolveWindow (via Resolve…), which renders
          // session.lastError unfiltered.
          if (session.lastError case final error?
              when error.codeName != 'Conflict')
            GbmWarningBanner(message: error.message),
          Expanded(
            child: GbmSplitPane(
              axis: Axis.vertical,
              spec: GbmLayout.splitterMainLog,
              storageId: 'main.log',
              controller: _logDrawerController,
              children: <Widget>[
                LogDrawer(records: session.operationLog),
                if (_sidebarVisible)
                  GbmSplitPane(
                    axis: Axis.horizontal,
                    spec: GbmLayout.splitterMainSidebar,
                    storageId: 'main.sidebar',
                    children: <Widget>[
                      SidebarPanel(
                        identity: identity,
                        filterFocusNode: _branchFilterFocusNode,
                        switcherController: _switcherController,
                      ),
                      widget.child,
                    ],
                  )
                else
                  // Not wrapped in Expanded -- the enclosing vertical
                  // GbmSplitPane already wraps children[1] in one
                  // internally (extent mode's Column branch); nesting a
                  // second Expanded directly around it throws Flutter's
                  // "Incorrect use of ParentDataWidget" error, since two
                  // ParentDataWidgets of the same type can't stack without
                  // an intervening Flex.
                  widget.child,
              ],
            ),
          ),
          if (chrome.statusBarVisible)
            StatusBar(
              currentBranch: session.refs.head.branchName.isNotEmpty
                  ? session.refs.head.branchName
                  : 'Detached',
              ahead: _headTrackingRef(session)?.ahead ?? 0,
              behind: _headTrackingRef(session)?.behind ?? 0,
              commitCount: session.graph.rows.length,
              lastScanDuration: _lastScanDuration ?? Duration.zero,
              graphLaneCapacity: session.graph.laneCount,
              backgroundTasks: _backgroundTasks(session),
              hasUnreadLog: hasUnreadLog,
              repoState: session.repoState,
              workingCopyStatus: session.workingCopyStatus,
              conflictActive: session.conflictActive,
              // Spec page 13 puts the commit selection summary in the status
              // bar, and the History tab is the only place that selection is
              // visible -- showing "4 commits · contiguous" while the user is
              // looking at Working Copy or a Compare tab would describe rows
              // that are off screen. StatusBar is presentational and has no
              // route awareness, so the tab test lives here.
              //
              // Plain equality against History's own route, the same primitive
              // activeWorkspaceTabIndex() uses -- deliberately *without* its
              // "no tab matched, fall back to History" clause, which exists to
              // keep a tab highlighted while a dialog is pushed on top. Here
              // that fallback would claim History is showing whenever any
              // dialog is open, including one pushed from Working Copy.
              selectionSummary:
                  GoRouterState.of(context).uri.toString() ==
                      RoutePaths.historyFor(repoId)
                  ? commitSelectionSummary(
                      selection: ref.watch(commitSelectionProvider(identity)),
                      allOids: session.graph.oidsHex,
                    )
                  : null,
              onOpenLog: () {
                setState(() {
                  _lastSeenOperationLogIndex = session.operationLog.length;
                });
                // Un-collapse the log drawer if the user has never dragged it
                // open -- otherwise the badge would clear with nothing visibly
                // having happened. See GbmSplitPaneController's doc comment.
                _logDrawerController.open();
              },
              onCancelTask: _cancelTask,
            ),
        ],
      ),
    );

    // Wrap with action shortcuts for keyboard handling
    return WorkspaceActionShortcuts(
      isMacOS: isMacOS,
      handlers: actionHandlers,
      child: PlatformMenuBarHost(
        menus: gbmMenus,
        handlers: actionHandlers,
        isMacOSOverride: isMacOS,
        child: scaffoldContent,
      ),
    );
  }

  String _displayName(String workDir) {
    final List<String> segments = workDir
        .split(RegExp(r'[\\/]'))
        .where((s) => s.isNotEmpty)
        .toList();
    return segments.isEmpty ? workDir : segments.last;
  }

  /// The [RefInfo] HEAD currently points to, or null if detached/unknown --
  /// source of the status bar's ahead/behind counts.
  RefInfo? _headTrackingRef(RepoSessionState session) {
    if (session.refs.head.fullRef.isEmpty) return null;
    for (final RefInfo ref in session.refs.refs) {
      if (ref.fullName == session.refs.head.fullRef) return ref;
    }
    return null;
  }

  /// Builds the action handlers map, wiring every [GbmActionId] that has a
  /// real implementation to its handler. Ids without an implementation are
  /// mapped to `null` (safe no-op when clicked or shortcut fired).
  ///
  /// This map is the single source every dispatch path reads from --
  /// [WorkspaceActionShortcuts] (keyboard), [PlatformMenuBarHost] (macOS
  /// system menu, via `onSelected: handlers[item.id]`), and
  /// [MenuBarRow]'s own `Actions.maybeInvoke` fallback for ids it doesn't
  /// special-case. It used to be a false single source: `repositoryFetch`,
  /// `repositoryPull`, `repositoryPush` and `viewToggleSidebar` were
  /// hardcoded to `null` here on the theory that "MenuBarRow handles it
  /// via a named param" -- true only for the in-window menu-click path,
  /// because [MenuBarRow]'s own `_resolveHandler` special-cases those four
  /// ids and reads `onFetch`/`onPull`/`onPush`/`onToggleSidebar` directly,
  /// bypassing this map entirely. The keyboard and system-menu paths read
  /// this map with no such special-casing, got `null`, and silently
  /// no-op'd -- Ctrl/Cmd+Shift+F, +Shift+P, +P, +B all did nothing (see
  /// `test/integration/workspace_intent_dispatch_parity_test.dart`). Fixed
  /// by giving these four real callbacks here too, then reading them back
  /// out of this same map for `MenuBarRow`'s params (see the `build()`
  /// call site) instead of computing them a second time.
  ///
  /// Wired handlers (real implementations):
  /// - viewHistory, viewWorkingCopy: navigation via GoRouter
  /// - filePreferences, repositorySettings: preferences dialog
  /// - branchMergeIntoCurrent: merge dialog
  /// - branchRebaseOnto: interactive rebase dialog
  /// - remoteManageRemotes: manage remotes dialog
  /// - remotePruneRemoteBranches: prune remote branches dialog (M6)
  /// - remoteFetchAllRemotes: fetch (same as repositoryFetch)
  /// - helpKeyboardShortcuts: keyboard shortcuts dialog
  /// - helpAbout: about dialog
  /// - editFilterBranches: reveals the sidebar (if hidden) and focuses
  ///   SidebarPanel's filter field
  /// - repositoryCompare: opens a new closable Compare tab (M6), defaulting
  ///   to current-branch-vs-Working-Copy, and navigates to it
  ///
  /// Every id in [gbmMenus] now resolves to a handler except the ones
  /// routed elsewhere or legitimately state-dependent:
  /// - fileExit: handled in MenuBarRow (SystemNavigator.pop)
  /// - repositoryFetch, repositoryPull, repositoryPush, viewToggleSidebar:
  ///   real handlers here, also read back out for MenuBarRow's params (see
  ///   above) -- not "handled elsewhere" any more, just shared
  /// - every id [isActionEnabled] gates (see gbm_action_availability.dart
  ///   for the full state-machine rules: spec page 07's conflict gate,
  ///   plus detached-HEAD and empty-unstaged-list): `null` when disabled
  ///
  /// A null handler renders the menu item disabled, which is the point --
  /// previously ~30 ids were null purely because nothing had been wired yet,
  /// so items that looked enabled did nothing when clicked.
  Map<GbmActionId, VoidCallback?> _buildActionHandlers(
    BuildContext context,
    WidgetRef ref,
    RepoIdentity identity,
    String repoId,
    RepoSessionState session,
  ) {
    return {
      // File
      // Open and Add-local are the same act here -- point the app at an
      // existing working directory -- and both go through the same path
      // prompt the switcher popover's footer uses, since this app has no
      // native folder-picker dependency (see pubspec.yaml). Opening one
      // records it in the manually-opened list (spec page 11 item 6). New
      // and Clone share the same footer entry points too -- see
      // promptNewRepository()/promptCloneRepository() in
      // repo_switcher_popover.dart.
      GbmActionId.fileNewRepository: () => promptNewRepository(context, ref),
      GbmActionId.fileOpenRepository: () => promptOpenRepository(context),
      GbmActionId.fileCloneRepository: () =>
          promptCloneRepository(context, ref),
      GbmActionId.fileSwitchRepository: () {
        // Same reveal-then-act pattern as editFilterBranches below: the
        // popover anchors to the sidebar's repository button, which is not
        // in the tree at all while the sidebar is hidden -- so reveal it
        // and open on the next frame, once the button has a rect.
        if (!_sidebarVisible) {
          setState(() => _sidebarVisible = true);
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _switcherController.open(),
          );
          return;
        }
        _switcherController.open();
      },
      GbmActionId.fileAddLocalRepository: () => promptOpenRepository(context),
      // Closes this workspace back to the welcome screen. Not
      // SystemNavigator.pop -- that is Exit, and the two must stay
      // distinguishable.
      GbmActionId.fileCloseWindow: () => context.go(RoutePaths.welcome),
      GbmActionId.filePreferences: () =>
          context.push(RoutePaths.preferencesDialog),
      GbmActionId.fileExit: null, // Handled specially in MenuBarRow
      // Edit
      // The five clipboard/history verbs dispatch Flutter's own text-editing
      // intents, so they act on whichever field has focus (commit message,
      // filter box, conflict editor) instead of needing a per-field wiring.
      // Unfocused, `maybeInvoke` finds no action and does nothing, which is
      // the correct behaviour for "Copy" with no text selected.
      GbmActionId.editUndo: () => _invokeTextIntent(
        const UndoTextIntent(SelectionChangedCause.keyboard),
      ),
      GbmActionId.editRedo: () => _invokeTextIntent(
        const RedoTextIntent(SelectionChangedCause.keyboard),
      ),
      GbmActionId.editCut: () => _invokeTextIntent(
        const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
      ),
      GbmActionId.editCopy: () =>
          _invokeTextIntent(CopySelectionTextIntent.copy),
      GbmActionId.editPaste: () => _invokeTextIntent(
        const PasteTextIntent(SelectionChangedCause.keyboard),
      ),
      GbmActionId.editSelectAll: _invokeSelectAll,
      // Both searches live on the History view: commit search filters the
      // commit list, and "find in files" is the same field scoped to paths.
      // Navigating there first means the shortcut works from Working Copy
      // too, rather than silently focusing a field that is not on screen.
      GbmActionId.editFindInHistory: () =>
          _focusHistorySearch(context, ref, identity, repoId),
      GbmActionId.editFindInFiles: () =>
          _focusHistorySearch(context, ref, identity, repoId),
      GbmActionId.editFilterBranches: () {
        // Reveal the sidebar first if hidden -- there is nothing to focus
        // otherwise (mirrors onOpenLog's un-collapse-then-reveal pattern
        // above for the log drawer).
        if (!_sidebarVisible) {
          setState(() => _sidebarVisible = true);
        }
        _branchFilterFocusNode.requestFocus();
      },
      // View
      GbmActionId.viewHistory: () => context.go(RoutePaths.historyFor(repoId)),
      GbmActionId.viewWorkingCopy: () =>
          context.go(RoutePaths.workingCopyFor(repoId)),
      // Cycles History -> Working Copy -> each open Compare tab (in the
      // order TabRow renders them) -> back to History. Built on the same
      // `tabs`/`location` shape TabRow itself derives its active tab from
      // (see tab_row.dart's build()), so the two never disagree about tab
      // order.
      GbmActionId.viewNextTab: () {
        final List<WorkspaceTab> tabs = <WorkspaceTab>[
          ...defaultWorkspaceTabs(
            repoId,
            pendingChangeCount: session.workingCopyStatus.entries.length,
          ),
          for (final CompareTabSpec spec in ref.read(
            compareTabsProvider(identity),
          ))
            compareWorkspaceTab(spec, repoId),
        ];
        final String location = GoRouterState.of(context).uri.toString();
        context.go(nextWorkspaceTabRoute(tabs, location));
      },
      GbmActionId.viewFileListAsTree: () async {
        final currentMode = ref.read(fileListViewModeProvider);
        final newMode = currentMode == FileListViewMode.list
            ? FileListViewMode.tree
            : FileListViewMode.list;
        await ref.read(fileListViewModeProvider.notifier).setMode(newMode);
      },
      GbmActionId.viewGraphColumns: () => _showGraphColumnsDialog(context),
      GbmActionId.viewCommitDetail: () =>
          ref.read(chromeVisibilityProvider.notifier).toggleCommitDetail(),
      // No state-dependent gate (see gbm_action_availability.dart) --
      // always a real callback, read back out for MenuBarRow's own
      // onToggleSidebar param (see the build() call site).
      GbmActionId.viewToggleSidebar: () =>
          setState(() => _sidebarVisible = !_sidebarVisible),
      GbmActionId.viewStatusBar: () =>
          ref.read(chromeVisibilityProvider.notifier).toggleStatusBar(),
      // Same un-collapse-then-reveal as the status bar's own log button, so
      // the menu item and the status bar agree on what "open the log" means.
      GbmActionId.viewLog: () {
        setState(() {
          _lastSeenOperationLogIndex = session.operationLog.length;
        });
        _logDrawerController.open();
      },
      GbmActionId.viewResetPanelSizes: () async {
        await ref.read(panelLayoutRepositoryProvider).clear();
        ref.read(panelLayoutGenerationProvider.notifier).state++;
      },
      // A submenu parent -- MenuBarRow builds the three variant items from
      // this id; invoking the parent itself cycles to the next variant, so
      // the keyboard path is not a dead end.
      GbmActionId.viewTheme: () {
        final GbmThemeVariant current = ref.read(themeVariantProvider);
        const List<GbmThemeVariant> order = GbmThemeVariant.values;
        final GbmThemeVariant next =
            order[(order.indexOf(current) + 1) % order.length];
        ref.read(themeVariantProvider.notifier).setVariant(next);
      },

      // Repository
      //
      // Fetch/Pull/Push are real callbacks here (not delegated elsewhere
      // any more, see this method's doc comment) so the keyboard shortcut
      // and macOS system menu item actually reach them; MenuBarRow reads
      // the same instances back out for its toolbar/menu params.
      GbmActionId.repositoryFetch:
          isActionEnabled(GbmActionId.repositoryFetch, session)
          ? () => ref.read(repoSessionProvider(identity).notifier).fetchRemote()
          : null,
      GbmActionId.repositoryPull:
          isActionEnabled(GbmActionId.repositoryPull, session)
          ? () => ref.read(repoSessionProvider(identity).notifier).pullChanges()
          : null,
      GbmActionId.repositoryPush:
          isActionEnabled(GbmActionId.repositoryPush, session)
          ? () => _push(context, ref, identity, repoId, session)
          : null,
      GbmActionId.repositoryCompare: () =>
          _openCompareTab(context, ref, identity, repoId, session),
      // Commit/Amend/Stage-all all act on the Working Copy view, so they
      // navigate there first -- firing Ctrl/Cmd+Enter from History would
      // otherwise commit a draft the user cannot see. Commit/Amend are
      // disabled mid-conflict (spec page 07: "Commit：停用，直到全部標記
      // resolved 才由 Continue 代為 commit"), matching the Commit button in
      // that view; Stage-all is disabled independently, while nothing is
      // unstaged (see gbm_action_availability.dart).
      GbmActionId.repositoryCommit:
          isActionEnabled(GbmActionId.repositoryCommit, session)
          ? () => context.go(RoutePaths.workingCopyFor(repoId))
          : null,
      GbmActionId.repositoryAmendLastCommit:
          isActionEnabled(GbmActionId.repositoryAmendLastCommit, session)
          ? () => context.go(RoutePaths.workingCopyFor(repoId))
          : null,
      GbmActionId.repositoryStageAll:
          isActionEnabled(GbmActionId.repositoryStageAll, session)
          ? () => ref
                .read(repoSessionProvider(identity).notifier)
                .stageFiles(<String>[
                  for (final WorkingCopyEntry e
                      in session.workingCopyStatus.unstaged)
                    e.path,
                ])
          : null,
      GbmActionId.repositoryOpenInTerminal: () =>
          _openInTerminal(ref, identity),
      GbmActionId.repositorySettings: () =>
          context.push(RoutePaths.repositorySettingsDialogFor(repoId)),

      // Branch
      //
      // Everything that moves HEAD or starts a second sequencer operation is
      // disabled mid-conflict, per spec page 07's STATES table ("切分支：停用,
      // 需先 Continue 或 Abort"). The banner's Abort/Skip/Continue stay the
      // only way forward, matching how Fetch/Pull/Push are already gated.
      // All gated via isActionEnabled() -- gbm_action_availability.dart is
      // the single source of truth for these rules.
      GbmActionId.branchNewBranch:
          isActionEnabled(GbmActionId.branchNewBranch, session)
          ? () => context.push(RoutePaths.newBranchDialogFor(repoId))
          : null,
      GbmActionId.branchCheckout:
          isActionEnabled(GbmActionId.branchCheckout, session)
          ? () => context.push(RoutePaths.checkoutDialogFor(repoId))
          : null,
      // Detached HEAD (no branch name) or mid-conflict: nothing to rename.
      // No `branch` query parameter -- the dialog reads HEAD itself, which
      // is what "the current branch" has to mean for a menu item and F2.
      GbmActionId.branchRenameCurrentBranch:
          isActionEnabled(GbmActionId.branchRenameCurrentBranch, session)
          ? () => context.push(RoutePaths.renameBranchDialogFor(repoId))
          : null,
      GbmActionId.branchMergeIntoCurrent:
          isActionEnabled(GbmActionId.branchMergeIntoCurrent, session)
          ? () => context.push(RoutePaths.mergeDialogFor(repoId))
          : null,
      // Branch → Rebase onto… is the plain rebase (spec page 06's Rebase
      // row), not the todo-plan editor -- that one is reached from the
      // interactive-rebase dialog's own entry point.
      GbmActionId.branchRebaseOnto:
          isActionEnabled(GbmActionId.branchRebaseOnto, session)
          ? () => context.push(RoutePaths.rebaseOntoDialogFor(repoId))
          : null,
      // Stashing mid-conflict would hide the very files being resolved.
      GbmActionId.branchStashChanges:
          isActionEnabled(GbmActionId.branchStashChanges, session)
          ? () => context.push(RoutePaths.stashChangesDialogFor(repoId))
          : null,
      GbmActionId.branchDeleteBranch:
          isActionEnabled(GbmActionId.branchDeleteBranch, session)
          ? () => context.push(RoutePaths.deleteBranchDialogFor(repoId))
          : null,

      // Remote
      // P04 MENUS labels this "Add remote…", and P14's rule is that the
      // ellipsis means it opens a dialog -- so it opens the add prompt
      // itself. It used to open the whole manage-remotes dialog, which was
      // the only way to reach the prompt before Remotes became a panel.
      GbmActionId.remoteAddRemote: () async {
        final ({String name, String url})? result = await promptAddRemote(
          context,
        );
        if (result == null) return;
        ref
            .read(repoSessionProvider(identity).notifier)
            .addRemote(result.name, result.url);
      },
      GbmActionId.remoteFetchAllRemotes:
          isActionEnabled(GbmActionId.remoteFetchAllRemotes, session)
          ? () => ref.read(repoSessionProvider(identity).notifier).fetchRemote()
          : null,
      GbmActionId.remotePruneRemoteBranches: () =>
          context.push(RoutePaths.pruneRemoteBranchesDialogFor(repoId)),
      // Same destination as Tools > Remotes… -- "同一功能不留兩條路" is
      // about carriers, not about how many menus point at one panel.
      GbmActionId.remoteManageRemotes: () => _openPanelTab(
        context,
        ref,
        identity,
        repoId,
        GbmPanelKind.manageRemotes,
      ),

      // Tools -- spec page 14's eighth menu. Every entry except Clean
      // untracked files… opens a *tab* (`_openPanelTab`), because
      // TOOLSMENU's note column reads 分頁 for all of them and IAMAP puts
      // them on "分頁（與 History / Working copy / Compare 同一條分頁列）".
      // Clean untracked files… shares the Rewrite history submenu but
      // belongs to IAMAP's "中型表單 / 確認框" group, so it stays a dialog --
      // menu adjacency is not carrier assignment.
      GbmActionId.toolsStashes: () => _openPanelTab(
        context,
        ref,
        identity,
        repoId,
        GbmPanelKind.manageStashes,
      ),
      GbmActionId.toolsWorktrees: () => _openPanelTab(
        context,
        ref,
        identity,
        repoId,
        GbmPanelKind.manageWorktrees,
      ),
      GbmActionId.toolsRemotes: () => _openPanelTab(
        context,
        ref,
        identity,
        repoId,
        GbmPanelKind.manageRemotes,
      ),
      GbmActionId.toolsSubmodules: () => _openPanelTab(
        context,
        ref,
        identity,
        repoId,
        GbmPanelKind.manageSubmodules,
      ),
      GbmActionId.toolsLargeFiles: () =>
          _openPanelTab(context, ref, identity, repoId, GbmPanelKind.manageLfs),
      GbmActionId.toolsPatches: () =>
          _openPanelTab(context, ref, identity, repoId, GbmPanelKind.patches),
      GbmActionId.toolsReflog: () =>
          _openPanelTab(context, ref, identity, repoId, GbmPanelKind.reflog),
      // "Rewrite history" names a group, not an action -- it has no handler
      // of its own, and menu_bar_row.dart renders it as a flyout trigger
      // from its declared children rather than reading this map for it.
      GbmActionId.toolsRewriteHistory: null,
      GbmActionId.toolsInteractiveRebase: () => _openPanelTab(
        context,
        ref,
        identity,
        repoId,
        GbmPanelKind.interactiveRebase,
      ),
      GbmActionId.toolsBisect: () =>
          _openPanelTab(context, ref, identity, repoId, GbmPanelKind.bisect),
      GbmActionId.toolsCleanUntrackedFiles: () =>
          context.push(RoutePaths.cleanUntrackedDialogFor(repoId)),

      // Help
      GbmActionId.helpDocumentation: () =>
          ref.read(desktopLauncherProvider).openUrl(GbmUrls.documentation),
      GbmActionId.helpKeyboardShortcuts: () =>
          context.push(RoutePaths.keyboardShortcutsDialog),
      GbmActionId.helpReportAnIssue: () =>
          ref.read(desktopLauncherProvider).openUrl(GbmUrls.reportAnIssue),
      GbmActionId.helpAbout: () => context.push(RoutePaths.aboutDialog),
    };
  }

  /// The tasks the status bar's progress area shows (spec page 10 item 2).
  ///
  /// Derived from session state rather than tracked separately, so a task
  /// cannot linger on screen after the operation that owns it has finished.
  /// Only the operations this layer can actually observe appear here: the
  /// history scan (`isRefreshing`) and an in-flight sequencer operation,
  /// whose step counts `RepoState` already carries. Transfer counts for
  /// fetch/pull/push ("12,480 / 31,206" in the spec's own example) need
  /// per-object progress the capi does not surface yet, so those are
  /// reported as indeterminate (`total: 0`) instead of with an invented
  /// denominator.
  List<BackgroundTask> _backgroundTasks(RepoSessionState session) {
    final List<BackgroundTask> tasks = <BackgroundTask>[];

    if (session.isRefreshing) {
      tasks.add(
        BackgroundTask(
          id: 'history-scan',
          label: 'Reading history',
          current: session.graph.rows.length,
          total: session.graph.complete ? session.graph.rows.length : 0,
          cancellable: true,
        ),
      );
    }

    final RepoState? state = session.repoState;
    if (state != null && state.isSequencerOperation) {
      // Non-cancellable by construction: spec page 10's TASKS table marks
      // Checkout/Merge/Rebase "不可取消" because interrupting them midway is
      // more dangerous than letting them finish.
      //
      // Gate stays on RepoState.isSequencerOperation, not
      // activeSequencerOperation() -- the two are deliberately different
      // predicates (see gbm_sequencer_operation.dart's doc comment):
      // isSequencerOperation includes the bare Sequencer flag (set for a
      // multi-commit cherry-pick's `sequencer/todo` dir with no per-commit
      // flag) and excludes merge, while activeSequencerOperation() only
      // looks at the four per-kind flags and includes merge. A
      // sequencer-flag-only state therefore passes this gate but has no
      // corresponding SequencerOperationKind, hence the fallback label
      // below -- 'Merging' is not exactly right for that case, but it is
      // the same fallback this code already used before the dedup.
      final String label = activeSequencerOperation(state)?.gerund ?? 'Merging';
      tasks.add(
        BackgroundTask(
          id: 'sequencer',
          label: label,
          current: state.rebaseStep,
          total: state.rebaseTotal,
          cancellable: false,
        ),
      );
    }

    return tasks;
  }

  /// Cancels a running task by id. Only the history scan is cancellable
  /// today (see [_backgroundTasks]); the sequencer entry is built with
  /// `cancellable: false`, so the status bar never offers Cancel for it and
  /// this is never called with its id.
  void _cancelTask(String id) {
    if (id != 'history-scan') return;
    // Re-requesting the current snapshot is what stops the incremental scan:
    // there is no separate cancel entry point in the capi, and the already
    // loaded rows are kept (spec page 10: "取消保留已載入的部分，不清空畫面").
    ref.read(repoSessionProvider(widget.identity).notifier).refreshHistory();
  }

  /// Push, routed through the force-push confirmation when the branch has
  /// diverged from its upstream.
  ///
  /// Diverged means ahead *and* behind: a plain push would be rejected as
  /// non-fast-forward, so the only way through is a force push, and spec
  /// page 06 requires stating how many remote commits that would overwrite
  /// first. Ahead-only pushes go straight out — there is nothing to
  /// overwrite and nothing to confirm.
  ///
  /// The confirmation is skipped when the user has turned it off
  /// ([AppPreferences.confirmForcePush], spec page 06: "可在 Preferences 關閉
  /// 此確認"), in which case the force push runs directly.
  void _push(
    BuildContext context,
    WidgetRef ref,
    RepoIdentity identity,
    String repoId,
    RepoSessionState session,
  ) {
    final RefInfo? head = _headTrackingRef(session);
    final bool diverged = head != null && head.ahead > 0 && head.behind > 0;

    if (!diverged) {
      ref.read(repoSessionProvider(identity).notifier).pushChanges();
      return;
    }

    if (ref.read(appPreferencesProvider).confirmForcePush) {
      context.push(RoutePaths.forcePushDialogFor(repoId));
    } else {
      ref
          .read(repoSessionProvider(identity).notifier)
          .pushChanges(forceWithLease: true);
    }
  }

  /// Dispatches a Flutter text-editing intent at the currently focused
  /// widget, which is how Edit → Undo/Redo/Cut/Copy/Paste reach whichever
  /// field has focus. Silently does nothing when no editable widget is
  /// focused -- the correct outcome for "Copy" with nothing selected.
  /// Ctrl/Cmd+A has to mean two different things depending on what has
  /// focus: "select every row" over a list (spec page 13's `MULTIKEYS`) and
  /// "select all text" inside an editor. Focus is the only thing that can
  /// tell them apart, so this offers the list intent first and falls back
  /// to the text one when nothing consumed it.
  ///
  /// The handler-map entry is deliberately **non-null**. All three dispatch
  /// paths read this one map (see CLAUDE.md's Intent / Action layer), and a
  /// null here would grey the macOS menu item out and make the keyboard
  /// path a no-op while leaving the in-window menu working -- the exact
  /// split `workspace_intent_dispatch_parity_test.dart` exists to catch.
  void _invokeSelectAll() {
    final BuildContext? focused = primaryFocus?.context;
    if (focused == null) return;
    if (Actions.maybeInvoke(focused, const GbmSelectAllIntent()) != null) {
      return;
    }
    Actions.maybeInvoke(
      focused,
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
    );
  }

  void _invokeTextIntent(Intent intent) {
    final BuildContext? focused = primaryFocus?.context;
    if (focused == null) return;
    Actions.maybeInvoke(focused, intent);
  }

  /// Navigates to History (the only view the commit filter exists on) and
  /// puts the caret in its search field.
  void _focusHistorySearch(
    BuildContext context,
    WidgetRef ref,
    RepoIdentity identity,
    String repoId,
  ) {
    context.go(RoutePaths.historyFor(repoId));
    // After the frame that builds HistoryPage -- the field does not exist
    // yet at the moment `go` is called, so focusing now would be a no-op.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(historySearchFocusNodeProvider(identity)).requestFocus();
      }
    });
  }

  /// Repository → Open in terminal (Ctrl/Cmd+`). Failure is reported into
  /// the operation log rather than a dialog, per spec page 10's rule that
  /// only user-initiated failures needing a decision open a window.
  Future<void> _openInTerminal(WidgetRef ref, RepoIdentity identity) async {
    final bool started = await ref
        .read(desktopLauncherProvider)
        .openTerminal(identity.workDir);
    if (!started && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('No terminal emulator was found.')),
      );
    }
  }

  /// Branch → Rename current branch…. Uses the same `promptText` field the
  /// sidebar's own rename uses, so the two entry points behave identically.
  void _handleConflictAbort(
    WidgetRef ref,
    RepoIdentity identity,
    RepoSessionState session,
  ) {
    final repoSessionNotifier = ref.read(
      repoSessionProvider(identity).notifier,
    );

    switch (activeSequencerOperation(session.repoState)) {
      case SequencerOperationKind.merge:
        repoSessionNotifier.mergeAbort();
      case SequencerOperationKind.cherryPick:
        repoSessionNotifier.cherryPickAbort();
      case SequencerOperationKind.rebase:
        // Covers both rebaseApply and rebaseMerge.
        repoSessionNotifier.abortRebase();
      case SequencerOperationKind.revert:
      case null:
        // Revert has no abort (SequencerOperationKind.canAbort is false for
        // it) and null means nothing is in progress to abort -- both
        // unreachable through the UI since ConflictBanner disables Abort in
        // either case. Exhaustive switch over the implicit "anything else
        // -> abortRebase" this replaced: that fallback would have
        // mis-dispatched a revert's Abort to rebase's --abort had the
        // button ever been reachable.
        break;
    }
  }

  void _handleConflictSkip(
    WidgetRef ref,
    RepoIdentity identity,
    RepoSessionState session,
  ) {
    final repoSessionNotifier = ref.read(
      repoSessionProvider(identity).notifier,
    );

    switch (activeSequencerOperation(session.repoState)) {
      case SequencerOperationKind.cherryPick:
        repoSessionNotifier.cherryPickSkip();
      case SequencerOperationKind.rebase:
        repoSessionNotifier.skipRebase();
      case SequencerOperationKind.merge:
      case SequencerOperationKind.revert:
      case null:
        // Neither has a skip (SequencerOperationKind.canSkip is false for
        // both) -- unreachable through the UI, ConflictBanner disables Skip
        // for merge/revert/no-op.
        break;
    }
  }

  void _handleConflictContinue(
    WidgetRef ref,
    RepoIdentity identity,
    RepoSessionState session,
  ) {
    final repoSessionNotifier = ref.read(
      repoSessionProvider(identity).notifier,
    );

    switch (activeSequencerOperation(session.repoState)) {
      case SequencerOperationKind.cherryPick:
        repoSessionNotifier.cherryPickContinue();
      case SequencerOperationKind.rebase:
        repoSessionNotifier.continueRebase();
      case SequencerOperationKind.merge:
      case SequencerOperationKind.revert:
      case null:
        // Neither has a continue (SequencerOperationKind.canContinue is
        // false for both) -- unreachable through the UI.
        break;
    }
  }

  /// Opens a new Compare tab defaulting to the current branch vs Working
  /// Copy -- immediately useful (shows uncommitted changes against HEAD's
  /// branch) without forcing a ref choice before the tab even opens; either
  /// side can be changed from the pickers once it's open.
  void _openCompareTab(
    BuildContext context,
    WidgetRef ref,
    RepoIdentity identity,
    String repoId,
    RepoSessionState session,
  ) {
    final String left = session.refs.head.branchName.isNotEmpty
        ? session.refs.head.branchName
        : 'HEAD';
    final String tabId = ref
        .read(compareTabsProvider(identity).notifier)
        .open(left: left);
    context.go(RoutePaths.compareFor(repoId, tabId));
  }

  /// Opens (or focuses, if already open) one of spec page 14's twelve
  /// management panels as a tab and navigates to it.
  ///
  /// `context.go`, not `push`: a panel is a tab beside History/Working
  /// Copy, so it *replaces* the shell's child rather than stacking over it
  /// -- `push` would leave the previous tab underneath and make the strip
  /// disagree with what is on screen. Same reasoning as `_openCompareTab`.
  void _openPanelTab(
    BuildContext context,
    WidgetRef ref,
    RepoIdentity identity,
    String repoId,
    GbmPanelKind kind, {
    String? subject,
  }) {
    final String tabId = ref
        .read(panelTabsProvider(identity).notifier)
        .open(kind, subject: subject);
    context.go(RoutePaths.panelFor(repoId, tabId));
  }

  /// Same navigate-away-first ordering as [_closeCompareTab], for the same
  /// reason: GoRouter must never render PanelPage for a tabId that is about
  /// to stop existing in panelTabsProvider.
  void _closePanelTab(
    BuildContext context,
    WidgetRef ref,
    RepoIdentity identity,
    String repoId,
    String tabId,
  ) {
    final String currentLocation = GoRouterState.of(context).uri.toString();
    if (currentLocation == RoutePaths.panelFor(repoId, tabId)) {
      context.go(RoutePaths.historyFor(repoId));
    }
    ref.read(panelTabsProvider(identity).notifier).close(tabId);
  }

  /// Navigates away first when closing the currently active Compare tab, so
  /// GoRouter never renders ComparePage for a tabId that's about to stop
  /// existing in compareTabsProvider.
  void _closeCompareTab(
    BuildContext context,
    WidgetRef ref,
    RepoIdentity identity,
    String repoId,
    String tabId,
  ) {
    final String currentLocation = GoRouterState.of(context).uri.toString();
    if (currentLocation == RoutePaths.compareFor(repoId, tabId)) {
      context.go(RoutePaths.historyFor(repoId));
    }
    ref.read(compareTabsProvider(identity).notifier).close(tabId);
  }
}

/// Resolves the `:repoId` route segment for `identity` -- the inverse of
/// `repoIdentityFromRouteParam` in routing/app_router.dart. Kept here
/// (rather than importing app_router.dart, which would create a routing ->
/// workspace -> routing import cycle) since it is a one-line pure function.
String repoIdForRoute(RepoIdentity identity) =>
    Uri.encodeComponent(identity.workDir);

/// Presentational -- no Riverpod dependency, takes [session] and the three
/// sequencer callbacks as plain data so it can be widget-tested directly
/// (see conflict_banner_test.dart), matching StatusBar/BranchTreeItem.
class ConflictBanner extends StatelessWidget {
  const ConflictBanner({
    super.key,
    required this.repoId,
    required this.session,
    required this.onAbort,
    required this.onSkip,
    required this.onContinue,
  });

  final String repoId;
  final RepoSessionState session;
  final VoidCallback onAbort;
  final VoidCallback onSkip;
  final VoidCallback onContinue;

  /// Which sequencer operation is active, if any -- single source of truth
  /// (gbm_sequencer_operation.dart), used for the status label, the
  /// Abort/Skip/Continue availability below, and the dispatchers in
  /// [_WorkspaceScreenState].
  SequencerOperationKind? get _kind =>
      activeSequencerOperation(session.repoState);

  /// Formats the status text with operation type and progress.
  String _getStatusText() {
    final SequencerOperationKind? kind = _kind;
    final int count = session.workingCopyStatus.conflicted.length;

    if (kind == null) {
      // No sequencer operation, just show file count
      if (count == 0) return '';
      return '$count file${count == 1 ? '' : 's'} conflicted';
    }

    // Format: "Merge in progress: 2 files conflicted"
    // or: "Rebase (3/8): 1 file conflicted"
    final StringBuffer buffer = StringBuffer(kind.label);
    buffer.write(' in progress');

    if (kind == SequencerOperationKind.rebase &&
        session.repoState!.rebaseTotal > 0) {
      buffer.write(
        ' (${session.repoState!.rebaseStep}/${session.repoState!.rebaseTotal})',
      );
    }

    if (count > 0) {
      buffer.write(': $count file${count == 1 ? '' : 's'} conflicted');
    }

    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    final String statusText = _getStatusText();
    final SequencerOperationKind? kind = _kind;
    final bool isRevert = kind == SequencerOperationKind.revert;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: GbmSpacing.space4,
        vertical: GbmSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: colors.diffDelBg,
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: <Widget>[
          if (statusText.isNotEmpty)
            Expanded(
              child: Text(
                statusText,
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.diffDelText,
                ),
              ),
            ),
          // Abort button
          if (kind != null)
            Tooltip(
              message: kind.canAbort
                  ? ''
                  : 'Revert has no abort (use Resolve…)',
              child: TextButton(
                onPressed: kind.canAbort ? onAbort : null,
                child: Text(
                  'Abort',
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.diffDelText,
                    fontWeight: GbmTypography.weightSemibold,
                  ),
                ),
              ),
            ),
          const SizedBox(width: GbmSpacing.space2),
          // Skip button
          if (kind != null)
            Tooltip(
              message: kind.canSkip
                  ? ''
                  : 'Skip not available for ${isRevert ? 'revert' : 'merge'}',
              child: TextButton(
                onPressed: kind.canSkip ? onSkip : null,
                child: Text(
                  'Skip',
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.diffDelText,
                    fontWeight: GbmTypography.weightSemibold,
                  ),
                ),
              ),
            ),
          const SizedBox(width: GbmSpacing.space2),
          // Continue button
          if (kind != null)
            Tooltip(
              message: kind.canContinue
                  ? ''
                  : 'Continue not available for '
                        '${isRevert ? 'revert' : 'merge'} yet -- resolve via '
                        'Resolve…',
              child: TextButton(
                onPressed: kind.canContinue ? onContinue : null,
                child: Text(
                  'Continue',
                  style: TextStyle(
                    fontSize: GbmTypography.textSm,
                    color: colors.diffDelText,
                    fontWeight: GbmTypography.weightSemibold,
                  ),
                ),
              ),
            ),
          const SizedBox(width: GbmSpacing.space2),
          // Resolve… button -- the actual route into ConflictResolveWindow's
          // three-pane editor. Independent of [kind] so it's reachable
          // during a real rebase/cherry-pick/merge/revert conflict, not
          // just the git-apply --3way edge case that has no sequencer
          // state; only Abort/Skip/Continue are sequencer-gated.
          if (session.workingCopyStatus.conflicted.isNotEmpty)
            TextButton(
              onPressed: () => context.go(RoutePaths.conflictsFor(repoId)),
              child: Text(
                'Resolve…',
                style: TextStyle(
                  fontSize: GbmTypography.textSm,
                  color: colors.diffDelText,
                  fontWeight: GbmTypography.weightSemibold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
