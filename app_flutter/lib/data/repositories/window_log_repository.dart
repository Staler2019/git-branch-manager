import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/operation_record.dart';
import '../models/operation_record.dart' as log_rules show retractLogEntries;
import 'app_preferences_repository.dart';

/// The Log of a window with no repository open (R13). A clone started from
/// the welcome screen that fails or is cancelled has no session to log into;
/// its lines land here, and the welcome screen's Log drawer and status bar
/// read them.
class WindowLogState {
  const WindowLogState({
    this.entries = const <GbmLogEntry>[],
    this.revision = 0,
  });

  /// Newest-last, capped like a session's log.
  final List<GbmLogEntry> entries;

  /// Moves on every change to [entries], including a running row replaced in
  /// place -- what a reader compares to tell an unseen line from a seen one.
  final int revision;
}

class WindowLogController extends StateNotifier<WindowLogState> {
  WindowLogController({required this.maxEntries})
    : super(const WindowLogState());

  final int maxEntries;

  /// An app action's line. Bound as an `AppActionRunner` sink; a no-op once
  /// disposed, since an action can outlive the window that started it.
  void recordAppLog(AppLogEntry entry) => _record(entry);

  /// Any line -- a clone job's git record, its running row with progress,
  /// or an app line -- under the session's append rule.
  void recordLogEntry(GbmLogEntry entry) => _record(entry);

  /// Takes back the git records with these ids: a successful clone's rows
  /// move to the new repository's Log (R12).
  void retractLogEntries(Set<int> ids) {
    if (!mounted) return;
    state = WindowLogState(
      entries: log_rules.retractLogEntries(state.entries, ids),
      revision: state.revision + 1,
    );
  }

  void _record(GbmLogEntry entry) {
    if (!mounted) return;
    state = WindowLogState(
      entries: appendLogEntry(state.entries, entry, maxEntries: maxEntries),
      revision: state.revision + 1,
    );
  }
}

/// One per app run: it outlives the welcome screen's widget, so lines logged
/// while a repository is open are still there when the window comes back.
/// The cap is read once (`ref.read`), as `repoSessionProvider` does.
final StateNotifierProvider<WindowLogController, WindowLogState>
windowLogProvider = StateNotifierProvider<WindowLogController, WindowLogState>(
  (ref) => WindowLogController(
    maxEntries: ref.read(appPreferencesProvider).logMemoryLimit,
  ),
);
