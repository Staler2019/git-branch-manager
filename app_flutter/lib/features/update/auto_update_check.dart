import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/update_state.dart';
import '../../data/repositories/app_preferences_repository.dart';
import '../../data/repositories/update_repository.dart';
import '../../theme/theme_mode_provider.dart';

/// When the last automatic check was attempted, as an ISO-8601 string.
///
/// A raw key rather than an [AppPreferences] field: this is state, not a
/// setting. Nothing in Preferences shows or edits it, and putting it there
/// would make the dialog's own "every field here is a setting the user can
/// see" shape untrue. Same call as `panelLayout.*`.
const String kLastAutoUpdateCheckKey = 'update.lastAutoCheck';

/// How long a recorded attempt suppresses the next one.
///
/// GitHub allows 60 unauthenticated requests per hour per IP; one a day is
/// far under it, and an app that is opened and closed twenty times in a
/// morning has no reason to ask twenty times.
const Duration kAutoUpdateCheckInterval = Duration(hours: 24);

/// How long after launch the check fires. Overridden in tests.
///
/// Not zero in production: the first seconds after launch are spent opening
/// the last repository, and a check racing that would compete for exactly
/// the moment the window is supposed to become usable.
final Provider<Duration> autoUpdateCheckDelayProvider = Provider<Duration>(
  (Ref ref) => const Duration(seconds: 5),
);

/// Injected so the once-a-day gate can be exercised without waiting a day.
final Provider<DateTime Function()> autoUpdateClockProvider =
    Provider<DateTime Function()>((Ref ref) => DateTime.now);

/// Runs the startup update check and hands an available release to
/// [onUpdateAvailable].
///
/// Mounted above the router rather than inside `WorkspaceScreen`: with no
/// repository open the app renders `WelcomeScreen`, which has no menu bar
/// and would never run a check hung off the workspace.
///
/// Renders [child] unchanged -- this widget contributes no layout.
class AutoUpdateCheck extends ConsumerStatefulWidget {
  const AutoUpdateCheck({
    super.key,
    required this.child,
    required this.onUpdateAvailable,
  });

  final Widget child;

  /// Called at most once per mount, and only when the check ends with a
  /// release worth offering. Supplied by the caller rather than pushing a
  /// route here, so this widget needs no opinion about routing and a test
  /// can observe the decision directly.
  final VoidCallback onUpdateAvailable;

  @override
  ConsumerState<AutoUpdateCheck> createState() => _AutoUpdateCheckState();
}

class _AutoUpdateCheckState extends ConsumerState<AutoUpdateCheck> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // A Timer rather than Future.delayed, so dispose can cancel it: the
    // window can close inside the delay, and a callback that outlives its
    // widget would read a disposed container.
    _timer = Timer(ref.read(autoUpdateCheckDelayProvider), _fire);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fire() async {
    // Read now, not at mount: a user who turns the setting off during the
    // delay has turned it off. Off means no request is made at all, not a
    // request whose answer is discarded.
    if (!ref.read(appPreferencesProvider).autoUpdateCheckEnabled) {
      return;
    }
    final SharedPreferences store = ref.read(sharedPreferencesProvider);
    final DateTime now = ref.read(autoUpdateClockProvider)();
    if (!_isDue(store, now)) {
      return;
    }

    // Recorded before the check, not after. A failed check therefore uses
    // up the day, which costs an offline launch its check -- accepted,
    // because the alternative needs the controller to report whether the
    // network answered, and `checkAutomatically` deliberately collapses
    // "up to date" and "unreachable" into the same silent outcome. Marking
    // afterwards would mean reopening that distinction for a marginal gain.
    await store.setString(kLastAutoUpdateCheckKey, now.toIso8601String());
    if (!mounted) return;

    await ref.read(updateProvider.notifier).checkAutomatically();
    if (!mounted) return;

    // Read straight back rather than through `ref.listen`. The credential
    // dialog listens because its trigger arrives from FFI with no call site
    // to await; here the call site is this line. A listener would also fire
    // for a *manual* check -- the update dialog runs one on mount -- and
    // push a second copy of the dialog on top of the one already open.
    if (ref.read(updateProvider).status == UpdateStatus.available) {
      widget.onUpdateAvailable();
    }
  }

  bool _isDue(SharedPreferences store, DateTime now) {
    final String? last = store.getString(kLastAutoUpdateCheckKey);
    if (last == null) return true;
    final DateTime? at = DateTime.tryParse(last);
    // An unreadable timestamp checks rather than blocks: a corrupt value
    // must not silence updates forever.
    if (at == null) return true;
    return now.difference(at) >= kAutoUpdateCheckInterval;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
