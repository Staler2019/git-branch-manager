import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A repository session whose native handle can be released early.
///
/// Narrower than `RepoSessionController` on purpose: [OpenRepoSessions] has
/// no business with state, events or commands, and a test can satisfy this
/// without standing up an FFI-shaped fake.
abstract interface class ClosableRepoSession {
  /// Releases the `gbm_capi` session handle. Must be idempotent -- the
  /// registry may call it on a session that is already closing.
  void closeNativeSession();
}

/// Every live repository session, so something outside the
/// `repoSessionProvider` family can release them all.
///
/// The self-install flow is the reason this exists: it has to close the FFI
/// sessions before `exit(0)`, or a refresh interrupted by the process
/// vanishing leaves an orphaned `git` child holding `.git/index.lock` in a
/// repository the user still has open -- and the next launch, of the *new*
/// build, opens onto "Another Git process appears to be running".
///
/// Riverpod cannot enumerate a family's live instances, so each controller
/// registers itself on construction and unregisters on dispose rather than
/// this reaching in to find them.
class OpenRepoSessions {
  final Set<ClosableRepoSession> _live = <ClosableRepoSession>{};

  void register(ClosableRepoSession session) => _live.add(session);

  void unregister(ClosableRepoSession session) => _live.remove(session);

  /// Releases every registered session. Runs immediately before the process
  /// exits, so one session failing must not strand the others -- an
  /// unreleased handle here is exactly the orphaned-lock outcome this is
  /// meant to prevent.
  void closeAll() {
    for (final ClosableRepoSession session in _live.toList()) {
      try {
        session.closeNativeSession();
      } on Object {
        // Nothing useful to do: the process is about to end, and there is no
        // surface left to report this on.
      }
    }
  }
}

/// App-scoped, never repo-scoped -- the whole point is to outlive any one
/// repository. Overridden in tests that need to observe registration.
final Provider<OpenRepoSessions> openRepoSessionsProvider =
    Provider<OpenRepoSessions>((Ref ref) => OpenRepoSessions());
