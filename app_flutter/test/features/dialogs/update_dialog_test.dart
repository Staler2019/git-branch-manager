import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/app_version.dart';
import 'package:gbm_flutter/data/models/release_asset.dart';
import 'package:gbm_flutter/data/models/update_state.dart';
import 'package:gbm_flutter/data/repositories/open_repo_sessions.dart';
import 'package:gbm_flutter/data/repositories/update_repository.dart';
import 'package:gbm_flutter/data/services/desktop_launcher.dart';
import 'package:gbm_flutter/data/services/github_release_gateway.dart';
import 'package:gbm_flutter/features/dialogs/update/update_dialog.dart';

import '../../support/pump_app.dart';

const ReleaseAsset _asset = ReleaseAsset(
  name: 'git-branch-manager-9.9.9-macos-arm64.dmg',
  downloadUrl: 'https://example.test/macos.dmg',
  sizeBytes: 24000000,
);

final LatestRelease _release = LatestRelease(
  version: const AppVersion(9, 9, 9),
  tagName: 'v9.9.9',
  htmlUrl: 'https://example.test/releases/tag/v9.9.9',
  notes: 'Faster blame on very large repositories.',
  assets: const <ReleaseAsset>[_asset],
);

/// Mirrors `FakeRepoSessionController`'s shape: a real subclass whose
/// overridden methods record instead of acting, so the widget is driven
/// through the same notifier API it uses in production.
class _FakeUpdate extends UpdateController {
  _FakeUpdate(UpdateState initial)
    : super(
        gateway: const GithubReleaseGateway(),
        currentVersion: const AppVersion(0, 30, 0),
      ) {
    state = initial;
  }

  final List<String> calls = <String>[];

  @override
  Future<void> check() async => calls.add('check');

  @override
  Future<void> download() async => calls.add('download');

  @override
  Future<void> install({required Future<void> Function() beforeExit}) async {
    calls.add('install');
    await beforeExit();
  }

  @override
  void cancel() => calls.add('cancel');

  @override
  void dismiss() => calls.add('dismiss');
}

class _RecordingLauncher extends DesktopLauncher {
  _RecordingLauncher() : super(operatingSystem: 'macos');

  final List<String> urls = <String>[];

  @override
  Future<bool> openUrl(String url) async {
    urls.add(url);
    return true;
  }
}

Future<_FakeUpdate> _pumpDialog(
  WidgetTester tester,
  UpdateState state, {
  DesktopLauncher? launcher,
  OpenRepoSessions? sessions,
}) async {
  final _FakeUpdate fake = _FakeUpdate(state);
  await pumpGbmWidget(
    tester,
    child: const UpdateDialogContent(),
    overrides: <Override>[
      updateProvider.overrideWith((Ref ref) => fake),
      if (launcher != null) desktopLauncherProvider.overrideWithValue(launcher),
      if (sessions != null)
        openRepoSessionsProvider.overrideWithValue(sessions),
    ],
  );
  await tester.pump();
  return fake;
}

