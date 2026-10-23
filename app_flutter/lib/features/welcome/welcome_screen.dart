import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../actions/gbm_action_id.dart';
import '../../actions/gbm_edit_intents.dart';
import '../../actions/gbm_menu_model.dart';
import '../../actions/gbm_no_repo_availability.dart';
import '../../actions/gbm_shortcuts.dart';
import '../../data/models/app_log_events.dart';
import '../../data/models/git_error.dart';
import '../../data/models/operation_record.dart';
import '../../data/repositories/app_preferences_repository.dart';
import '../../data/repositories/chrome_visibility_repository.dart';
import '../../data/repositories/clone_job_repository.dart';
import '../../data/repositories/discovery_repository.dart';
import '../../data/repositories/window_log_repository.dart';
import '../../data/services/app_action_runner.dart';
import '../../data/services/app_actions.dart';
import '../../data/services/desktop_launcher.dart';
import '../../routing/dialog_route.dart';
import '../../routing/route_paths.dart';
import '../../theme/gbm_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/gbm_button.dart';
import '../../widgets/gbm_kbd_chip.dart';
import '../../widgets/split_pane.dart';
import '../log_drawer/log_drawer.dart';
import '../repo_switcher/repo_switcher_popover.dart';
import '../status_bar/clone_job_tasks.dart';
import '../status_bar/status_bar.dart';
import '../workspace/widgets/menu_bar_row.dart';
import '../workspace/widgets/platform_menu_bar_host.dart';
import '../workspace/widgets/workspace_action_shortcuts.dart';
import 'scan_summary.dart';

