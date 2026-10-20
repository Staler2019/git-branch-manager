// The repository switcher (spec page 02 item 15): the merged recents +
// discovery list, the search field, the fixed Open / Clone footer, the 05-A
// row context menu, and the popover the sidebar button opens.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/repo_record.dart';
import 'package:gbm_flutter/data/repositories/discovery_repository.dart';
import 'package:gbm_flutter/data/repositories/gbm_bindings_provider.dart';
import 'package:gbm_flutter/data/repositories/recents_repository.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/repositories/window_log_repository.dart';
import 'package:gbm_flutter/data/services/desktop_launcher.dart';
import 'package:gbm_flutter/data/services/file_save_picker.dart';
import 'package:gbm_flutter/features/repo_switcher/repo_switcher_popover.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/lucide_icon.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

const String _workDir1 = '/Users/test/repo1';
const String _workDir2 = '/Users/test/repo2';

RepoRecord _record({
  int id = 1,
  String workDir = _workDir1,
  String name = 'test-repo-1',
  int? missingSince,
}) {
  return RepoRecord(
    id: id,
    baseFolderId: 1,
    workDir: workDir,
    gitDir: '$workDir/.git',
    commonDir: '$workDir/.git',
    kind: RepoKind.normal,
    name: name,
    parentRepoId: null,
    depth: 0,
    discoveredAt: 1000000,
    missingSince: missingSince,
  );
}

class _Launcher extends DesktopLauncher {
  _Launcher() : super(operatingSystem: 'linux');

  final List<String> calls = <String>[];

  @override
  Future<bool> openInFileManager(String path) async {
    calls.add('manager $path');
    return true;
  }

