// DLGS New repository, as new-repository-spec.html screen 1 draws it after
// the 2026-10-23 rulings: 名稱 / 位置 (with 瀏覽…) / 預設分支名, no
// checkboxes (N-D1, N-D4), warn for an existing repository (disabled) or a
// non-empty directory (allowed) (N-D2), and Create closes the dialog with
// the result going only to the Log (N-D5).
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/base_folder_record.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/discovery_repository.dart';
import 'package:gbm_flutter/data/repositories/gbm_bindings_provider.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/repositories/window_log_repository.dart';
import 'package:gbm_flutter/data/services/file_save_picker.dart';
import 'package:gbm_flutter/routing/app_router.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:gbm_flutter/widgets/gbm_dialog_field_kinds.dart';
import 'package:go_router/go_router.dart';

import '../../../support/fake_repo_session.dart';

class _Bindings implements GbmBindings {
  int initResult = 0;
  String errorJson = '';
  final List<(String, String)> inits = <(String, String)>[];

  @override
  RepoInitDart get repoInit =>
      (Pointer<Utf8> path, Pointer<Utf8> initialBranch) {
        inits.add((path.toDartString(), initialBranch.toDartString()));
        return initResult;
      };

  @override
  LastResultJsonLenDart get lastResultJsonLen =>
      () => errorJson.length;

  @override
  LastResultJsonCopyDart get lastResultJsonCopy =>
      (Pointer<Uint8> out, int outLen) {
        for (int i = 0; i < outLen && i < errorJson.length; i++) {
          out[i] = errorJson.codeUnitAt(i);
        }
      };

  @override
  Never noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used');
}

class _Discovery extends StateNotifier<DiscoveryState>
    implements DiscoveryController {
  _Discovery(List<BaseFolderRecord> folders)
    : super(DiscoveryState(baseFolders: folders));

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used');
}

class _Picker implements FileSavePicker {
  _Picker(this.directory);
  final String? directory;

  @override
  Future<String?> pickDirectory() async => directory;

  @override
  Future<List<String>> openFiles({
    List<String> extensions = const <String>[],
  }) => throw UnimplementedError();

  @override
  Future<String?> saveFile({required String suggestedName}) =>
      throw UnimplementedError();
}

BaseFolderRecord _folder(String path, {bool enabled = true}) =>
    BaseFolderRecord(
      id: path.length,
      path: path,
      enabled: enabled,
      maxDepth: 3,
      followLinks: false,
      lastScanStarted: 0,
      lastScanFinished: 0,
      lastScanDirs: 0,
      lastScanMs: 0,
      lastScanSkipped: 0,
    );

final RepoIdentity _origin = RepoIdentity.forWorkDir('/src/current');

class _Harness {
  _Harness(this.bindings, this.container, this.router, this.session);
  final _Bindings bindings;
  final ProviderContainer container;
  final GoRouter router;
  final FakeRepoSessionController session;

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();
}

Future<_Harness> _pump(
  WidgetTester tester, {
  List<BaseFolderRecord> folders = const <BaseFolderRecord>[],
  String? picked,
  String? originWorkDir,
}) async {
  final _Bindings bindings = _Bindings();
  final FakeRepoSessionController session = FakeRepoSessionController(
    _origin,
    const RepoSessionState(isOpen: true),
  );
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('below')),
      ),
      GoRoute(
        path: RoutePaths.history,
        builder: (context, state) => Scaffold(
          body: Text('workspace: ${state.pathParameters['repoId']}'),
        ),
      ),
      newRepositoryDialogRoute(),
    ],
  );
  addTearDown(router.dispose);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      gbmBindingsProvider.overrideWithValue(bindings),
      discoveryProvider.overrideWith((ref) => _Discovery(folders)),
      fileSavePickerProvider.overrideWithValue(_Picker(picked)),
      windowLogProvider.overrideWith(
        (ref) => WindowLogController(maxEntries: 100),
      ),
      repoSessionProvider(_origin).overrideWith((Ref ref) => session),
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
  router.push(RoutePaths.newRepositoryDialogPath(originWorkDir: originWorkDir));
  await tester.pumpAndSettle();
  return _Harness(bindings, container, router, session);
}

