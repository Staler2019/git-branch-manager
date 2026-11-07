// #207's loop broken end to end through the real bootstrapApp: a launch that sets the
// auto-reopen marker clears it once the repository's first load settles, and a launch that
// finds it still set lands on the welcome screen with a row saying why. Only the host is
// mounted, never GbmApp: the welcome screen and workspace need discovery, clone jobs and a
// real session, none of which this is about.
import 'dart:convert';
import 'dart:ffi';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/app_bootstrap.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/auto_reopen_marker_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/repositories/window_log_repository.dart';
import 'package:gbm_flutter/features/app_lifecycle/auto_reopen_host.dart';
import 'package:gbm_flutter/features/app_lifecycle/dart_error_handlers.dart';
import 'package:gbm_flutter/routing/app_router.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/fake_repo_session.dart';

const String _workDir = '/r/工作樹wt';
const String _logPath = '/logs/gbm-native-errors.log';
const String _key = AutoReopenMarkerRepository.key;

class _LogPathBindings extends FakeGbmBindings {
  final List<int> _bytes = utf8.encode('{"path":"$_logPath"}');

  @override
  NativeErrorLogPathJsonDart get nativeErrorLogPathJson =>
      () => 0;

  @override
  LastResultJsonLenDart get lastResultJsonLen =>
      () => _bytes.length;

  @override
  LastResultJsonCopyDart get lastResultJsonCopy =>
      (Pointer<Uint8> out, int outLen) =>
          out.asTypedList(outLen).setAll(0, _bytes.take(outLen));
}

class _Launch {
  _Launch(this.prefs, this.app, this.sessions);

  final SharedPreferences prefs;
  final Widget app;
  final Map<RepoIdentity, FakeRepoSessionController> sessions;
}

Future<_Launch> _bootstrap(Map<String, Object> stored) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'recents.repos': jsonEncode(<Object>[
      <String, Object>{'workDir': _workDir, 'lastOpenedEpochMs': 1},
    ]),
    ...stored,
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final Map<RepoIdentity, FakeRepoSessionController> sessions =
      <RepoIdentity, FakeRepoSessionController>{};
  final Widget app = await bootstrapApp(
    openBindings: _LogPathBindings.new,
    loadPrefs: () async => prefs,
    install: ({required ExternalErrorReport report}) => () {},
    extraOverrides: <Override>[
      repoSessionProvider.overrideWith(
        (Ref ref, RepoIdentity identity) =>
            sessions[identity] = FakeRepoSessionController(
              identity,
              const RepoSessionState(isOpen: true, isRefreshing: true),
            ),
      ),
    ],
    child: const AutoReopenHost(child: SizedBox()),
  );
  return _Launch(prefs, app, sessions);
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(SizedBox)));

String _initialPath(WidgetTester tester) =>
    _container(tester)
        .read(appRouterProvider)
        .routeInformationProvider
        .value
        .uri
        .path;

void main() {
  testWidgets(
    'a launch reopening a repository marks it until its first load settles',
    (WidgetTester tester) async {
      final _Launch launch = await _bootstrap(const <String, Object>{});
      expect(
        launch.prefs.getString(_key),
        _workDir,
        reason: 'on disk before any session opens',
      );

      await tester.pumpWidget(launch.app);
      expect(
        _initialPath(tester),
        RoutePaths.workspaceFor(repoIdFor(_workDir)),
      );
      await tester.pump();
      expect(launch.prefs.getString(_key), _workDir, reason: 'still reading');

      launch.sessions[RepoIdentity.forWorkDir(_workDir)]!.emit(
        const RepoSessionState(isOpen: true),
      );
      await tester.pump();

      expect(launch.prefs.containsKey(_key), isFalse);
    },
  );

  testWidgets(
    'a launch after one that ended while opening lands on welcome, once, and says so',
    (WidgetTester tester) async {
      final _Launch launch = await _bootstrap(const <String, Object>{
        _key: _workDir,
      });
      expect(
        launch.prefs.containsKey(_key),
        isFalse,
        reason: 'skipped once only',
      );

      await tester.pumpWidget(launch.app);
      expect(_initialPath(tester), RoutePaths.welcome);
      await tester.pump();

      final List<GbmLogEntry> rows = _container(tester)
          .read(windowLogProvider)
          .entries;
      expect(rows, hasLength(1));
      expect(rows.single.level, OperationLogLevel.error);
      expect(
        (rows.single as AppLogEntry).message,
        'Skipped reopening $_workDir: git-branch-manager quit while opening it last '
        'time. Open it again from File → Switch repository… (details: $_logPath)',
      );
      expect(launch.sessions, isEmpty, reason: 'nothing reopened');
    },
  );
}