  @override
  Future<bool> openTerminal(String path) async {
    calls.add('terminal $path');
    return true;
  }
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

/// Pumps [child] under a router with a workspace and a repository-settings
/// route to navigate to, plus stub recents/discovery providers.
Future<GoRouter> _pump(
  WidgetTester tester,
  Widget child, {
  List<RecentRepoEntry> recents = const <RecentRepoEntry>[],
  List<RepoRecord> repos = const <RepoRecord>[],
  _TestRecentsRepository? recentsRepository,
  GbmThemeVariant variant = GbmThemeVariant.darkTechnical,
  _FakeGbmBindings? bindings,
  _FakeFolderPicker? picker,
  List<Override> overrides = const <Override>[],
}) async {
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(body: child),
      ),
      GoRoute(
        path: RoutePaths.cloneRepositoryDialog,
        builder: (context, state) => Scaffold(
          body: Text(
            'clone dialog from ${state.uri.queryParameters['origin']}',
          ),
        ),
      ),
      GoRoute(
        path: RoutePaths.history,
        builder: (context, state) => Scaffold(
          body: Text('workspace: ${state.pathParameters['repoId']}'),
        ),
      ),
      GoRoute(
        path: RoutePaths.repositorySettingsDialog,
        builder: (context, state) =>
            const Scaffold(body: Text('repository-settings-dialog')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        recentsRepositoryProvider.overrideWithValue(
          recentsRepository ?? _TestRecentsRepository(recents.toList()),
        ),
        gbmBindingsProvider.overrideWithValue(bindings ?? _FakeGbmBindings()),
        fileSavePickerProvider.overrideWithValue(
          picker ?? _FakeFolderPicker(null),
        ),
        discoveryProvider.overrideWith(
          (ref) => _TestDiscoveryController(repos),
        ),
        ...overrides,
      ],
      child: MaterialApp.router(
        theme: buildGbmTheme(variant),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  group('buildRepoSwitcherEntries', () {
    test('lists recents first, in order, then the rest by name', () {
      final List<RepoSwitcherEntry> entries = buildRepoSwitcherEntries(
        recents: <RecentRepoEntry>[
          const RecentRepoEntry(workDir: _workDir2, lastOpenedEpochMs: 2),
        ],
        discovered: <RepoRecord>[
          _record(id: 1, workDir: '/z/zeta', name: 'zeta'),
          _record(id: 2, workDir: _workDir2, name: 'test-repo-2'),
          _record(id: 3, workDir: '/a/alpha', name: 'alpha'),
        ],
      );

      expect(entries.map((RepoSwitcherEntry e) => e.name), <String>[
        'test-repo-2',
        'alpha',
        'zeta',
      ]);
    });

    test('a repo in both sources appears once and counts as scanned', () {
      final List<RepoSwitcherEntry> entries = buildRepoSwitcherEntries(
        recents: <RecentRepoEntry>[
          const RecentRepoEntry(workDir: _workDir1, lastOpenedEpochMs: 1),
        ],
        discovered: <RepoRecord>[_record()],
      );

      expect(entries, hasLength(1));
      expect(entries.single.isManual, isFalse);
      expect(entries.single.name, 'test-repo-1');
    });

    test('a recent no scan ever found is manual, named after its folder', () {
      final List<RepoSwitcherEntry> entries = buildRepoSwitcherEntries(
        recents: <RecentRepoEntry>[
          const RecentRepoEntry(
            workDir: '/tmp/spike-lfs/',
            lastOpenedEpochMs: 1,
          ),
        ],
        discovered: const <RepoRecord>[],
      );

      expect(entries.single.isManual, isTrue);
      expect(entries.single.name, 'spike-lfs');
    });

    test('carries the missing flag through from the discovery record', () {
      final List<RepoSwitcherEntry> entries = buildRepoSwitcherEntries(
        recents: const <RecentRepoEntry>[],
        discovered: <RepoRecord>[_record(missingSince: 42)],
      );

      expect(entries.single.isMissing, isTrue);
    });
  });

  group('filterRepoSwitcherEntries', () {
    const List<RepoSwitcherEntry> entries = <RepoSwitcherEntry>[
      RepoSwitcherEntry(workDir: '/a/alpha', name: 'alpha', isManual: false),
      RepoSwitcherEntry(workDir: '/b/beta', name: 'beta', isManual: true),
    ];

    test('an empty query keeps everything', () {
      expect(filterRepoSwitcherEntries(entries, '   '), entries);
    });

    test('matches name and path, case-insensitively', () {
      expect(filterRepoSwitcherEntries(entries, 'ALPH').single.name, 'alpha');
      expect(filterRepoSwitcherEntries(entries, '/b/').single.name, 'beta');
      expect(filterRepoSwitcherEntries(entries, 'gamma'), isEmpty);
    });
  });

  group('RepoSwitcherList', () {
    // Q5's red line under the footer is gone (R14): a clone is a background
    // job whose failure goes to the Log. The footer only opens the dialog,
    // naming this list's repository as the window it came from.
    testWidgets('Clone repository… opens the Clone dialog for this window', (
      tester,
    ) async {
      await _pump(tester, const RepoSwitcherList(currentWorkDir: _workDir1));
      await tester.tap(find.text('Clone repository…'));
      await tester.pumpAndSettle();
      expect(find.text('clone dialog from $_workDir1'), findsOneWidget);
    });

    testWidgets('renders the merged list and the fixed footer', (tester) async {
      await _pump(
        tester,
        const RepoSwitcherList(),
        recents: <RecentRepoEntry>[
          const RecentRepoEntry(workDir: _workDir1, lastOpenedEpochMs: 2),
        ],
        repos: <RepoRecord>[
          _record(),
          _record(id: 2, workDir: _workDir2, name: 'test-repo-2'),
        ],
      );

      expect(find.text('test-repo-1'), findsOneWidget);
      expect(find.text('test-repo-2'), findsOneWidget);
      expect(find.text('Open repository…'), findsOneWidget);
      expect(find.text('Clone repository…'), findsOneWidget);
    });

    // W-D2b: the system folder picker, not a typed path (spec page 01 lists
    // the file picker among what the app takes from the OS).
    testWidgets('Open repository… asks for a folder and opens it', (
      tester,
    ) async {
      final _FakeFolderPicker picker = _FakeFolderPicker(_workDir2);
      int dismissed = 0;
      final GoRouter router = await _pump(
        tester,
        RepoSwitcherList(onDismiss: () => dismissed++),
        picker: picker,
      );

      await tester.tap(find.text('Open repository…'));
      await tester.pumpAndSettle();

      expect(picker.calls, 1);
      expect(dismissed, 1);
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        RoutePaths.workspaceFor(Uri.encodeComponent(_workDir2)),
      );
    });

    // Esc on the picker leaves the switcher exactly as it was (P02 #15
    // 「Esc 關閉不切換」).
    testWidgets('cancelling the folder picker changes nothing', (tester) async {
      final _FakeFolderPicker picker = _FakeFolderPicker(null);
      int dismissed = 0;
      final GoRouter router = await _pump(
        tester,
        RepoSwitcherList(onDismiss: () => dismissed++),
        picker: picker,
      );

      await tester.tap(find.text('Open repository…'));
      await tester.pumpAndSettle();

      expect(picker.calls, 1);
      expect(dismissed, 0);
      expect(router.routerDelegate.currentConfiguration.uri.toString(), '/');
      // No typed-path prompt either: the search box is the only field.
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('the search field filters the list', (tester) async {
      await _pump(
        tester,
        const RepoSwitcherList(),
        repos: <RepoRecord>[
          _record(),
          _record(id: 2, workDir: _workDir2, name: 'other-repo'),
        ],
      );

      await tester.enterText(find.byType(TextField), 'other');
      await tester.pumpAndSettle();

      expect(find.text('test-repo-1'), findsNothing);
      expect(find.text('other-repo'), findsOneWidget);
    });

    testWidgets('says so when nothing matches the query', (tester) async {
      await _pump(
        tester,
        const RepoSwitcherList(),
        repos: <RepoRecord>[_record()],
      );

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();

      expect(find.textContaining('No repository matches'), findsOneWidget);
    });

    testWidgets('points at Preferences when there is nothing to list', (
      tester,
    ) async {
      await _pump(tester, const RepoSwitcherList());

      expect(
        find.textContaining('Preferences → Repository sources'),
        findsOneWidget,
      );
    });

    testWidgets('tapping a row switches the window to that repository', (
      tester,
    ) async {
      final GoRouter router = await _pump(
        tester,
        const RepoSwitcherList(),
        repos: <RepoRecord>[_record()],
      );

      await tester.tap(find.text('test-repo-1'));
      await tester.pumpAndSettle();

      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        RoutePaths.workspaceFor(Uri.encodeComponent(_workDir1)),
      );
    });

    testWidgets('a manually-opened row can be removed from the list', (
      tester,
    ) async {
      final _TestRecentsRepository recents = _TestRecentsRepository(
        <RecentRepoEntry>[
          const RecentRepoEntry(workDir: '/tmp/spike', lastOpenedEpochMs: 1),
        ],
      );
      await _pump(tester, const RepoSwitcherList(), recentsRepository: recents);

      expect(find.text('spike'), findsOneWidget);
      await _rightClick(tester, find.text('spike'));
      await tester.tap(find.text('Remove from list'));
      await tester.pumpAndSettle();

      expect(recents.read(), isEmpty);
      expect(find.text('spike'), findsNothing);
    });
  });

  // Ruling R4 「每個動作都要有log」: 05-A's two launcher items go through
  // AppActionRunner, into the window the list belongs to -- the welcome
  // screen's own Log with no repository open (R13), the repository's when
  // one is.
  group('05-A launcher items are logged', () {
    testWidgets('with no repository open, into the window Log', (tester) async {
      final _Launcher launcher = _Launcher();
      // The window Log reads its cap from preferences.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      late WidgetRef scope;
      await _pump(
        tester,
        Consumer(
          builder: (context, ref, _) {
            scope = ref;
            return const RepoSwitcherList();
          },
        ),
        repos: <RepoRecord>[_record()],
        overrides: <Override>[
          desktopLauncherProvider.overrideWithValue(launcher),
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );

      await _rightClick(tester, find.text('test-repo-1'));
      await tester.tap(find.text('Open in file manager'));
      await tester.pumpAndSettle();
      await _rightClick(tester, find.text('test-repo-1'));
      await tester.tap(find.text('Open in terminal'));
      await tester.pumpAndSettle();

      expect(launcher.calls, <String>[
        'manager $_workDir1',
        'terminal $_workDir1',
      ]);
      expect(
        scope
            .read(windowLogProvider)
            .entries
            .whereType<AppLogEntry>()
            .map((AppLogEntry e) => e.message),
        <String>[
          'Showed $_workDir1 in the file manager',
          'Opened a terminal in $_workDir1',
        ],
      );
    });

    testWidgets('inside a repository, into that repository\'s Log', (
      tester,
    ) async {
      final _Launcher launcher = _Launcher();
      final RepoIdentity current = RepoIdentity.forWorkDir(_workDir2);
      final FakeRepoSessionController session = FakeRepoSessionController(
        current,
        const RepoSessionState(isOpen: true),
      );
      await _pump(
        tester,
        const RepoSwitcherList(currentWorkDir: _workDir2),
        repos: <RepoRecord>[_record()],
        overrides: <Override>[
          desktopLauncherProvider.overrideWithValue(launcher),
          repoSessionProvider(current).overrideWith((ref) => session),
        ],
      );

      await _rightClick(tester, find.text('test-repo-1'));
      await tester.tap(find.text('Open in terminal'));
      await tester.pumpAndSettle();

      expect(
        session.state.operationLog.whereType<AppLogEntry>().map(
          (AppLogEntry e) => e.message,
        ),
        <String>['Opened a terminal in $_workDir1'],
      );
    });
  });

  group('RepoSwitcherRow', () {
    const RepoSwitcherEntry scanned = RepoSwitcherEntry(
      workDir: _workDir1,
      name: 'test-repo-1',
      isManual: false,
    );

    // The mockup draws the popover's repositories as `.gbm-menu-item`, whose
    // `:hover` is an accent fill with `--text-on-accent` text -- the same
    // hover every other menu in the app paints, not a list row's grey.
    testWidgets('hover paints the menu-item accent', (tester) async {
      final GbmColors colors = tokensFor(GbmThemeVariant.darkTechnical);
      await _pump(
        tester,
        RepoSwitcherRow(
          entry: const RepoSwitcherEntry(
            workDir: _workDir1,
            name: 'test-repo-1',
            isManual: true,
          ),
          onTap: () {},
          isCurrent: true,
        ),
      );
      Color? fill() =>
          (tester
                      .widget<Container>(
                        find
                            .descendant(
                              of: find.byType(RepoSwitcherRow),
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration!
                  as BoxDecoration)
              .color;
      Color? nameColor() =>
          tester.widget<Text>(find.text('test-repo-1')).style!.color;
      Color? tagColor() =>
          tester.widget<Text>(find.text('manual')).style!.color;
      Color? iconColor() => tester
          .widget<LucideIcon>(
            find.descendant(
              of: find.byType(RepoSwitcherRow),
              matching: find.byType(LucideIcon),
            ),
          )
          .color;

      expect(fill(), colors.surfaceSelected);
      expect(nameColor(), colors.textPrimary);

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(mouse.removePointer);
      // A corner the row (pumped at the top-left) does not reach.
      const Offset outside = Offset(799, 599);
      await mouse.addPointer(location: outside);
      await mouse.moveTo(tester.getCenter(find.byType(RepoSwitcherRow)));
      await tester.pump();

      expect(fill(), colors.accent);
      expect(nameColor(), colors.textOnAccent);
      expect(iconColor(), colors.textOnAccent);
      // `.gbm-menu-item:hover .gbm-menu-shortcut`: the tag sits in that slot.
      expect(tagColor(), colors.textOnAccent.withValues(alpha: 0.8));

      await mouse.moveTo(outside);
      await tester.pump();
      expect(fill(), colors.surfaceSelected);
    });

    testWidgets('right-click shows the 05-A menu', (tester) async {
      await _pump(tester, RepoSwitcherRow(entry: scanned, onTap: () {}));
      await _rightClick(tester, find.byType(RepoSwitcherRow));

      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Open in file manager'), findsOneWidget);
      expect(find.text('Open in terminal'), findsOneWidget);
      expect(find.text('Settings…'), findsOneWidget);
      expect(find.text('Remove from list'), findsOneWidget);
    });

    testWidgets('Remove from list is styled danger', (tester) async {
      await _pump(tester, RepoSwitcherRow(entry: scanned, onTap: () {}));
      await _rightClick(tester, find.byType(RepoSwitcherRow));

      final Text label = tester.widget<Text>(find.text('Remove from list'));
      expect(
        label.style?.color,
        tokensFor(GbmThemeVariant.darkTechnical).danger,
      );
    });

    testWidgets('tapping Open invokes onTap', (tester) async {
      bool opened = false;
      await _pump(
        tester,
        RepoSwitcherRow(entry: scanned, onTap: () => opened = true),
      );
      await _rightClick(tester, find.byType(RepoSwitcherRow));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(opened, isTrue);
    });

    testWidgets('Settings… pushes the repository settings route', (
      tester,
    ) async {
      await _pump(tester, RepoSwitcherRow(entry: scanned, onTap: () {}));
      await _rightClick(tester, find.byType(RepoSwitcherRow));
      await tester.tap(find.text('Settings…'));
      await tester.pumpAndSettle();

      expect(find.text('repository-settings-dialog'), findsOneWidget);
    });

    testWidgets('a scanned row says nothing about being manual', (
      tester,
    ) async {
      await _pump(tester, RepoSwitcherRow(entry: scanned, onTap: () {}));
      expect(find.text('manual'), findsNothing);
    });

    testWidgets('a manual row is labelled with its source', (tester) async {
      await _pump(
        tester,
        RepoSwitcherRow(
          entry: const RepoSwitcherEntry(
            workDir: '/tmp/spike',
            name: 'spike',
            isManual: true,
          ),
          onTap: () {},
        ),
      );
      expect(find.text('manual'), findsOneWidget);
    });

    testWidgets('a missing row is flagged offline', (tester) async {
      await _pump(
        tester,
        RepoSwitcherRow(
          entry: const RepoSwitcherEntry(
            workDir: _workDir1,
            name: 'test-repo-1',
            isManual: false,
            isMissing: true,
          ),
          onTap: () {},
        ),
      );
      expect(find.text('offline'), findsOneWidget);
    });
  });

  group('RepoSwitcherButton', () {
    // P2's mockup, twice: `height:26px;padding:0 7px` inline on the trigger.
    testWidgets('is 26 tall with 7px side padding', (tester) async {
      await _pump(
        tester,
        const SizedBox(
          width: 240,
          child: RepoSwitcherButton(currentWorkDir: _workDir1),
        ),
        repos: <RepoRecord>[_record()],
      );
      final Finder box = find
          .descendant(
            of: find.byType(RepoSwitcherButton),
            matching: find.byType(Container),
          )
          .first;
      expect(tester.getSize(box).height, 26);
      expect(
        tester.widget<Container>(box).padding,
        const EdgeInsets.symmetric(horizontal: 7),
      );
    });

    // The mockup's trigger is an inline-styled span with no hover rule; the
    // user ruled it hovers like a secondary button, `surface-hover` (#169).
    // Its own opaque fill sits above any InkWell ink, so the fill is what
    // has to change.
    //
    // Light IDE, not the dark default: the spec itself makes dark's
    // `--surface-panel-raised` and `--surface-hover` the same #161b22, so in
    // dark this assertion could not tell the two fills apart.
    testWidgets('hover swaps the fill to surfaceHover', (tester) async {
      const GbmThemeVariant variant = GbmThemeVariant.lightIde;
      final GbmColors colors = tokensFor(variant);
      expect(colors.surfaceHover, isNot(colors.surfacePanelRaised));
      await _pump(
        tester,
        const SizedBox(
          width: 240,
          child: RepoSwitcherButton(currentWorkDir: _workDir1),
        ),
        repos: <RepoRecord>[_record()],
        variant: variant,
      );
      Color? fill() =>
          (tester
                      .widget<Container>(
                        find
                            .descendant(
                              of: find.byType(RepoSwitcherButton),
                              matching: find.byType(Container),
                            )
                            .first,
                      )
                      .decoration!
                  as BoxDecoration)
              .color;
      expect(fill(), colors.surfacePanelRaised);

      final TestGesture mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(799, 599));
      await mouse.moveTo(tester.getCenter(find.byType(RepoSwitcherButton)));
      await tester.pump();

      expect(fill(), colors.surfaceHover);
    });

    testWidgets('shows the current repository and opens the popover', (
      tester,
    ) async {
      await _pump(
        tester,
        const SizedBox(
          width: 240,
          child: RepoSwitcherButton(currentWorkDir: _workDir1),
        ),
        repos: <RepoRecord>[_record()],
      );

      expect(find.text('repo1'), findsOneWidget);
      expect(find.byType(RepoSwitcherList), findsNothing);

      await tester.tap(find.byType(RepoSwitcherButton));
      await tester.pumpAndSettle();

      expect(find.byType(RepoSwitcherList), findsOneWidget);
      expect(find.text('test-repo-1'), findsOneWidget);
    });

    // A window with no repository open (P15 A) still shows the switcher; P02
    // #15 draws no empty state for it, so the label is the design page's
    // inferred 「No repository」 in textTertiary (welcome-and-clone-spec.html).
    testWidgets('with no repository reads "No repository" and still opens', (
      tester,
    ) async {
      await _pump(
        tester,
        const SizedBox(width: 240, child: RepoSwitcherButton()),
        repos: <RepoRecord>[_record()],
      );

      expect(
        tester.widget<Text>(find.text('No repository')).style?.color,
        tokensFor(GbmThemeVariant.darkTechnical).textTertiary,
      );
      expect(
        find.descendant(
          of: find.byType(RepoSwitcherButton),
          matching: find.byType(Tooltip),
        ),
        findsNothing,
      );

      await tester.tap(find.byType(RepoSwitcherButton));
      await tester.pumpAndSettle();
      expect(find.byType(RepoSwitcherList), findsOneWidget);
    });

    testWidgets('Esc closes the popover without switching', (tester) async {
      final GoRouter router = await _pump(
        tester,
        const SizedBox(
          width: 240,
          child: RepoSwitcherButton(currentWorkDir: _workDir1),
        ),
        repos: <RepoRecord>[_record()],
      );

      await tester.tap(find.byType(RepoSwitcherButton));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(RepoSwitcherList), findsNothing);
      expect(router.routerDelegate.currentConfiguration.uri.toString(), '/');
    });

    testWidgets('the controller opens the popover from outside the button', (
      tester,
    ) async {
      final RepoSwitcherController controller = RepoSwitcherController();
      await _pump(
        tester,
        SizedBox(
          width: 240,
          child: RepoSwitcherButton(
            currentWorkDir: _workDir1,
            controller: controller,
          ),
        ),
        repos: <RepoRecord>[_record()],
      );

      controller.open();
      await tester.pumpAndSettle();

      expect(find.byType(RepoSwitcherList), findsOneWidget);
    });
  });
}

/// Fake GbmBindings: nothing in these tests reaches the native layer, so any
/// call at all is a test bug rather than something to stub out.
class _FakeGbmBindings implements GbmBindings {
  @override
  Never noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Not implemented for testing');
  }
}

class _TestRecentsRepository implements RecentsRepository {
  _TestRecentsRepository(this._entries);

  final List<RecentRepoEntry> _entries;

  @override
  List<RecentRepoEntry> read() => List<RecentRepoEntry>.unmodifiable(_entries);

  @override
  Future<void> recordOpen(String workDir) async {
    _entries.insert(0, RecentRepoEntry(workDir: workDir, lastOpenedEpochMs: 0));
  }

  @override
  Future<void> remove(String workDir) async {
    _entries.removeWhere((RecentRepoEntry e) => e.workDir == workDir);
  }

  @override
  Future<void> clear() async => _entries.clear();
}

class _TestDiscoveryController extends StateNotifier<DiscoveryState>
    implements DiscoveryController {
  _TestDiscoveryController(List<RepoRecord> repos)
    : super(DiscoveryState(repos: repos));

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

/// Returns [path] from the folder picker and counts the asks.
class _FakeFolderPicker extends FileSavePicker {
  _FakeFolderPicker(this.path);

  final String? path;
  int calls = 0;

  @override
  Future<String?> pickDirectory() async {
    calls++;
    return path;
  }
}