Finder _field(String key) => find.byKey(Key(key));

TextEditingController _text(WidgetTester tester, String key) =>
    tester.widget<TextField>(_field(key)).controller!;

GbmButton _create(WidgetTester tester) => tester.widget<GbmButton>(
  find.widgetWithText(GbmButton, 'Create repository'),
);

const String _name = 'new-repo-name-field';
const String _location = 'new-repo-location-field';
const String _branch = 'new-repo-branch-field';

void main() {
  late Directory base;

  setUp(() => base = Directory.systemTemp.createTempSync('gbm_new_repo_'));
  tearDown(() => base.deleteSync(recursive: true));

  testWidgets('draws DLGS\'s title, three fields and hint, no checkboxes', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('New repository'), findsOneWidget);
    expect(find.text('名稱'), findsOneWidget);
    expect(find.text('位置'), findsOneWidget);
    expect(find.text('預設分支名'), findsOneWidget);
    expect(find.text('預設為 Preferences 的第一個來源資料夾'), findsOneWidget);
    expect(find.widgetWithText(GbmButton, '瀏覽…'), findsOneWidget);
    expect(find.widgetWithText(GbmButton, 'Cancel'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.byType(Checkbox), findsNothing);
    // 名稱 is DLGS k:'focus' with no mono; 位置 and 預設分支名 are mono.
    final TextField name = tester.widget<TextField>(_field(_name));
    expect(name.autofocus, isTrue);
    expect(name.style?.fontFamily, isNot(GbmTypography.fontMono));
    expect(
      tester.widget<TextField>(_field(_location)).style?.fontFamily,
      GbmTypography.fontMono,
    );
    expect(
      tester.widget<TextField>(_field(_branch)).style?.fontFamily,
      GbmTypography.fontMono,
    );
  });

  testWidgets('位置 starts at the first enabled base folder, the branch at '
      'main (N-D6)', (tester) async {
    await _pump(
      tester,
      folders: <BaseFolderRecord>[
        _folder('/off', enabled: false),
        _folder('/Users/alice/src'),
      ],
    );
    expect(_text(tester, _name).text, '');
    expect(_text(tester, _location).text, '/Users/alice/src');
    expect(_text(tester, _branch).text, 'main');
  });

  testWidgets('with no base folder, 位置 is empty and Create is disabled', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(_field(_name), 'graph-bench');
    await tester.pump();
    expect(_text(tester, _location).text, '');
    expect(_create(tester).onPressed, isNull);
  });

  testWidgets('Create needs a usable name and a branch', (tester) async {
    await _pump(tester, folders: <BaseFolderRecord>[_folder(base.path)]);
    expect(_create(tester).onPressed, isNull, reason: 'empty name');
    for (final String bad in <String>['a/b', r'a\b', '.', '..', '  ']) {
      await tester.enterText(_field(_name), bad);
      await tester.pump();
      expect(_create(tester).onPressed, isNull, reason: bad);
    }
    await tester.enterText(_field(_name), 'graph-bench');
    await tester.pump();
    expect(_create(tester).onPressed, isNotNull);
    await tester.enterText(_field(_branch), ' ');
    await tester.pump();
    expect(_create(tester).onPressed, isNull, reason: 'empty branch');
  });

  testWidgets('瀏覽… puts the picked folder into 位置', (tester) async {
    await _pump(
      tester,
      folders: <BaseFolderRecord>[_folder('/Users/alice/src')],
      picked: '/Volumes/work',
    );
    await tester.tap(find.widgetWithText(GbmButton, '瀏覽…'));
    await tester.pumpAndSettle();
    expect(_text(tester, _location).text, '/Volumes/work');
  });

  testWidgets('a target that is already a repository warns and disables', (
    tester,
  ) async {
    Directory('${base.path}/existing/.git').createSync(recursive: true);
    await _pump(tester, folders: <BaseFolderRecord>[_folder(base.path)]);
    await tester.enterText(_field(_name), 'existing');
    await tester.pump();
    expect(
      find.widgetWithText(
        GbmDialogWarnField,
        '${base.path}/existing 已經是 git repository。',
      ),
      findsOneWidget,
    );
    expect(_create(tester).onPressed, isNull);
  });

  testWidgets('a non-empty target warns but still allows Create', (
    tester,
  ) async {
    File('${base.path}/notes/a.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync('x');
    await _pump(tester, folders: <BaseFolderRecord>[_folder(base.path)]);
    await tester.enterText(_field(_name), 'notes');
    await tester.pump();
    expect(
      find.widgetWithText(
        GbmDialogWarnField,
        '${base.path}/notes 已存在且不是空的，會在現有檔案上建立 repository。',
      ),
      findsOneWidget,
    );
    expect(_create(tester).onPressed, isNotNull);
  });

  testWidgets('an empty or missing target draws no warning', (tester) async {
    Directory('${base.path}/empty').createSync();
    await _pump(tester, folders: <BaseFolderRecord>[_folder(base.path)]);
    for (final String name in <String>['empty', 'missing']) {
      await tester.enterText(_field(_name), name);
      await tester.pump();
      expect(find.byType(GbmDialogWarnField), findsNothing, reason: name);
      expect(_create(tester).onPressed, isNotNull, reason: name);
    }
  });

  testWidgets('Create closes the dialog, inits 位置/名稱 on the branch, logs '
      'to the window Log and opens the repository (N-D5)', (tester) async {
    final _Harness h = await _pump(
      tester,
      folders: <BaseFolderRecord>[_folder('/Users/alice/src/')],
    );
    await tester.enterText(_field(_name), ' graph-bench ');
    await tester.enterText(_field(_branch), ' trunk ');
    await tester.pump();
    await tester.tap(find.widgetWithText(GbmButton, 'Create repository'));
    await tester.pumpAndSettle();

    expect(h.bindings.inits, <(String, String)>[
      ('/Users/alice/src/graph-bench', 'trunk'),
    ]);
    expect(find.text('New repository'), findsNothing);
    expect(
      h.container.read(windowLogProvider).entries.map((e) => e.message),
      <String>['Created a repository at /Users/alice/src/graph-bench'],
    );
    expect(h.session.state.operationLog, isEmpty);
    expect(
      h.location,
      RoutePaths.workspaceFor(
        Uri.encodeComponent('/Users/alice/src/graph-bench'),
      ),
    );
  });

  testWidgets('from a repository window, a failure is an error line in that '
      'session and nothing opens', (tester) async {
    final _Harness h = await _pump(
      tester,
      folders: <BaseFolderRecord>[_folder('/repos')],
      originWorkDir: _origin.workDir,
    );
    h.bindings
      ..initResult = -3
      ..errorJson =
          '{"code":2,"codeName":"InvalidArgument",'
          '"message":"\'a..b\' is not a valid branch name","detail":"",'
          '"argv":[],"exitCode":0}';
    await tester.enterText(_field(_name), 'blocked');
    await tester.enterText(_field(_branch), 'a..b');
    await tester.pump();
    await tester.tap(find.widgetWithText(GbmButton, 'Create repository'));
    await tester.pumpAndSettle();

    expect(find.text('New repository'), findsNothing);
    expect(
      h.session.state.operationLog.whereType<AppLogEntry>().map(
        (AppLogEntry e) => (e.level, e.message),
      ),
      <(OperationLogLevel, String)>[
        (
          OperationLogLevel.error,
          "Could not create a repository at /repos/blocked: "
              "'a..b' is not a valid branch name",
        ),
      ],
    );
    expect(h.container.read(windowLogProvider).entries, isEmpty);
    expect(h.location, '/');
  });

  test('the path carries the origin as a query, and only when given', () {
    expect(
      RoutePaths.newRepositoryDialogPath(),
      RoutePaths.newRepositoryDialog,
    );
    expect(
      RoutePaths.newRepositoryDialogPath(originWorkDir: '/a b'),
      '${RoutePaths.newRepositoryDialog}?origin=%2Fa+b',
    );
  });
}
