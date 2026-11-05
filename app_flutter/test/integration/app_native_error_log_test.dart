// The whole Dart half of the native error channel, in the real GbmApp: the function pointer
// it registers is called as the library would call it, and the line has to reach every Log.
// Without this, each piece could pass its own tests while nothing under lib/ mounted it.
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/app.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/app_version.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/models/release_asset.dart';
import 'package:gbm_flutter/data/repositories/build_version_repository.dart';
import 'package:gbm_flutter/data/repositories/gbm_bindings_provider.dart';
import 'package:gbm_flutter/data/repositories/open_repo_sessions.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/repositories/window_log_repository.dart';
import 'package:gbm_flutter/data/services/github_release_gateway.dart';
import 'package:gbm_flutter/data/services/update_installer.dart';
import 'package:gbm_flutter/features/app_lifecycle/native_error_log_listener.dart';
import 'package:gbm_flutter/features/update/auto_update_check.dart';
import 'package:gbm_flutter/routing/app_router.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repo_session.dart';

typedef _CallbackDart = void Function(
  Pointer<Uint8> payload,
  int payloadLen,
  Pointer<Void> userData,
);

class _Bindings extends FakeGbmBindings {
  _Bindings(this.order);

  final List<String> order;
  final List<Pointer<NativeFunction<GbmNativeErrorCallbackNative>>> registered =
      <Pointer<NativeFunction<GbmNativeErrorCallbackNative>>>[];

  @override
  SetNativeErrorCallbackDart get setNativeErrorCallback =>
      (
        Pointer<NativeFunction<GbmNativeErrorCallbackNative>> callback,
        Pointer<Void> userData,
      ) {
        registered.add(callback);
        if (callback == nullptr) order.add('callback cleared');
      };

  @override
  FreeEventPayloadDart get freeEventPayload =>
      (Pointer<Uint8> payload) => malloc.free(payload);

  void fire(String json) {
    final List<int> bytes = utf8.encode(json);
    final Pointer<Uint8> buffer = malloc<Uint8>(bytes.length);
    buffer.asTypedList(bytes.length).setAll(0, bytes);
    registered.first.asFunction<_CallbackDart>()(buffer, bytes.length, nullptr);
  }
}

class _Session extends FakeRepoSessionController {
  _Session(this.order, OpenRepoSessions sessions)
    : super(
        RepoIdentity.forWorkDir('/test/repo'),
        const RepoSessionState(isOpen: true),
        openSessions: sessions,
      );

  final List<String> order;

  @override
  void closeNativeSession() {
    order.add('session closed');
    super.closeNativeSession();
  }
}

class _NoUpdateGateway extends GithubReleaseGateway {
  @override
  Future<LatestRelease> fetchLatest() async => LatestRelease(
    version: const AppVersion(0, 30, 0),
    tagName: 'v0.30.0',
    htmlUrl: 'https://example.test/',
    notes: '',
    assets: const <ReleaseAsset>[],
  );
}

class _InertInstaller extends UpdateInstaller {
  const _InertInstaller({
    required super.operatingSystem,
    required super.executablePath,
    required super.abi,
  });

  @override
  Future<void> sweepUpdateLeftovers({
    Directory? tempDir,
    DateTime Function()? now,
  }) async {}
}

const String _literal =
    '{"whenEpochMs":1793889351496,"where":"gbm_x",'
    '"summary":"std::runtime_error: clone https://user:secret@host/x failed",'
    '"logPath":"/logs/gbm-native-errors.log"}';

const String _expectedLine =
    'Native error in gbm_x: std::runtime_error: clone '
    'https://user:••••@host/x failed (details: /logs/gbm-native-errors.log)';

class _Harness {
  _Harness(this.bindings, this.sessions, this.session, this.order);

  final _Bindings bindings;
  final OpenRepoSessions sessions;
  final _Session session;
  final List<String> order;
}

