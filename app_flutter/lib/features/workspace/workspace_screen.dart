import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../actions/gbm_action_id.dart';
import '../../actions/gbm_menu_model.dart';
import '../../data/models/ref_snapshot.dart';
import '../../data/models/repo_state.dart';
import '../../data/models/working_copy_status.dart';
import '../../data/repositories/app_preferences_repository.dart';
import '../../data/repositories/chrome_visibility_repository.dart';
import '../../data/repositories/compare_tabs_repository.dart';
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
import '../../widgets/prompt_text_dialog.dart';
import '../../widgets/split_pane.dart';
import '../history_graph/commit_search.dart';
import '../history_graph/widgets/graph_columns_selector.dart';
import '../log_drawer/log_drawer.dart';
import '../repo_switcher/repo_switcher_popover.dart';
import '../sidebar/sidebar_panel.dart';
import '../status_bar/background_task.dart';
import '../status_bar/status_bar.dart';
import 'widgets/menu_bar_row.dart';
import 'widgets/platform_menu_bar_host.dart';
import 'widgets/tab_row.dart';
import 'widgets/top_bar.dart';
import 'widgets/workspace_action_shortcuts.dart';

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

  @override
  void dispose() {
    _branchFilterFocusNode.dispose();
    super.dispose();
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
          if (!isMacOS)
            MenuBarRow(
              repoId: repoId,
              sidebarVisible: _sidebarVisible,
              onToggleSidebar: () =>
                  setState(() => _sidebarVisible = !_sidebarVisible),
              onFetch: session.conflictActive
                  ? null
                  : () => ref
                        .read(repoSessionProvider(identity).notifier)
                        .fetchRemote(),
              onPull: session.conflictActive
                  ? null
                  : () => ref
                        .read(repoSessionProvider(identity).notifier)
                        .pullChanges(),
              onPush: session.conflictActive
                  ? null
                  : () => _push(context, ref, identity, repoId, session),
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
  /// Every id in [gbmMenus] now resolves to a handler except the four routed
  /// elsewhere and the two that are legitimately state-dependent:
  /// - fileExit: handled in MenuBarRow (SystemNavigator.pop)
  /// - repositoryFetch, repositoryPull, repositoryPush, viewToggleSidebar:
  ///   handled via MenuBarRow callback params
  /// - repositoryStageAll: null while nothing is unstaged
  /// - branchRenameCurrentBranch: null on a detached HEAD
  /// - the Branch menu and Commit/Amend: null mid-conflict, per spec page
  ///   07's STATES table
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
      // records it in the manually-opened list (spec page 11 item 6).
      //
      // New and Clone are disabled rather than routed somewhere plausible:
      // neither `git init` nor clone exists anywhere below this layer (no
      // entry point in gbm_capi.h, nothing in src/core), so there is
      // nothing for them to call. They used to navigate to the repository
      // list, which never created or cloned anything either.
      GbmActionId.fileNewRepository: null,
      GbmActionId.fileOpenRepository: () => promptOpenRepository(context),
      GbmActionId.fileCloneRepository: null,
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
      GbmActionId.viewNextTab: null,
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
      GbmActionId.viewToggleSidebar: null, // Handled via MenuBarRow param
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
      GbmActionId.repositoryFetch: null, // Handled via MenuBarRow param
      GbmActionId.repositoryPull: null, // Handled via MenuBarRow param
      GbmActionId.repositoryPush: null, // Handled via MenuBarRow param
      GbmActionId.repositoryCompare: () =>
          _openCompareTab(context, ref, identity, repoId, session),
      // Commit/Amend/Stage-all all act on the Working Copy view, so they
      // navigate there first -- firing Ctrl/Cmd+Enter from History would
      // otherwise commit a draft the user cannot see. Both are disabled
      // mid-conflict (spec page 07: "Commit：停用，直到全部標記 resolved 才由
      // Continue 代為 commit"), matching the Commit button in that view.
      GbmActionId.repositoryCommit: session.conflictActive
          ? null
          : () => context.go(RoutePaths.workingCopyFor(repoId)),
      GbmActionId.repositoryAmendLastCommit: session.conflictActive
          ? null
          : () => context.go(RoutePaths.workingCopyFor(repoId)),
      GbmActionId.repositoryStageAll: session.workingCopyStatus.unstaged.isEmpty
          ? null
          : () => ref.read(repoSessionProvider(identity).notifier).stageFiles(
              <String>[
                for (final WorkingCopyEntry e
                    in session.workingCopyStatus.unstaged)
                  e.path,
              ],
            ),
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
      GbmActionId.branchNewBranch: session.conflictActive
          ? null
          : () => context.push(RoutePaths.newBranchDialogFor(repoId)),
      GbmActionId.branchCheckout: session.conflictActive
          ? null
          : () => context.push(RoutePaths.checkoutDialogFor(repoId)),
      GbmActionId.branchRenameCurrentBranch:
          session.refs.head.branchName.isEmpty || session.conflictActive
          ? null // Detached HEAD: there is no branch to rename.
          : () => _renameCurrentBranch(context, ref, identity, session),
      GbmActionId.branchMergeIntoCurrent: session.conflictActive
          ? null
          : () => context.push(RoutePaths.mergeDialogFor(repoId)),
      // Branch → Rebase onto… is the plain rebase (spec page 06's Rebase
      // row), not the todo-plan editor -- that one is reached from the
      // interactive-rebase dialog's own entry point.
      GbmActionId.branchRebaseOnto: session.conflictActive
          ? null
          : () => context.push(RoutePaths.rebaseOntoDialogFor(repoId)),
      // Stashing mid-conflict would hide the very files being resolved.
      GbmActionId.branchStashChanges: session.conflictActive
          ? null
          : () => context.push(RoutePaths.stashChangesDialogFor(repoId)),
      GbmActionId.branchDeleteBranch: session.conflictActive
          ? null
          : () => context.push(RoutePaths.deleteBranchDialogFor(repoId)),

      // Remote
      GbmActionId.remoteAddRemote: () =>
          context.push(RoutePaths.manageRemotesDialogFor(repoId)),
      GbmActionId.remoteFetchAllRemotes: session.conflictActive
          ? null
          : () =>
                ref.read(repoSessionProvider(identity).notifier).fetchRemote(),
      GbmActionId.remotePruneRemoteBranches: () =>
          context.push(RoutePaths.pruneRemoteBranchesDialogFor(repoId)),
      GbmActionId.remoteManageRemotes: () =>
          context.push(RoutePaths.manageRemotesDialogFor(repoId)),

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
      final String label = state.isRebasing
          ? 'Rebasing'
          : state.isCherryPicking
          ? 'Cherry-picking'
          : state.isReverting
          ? 'Reverting'
          : 'Merging';
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
  Future<void> _renameCurrentBranch(
    BuildContext context,
    WidgetRef ref,
    RepoIdentity identity,
    RepoSessionState session,
  ) async {
    final String current = session.refs.head.branchName;
    if (current.isEmpty) return;
    final String? newName = await promptText(
      context,
      title: 'Rename Branch',
      label: 'New name',
      initialValue: current,
    );
    if (newName == null || newName == current || !mounted) return;
    ref
        .read(repoSessionProvider(identity).notifier)
        .renameBranch(from: current, to: newName);
  }

  void _handleConflictAbort(
    WidgetRef ref,
    RepoIdentity identity,
    RepoSessionState session,
  ) {
    final repoSessionNotifier = ref.read(
      repoSessionProvider(identity).notifier,
    );

    // Abort based on the operation type
    if (session.repoState?.isMerging ?? false) {
      repoSessionNotifier.mergeAbort();
    } else if (session.repoState?.isCherryPicking ?? false) {
      repoSessionNotifier.cherryPickAbort();
    } else {
      // rebase -- covers both rebaseApply and rebaseMerge
      repoSessionNotifier.abortRebase();
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

    // Skip only applies to rebase and cherry-pick
    if (session.repoState?.isCherryPicking ?? false) {
      repoSessionNotifier.cherryPickSkip();
    } else {
      // rebase
      repoSessionNotifier.skipRebase();
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

    // Continue based on the operation type
    if (session.repoState?.isCherryPicking ?? false) {
      repoSessionNotifier.cherryPickContinue();
    } else {
      // rebase
      repoSessionNotifier.continueRebase();
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

  /// Determines the operation type (merge/rebase/cherry-pick/revert or null).
  /// Priority order: rebase > cherry-pick > revert > merge.
  String? _getOperationLabel() {
    if (session.repoState == null) return null;

    // Check for rebase first (can be rebaseMerge or rebaseApply)
    if (session.repoState!.isRebasing) {
      return 'Rebase';
    }
    if (session.repoState?.isCherryPicking ?? false) {
      return 'Cherry-pick';
    }
    if (session.repoState?.isReverting ?? false) {
      return 'Revert';
    }
    if (session.repoState?.isMerging ?? false) {
      return 'Merge';
    }

    return null;
  }

  /// Whether skip/continue/abort buttons should be shown.
  bool _hasSequencerOperation() {
    if (session.repoState == null) return false;
    final state = session.repoState!;

    return (state.isMerging ||
        state.isCherryPicking ||
        state.isReverting ||
        state.isRebasing);
  }

  /// Whether revert operation is active (has no skip/continue/abort).
  bool _isRevertOnly() => session.repoState?.isReverting ?? false;

  /// Whether Continue has a valid backend action for the current operation.
  /// Cherry-pick and rebase have real `_continue()` capi calls
  /// (`gbm_cherry_pick_continue`/`gbm_rebase_continue`). Merge has none --
  /// real git finishes a merge with a plain commit, there is no
  /// `gbm_merge_continue()`. Revert has none either, by design -- see
  /// RevertOps.h: "Continue/skip/abort for an in-progress revert have no UI
  /// entry point yet". Routing either of those into `continueRebase()`
  /// would call `git rebase --continue` while not mid-rebase.
  bool _canContinue() =>
      (session.repoState?.isCherryPicking ?? false) ||
      (session.repoState?.isRebasing ?? false);

  /// Formats the status text with operation type and progress.
  String _getStatusText() {
    final String? opLabel = _getOperationLabel();
    final int count = session.workingCopyStatus.conflicted.length;

    if (opLabel == null) {
      // No sequencer operation, just show file count
      if (count == 0) return '';
      return '$count file${count == 1 ? '' : 's'} conflicted';
    }

    // Format: "Merge in progress: 2 files conflicted"
    // or: "Rebase (3/8): 1 file conflicted"
    final StringBuffer buffer = StringBuffer(opLabel);
    buffer.write(' in progress');

    if (opLabel == 'Rebase' && session.repoState!.rebaseTotal > 0) {
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
    final bool isRevert = _isRevertOnly();

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
          if (_hasSequencerOperation())
            Tooltip(
              message: isRevert ? 'Revert has no abort (use Resolve…)' : '',
              child: TextButton(
                onPressed: isRevert ? null : onAbort,
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
          if (_hasSequencerOperation())
            Tooltip(
              message: isRevert || session.repoState?.isMerging == true
                  ? 'Skip not available for ${isRevert ? 'revert' : 'merge'}'
                  : '',
              child: TextButton(
                onPressed: (isRevert || session.repoState?.isMerging == true)
                    ? null
                    : onSkip,
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
          if (_hasSequencerOperation())
            Tooltip(
              message: _canContinue()
                  ? ''
                  : 'Continue not available for '
                        '${isRevert ? 'revert' : 'merge'} yet -- resolve via '
                        'Resolve…',
              child: TextButton(
                onPressed: _canContinue() ? onContinue : null,
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
          // three-pane editor. Independent of _hasSequencerOperation() so
          // it's reachable during a real rebase/cherry-pick/merge/revert
          // conflict, not just the git-apply --3way edge case that has no
          // sequencer state; only Abort/Skip/Continue are sequencer-gated.
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
