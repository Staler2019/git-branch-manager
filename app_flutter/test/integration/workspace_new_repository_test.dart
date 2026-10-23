// File → New repository… through the real WorkspaceScreen: the action's line
// lands in the session the user started it from (epoch 4.1's sink table).
// Until this file, that wiring was confirmed by reading only (ledger
// 2026-10-18, verifier advisory A1).
import 'dart:ffi';

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
import 'package:gbm_flutter/routing/app_router.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:go_router/go_router.dart';

import '../support/fake_repo_session.dart';
import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity.forWorkDir('/test/repo');

class _FailingInit extends FakeGbmBindings {
  static const String _error =
      '{"code":2,"codeName":"InvalidArgument",'
      '"message":"A repository path is required","detail":"",'
      '"argv":[],"exitCode":0}';

  @override
  RepoInitDart get repoInit =>
      (Pointer<Utf8> path, Pointer<Utf8> initialBranch) => -3;

  @override
  LastResultJsonLenDart get lastResultJsonLen =>
      () => _error.length;

  @override
  LastResultJsonCopyDart get lastResultJsonCopy =>
      (Pointer<Uint8> out, int outLen) {
        for (int i = 0; i < outLen && i < _error.length; i++) {
          out[i] = _error.codeUnitAt(i);
        }
      };
}

/// One enabled base folder, so 位置 starts at `/repos`.
class _Discovery extends StateNotifier<DiscoveryState>
    implements DiscoveryController {
  _Discovery()
    : super(
        const DiscoveryState(
          baseFolders: <BaseFolderRecord>[
            BaseFolderRecord(
              id: 1,
              path: '/repos',
              enabled: true,
              maxDepth: 3,
              followLinks: false,
              lastScanStarted: 0,
              lastScanFinished: 0,
              lastScanDirs: 0,
              lastScanMs: 0,
              lastScanSkipped: 0,
            ),
          ],
        ),
      );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('not used');
}

void main() {
  testWidgets('a failed New repository… is an error line in this session', (
    tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: _identity,
      overrides: <Override>[
        gbmBindingsProvider.overrideWithValue(_FailingInit()),
        discoveryProvider.overrideWith((ref) => _Discovery()),
      ],
      topLevelRoutes: <RouteBase>[newRepositoryDialogRoute()],
    );

    await tester.tap(find.text('File'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New repository…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('new-repo-name-field')),
      'blocked',
    );
    await tester.pump();
    await tester.tap(find.widgetWithText(GbmButton, 'Create repository'));
    await tester.pumpAndSettle();

    expect(
      pumped.controller.state.operationLog.whereType<AppLogEntry>().map(
        (AppLogEntry e) => (e.level, e.message),
      ),
      <(OperationLogLevel, String)>[
        (
          OperationLogLevel.error,
          'Could not create a repository at /repos/blocked: '
              'A repository path is required',
        ),
      ],
    );
  });
}
