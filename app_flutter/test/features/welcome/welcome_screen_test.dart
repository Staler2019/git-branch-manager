// The `/` screen shown when no repository is open, rebuilt to spec page 15 A
// (welcome-and-clone-spec.html screen 1): the workspace's menu bar with the
// repository menus off, a sidebar holding only P02 #15's switcher button, the
// product name and three equal-width buttons in the centre, and a status bar
// and Log of the window's own.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/app_log_events.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/models/repo_record.dart';
import 'package:gbm_flutter/data/repositories/discovery_repository.dart';
import 'package:gbm_flutter/data/repositories/gbm_bindings_provider.dart';
import 'package:gbm_flutter/data/repositories/recents_repository.dart';
import 'package:gbm_flutter/data/repositories/window_log_repository.dart';
import 'package:gbm_flutter/data/services/file_save_picker.dart';
import 'package:gbm_flutter/features/log_drawer/log_drawer.dart';
import 'package:gbm_flutter/features/repo_switcher/repo_switcher_popover.dart';
import 'package:gbm_flutter/features/status_bar/status_bar.dart';
import 'package:gbm_flutter/features/welcome/welcome_screen.dart';
import 'package:gbm_flutter/features/workspace/widgets/menu_bar_row.dart';
import 'package:gbm_flutter/features/workspace/widgets/platform_menu_bar_host.dart';
import 'package:gbm_flutter/features/workspace/widgets/workspace_action_shortcuts.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _workDir = '/Users/test/repo1';

final RepoRecord _repo = RepoRecord(
  id: 1,
  baseFolderId: 1,
  workDir: _workDir,
  gitDir: '$_workDir/.git',
  commonDir: '$_workDir/.git',
  kind: RepoKind.normal,
  name: 'test-repo-1',
  parentRepoId: null,
  depth: 0,
  discoveredAt: 1000000,
  missingSince: null,
);

late _TestDiscoveryController _discovery;

Future<(GoRouter, ProviderContainer)> _pump(
  WidgetTester tester, {
  List<RepoRecord> repos = const <RepoRecord>[],
  bool isMacOS = false,
}) async {
  // The real window, not the 800x600 default: the centre column, the sidebar
  // and the menu bar all have to fit at once.
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  _discovery = _TestDiscoveryController(repos);

  final GoRouter router = GoRouter(
    initialLocation: RoutePaths.welcome,
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.welcome,
        builder: (context, state) => WelcomeScreen(isMacOS: isMacOS),
      ),
      GoRoute(
        path: RoutePaths.history,
        builder: (context, state) => Scaffold(
          body: Text('workspace: ${state.pathParameters['repoId']}'),
        ),
      ),
    ],
  );

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      recentsRepositoryProvider.overrideWithValue(RecentsRepository(prefs)),
      gbmBindingsProvider.overrideWithValue(_FakeGbmBindings()),
      fileSavePickerProvider.overrideWithValue(_FakeFolderPicker(_workDir)),
      discoveryProvider.overrideWith((ref) => _discovery),
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
  await tester.pumpAndSettle();
  return (router, container);
}

Finder _centre(String text) => find.descendant(
  of: find.byKey(WelcomeScreen.centreKey),
  matching: find.text(text),
);