void main() {
  group('UpdateDialogContent', () {
    testWidgets('checks once when opened with nothing in flight', (
      WidgetTester tester,
    ) async {
      final _FakeUpdate fake = await _pumpDialog(
        tester,
        const UpdateState.idle(),
      );

      expect(fake.calls, <String>['check']);
    });

    // Re-opening while a download is running must not restart the check and
    // throw away the bytes already fetched.
    testWidgets('does not re-check while an update is already in flight', (
      WidgetTester tester,
    ) async {
      final _FakeUpdate fake = await _pumpDialog(
        tester,
        UpdateState.downloading(
          release: _release,
          asset: _asset,
          downloadedBytes: 100,
          totalBytes: 200,
        ),
      );

      expect(fake.calls, isEmpty);
    });

    testWidgets('says a developer build is not updatable', (
      WidgetTester tester,
    ) async {
      await _pumpDialog(tester, const UpdateState.developmentBuild());

      expect(find.textContaining('Development build'), findsOneWidget);
      expect(find.text('Download and install'), findsNothing);
    });

    testWidgets('names the latest version when already up to date', (
      WidgetTester tester,
    ) async {
      await _pumpDialog(tester, UpdateState.upToDate(_release));

      expect(find.textContaining('9.9.9'), findsOneWidget);
      expect(find.text('Download and install'), findsNothing);
    });

    testWidgets('offers the download and shows the release notes', (
      WidgetTester tester,
    ) async {
      final _FakeUpdate fake = await _pumpDialog(
        tester,
        UpdateState.available(release: _release, asset: _asset),
      );

      expect(
        find.textContaining('Faster blame on very large repositories.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Download and install'));
      await tester.pump();

      expect(fake.calls, contains('download'));
    });

    // The degradation path. Offering a download that can never be installed
    // would waste 24MB and end in a failure the user cannot act on.
    testWidgets('replaces the download button with a link when blocked', (
      WidgetTester tester,
    ) async {
      final _RecordingLauncher launcher = _RecordingLauncher();
      await _pumpDialog(
        tester,
        UpdateState.available(
          release: _release,
          blockedReason: 'The install directory is not writable by this user.',
        ),
        launcher: launcher,
      );

      expect(find.text('Download and install'), findsNothing);
      expect(find.textContaining('not writable'), findsOneWidget);

      await tester.tap(find.text('Open releases page'));
      await tester.pump();

      expect(launcher.urls, <String>[GbmUrls.releasesPage]);
    });

    testWidgets('cancels a download in progress', (WidgetTester tester) async {
      final _FakeUpdate fake = await _pumpDialog(
        tester,
        UpdateState.downloading(
          release: _release,
          asset: _asset,
          downloadedBytes: 120,
          totalBytes: 240,
        ),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pump();

      expect(fake.calls, contains('cancel'));
    });

    // The install call has to release the FFI sessions before the process
    // exits, or an interrupted refresh strands a git child holding
    // .git/index.lock. Asserted through the real callback the dialog passes,
    // not by reading the dialog's source.
    testWidgets('closes every open session before handing over', (
      WidgetTester tester,
    ) async {
      final _CountingSessions sessions = _CountingSessions();
      final _FakeUpdate fake = await _pumpDialog(
        tester,
        UpdateState.readyToInstall(
          release: _release,
          asset: _asset,
          downloadedPath: '/tmp/x.dmg',
        ),
        sessions: sessions,
      );

      await tester.tap(find.text('Install and restart'));
      await tester.pump();

      expect(fake.calls, contains('install'));
      expect(sessions.closeAllCalls, 1);
    });

    // Past the point of no return: the detached script is already running.
    testWidgets('offers nothing to press while installing', (
      WidgetTester tester,
    ) async {
      await _pumpDialog(
        tester,
        UpdateState.installing(
          release: _release,
          asset: _asset,
          downloadedPath: '/tmp/x.dmg',
        ),
      );

      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Install and restart'), findsNothing);
    });

    testWidgets('shows a failure and offers to try again', (
      WidgetTester tester,
    ) async {
      final _FakeUpdate fake = await _pumpDialog(
        tester,
        const UpdateState.failed('The update check failed: no network.'),
      );

      expect(find.textContaining('no network'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();

      expect(fake.calls, contains('check'));
    });

    // CLAUDE.md's cancel-surface section: an indeterminate indicator
    // schedules frames forever, so any test that pumpAndSettle()s a screen
    // showing one times out instead of failing on its own assertion. This
    // dialog must never render one, in any state.
    testWidgets('never renders an indeterminate progress indicator', (
      WidgetTester tester,
    ) async {
      final List<UpdateState> every = <UpdateState>[
        const UpdateState.idle(),
        const UpdateState.checking(),
        const UpdateState.developmentBuild(),
        UpdateState.upToDate(_release),
        UpdateState.available(release: _release, asset: _asset),
        UpdateState.available(release: _release, blockedReason: 'no'),
        UpdateState.downloading(release: _release, asset: _asset),
        UpdateState.verifying(
          release: _release,
          asset: _asset,
          downloadedPath: '/tmp/x',
        ),
        UpdateState.readyToInstall(
          release: _release,
          asset: _asset,
          downloadedPath: '/tmp/x',
        ),
        UpdateState.installing(
          release: _release,
          asset: _asset,
          downloadedPath: '/tmp/x',
        ),
        const UpdateState.failed('boom'),
      ];

      for (final UpdateState state in every) {
        await _pumpDialog(tester, state);
        expect(
          find.byWidgetPredicate(
            (Widget w) => w is ProgressIndicator && w.value == null,
          ),
          findsNothing,
          reason: '${state.status} renders an indeterminate indicator',
        );
      }
    });
  });
}

class _CountingSessions implements OpenRepoSessions {
  int closeAllCalls = 0;

  @override
  void closeAll() => closeAllCalls++;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
