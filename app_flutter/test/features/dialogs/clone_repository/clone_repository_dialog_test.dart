// DLGS Clone repository, as welcome-and-clone-spec.html screen 4 draws it:
// URL and destination, the two checkboxes (R18, ASK-3 (a) / W-D5), the
// note, and Clone closes the dialog and starts a background job (R14: no
// error under the fields, no reopening).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/clone_job_native.dart';
import 'package:gbm_flutter/data/ffi/event_dispatcher.dart';
import 'package:gbm_flutter/data/models/base_folder_record.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/git_version.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/clone_job_repository.dart';
import 'package:gbm_flutter/data/repositories/discovery_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/repositories/window_log_repository.dart';
import 'package:gbm_flutter/data/services/file_save_picker.dart';
import 'package:gbm_flutter/routing/app_router.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:go_router/go_router.dart';

import '../../../support/fake_repo_session.dart';

class _Job implements CloneJobHandle {
  @override
  void cancel() {}
  @override
  void provideCredential(String secret) {}
  @override
  void cancelCredential() {}
  @override
  void close() {}
}

class _Native implements CloneJobNative {
  _Native(this.version);
  final GitVersion? version;
  final List<Map<String, Object>> starts = <Map<String, Object>>[];
  bool refuse = false;

  @override
  CloneJobStart start({
    required String url,
    required String destPath,
    required bool recurseSubmodules,
    required int depth,
    required void Function(GbmEvent event) onEvent,
  }) {
    starts.add(<String, Object>{
      'url': url,
      'dest': destPath,
      'recurse': recurseSubmodules,
      'depth': depth,
    });
    return refuse
        ? const CloneJobRefused(
            GitError(
              code: 1,
              codeName: 'InvalidArgument',
              message: 'bad url',
              detail: '',
              argv: <String>[],
              exitCode: 0,
            ),
          )
        : CloneJobStarted(_Job());
  }

  @override
  GitVersion? gitVersion() => version;
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
  _Harness(this.native, this.container, this.router, this.session);
  final _Native native;
  final ProviderContainer container;
  final GoRouter router;
  final FakeRepoSessionController session;
}

Future<_Harness> _pump(
  WidgetTester tester, {
  GitVersion? version = const GitVersion(2, 50, 1),
  List<BaseFolderRecord> folders = const <BaseFolderRecord>[],
  String? originWorkDir,
  String? picked,
}) async {
  final _Native native = _Native(version);
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
      cloneRepositoryDialogRoute(),
    ],
  );
  addTearDown(router.dispose);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      cloneJobNativeProvider.overrideWithValue(native),
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
  router.push(
    RoutePaths.cloneRepositoryDialogPath(originWorkDir: originWorkDir),
  );
  await tester.pumpAndSettle();
  return _Harness(native, container, router, session);
}

Finder _field(String key) => find.byKey(Key(key));

GbmButton _cloneButton(WidgetTester tester) =>
    tester.widget<GbmButton>(find.widgetWithText(GbmButton, 'Clone'));

CheckboxListTile _check(WidgetTester tester, String label) => tester
    .widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, label));

const String _submodules = '一併 clone submodule';
const String _shallow = '淺層 clone（--depth 1）';

