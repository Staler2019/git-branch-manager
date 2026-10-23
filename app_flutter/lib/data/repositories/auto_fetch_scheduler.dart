import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../actions/auto_fetch_gate.dart';

/// `Timer.periodic`'s shape, injected so a test ticks an interval by hand.
typedef AutoFetchPeriodicTimer = Timer Function(
  Duration period,
  void Function(Timer) onTick,
);

/// Spec P11 item 9's periodic fetch for **one** repository session: once when
/// the session opens, then every `autoFetchMinutes`.
///
/// One instance per open repository rather than one per app: 「切換 repo 時計
/// 時器重置」 is then a new instance, and a fetch still finishing in the
/// repository the user left can never clear this one's in-flight flag.
///
/// Owns the two inputs to [decideAutoFetch] that only it can know -- whether
/// its own fetch is in flight and whether an Auth/HostKey failure paused it
/// -- and asks the caller for the rest at each tick.
class AutoFetchScheduler {
  AutoFetchScheduler._(
    this._periodic,
    this._readConditions,
    this._fetch,
    this._onPaused,
  );

  final AutoFetchPeriodicTimer _periodic;
  final AutoFetchConditions Function() _readConditions;
  final void Function() _fetch;
  final void Function(String codeName) _onPaused;

  Timer? _timer;
  bool? _enabled;
  Duration? _interval;
  bool _inFlight = false;
  bool _paused = false;
  bool _disposed = false;

  /// Error codes (`GitError.codeName`) that pause auto fetch until a manual
  /// fetch succeeds (使用者裁定 2026-10-23): retrying a rejected credential
  /// every interval can drop it from the keychain or trip a server's ban.
  /// Anything else -- the network above all -- is retried at the next
  /// interval, as spec P11 item 9 says.
  static const Set<String> pausingErrorCodes = <String>{'Auth', 'HostKey'};

  /// Applies the current Preferences. Called on open and on every change;
  /// the same values again do nothing.
  ///
  /// Turning it on -- including the first call with it on, which is the
  /// session opening -- fetches at once and arms the interval; a new
  /// interval while on re-arms from now without an extra fetch; off cancels
  /// the timer. Below one minute counts as one: a zero period would spin.
  void configure({required bool enabled, required int minutes}) {
    if (_disposed) return;
    final Duration interval = Duration(minutes: math.max(1, minutes));
    if (enabled == _enabled && (!enabled || interval == _interval)) return;
    final bool turningOn = enabled && _enabled != true;
    _enabled = enabled;
    _interval = interval;
    _timer?.cancel();
    _timer = null;
    if (!enabled) return;
    _timer = _periodic(interval, (_) => _tick());
    if (turningOn) _tick();
  }

  /// Reports a fetch of this session finishing -- the auto fetch's own
  /// ([background]) or the user's.
  void onFetchFinished({
    required bool background,
    required bool succeeded,
    String? errorCodeName,
  }) {
    if (_disposed) return;
    if (background) {
      _inFlight = false;
      if (!succeeded && pausingErrorCodes.contains(errorCodeName)) {
        _paused = true;
        _onPaused(errorCodeName!);
      }
    } else if (succeeded) {
      _paused = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }

  void _tick() {
    final AutoFetchDecision decision = decideAutoFetch(
      _readConditions().copyWith(
        pausedAfterAuthFailure: _paused,
        autoFetchInFlight: _inFlight,
      ),
    );
    switch (decision) {
      case AutoFetchRun():
        _inFlight = true;
        _fetch();
      case AutoFetchSkip():
        break;
    }
  }
}

/// Builds [AutoFetchScheduler]s with the app's timer; a test supplies its
/// own [periodic].
class AutoFetchSchedulerFactory {
  const AutoFetchSchedulerFactory({this.periodic = Timer.periodic});

  final AutoFetchPeriodicTimer periodic;

  /// [readConditions] supplies every [AutoFetchConditions] input except the
  /// two the scheduler owns, which it overwrites. [onPaused] fires once per
  /// pause with the error code that caused it, for the caller to say
  /// so in the log.
  AutoFetchScheduler create({
    required AutoFetchConditions Function() readConditions,
    required void Function() fetch,
    required void Function(String codeName) onPaused,
  }) => AutoFetchScheduler._(periodic, readConditions, fetch, onPaused);
}

/// Overridden in tests with a hand-ticked timer.
final Provider<AutoFetchSchedulerFactory> autoFetchSchedulerFactoryProvider =
    Provider<AutoFetchSchedulerFactory>(
      (Ref ref) => const AutoFetchSchedulerFactory(),
    );
