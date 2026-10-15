// Device-tier E2E for the status bar's Cancel on a running git action.
//
// Why this tier: `gbm_cancel_operation` is bound across `dart:ffi`, and its
// return value changed meaning this round (a status code, with a refusal also
// raised as GBM_EVENT_ERROR_OCCURRED). `lookupFunction` matches by symbol name
// only ([TEST-ffi-matches-symbol-only]), and every `test/**` suite runs on
// FakeGbmBindings -- so only here does a real Cancel click reach core's
// OperationRunner::cancel(id) and come back.
//
// The push is held mid-flight by a pre-receive hook that waits for a release
// file, the same technique as tests/capi/CancelOperationApiTest.cpp's
// HeldPushTest. A push updates refs inside one git call, so core must refuse
// the cancel (使用者裁定 2026-10-15: 「capi不行cancel會拋錯」) and the push
// must still land once released.
//
// The test polls the bare remote's ref file, never git: a dart:io Process
// alive while core runs git breaks that git ([TEST-no-dart-process-while-
// core-runs-git]).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/app.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/status_bar/status_bar.dart';
import 'package:integration_test/integration_test.dart';

import 'support/real_repo_harness.dart';

Finder _statusBarCancel() => find.descendant(
  of: find.byType(StatusBar),
  matching: find.widgetWithText(TextButton, 'Cancel'),
);

String? _remoteMain(String originPath) {
  final File ref = File('$originPath/refs/heads/main');
  return ref.existsSync() ? ref.readAsStringSync().trim() : null;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late String repoPath;
  late String originPath;
  late File release;

  setUp(() {
    repoPath = createTempGitRepo();
    originPath = Directory.systemTemp
        .createTempSync('gbm_e2e_origin_')
        .resolveSymbolicLinksSync();
    Process.runSync('git', <String>[
      'init',
      '--bare',
      '--initial-branch=main',
      originPath,
    ]);
    runGit(repoPath, <String>['remote', 'add', 'origin', originPath]);
    // A push writes a loose ref, so _remoteMain reads it without git.
    runGit(repoPath, <String>['push', '--set-upstream', 'origin', 'main']);

    release = File('$originPath-release');
    final File hook = File('$originPath/hooks/pre-receive');
    hook.writeAsStringSync(
      '#!/bin/sh\n'
      "while [ ! -f '${release.path.replaceAll(r'\', '/')}' ]; "
      'do sleep 0.05; done\n'
      'exit 0\n',
    );
    if (!Platform.isWindows) {
      Process.runSync('chmod', <String>['+x', hook.path]);
    }

    File('$repoPath/README.md').writeAsStringSync('# changed\n');
    runGit(repoPath, <String>['commit', '-am', 'second']);
  });

  tearDown(() {
    if (!release.existsSync()) release.writeAsStringSync('go\n');
    deleteTempGitRepo(repoPath);
    deleteTempGitRepo(originPath);
    if (release.existsSync()) release.deleteSync();
  });

  testWidgets(
    'Cancel on a running push is refused by core and the push still lands',
    (tester) async {
      final String head = runGit(repoPath, <String>[
        'rev-parse',
        'HEAD',
      ]).stdout.toString().trim();
      expect(_remoteMain(originPath), isNot(head));

      await pumpRealAppOn(tester, repoPath);
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(GbmApp)),
        listen: false,
      );
      final RepoIdentity identity = RepoIdentity.forWorkDir(repoPath);
      container
          .read(repoSessionProvider(identity).notifier)
          .pushChanges(remoteName: 'origin');

      // The bar is indeterminate while the push runs, so pumpAndSettle could
      // only time out ([TEST-no-pumpandsettle-with-spinner]).
      await pumpUntil(
        tester,
        () => find.text('Pushing origin').evaluate().isNotEmpty,
        maxAttempts: 100,
      );
      expect(
        find.descendant(
          of: find.byType(StatusBar),
          matching: find.text('Pushing origin'),
        ),
        findsOneWidget,
        reason: 'the held push is a running record with a queued id',
      );
      expect(
        tester.widget<TextButton>(_statusBarCancel()).onPressed,
        isNotNull,
        reason: 'whether it can stop is core\'s call; the button always asks',
      );

      await tester.tap(_statusBarCancel());
      await pumpUntil(
        tester,
        () =>
            container.read(repoSessionProvider(identity)).lastError?.codeName ==
            'NotCancellable',
      );
      expect(
        container.read(repoSessionProvider(identity)).lastError?.codeName,
        'NotCancellable',
        reason: 'core refuses to stop a push mid-flight and says so',
      );
      expect(
        _remoteMain(originPath),
        isNot(head),
        reason: 'still held: the refusal must not have finished the push',
      );

      release.writeAsStringSync('go\n');
      await pumpUntil(
        tester,
        () => _remoteMain(originPath) == head,
        maxAttempts: 100,
      );
      expect(
        _remoteMain(originPath),
        head,
        reason: 'a refused cancel leaves the push to run to completion',
      );
    },
  );
}