void main() {
  testWidgets('draws DLGS\'s title, fields, checkboxes and note', (
    tester,
  ) async {
    await _pump(tester);
    expect(find.text('Clone repository'), findsOneWidget);
    expect(find.text('URL'), findsOneWidget);
    expect(find.text('目標路徑'), findsOneWidget);
    expect(find.text('URL 貼上後自動帶出資料夾名，可手改'), findsOneWidget);
    expect(find.text(_submodules), findsOneWidget);
    expect(find.text(_shallow), findsOneWidget);
    expect(find.text('進行中不卡 dialog：進度走 P10 背景作業列，完成後自動開啟。'), findsOneWidget);
    // The URL field has focus (DLGS k:'focus'); both fields are mono.
    final TextField url = tester.widget<TextField>(_field('clone-url-field'));
    expect(url.autofocus, isTrue);
    expect(url.style?.fontFamily, GbmTypography.fontMono);
    expect(
      tester.widget<TextField>(_field('clone-dest-field')).style?.fontFamily,
      GbmTypography.fontMono,
    );
  });

  testWidgets('Clone stays disabled until both fields are filled', (
    tester,
  ) async {
    await _pump(tester);
    expect(_cloneButton(tester).onPressed, isNull);
    await tester.enterText(_field('clone-url-field'), 'https://h/o/r.git');
    await tester.pump();
    expect(_cloneButton(tester).onPressed, isNull);
    await tester.enterText(_field('clone-dest-field'), '/x/r');
    await tester.pump();
    expect(_cloneButton(tester).onPressed, isNotNull);
  });

  testWidgets('a fixed git checks submodules by default, no hint', (
    tester,
  ) async {
    await _pump(tester);
    expect(_check(tester, _submodules).value, isTrue);
    expect(_check(tester, _shallow).value, isFalse);
    expect(find.textContaining('CVE-2025-48384'), findsNothing);
  });

  testWidgets('an older git leaves submodules unchecked and says why', (
    tester,
  ) async {
    await _pump(tester, version: const GitVersion(2, 39, 5));
    expect(_check(tester, _submodules).value, isFalse);
    expect(
      find.text(
        'git 2.39.5 低於 2.50.1，clone 不信任的 repository 時遞迴 submodule '
        '有已知漏洞（CVE-2025-48384），所以預設不勾。',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the URL fills the destination under the first enabled base '
      'folder until the user edits it', (tester) async {
    await _pump(
      tester,
      folders: <BaseFolderRecord>[
        _folder('/off', enabled: false),
        _folder('/Users/alice/src'),
      ],
    );
    await tester.enterText(
      _field('clone-url-field'),
      'git@github.com:org/design-tokens.git',
    );
    await tester.pump();
    TextField dest = tester.widget<TextField>(_field('clone-dest-field'));
    expect(dest.controller!.text, '/Users/alice/src/design-tokens');

    await tester.enterText(_field('clone-dest-field'), '/elsewhere/mine');
    await tester.enterText(_field('clone-url-field'), 'https://h/o/other');
    await tester.pump();
    dest = tester.widget<TextField>(_field('clone-dest-field'));
    expect(dest.controller!.text, '/elsewhere/mine');
  });

  testWidgets('with no base folder the destination is left to the user', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(_field('clone-url-field'), 'https://h/o/r.git');
    await tester.pump();
    expect(
      tester.widget<TextField>(_field('clone-dest-field')).controller!.text,
      '',
    );
  });

  // C-D1: 瀏覽… picks the parent; the URL keeps naming the folder under it
  // until the destination is edited by hand.
  testWidgets('瀏覽… picks the parent folder the URL\'s name goes under', (
    tester,
  ) async {
    await _pump(
      tester,
      folders: <BaseFolderRecord>[_folder('/Users/alice/src')],
      picked: '/Volumes/work',
    );
    expect(find.widgetWithText(GbmButton, '瀏覽…'), findsOneWidget);
    await tester.tap(find.widgetWithText(GbmButton, '瀏覽…'));
    await tester.pumpAndSettle();
    TextField dest = tester.widget<TextField>(_field('clone-dest-field'));
    expect(dest.controller!.text, '/Volumes/work');

    await tester.enterText(_field('clone-url-field'), 'https://h/o/tokens.git');
    await tester.pump();
    dest = tester.widget<TextField>(_field('clone-dest-field'));
    expect(dest.controller!.text, '/Volumes/work/tokens');

    await tester.enterText(_field('clone-dest-field'), '/mine');
    await tester.enterText(_field('clone-url-field'), 'https://h/o/other');
    await tester.pump();
    dest = tester.widget<TextField>(_field('clone-dest-field'));
    expect(dest.controller!.text, '/mine');
  });

  testWidgets('瀏覽… after a hand edit starts following the URL again', (
    tester,
  ) async {
    await _pump(tester, picked: '/Volumes/work');
    await tester.enterText(_field('clone-url-field'), 'https://h/o/r.git');
    await tester.enterText(_field('clone-dest-field'), '/mine');
    await tester.tap(find.widgetWithText(GbmButton, '瀏覽…'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_field('clone-dest-field')).controller!.text,
      '/Volumes/work/r',
    );
    await tester.enterText(_field('clone-url-field'), 'https://h/o/next');
    await tester.pump();
    expect(
      tester.widget<TextField>(_field('clone-dest-field')).controller!.text,
      '/Volumes/work/next',
    );
  });

  testWidgets('a cancelled 瀏覽… leaves the destination alone', (tester) async {
    await _pump(tester, folders: <BaseFolderRecord>[_folder('/src')]);
    await tester.enterText(_field('clone-url-field'), 'https://h/o/r.git');
    await tester.tap(find.widgetWithText(GbmButton, '瀏覽…'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(_field('clone-dest-field')).controller!.text,
      '/src/r',
    );
  });

  testWidgets('Clone closes the dialog and starts the job as set', (
    tester,
  ) async {
    final _Harness h = await _pump(tester);
    await tester.enterText(_field('clone-url-field'), ' https://h/o/r.git ');
    await tester.enterText(_field('clone-dest-field'), ' /x/r ');
    await tester.tap(find.text(_submodules));
    await tester.tap(find.text(_shallow));
    await tester.pump();
    await tester.tap(find.widgetWithText(GbmButton, 'Clone'));
    await tester.pumpAndSettle();

    expect(h.native.starts.single, <String, Object>{
      'url': 'https://h/o/r.git',
      'dest': '/x/r',
      'recurse': false,
      'depth': 1,
    });
    expect(find.text('Clone repository'), findsNothing);
    expect(find.text('below'), findsOneWidget);
    expect(h.container.read(cloneJobsProvider), hasLength(1));
  });

  testWidgets('with no origin, a refusal lands in the window Log (R13)', (
    tester,
  ) async {
    final _Harness h = await _pump(tester);
    h.native.refuse = true;
    await tester.enterText(_field('clone-url-field'), 'u');
    await tester.enterText(_field('clone-dest-field'), '/x/r');
    await tester.pump();
    await tester.tap(find.widgetWithText(GbmButton, 'Clone'));
    await tester.pumpAndSettle();
    expect(
      h.container.read(windowLogProvider).entries.single.message,
      'InvalidArgument: bad url',
    );
    expect(h.session.state.operationLog, isEmpty);
  });

  testWidgets('from a repository window, it lands in that session\'s Log', (
    tester,
  ) async {
    final _Harness h = await _pump(tester, originWorkDir: _origin.workDir);
    h.native.refuse = true;
    await tester.enterText(_field('clone-url-field'), 'u');
    await tester.enterText(_field('clone-dest-field'), '/x/r');
    await tester.pump();
    await tester.tap(find.widgetWithText(GbmButton, 'Clone'));
    await tester.pumpAndSettle();
    expect(
      h.session.state.operationLog.single,
      isA<AppLogEntry>().having(
        (AppLogEntry e) => e.message,
        'message',
        'InvalidArgument: bad url',
      ),
    );
    expect(h.container.read(windowLogProvider).entries, isEmpty);
  });

  test('the path carries the origin as a query, and only when given', () {
    expect(
      RoutePaths.cloneRepositoryDialogPath(),
      RoutePaths.cloneRepositoryDialog,
    );
    expect(
      RoutePaths.cloneRepositoryDialogPath(originWorkDir: '/a b'),
      '${RoutePaths.cloneRepositoryDialog}?origin=%2Fa+b',
    );
  });
}