void main() {
  testWidgets('lays out P15 A with no overflow and none of the old chrome', (
    tester,
  ) async {
    await _pump(tester, repos: <RepoRecord>[_repo]);

    expect(find.byType(MenuBarRow), findsOneWidget);
    expect(find.byType(RepoSwitcherButton), findsOneWidget);
    expect(find.text('No repository'), findsOneWidget);
    expect(_centre('git-branch-manager'), findsOneWidget);
    expect(
      _centre(
        '沒有開啟的 repository。掃描的來源資料夾設定在 '
        'Preferences → Repository sources。',
      ),
      findsOneWidget,
    );
    expect(find.byType(StatusBar), findsOneWidget);
    expect(find.byType(LogDrawer), findsOneWidget);

    // What the old screen had and P15 A does not.
    expect(find.byType(AppBar), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.byType(RepoSwitcherList), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the product name is 17 / 600 / -.01em', (tester) async {
    await _pump(tester);
    final TextStyle style = tester
        .widget<Text>(_centre('git-branch-manager'))
        .style!;
    expect(style.fontSize, 17);
    expect(style.fontWeight, FontWeight.w600);
    expect(style.letterSpacing, closeTo(-0.17, 1e-9));
  });

  // 使用者裁定 「按鈕要等寬」: 172 each, and the longest shortcut chip
  // beside Clone must not squeeze it.
  testWidgets('the three buttons are sm, 172 wide, Open primary', (
    tester,
  ) async {
    await _pump(tester);
    const List<String> labels = <String>[
      'Open repository…',
      'Clone repository…',
      'New repository…',
    ];
    for (final String label in labels) {
      final Finder button = find.ancestor(
        of: find.text(label),
        matching: find.byType(GbmButton),
      );
      expect(tester.getSize(button).width, 172, reason: label);
      expect(tester.widget<GbmButton>(button).size, GbmButtonSize.sm);
      expect(
        tester.widget<GbmButton>(button).kind,
        label == labels.first ? GbmButtonKind.primary : GbmButtonKind.secondary,
        reason: label,
      );
    }
    // Left-aligned like the mock's `justify-content:flex-start`. Read off
    // the widget: in test-font terms these labels are wider than 172, so
    // where they paint cannot tell centred from left (gbm_components_test
    // proves what the field does).
    for (final String label in labels) {
      expect(
        tester
            .widget<GbmButton>(
              find.ancestor(
                of: find.text(label),
                matching: find.byType(GbmButton),
              ),
            )
            .alignment,
        Alignment.centerLeft,
        reason: label,
      );
    }
  });

  testWidgets('each button carries its own platform shortcut', (tester) async {
    await _pump(tester);
    expect(_centre('Ctrl+O'), findsOneWidget);
    expect(_centre('Ctrl+Shift+N'), findsOneWidget);
    expect(_centre('Ctrl+N'), findsOneWidget);
  });

  // [ACT-one-handler-map]: the keyboard, the macOS menu and the in-window
  // menu read one map, and it is the no-repository one.
  testWidgets('one handler map, with the repository menus off', (tester) async {
    await _pump(tester);
    final Map<GbmActionId, VoidCallback?> menu = tester
        .widget<MenuBarRow>(find.byType(MenuBarRow))
        .actionHandlers;
    final Map<GbmActionId, VoidCallback?> keys = tester
        .widget<WorkspaceActionShortcuts>(find.byType(WorkspaceActionShortcuts))
        .handlers;
    expect(identical(menu, keys), isTrue);

    for (final GbmActionId id in <GbmActionId>[
      GbmActionId.fileOpenRepository,
      GbmActionId.fileCloneRepository,
      GbmActionId.fileNewRepository,
      GbmActionId.fileSwitchRepository,
      GbmActionId.filePreferences,
      GbmActionId.viewLog,
      GbmActionId.helpAbout,
    ]) {
      expect(menu[id], isNotNull, reason: id.name);
    }
    for (final GbmActionId id in <GbmActionId>[
      GbmActionId.repositoryFetch,
      GbmActionId.branchNewBranch,
      GbmActionId.fileCloseWindow,
      GbmActionId.viewToggleSidebar,
      GbmActionId.toolsBisect,
    ]) {
      expect(menu[id], isNull, reason: id.name);
    }
    expect(
      tester.widget<MenuBarRow>(find.byType(MenuBarRow)).onToggleSidebar,
      isNull,
    );
  });

  testWidgets('on macOS the menus go to the system bar, same map', (
    tester,
  ) async {
    await _pump(tester, isMacOS: true);
    expect(find.byType(MenuBarRow), findsNothing);
    final Map<GbmActionId, VoidCallback?> system = tester
        .widget<PlatformMenuBarHost>(find.byType(PlatformMenuBarHost))
        .handlers;
    final Map<GbmActionId, VoidCallback?> keys = tester
        .widget<WorkspaceActionShortcuts>(find.byType(WorkspaceActionShortcuts))
        .handlers;
    expect(identical(system, keys), isTrue);
    expect(system[GbmActionId.repositoryFetch], isNull);
  });

  testWidgets('the switcher button opens P02 #15 and picks a repository', (
    tester,
  ) async {
    final (GoRouter router, _) = await _pump(
      tester,
      repos: <RepoRecord>[_repo],
    );

    await tester.tap(find.byType(RepoSwitcherButton));
    await tester.pumpAndSettle();
    expect(find.byType(RepoSwitcherList), findsOneWidget);

    await tester.tap(find.text('test-repo-1'));
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      RoutePaths.workspaceFor(Uri.encodeComponent(_workDir)),
    );
  });

  testWidgets('File → Switch repository… opens the same popover', (
    tester,
  ) async {
    await _pump(tester, repos: <RepoRecord>[_repo]);
    tester
        .widget<MenuBarRow>(find.byType(MenuBarRow))
        .actionHandlers[GbmActionId.fileSwitchRepository]!();
    await tester.pumpAndSettle();
    expect(find.byType(RepoSwitcherList), findsOneWidget);
  });

  testWidgets('Open repository… opens the picked folder', (tester) async {
    final (GoRouter router, _) = await _pump(tester);
    await tester.tap(find.text('Open repository…'));
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.uri.toString(),
      RoutePaths.workspaceFor(Uri.encodeComponent(_workDir)),
    );
  });

  testWidgets('the status bar writes the scan summary', (tester) async {
    await _pump(tester, repos: <RepoRecord>[_repo]);
    // No enabled source folder in the fake: scanSummaryLabel's first case.
    expect(find.text('還沒有來源資料夾'), findsOneWidget);
  });

  group('Log', () {
    AppLogEntry error() => AppLogEvents.errorOccurred(
      codeName: 'GitFailed',
      message: 'clone failed',
      atEpochMs: 1,
    );

    testWidgets('an unread error lights the summary; Log marks it seen', (
      tester,
    ) async {
      final (_, ProviderContainer container) = await _pump(tester);
      container.read(windowLogProvider.notifier).recordAppLog(error());
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(StatusBar),
          matching: find.text('GitFailed: clone failed'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Log'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(StatusBar),
          matching: find.text('GitFailed: clone failed'),
        ),
        findsNothing,
      );
    });

    testWidgets('Ctrl+Shift+L is View → Log here too', (tester) async {
      final (_, ProviderContainer container) = await _pump(tester);
      container.read(windowLogProvider.notifier).recordAppLog(error());
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(StatusBar),
          matching: find.text('GitFailed: clone failed'),
        ),
        findsNothing,
      );
    });

    testWidgets('the drawer reads the window Log', (tester) async {
      final (_, ProviderContainer container) = await _pump(tester);
      container.read(windowLogProvider.notifier).recordAppLog(error());
      await tester.pumpAndSettle();
      expect(
        tester.widget<LogDrawer>(find.byType(LogDrawer)).records,
        container.read(windowLogProvider).entries,
      );
    });

    // The banner that showed a discovery failure is gone with the rest of the
    // old chrome; P15 B puts a notice in the Log and the status bar.
    testWidgets('a discovery failure is written to the window Log', (
      tester,
    ) async {
      final (_, ProviderContainer container) = await _pump(tester);
      _discovery.fail(
        const GitError(
          code: 1,
          codeName: 'NotFound',
          message: 'base folder is gone',
          detail: '',
          argv: <String>[],
          exitCode: 0,
        ),
      );
      await tester.pumpAndSettle();

      final entries = container.read(windowLogProvider).entries;
      expect(entries, hasLength(1));
      expect(entries.single.message, 'NotFound: base folder is gone');
      expect(
        find.descendant(
          of: find.byType(StatusBar),
          matching: find.text('NotFound: base folder is gone'),
        ),
        findsOneWidget,
      );
    });
  });
}

/// Fake GbmBindings: nothing on this screen reaches the native layer once
/// `discoveryProvider` is overridden, so any call at all is a test bug.
class _FakeGbmBindings implements GbmBindings {
  @override
  Never noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Not implemented for testing');
  }
}

class _TestDiscoveryController extends StateNotifier<DiscoveryState>
    implements DiscoveryController {
  _TestDiscoveryController(List<RepoRecord> repos)
    : super(DiscoveryState(repos: repos));

  void fail(GitError error) => state = state.copyWith(lastError: error);

  @override
  void addBaseFolderAndScan(String path) {}

  @override
  void removeBaseFolder(int baseFolderId) {}

  @override
  void rescan() {}

  @override
  void setBaseFolderEnabled(int baseFolderId, bool enabled) {}

  @override
  void setBaseFolderDepth(int baseFolderId, int maxDepth) {}
}

class _FakeFolderPicker extends FileSavePicker {
  const _FakeFolderPicker(this.path);

  final String? path;

  @override
  Future<String?> pickDirectory() async => path;
}
