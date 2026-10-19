// The controller methods a surface calls when a user's own click failed
// (open-with-apps-spec.html, screen 3): each appends one error line through
// withOperationRecord, so operationLogRevision moves and the status bar's
// summary can see it ([FLU-log-row-is-replaced-by-id]).
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

void main() {
  late FakeRepoSessionController controller;

  setUp(() {
    controller = FakeRepoSessionController(
      RepoIdentity.forWorkDir('/test/repo'),
      const RepoSessionState(isOpen: true),
    );
  });
  tearDown(() => controller.dispose());

  void expectOneError(String message) {
    expect(controller.state.operationLog.length, 1);
    final GbmLogEntry entry = controller.state.operationLog.single;
    expect(entry, isA<AppLogEntry>());
    expect(entry.message, message);
    expect(entry.level, OperationLogLevel.error);
    expect(controller.state.operationLogRevision, 1);
  }

  test('recordTerminalNotFound', () {
    controller.recordTerminalNotFound();
    expectOneError('No terminal emulator was found');
  });

  test('recordExternalAppFailed', () {
    controller.recordExternalAppFailed(label: 'Rider', detail: 'boom');
    expectOneError('Could not run "Rider": boom');
  });

  test('recordExportFailed', () {
    controller.recordExportFailed(path: 'a.txt', detail: 'boom');
    expectOneError('Could not export a.txt: boom');
  });

  test('recordLogSaveFailed', () {
    controller.recordLogSaveFailed(detail: 'boom');
    expectOneError('Could not save the log: boom');
  });

  test('recordRepositoryInitFailed', () {
    controller.recordRepositoryInitFailed(path: '/x', detail: 'boom');
    expectOneError('Could not create a repository at /x: boom');
  });

  test('recordAppLog appends the entry as given', () {
    controller.recordAppLog(
      const AppLogEntry(
        whenEpochMs: 1,
        level: OperationLogLevel.error,
        message: 'boom',
      ),
    );
    expectOneError('boom');
  });

  test('recordAppLog after dispose does nothing and does not throw', () {
    final FakeRepoSessionController gone = FakeRepoSessionController(
      RepoIdentity.forWorkDir('/test/gone'),
      const RepoSessionState(isOpen: true),
    )..dispose();
    gone.recordAppLog(
      const AppLogEntry(
        whenEpochMs: 1,
        level: OperationLogLevel.info,
        message: 'late',
      ),
    );
  });
}
