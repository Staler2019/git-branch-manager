// A read that throws inside the real library still releases what Dart waits on: a real
// gbm_capi, a real RepoSessionController and a real git repository, with the throw injected
// by gbm_test_fail_read(), which arms one postRead() name so the reads a session posts on its
// own cannot use it up. Before postRead the pool's own catch only logged, and each wait below
// waited for good.
//
// Needs a library built with tests, so `capi-build` in ci.yml runs this file beside
// native_error_real_library_test.dart. A plain `flutter test` names no library and skips.
// To run it by hand:
//
//   GBM_CAPI_LIBRARY_PATH=$PWD/../build/capi-only/src/capi/libgbm_capi.dylib \
//   GBM_NATIVE_ERROR_LOG_DIR=$(mktemp -d) \
//   flutter test test/data/ffi/read_failure_real_library_test.dart
import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/ffi/native_library.dart';
import 'package:gbm_flutter/data/models/branch_deletion_probe.dart';
import 'package:gbm_flutter/data/repositories/gbm_bindings_provider.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/app_lifecycle/auto_reopen_host.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

typedef _FailReadNative = Void Function(Pointer<Utf8> where);
typedef _FailReadDart = void Function(Pointer<Utf8> where);

/// Long enough for a slow CI runner, short enough that a read which never answers is a red
/// with a message rather than a hang until the job's timeout.
const Duration _replyDeadline = Duration(seconds: 20);

void main() {
  final String? libraryPath = Platform.environment['GBM_CAPI_LIBRARY_PATH'];
  final Object skip = libraryPath == null
      ? 'GBM_CAPI_LIBRARY_PATH is not set'
      : false;

  late Directory repo;
  late ProviderContainer container;
  late RepoSessionController controller;
  late _FailReadDart failRead;

  void git(List<String> args) {
    final ProcessResult result = Process.runSync(
      'git',
      args,
      workingDirectory: repo.path,
    );
    expect(result.exitCode, 0, reason: '${args.join(' ')}: ${result.stderr}');
  }

  void arm(String where) {
    using((Arena arena) => failRead(where.toNativeUtf8(allocator: arena)));
  }

  /// Resolves on the first state [test] accepts, the current one included.
  Future<RepoSessionState> stateWhere(bool Function(RepoSessionState s) test) {
    final Completer<RepoSessionState> reached = Completer<RepoSessionState>();
    final RemoveListener stop = controller.addListener((RepoSessionState s) {
      if (!reached.isCompleted && test(s)) reached.complete(s);
    });
    return reached.future.timeout(_replyDeadline).whenComplete(stop);
  }

  setUp(() async {
    if (libraryPath == null) return;
    // Required rather than defaulted, so that the injected failures never reach the
    // user's real log.
    expect(Platform.environment['GBM_NATIVE_ERROR_LOG_DIR'], isNotNull);
    repo = Directory.systemTemp.createTempSync('gbm-read-failure-');
    addTearDown(() => repo.deleteSync(recursive: true));
    git(<String>['init', '--quiet', '--initial-branch=main']);
    git(<String>['config', 'user.email', 'test@example.invalid']);
    git(<String>['config', 'user.name', 'Test']);
    git(<String>['config', 'commit.gpgsign', 'false']);
    File('${repo.path}/file.txt').writeAsStringSync('hello\n');
    git(<String>['add', 'file.txt']);
    git(<String>['commit', '--quiet', '-m', 'Initial commit']);
    git(<String>['branch', 'feature']);

    final DynamicLibrary library = openGbmCapiLibrary();
    failRead = library.lookupFunction<_FailReadNative, _FailReadDart>(
      'gbm_test_fail_read',
    );
    addTearDown(() => arm(''));

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    container = ProviderContainer(
      overrides: <Override>[
        gbmBindingsProvider.overrideWithValue(GbmBindings(library)),
        sharedPreferencesProvider.overrideWithValue(prefs),
      ],
    );
    addTearDown(container.dispose);
    controller = container.read(
      repoSessionProvider(RepoIdentity.forWorkDir(repo.path)).notifier,
    );
    // Open's own reads first, so each case below starts from a quiet session.
    final RepoSessionState opened = await stateWhere(isFirstLoadSettled);
    expect(opened.lastError, isNull);
  });

  test(
    'a branch deletion probe that throws still answers its request',
    () async {
      arm('Session::requestBranchDeletionProbe');

      final BranchDeletionProbeReply reply = await controller
          .probeBranchDeletion(<String>['feature'])
          .timeout(_replyDeadline);

      expect(reply.error?.codeName, 'Unknown');
      expect(reply.probes, isEmpty);
      expect(controller.state.lastError, isNull);
    },
    skip: skip,
  );

  test('an export that throws still answers for its destination', () async {
    arm('Session::exportFileAtRevision');
    final String destPath = '${repo.path}/exported.txt';

    final FileAtRevisionExport export = await controller
        .exportFileAtRevisionAwaiting(
          revision: 'HEAD',
          path: 'file.txt',
          destPath: destPath,
        )
        .timeout(_replyDeadline);

    expect(export.destPath, destPath);
    expect(export.succeeded, isFalse);
    expect(export.error?.codeName, 'Unknown');
    expect(controller.state.lastError, isNull);
  }, skip: skip);

  test(
    'a history refresh that throws ends the refresh, and the next one runs',
    () async {
      arm('Session::dispatchRefresh');

      controller.refreshHistory();
      final RepoSessionState failed = await stateWhere(
        (RepoSessionState s) => !s.isRefreshing && s.lastError != null,
      );
      expect(failed.lastError?.codeName, 'Unknown');

      final int second = controller.refreshHistory();
      expect(second, isNot(0));
      final RepoSessionState refreshed = await stateWhere(
        (RepoSessionState s) => s.refsCoverRequest >= second && !s.isRefreshing,
      );
      expect(refreshed.lastError, isNull);
    },
    skip: skip,
  );
}
