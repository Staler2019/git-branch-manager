import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_preferences_repository.dart';
import 'gbm_bindings_provider.dart';

/// Keeps core's git timeout multiplier equal to
/// [AppPreferences.gitTimeoutMultiplier] for the whole life of the app.
///
/// Pushes the stored value when first read and again on every change. The
/// multiplier is process-wide in core and git runs before any repository is
/// open too -- a clone from the welcome screen has no session -- so the push
/// belongs to the app: [GbmApp] watches this, and `repoSessionProvider`
/// reads it before a session's first read. It used to live in
/// `repoSessionProvider` alone, which left that clone, and any change made
/// with no repository open, at 1x.
///
/// `read` + `listen` rather than `watch`: watching the preferences would
/// re-push on every unrelated preference change.
final Provider<void> gitTimeoutMultiplierSyncProvider = Provider<void>((ref) {
  final bindings = ref.read(gbmBindingsProvider);
  bindings.setTimeoutMultiplier(
    ref.read(appPreferencesProvider).gitTimeoutMultiplier,
  );
  ref.listen<AppPreferences>(appPreferencesProvider, (
    AppPreferences? previous,
    AppPreferences next,
  ) {
    if (previous?.gitTimeoutMultiplier != next.gitTimeoutMultiplier) {
      bindings.setTimeoutMultiplier(next.gitTimeoutMultiplier);
    }
  });
});
