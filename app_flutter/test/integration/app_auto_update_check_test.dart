import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/app.dart';
import 'package:gbm_flutter/data/models/app_version.dart';
import 'package:gbm_flutter/data/models/release_asset.dart';
import 'package:gbm_flutter/data/repositories/build_version_repository.dart';
import 'package:gbm_flutter/data/services/github_release_gateway.dart';
import 'package:gbm_flutter/data/services/update_installer.dart';
import 'package:gbm_flutter/features/update/auto_update_check.dart';
import 'package:gbm_flutter/features/update/update_leftover_sweep.dart';
import 'package:gbm_flutter/routing/app_router.dart';
import 'package:gbm_flutter/routing/dialog_route.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Crosses the one seam the widget tier cannot: `GbmApp` really mounts the
/// two startup update widgets, and the callback it hands [AutoUpdateCheck]
/// really reaches the update dialog's route.
///
/// Without this, `AutoUpdateCheck` could pass every test it owns while
/// nothing under `lib/` mounted it -- the orphan-wiring shape this repo has
/// already shipped once (the old `deleteRemoteBranchDialog` route) and
/// twice found by audit (`gbm_context_menus.dart`, `readOrder()`).
class _StubGateway extends GithubReleaseGateway {
  _StubGateway(this.tag);

  final String tag;
  int calls = 0;

  @override
  Future<LatestRelease> fetchLatest() async {
    calls++;
    return LatestRelease(
      version: AppVersion.tryParse(tag)!,
      tagName: tag,
      htmlUrl: 'https://example.test/releases/tag/$tag',
      notes: '',
      assets: const <ReleaseAsset>[
        ReleaseAsset(
          name: 'git-branch-manager-9.9.9-linux-x86_64.tar.gz',
          downloadUrl: 'https://example.test/linux.tar.gz',
          sizeBytes: 100,
        ),
        ReleaseAsset(
          name: kChecksumManifestName,
          downloadUrl: 'https://example.test/sha256sums.txt',
          sizeBytes: 10,
        ),
      ],
    );
  }
}

/// Installable, and inert when swept.
///
/// `UpdateLeftoverSweep` is mounted here too, and the real sweep reads the
/// machine's actual `Directory.systemTemp` -- so leaving it live would give
/// this test side effects on the developer's own temp directory. What the
/// sweep does is pinned by its own unit tests.
class _InertSweepInstaller extends UpdateInstaller {
  const _InertSweepInstaller({
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

UpdateInstaller _installable() {
  final Directory install = Directory(
    '${Directory.systemTemp.createTempSync('gbm-app-auto').path}/opt/gbm',
  )..createSync(recursive: true);
  return _InertSweepInstaller(
    operatingSystem: 'linux',
    executablePath: '${install.path}/gbm_flutter',
    abi: Abi.linuxX64,
  );
}

/// A stand-in for the real router: `appRouterProvider`'s own tree starts on
/// `WelcomeScreen`, which needs repository discovery and the native
/// bindings. Neither is what this test is about, and overriding the router
/// keeps the assertion on the wiring rather than on the welcome screen.
GoRouter _router() {
  return GoRouter(
    initialLocation: RoutePaths.welcome,
    routes: <RouteBase>[
      GoRoute(
        path: RoutePaths.welcome,
        builder: (BuildContext c, GoRouterState s) =>
            const Scaffold(body: Text('welcome')),
      ),
      dialogRoute(
        path: RoutePaths.updateDialog,
        builder: (BuildContext c, GoRouterState s) =>
            const Text('update-dialog'),
      ),
    ],
  );
}

Future<_StubGateway> _pumpApp(
  WidgetTester tester, {
  String tag = 'v9.9.9',
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences store = await SharedPreferences.getInstance();
  final _StubGateway gateway = _StubGateway(tag);

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        sharedPreferencesProvider.overrideWithValue(store),
        appRouterProvider.overrideWithValue(_router()),
        githubReleaseGatewayProvider.overrideWithValue(gateway),
        buildVersionProvider.overrideWithValue(const AppVersion(0, 30, 0)),
        updateInstallerProvider.overrideWithValue(_installable()),
        autoUpdateCheckDelayProvider.overrideWithValue(Duration.zero),
      ],
      child: const GbmApp(),
    ),
  );
  return gateway;
}

void main() {
  group('GbmApp startup update check', () {
    testWidgets('mounts the check above the router', (
      WidgetTester tester,
    ) async {
      await _pumpApp(tester);
      await tester.pumpAndSettle();

      expect(find.byType(AutoUpdateCheck), findsOneWidget);
      // Unconditional housekeeping, mounted alongside the check rather than
      // inside it -- turning off update *checking* says nothing about the
      // leftovers of an update that already happened.
      expect(find.byType(UpdateLeftoverSweep), findsOneWidget);
      // Above the router, so it is there on the welcome screen too -- the
      // screen with no menu bar and therefore no manual entry point.
      expect(find.text('welcome'), findsOneWidget);
    });

    testWidgets('an available release opens the update dialog', (
      WidgetTester tester,
    ) async {
      final _StubGateway gateway = await _pumpApp(tester);
      await tester.pumpAndSettle();

      expect(gateway.calls, 1);
      expect(find.text('update-dialog'), findsOneWidget);
    });

    // The whole point of the silence rule: an up-to-date app must open
    // nothing at all on launch.
    testWidgets('an up-to-date app opens nothing', (WidgetTester tester) async {
      final _StubGateway gateway = await _pumpApp(tester, tag: 'v0.30.0');
      await tester.pumpAndSettle();

      expect(gateway.calls, 1);
      expect(find.text('update-dialog'), findsNothing);
      expect(find.text('welcome'), findsOneWidget);
    });
  });
}
