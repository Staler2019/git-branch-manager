import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/open_repo_sessions.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';

import '../../support/fake_repo_session.dart';

/// The registry that lets something outside the `repoSessionProvider` family
/// close every live session.
///
/// It exists because the self-install flow has to release the FFI sessions
/// before `exit(0)`: a refresh interrupted by the process vanishing leaves an
/// orphaned `git` child holding `.git/index.lock` in a repository the user
/// still has open. Riverpod cannot enumerate a family's live instances, so
/// each controller registers itself.
class _Recorder implements ClosableRepoSession {
  int closes = 0;

  @override
  void closeNativeSession() => closes++;
}

void main() {
  group('OpenRepoSessions', () {
    test('closes every registered session', () {
      final OpenRepoSessions registry = OpenRepoSessions();
      final _Recorder a = _Recorder();
      final _Recorder b = _Recorder();
      registry
        ..register(a)
        ..register(b);

      registry.closeAll();

      expect(a.closes, 1);
      expect(b.closes, 1);
    });

    test('does not close a session that has already been disposed', () {
      final OpenRepoSessions registry = OpenRepoSessions();
      final _Recorder gone = _Recorder();
      final _Recorder live = _Recorder();
      registry
        ..register(gone)
        ..register(live)
        ..unregister(gone);

      registry.closeAll();

      expect(gone.closes, 0);
      expect(live.closes, 1);
    });

    // Registering twice must not double-close: `closeNativeSession` is
    // idempotent on the real controller, but a registry that grows a
    // duplicate is hiding a leak rather than tolerating one.
    test('holds each session once', () {
      final OpenRepoSessions registry = OpenRepoSessions();
      final _Recorder only = _Recorder();
      registry
        ..register(only)
        ..register(only);

      registry.closeAll();

      expect(only.closes, 1);
    });

    // Through the real RepoSessionController base class, not a stand-in:
    // the thing that can regress is the registration call sitting in a
    // constructor and the unregistration sitting in dispose, and only the
    // real class has those.
    test('a live controller registers itself and unregisters on dispose', () {
      final OpenRepoSessions registry = OpenRepoSessions();
      final _TrackingSession session = _TrackingSession(registry);

      registry.closeAll();
      expect(session.closes, 1, reason: 'a live session must be reachable');

      // dispose() releases the handle itself, which is correct and is not
      // what is being measured -- the question is only whether the registry
      // can still reach a session that has gone.
      session.dispose();
      final int afterDispose = session.closes;
      registry.closeAll();
      expect(
        session.closes,
        afterDispose,
        reason: 'the registry must not reach a disposed session',
      );
    });

    // closeAll runs immediately before the process exits, so one session
    // that throws must not stop the rest from being released.
    test('keeps going when one session throws', () {
      final OpenRepoSessions registry = OpenRepoSessions();
      final _Recorder after = _Recorder();
      registry
        ..register(_ThrowingSession())
        ..register(after);

      registry.closeAll();

      expect(after.closes, 1);
    });
  });
}

class _ThrowingSession implements ClosableRepoSession {
  @override
  void closeNativeSession() => throw StateError('already gone');
}

/// The real controller, with the one call under test counted on the way
/// through. `FakeRepoSessionController`'s session handle is always null, so
/// the base implementation is a no-op -- what is being pinned is that the
/// registry reaches it at all.
class _TrackingSession extends FakeRepoSessionController {
  _TrackingSession(OpenRepoSessions registry)
    : super(
        RepoIdentity(workDir: '/test/repo', gitDir: '/test/repo/.git'),
        const RepoSessionState(),
        openSessions: registry,
      );

  int closes = 0;

  @override
  void closeNativeSession() {
    closes++;
    super.closeNativeSession();
  }
}