/// What the window shows when no repository is open -- route `/`, spec page
/// 15 A, drawn in welcome-and-clone-spec.html screen 1.
///
/// The workspace's own chrome, with nothing to act on: the menu bar (system
/// bar on macOS) with every repository menu off ([noRepoActionHandlers]), a
/// sidebar holding only P02 #15's switcher button (W-D2 「放本來branch上方那
/// 邊」), the product name and the three ways in, and a status bar and Log of
/// the window's own ([windowLogProvider], R13).
///
/// The app normally never lands here: [appRouterProvider] opens straight
/// into the most recently used repository, and this is where File → Close
/// window comes back to.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key, this.isMacOS});

  /// Platform override for tests, as [WorkspaceScreen.isMacOS]; null reads
  /// [Platform.isMacOS].
  final bool? isMacOS;

  /// The centre column, so a test can tell its product name from the menu
  /// bar's.
  static const Key centreKey = ValueKey<String>('welcome.centre');

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final GbmSplitPaneController _logDrawerController = GbmSplitPaneController();
  final RepoSwitcherController _switcherController = RepoSwitcherController();

  /// Same three fields and same rules as the workspace's: see
  /// `_WorkspaceScreenState._seenError`.
  GbmLogEntry? _seenError;
  GbmLogEntry? _logFocus;
  int _logFocusSerial = 0;

  /// Help → Documentation / Report an issue, as a line in this window's own
  /// Log (rulings R4, R13).
  Future<void> _openUrl(String url) => ref
      .read(appActionRunnerProvider)
      .run(
        openUrlAction(ref.read(desktopLauncherProvider), url),
        sink: ref.read(windowLogProvider.notifier).recordAppLog,
      );

  @override
  void initState() {
    super.initState();
    _logDrawerController.onCollapsed = () {
      if (mounted) setState(() => _logFocus = null);
    };
  }

  static GbmLogEntry? _newestError(List<GbmLogEntry> log) {
    for (int i = log.length - 1; i >= 0; i--) {
      if (log[i].level == OperationLogLevel.error) return log[i];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bool isMacOS = widget.isMacOS ?? Platform.isMacOS;
    final DiscoveryState discovery = ref.watch(discoveryProvider);
    final WindowLogState windowLog = ref.watch(windowLogProvider);
    final ChromeVisibility chrome = ref.watch(chromeVisibilityProvider);

    // The banner that used to show a discovery failure went with the rest of
    // the old chrome; P15 B files a notice under 「留在 log 抽屜與狀態列」.
    // Only a new failure: one already present when this screen mounted was
    // either logged then or belongs to a window that has since moved on.
    ref.listen<GitError?>(
      discoveryProvider.select((DiscoveryState s) => s.lastError),
      (GitError? previous, GitError? next) {
        if (next == null || identical(previous, next)) return;
        ref
            .read(windowLogProvider.notifier)
            .recordAppLog(
              AppLogEvents.errorOccurred(
                codeName: next.codeName,
                message: next.message,
                atEpochMs: DateTime.now().millisecondsSinceEpoch,
              ),
            );
      },
    );

    final GbmLogEntry? newestError = _newestError(windowLog.entries);
    final GbmLogEntry? unreadError = identical(newestError, _seenError)
        ? null
        : newestError;

    final Map<GbmActionId, VoidCallback?> handlers = noRepoActionHandlers(
      _callbacks(windowLog),
    );
    final Map<GbmActionId, GbmKeyboardShortcut> shortcuts = gbmActionShortcuts(
      isMacOS,
    );

    final Widget scaffold = Scaffold(
      body: Column(
        children: <Widget>[
          if (!isMacOS)
            MenuBarRow(
              repoId: '',
              sidebarVisible: true,
              onToggleSidebar: null,
              onFetch: null,
              onPull: null,
              onPush: null,
              actionHandlers: handlers,
            ),
          Expanded(
            child: GbmSplitPane(
              axis: Axis.vertical,
              spec: GbmLayout.splitterMainLog,
              storageId: 'main.log',
              fixedPaneEnd: GbmFixedPaneEnd.trailing,
              controller: _logDrawerController,
              children: <Widget>[
                LogDrawer(
                  records: windowLog.entries,
                  sink: ref.read(windowLogProvider.notifier).recordAppLog,
                  focusEntry: _logFocus,
                  focusSerial: _logFocusSerial,
                  showTimeouts: ref.watch(
                    appPreferencesProvider.select(
                      (AppPreferences p) => p.showLogTimeouts,
                    ),
                  ),
                  showColumnHeaders: ref.watch(
                    appPreferencesProvider.select(
                      (AppPreferences p) => p.showLogColumnHeaders,
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _Sidebar(switcherController: _switcherController),
                    Expanded(
                      child: _Centre(handlers: handlers, shortcuts: shortcuts),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (chrome.statusBarVisible)
            StatusBar.window(
              windowSummary: scanSummaryLabel(discovery),
              backgroundTasks: backgroundTasksFromCloneJobs(
                ref.watch(cloneJobsProvider),
              ),
              unreadError: unreadError,
              onOpenError: () {
                setState(() {
                  _seenError = newestError;
                  _logFocus = unreadError;
                  _logFocusSerial++;
                });
                _logDrawerController.open();
              },
              onToggleLog: () => handlers[GbmActionId.viewLog]?.call(),
              onCancelTask: (String id) {
                if (cloneJobIdOf(id) case final int job) {
                  ref.read(cloneJobsProvider.notifier).cancel(job);
                }
              },
            ),
        ],
      ),
    );

    return WorkspaceActionShortcuts(
      isMacOS: isMacOS,
      handlers: handlers,
      child: PlatformMenuBarHost(
        menus: gbmMenus,
        handlers: handlers,
        isMacOSOverride: isMacOS,
        child: scaffold,
      ),
    );
  }

  /// Every action this window can do; [noRepoActionHandlers] decides which of
  /// them the menus offer. The ones shared with the workspace call the same
  /// functions its `_buildActionHandlers()` does.
  Map<GbmActionId, VoidCallback> _callbacks(WindowLogState windowLog) {
    return <GbmActionId, VoidCallback>{
      GbmActionId.fileNewRepository: () => promptNewRepository(context),
      GbmActionId.fileOpenRepository: () => promptOpenRepository(context, ref),
      GbmActionId.fileCloneRepository: () => promptCloneRepository(context),
      GbmActionId.fileSwitchRepository: _switcherController.open,
      GbmActionId.fileAddLocalRepository: () =>
          promptOpenRepository(context, ref),
      GbmActionId.filePreferences: () =>
          pushDialogRoute(context, RoutePaths.preferencesDialog),
      ...buildEditActionHandlers(),
      // As the workspace's View → Log: seen only on the opening half.
      GbmActionId.viewLog: () {
        if (!_logDrawerController.isOpen) {
          setState(() => _seenError = _newestError(windowLog.entries));
        }
        _logDrawerController.toggle();
      },
      GbmActionId.helpDocumentation: () => _openUrl(GbmUrls.documentation),
      GbmActionId.helpKeyboardShortcuts: () =>
          pushDialogRoute(context, RoutePaths.keyboardShortcutsDialog),
      GbmActionId.helpReportAnIssue: () => _openUrl(GbmUrls.reportAnIssue),
      GbmActionId.helpAbout: () =>
          pushDialogRoute(context, RoutePaths.aboutDialog),
    };
  }
}

/// The workspace sidebar's width and ground, holding only the switcher
/// button (welcome-and-clone-spec.html, sidebar row).
class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.switcherController});

  final RepoSwitcherController switcherController;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Container(
      width: GbmLayout.sidebarDefaultWidth,
      decoration: BoxDecoration(
        color: colors.surfacePanel,
        border: Border(right: BorderSide(color: colors.borderSubtle)),
      ),
      alignment: Alignment.topCenter,
      child: RepoSwitcherButton(controller: switcherController),
    );
  }
}

/// P15 A's centre: product name, one line of help, three equal buttons.
class _Centre extends StatelessWidget {
  const _Centre({required this.handlers, required this.shortcuts});

  final Map<GbmActionId, VoidCallback?> handlers;
  final Map<GbmActionId, GbmKeyboardShortcut> shortcuts;

  @override
  Widget build(BuildContext context) {
    final GbmColors colors = context.gbmColors;
    return Center(
      child: SingleChildScrollView(
        // [P15] padding 22px 26px.
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 26),
        child: Column(
          key: WelcomeScreen.centreKey,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'git-branch-manager',
              style: TextStyle(
                fontSize: 17,
                fontWeight: GbmTypography.weightSemibold,
                letterSpacing: -0.01 * 17,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 14),
            // [P15] max-width 280 on the column; held on the text alone, so
            // the button rows below cannot be squeezed by it (the mock's own
            // Clone row was -- 使用者裁定「按鈕要等寬」).
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 280),
              child: Text(
                '沒有開啟的 repository。掃描的來源資料夾設定在 '
                'Preferences → Repository sources。',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.75,
                  color: colors.textTertiary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            for (final (int i, (GbmActionId id, String label))
                in const <(GbmActionId, String)>[
                  (GbmActionId.fileOpenRepository, 'Open repository…'),
                  (GbmActionId.fileCloneRepository, 'Clone repository…'),
                  (GbmActionId.fileNewRepository, 'New repository…'),
                ].indexed) ...<Widget>[
              if (i > 0) const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  SizedBox(
                    width: 172,
                    child: GbmButton(
                      label: label,
                      size: GbmButtonSize.sm,
                      kind: i == 0
                          ? GbmButtonKind.primary
                          : GbmButtonKind.secondary,
                      alignment: Alignment.centerLeft,
                      onPressed: handlers[id],
                    ),
                  ),
                  if (shortcuts[id] case final GbmKeyboardShortcut shortcut)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: GbmKbdChip(label: shortcut.displayLabel),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
