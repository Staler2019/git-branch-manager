import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repo_identity.dart';
import '../../data/repositories/repo_session_repository.dart';

/// Calls [onSweep] each time a new focus/F5 sweep starts
/// ([RepoSessionController.refreshRepoStatus]) while the caller is mounted.
///
/// For a panel whose data is deliberately *not* in that sweep because the
/// panel is its only reader: it keeps its own `initState` read for the
/// first load, and calls this from `build()` so it stays as fresh as the
/// sweep would have kept it -- without every alt-tab paying for a panel
/// that is usually not on screen.
///
/// Keyed on [RefreshTimings.focusAt], which only `refreshRepoStatus()`
/// replaces; `ref.listen` does not fire for the value already there at
/// mount, and is torn down with the element.
void listenToRefreshSweep(
  WidgetRef ref,
  RepoIdentity identity,
  VoidCallback onSweep,
) {
  ref.listen<DateTime?>(
    repoSessionProvider(identity)
        .select((RepoSessionState s) => s.refreshTimings.focusAt),
    // `select` already fires only when focusAt changes, and only
    // `refreshRepoStatus()` changes it -- never back to null.
    (DateTime? previous, DateTime? next) => onSweep(),
  );
}
