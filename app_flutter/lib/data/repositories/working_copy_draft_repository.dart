import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/theme_mode_provider.dart';
import 'repo_identity.dart';

/// Persists the commit message draft of one repository, so closing the app
/// mid-sentence does not throw the sentence away.
///
/// Only the message is stored. [WorkingCopyDraft.diffScrollOffset] stays in
/// memory on purpose: it is an offset into a diff of whichever file was
/// selected, and after a restart nothing is selected, so restoring it would
/// scroll something else to an arbitrary place.
class WorkingCopyDraftRepository {
  WorkingCopyDraftRepository(this._prefs);

  final SharedPreferences _prefs;

  /// Keyed by working directory, so two open repositories keep two drafts
  /// and neither inherits the other's half-written message.
  static String _key(RepoIdentity identity) =>
      'workingCopyDraft:${identity.workDir}';

  /// One list of exactly two entries rather than two keys: a message is one
  /// thing, and two `setString` calls can half-land, leaving a body with
  /// somebody else's subject.
  WorkingCopyDraft read(RepoIdentity identity) {
    final List<String>? stored = _prefs.getStringList(_key(identity));
    if (stored == null || stored.length != 2) return const WorkingCopyDraft();
    return WorkingCopyDraft(summary: stored[0], description: stored[1]);
  }

  Future<void> write(RepoIdentity identity, WorkingCopyDraft draft) {
    return _prefs.setStringList(_key(identity), <String>[
      draft.summary,
      draft.description,
    ]);
  }

  Future<void> clear(RepoIdentity identity) => _prefs.remove(_key(identity));
}

final Provider<WorkingCopyDraftRepository> workingCopyDraftRepositoryProvider =
    Provider<WorkingCopyDraftRepository>((Ref ref) {
      return WorkingCopyDraftRepository(ref.watch(sharedPreferencesProvider));
    });

/// Immutable snapshot of working copy commit message draft and diff scroll state.
/// Created with default values; updated via [WorkingCopyDraftController] methods.
class WorkingCopyDraft {
  const WorkingCopyDraft({
    this.summary = '',
    this.description = '',
    this.diffScrollOffset = 0.0,
    this.amending = false,
    this.preAmendSummary = '',
    this.preAmendDescription = '',
  });

  /// First line of the commit message (typically treated separately by Git).
  final String summary;

  /// Additional commit message body (lines after the first).
  final String description;

  /// Scroll position in the diff pane (in logical pixels), preserved when
  /// switching between history and working-copy tabs.
  final double diffScrollOffset;

  /// Whether the message box is amending the last commit rather than
  /// writing a new one.
  ///
  /// A mode, not a second button: the box shows HEAD's message so it can be
  /// edited, and the only way to see what you are about to rewrite is for
  /// the box to hold it. Never persisted -- coming back tomorrow to a box
  /// silently poised to rewrite a commit you no longer remember is the one
  /// thing this mode must not do.
  final bool amending;

  /// What the box held before [amending] began, restored by cancelling.
  final String preAmendSummary;
  final String preAmendDescription;

  /// Creates a copy with any fields optionally replaced.
  WorkingCopyDraft copyWith({
    String? summary,
    String? description,
    double? diffScrollOffset,
    bool? amending,
    String? preAmendSummary,
    String? preAmendDescription,
  }) {
    return WorkingCopyDraft(
      summary: summary ?? this.summary,
      description: description ?? this.description,
      diffScrollOffset: diffScrollOffset ?? this.diffScrollOffset,
      amending: amending ?? this.amending,
      preAmendSummary: preAmendSummary ?? this.preAmendSummary,
      preAmendDescription: preAmendDescription ?? this.preAmendDescription,
    );
  }
}

/// State notifier for mutable working copy draft state.
/// Updates are applied via copyWith() -- never in-place mutation.
class WorkingCopyDraftController extends StateNotifier<WorkingCopyDraft> {
  WorkingCopyDraftController(this._repo, this._identity)
    : super(_repo.read(_identity));