Future<_Harness> _pumpApp(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(const <String, Object>{});
  final SharedPreferences store = await SharedPreferences.getInstance();
  final List<String> order = <String>[];
  final _Bindings bindings = _Bindings(order);
  final OpenRepoSessions sessions = OpenRepoSessions();
  final _Session session = _Session(order, sessions);
  addTearDown(session.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(store),
        gbmBindingsProvider.overrideWithValue(bindings),
        openRepoSessionsProvider.overrideWithValue(sessions),
        appRouterProvider.overrideWithValue(
          GoRouter(
            initialLocation: RoutePaths.welcome,
            routes: <RouteBase>[
              GoRoute(
                path: RoutePaths.welcome,
                builder: (BuildContext c, GoRouterState s) =>
                    const Scaffold(body: Text('welcome')),
              ),
            ],
          ),
        ),
        githubReleaseGatewayProvider.overrideWithValue(_NoUpdateGateway()),
        buildVersionProvider.overrideWithValue(const AppVersion(0, 30, 0)),
        updateInstallerProvider.overrideWithValue(
          _InertInstaller(
            operatingSystem: 'linux',
            executablePath: '${Directory.systemTemp.path}/gbm_flutter',
            abi: Abi.linuxX64,
          ),
        ),
        autoUpdateCheckDelayProvider.overrideWithValue(Duration.zero),
      ],
      child: const GbmApp(),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(bindings, sessions, session, order);
}

/// A listener call arrives through the real event loop, which fake time does not run.
Future<void> _deliver(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 20)),
  );
  await tester.pump();
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(GbmApp)));

List<String> _messages(Iterable<GbmLogEntry> log) => log
    .whereType<AppLogEntry>()
    .where((AppLogEntry e) => e.level == OperationLogLevel.error)
    .map((AppLogEntry e) => e.message)
    .toList();

void main() {
  testWidgets('the channel is registered once, by the listener GbmApp mounts', (
    WidgetTester tester,
  ) async {
    final _Harness harness = await _pumpApp(tester);

    expect(find.byType(NativeErrorLogListener), findsOneWidget);
    expect(harness.bindings.registered, hasLength(1));
    expect(harness.bindings.registered.single, isNot(nullptr));
  });

  testWidgets(
    'a report reaches the window Log and every open session, masked',
    (WidgetTester tester) async {
      final _Harness harness = await _pumpApp(tester);
      final _Session second = _Session(harness.order, harness.sessions);
      addTearDown(second.dispose);

      harness.bindings.fire(_literal);
      await _deliver(tester);

      final WindowLogState window = _container(tester).read(windowLogProvider);
      expect(_messages(window.entries), <String>[_expectedLine]);
      expect(_messages(harness.session.state.operationLog), <String>[
        _expectedLine,
      ]);
      expect(_messages(second.state.operationLog), <String>[_expectedLine]);
      await tester.pump(const Duration(seconds: 1));
    },
  );

  testWidgets('a burst of the same report is one line and a count', (
    WidgetTester tester,
  ) async {
    final _Harness harness = await _pumpApp(tester);

    harness.bindings
      ..fire(_literal)
      ..fire(_literal)
      ..fire(_literal);
    await _deliver(tester);
    expect(_messages(harness.session.state.operationLog), <String>[
      _expectedLine,
    ]);

    await tester.pump(const Duration(seconds: 1));
    final List<String> lines = _messages(harness.session.state.operationLog);
    expect(lines, hasLength(2));
    expect(lines.last, contains('(repeated x2)'));
  });

  // A session closing can still report, and a closed NativeCallable aborts when invoked.
  testWidgets(
    'quitting closes the sessions, and only then clears the callback',
    (WidgetTester tester) async {
      final _Harness harness = await _pumpApp(tester);

      final AppExitResponse response = await tester.binding
          .handleRequestAppExit();

      expect(response, AppExitResponse.exit);
      expect(harness.order, <String>['session closed', 'callback cleared']);
    },
  );

  testWidgets(
    'unmounting with a count pending neither throws nor leaves a timer',
    (WidgetTester tester) async {
      final _Harness harness = await _pumpApp(tester);
      harness.bindings
        ..fire(_literal)
        ..fire(_literal);
      await _deliver(tester);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(tester.takeException(), isNull);
      expect(harness.bindings.registered.last, nullptr);
    },
  );
}
