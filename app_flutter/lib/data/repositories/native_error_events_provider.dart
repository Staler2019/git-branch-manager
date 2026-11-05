import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/native_error_events.dart';
import 'gbm_bindings_provider.dart';
import 'open_repo_sessions.dart';

/// Owns the process-wide native error channel. It is closed after the sessions on every
/// way out of the process that closes them: a session closing can still report, and
/// invoking a closed `NativeCallable` aborts.
final Provider<GbmNativeErrorEvents> nativeErrorEventsProvider =
    Provider<GbmNativeErrorEvents>((Ref ref) {
      final GbmNativeErrorEvents events = GbmNativeErrorEvents(
        ref.read(gbmBindingsProvider),
      );
      ref.read(openRepoSessionsProvider).addAfterCloseAll(events.dispose);
      ref.onDispose(events.dispose);
      return events;
    });