  final WorkingCopyDraftRepository _repo;
  final RepoIdentity _identity;

  Future<void>? _inFlight;
  bool _dirty = false;

  /// Updates the commit message summary (first line).
  void updateSummary(String value) {
    state = state.copyWith(summary: value);
    _persist();
  }

  /// Updates the commit message description (body text).
  void updateDescription(String value) {
    state = state.copyWith(description: value);
    _persist();
  }

  /// Updates the diff pane scroll offset (in logical pixels).
  ///
  /// Memory only -- see [WorkingCopyDraftRepository]'s doc comment.
  void updateDiffScrollOffset(double value) {
    state = state.copyWith(diffScrollOffset: value);
  }

  /// Enters amend mode, keeping what the box held so cancelling can put it
  /// back.
  ///
  /// Does **not** fill in HEAD's message: that arrives asynchronously and is
  /// applied by [applyAmendedMessage]. Assuming it is already in
  /// `commitMetaCache` would give an empty box whenever the user has not
  /// scrolled History far enough to have loaded it.
  void beginAmend() {
    if (state.amending) return;
    state = state.copyWith(
      amending: true,
      preAmendSummary: state.summary,
      preAmendDescription: state.description,
    );
  }

  /// Fills the box in from HEAD's commit message.
  void applyAmendedMessage({
    required String summary,
    required String description,
  }) {
    if (!state.amending) return;
    state = state.copyWith(summary: summary, description: description);
    _persist();
  }

  /// Leaves amend mode, putting back whatever the box held before it.
  void cancelAmend() {
    if (!state.amending) return;
    state = state.copyWith(
      amending: false,
      summary: state.preAmendSummary,
      description: state.preAmendDescription,
      preAmendSummary: '',
      preAmendDescription: '',
    );
    _persist();
  }

  /// Resets all fields to their defaults, on disk as well as in memory.
  /// Called after a successful commit: the message has become a commit, and
  /// offering it again on the next launch would invite committing it twice.
  void reset() {
    _dirty = false;
    state = const WorkingCopyDraft();
    unawaited(_repo.clear(_identity));
  }

  /// Coalesces writes instead of doing one per keystroke: while a write is
  /// in flight, later edits only set a flag, and one more write happens when
  /// it lands.
  ///
  /// **Not the 500ms debounce timer the plan specified.** A [Timer] inside a
  /// widget makes every widget test that types into the box responsible for
  /// draining it or failing on a pending timer -- the same infectious
  /// obligation the temporary-scope round hit. Coalescing needs no timer and
  /// loses strictly less on a hard crash: at most the keystrokes made during
  /// one disk write, rather than a fixed 500ms of them.
  void _persist() {
    _dirty = true;
    _inFlight ??= _drain();
  }

  Future<void> _drain() async {
    while (_dirty) {
      _dirty = false;
      await _repo.write(_identity, state);
    }
    _inFlight = null;
  }
}

/// Provider for per-repository working copy draft state.
///
/// Keyed by [RepoIdentity], so each open repository keeps its own draft
/// independently. The provider is NOT autoDispose -- state must survive the
/// WorkingCopyView widget rebuilding when the user switches between the
/// History and Working Copy tabs. The ShellRoute (features/workspace) stays
/// mounted across that switch and is the provider's implied watcher; only
/// when the entire repo ShellRoute unmounts does the provider dispose.
///
/// Since the message is also on disk, disposal is no longer where a draft
/// goes to die -- closing the repository and reopening it brings the
/// half-written message back.
final workingCopyDraftProvider =
    StateNotifierProvider.family<
      WorkingCopyDraftController,
      WorkingCopyDraft,
      RepoIdentity
    >(
      (Ref ref, RepoIdentity identity) => WorkingCopyDraftController(
        ref.watch(workingCopyDraftRepositoryProvider),
        identity,
      ),
    );
