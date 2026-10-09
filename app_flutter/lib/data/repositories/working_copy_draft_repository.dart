import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/theme_mode_provider.dart';
import '../models/prepared_message_policy.dart';
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
    this.preparedEpisodeActive = false,
    this.preparedFilled = false,
    this.prePreparedSummary = '',
    this.prePreparedDescription = '',
    this.hasAutofill = false,
    this.autofilledSummary = '',
    this.autofilledDescription = '',
    this.pendingCommitFrom,
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

  /// A merge or squash has left git a prepared message, and this box has
  /// taken part in it (`prepared_message_policy.dart`). Memory only, like
  /// [amending]: after a restart the episode starts over, which is ruling
  /// ⑪'s 「啟動時也覆蓋」.
  final bool preparedEpisodeActive;

  /// The box was replaced or deliberately kept in this episode.
  final bool preparedFilled;

  /// What the box held before the prepared message replaced it.
  final String prePreparedSummary;
  final String prePreparedDescription;

  /// The box was replaced this episode, and with what -- so ending the
  /// episode can tell an untouched autofill from the user's own edit.
  final bool hasAutofill;
  final String autofilledSummary;
  final String autofilledDescription;

  /// HEAD's oid when a commit from this box was submitted, or null when none
  /// is outstanding. The box is cleared when HEAD moves off it, **not** when
  /// the commit is sent: a commit that failed -- nothing staged, a rejecting
  /// hook, a bad identity -- would otherwise take the message with it.
  /// Memory only; one place sets it ([submitCommit]) for the button, the
  /// shortcut and the menu alike, and `WorkspaceScreen` watches HEAD for it.
  final String? pendingCommitFrom;

  /// Creates a copy with any fields optionally replaced.
  WorkingCopyDraft copyWith({
    String? summary,
    String? description,
    double? diffScrollOffset,
    bool? amending,
    String? preAmendSummary,
    String? preAmendDescription,
    bool? preparedEpisodeActive,
    bool? preparedFilled,
    String? prePreparedSummary,
    String? prePreparedDescription,
    bool? hasAutofill,
    String? autofilledSummary,
    String? autofilledDescription,
    String? pendingCommitFrom,
    bool clearPendingCommit = false,
  }) {
    return WorkingCopyDraft(
      summary: summary ?? this.summary,
      description: description ?? this.description,
      diffScrollOffset: diffScrollOffset ?? this.diffScrollOffset,
      amending: amending ?? this.amending,
      preAmendSummary: preAmendSummary ?? this.preAmendSummary,
      preAmendDescription: preAmendDescription ?? this.preAmendDescription,
      preparedEpisodeActive:
          preparedEpisodeActive ?? this.preparedEpisodeActive,
      preparedFilled: preparedFilled ?? this.preparedFilled,
      prePreparedSummary: prePreparedSummary ?? this.prePreparedSummary,
      prePreparedDescription:
          prePreparedDescription ?? this.prePreparedDescription,
      hasAutofill: hasAutofill ?? this.hasAutofill,
      autofilledSummary: autofilledSummary ?? this.autofilledSummary,
      autofilledDescription:
          autofilledDescription ?? this.autofilledDescription,
      pendingCommitFrom: clearPendingCommit
          ? null
          : (pendingCommitFrom ?? this.pendingCommitFrom),
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

  /// Advances the prepared-message episode one step and returns what was
  /// decided, so the caller can ask core for the message
  /// ([PreparedMessageAction.startAndRequest]) or sync its text controllers
  /// ([PreparedMessageAction.replace], [PreparedMessageAction.restoreAndEnd]).
  /// [summary]/[description] are the reply's text, read only on `replace`.
  PreparedMessageAction reconcilePreparedMessage({
    required bool pending,
    required PreparedReplyStatus reply,
    required String summary,
    required String description,
    required bool overwrite,
  }) {
    final WorkingCopyDraft d = state;
    final PreparedMessageAction action = decidePreparedMessageAction(
      PreparedMessageContext(
        pending: pending,
        episodeActive: d.preparedEpisodeActive,
        filled: d.preparedFilled,
        amending: d.amending,
        reply: reply,
        overwrite: overwrite,
        boxEmpty: d.summary.trim().isEmpty && d.description.trim().isEmpty,
        commitInFlight: d.pendingCommitFrom != null,
        boxMatchesAutofill:
            d.hasAutofill &&
            d.summary == d.autofilledSummary &&
            d.description == d.autofilledDescription,
      ),
    );
    switch (action) {
      case PreparedMessageAction.nothing:
        break;
      case PreparedMessageAction.startAndRequest:
        state = d.copyWith(preparedEpisodeActive: true, preparedFilled: false);
      case PreparedMessageAction.cancelAmendAndStart:
        cancelAmend();
        state = state.copyWith(
          preparedEpisodeActive: true,
          preparedFilled: false,
        );
      case PreparedMessageAction.replace:
        state = d.copyWith(
          preparedFilled: true,
          prePreparedSummary: d.summary,
          prePreparedDescription: d.description,
          hasAutofill: true,
          autofilledSummary: summary,
          autofilledDescription: description,
          summary: summary,
          description: description,
        );
        _persist();
      case PreparedMessageAction.keep:
        state = d.copyWith(preparedFilled: true);
      case PreparedMessageAction.restoreAndEnd:
        state = _endedEpisode(
          d.copyWith(
            summary: d.prePreparedSummary,
            description: d.prePreparedDescription,
          ),
        );
        _persist();
      case PreparedMessageAction.end:
        state = _endedEpisode(d);
    }
    return action;
  }

  static WorkingCopyDraft _endedEpisode(WorkingCopyDraft d) => d.copyWith(
    preparedEpisodeActive: false,
    preparedFilled: false,
    prePreparedSummary: '',
    prePreparedDescription: '',
    hasAutofill: false,
    autofilledSummary: '',
    autofilledDescription: '',
  );

  /// A commit was sent from HEAD [head]; wait for HEAD to move off it.
  void commitSubmitted(String head) {
    state = state.copyWith(pendingCommitFrom: head);
  }

  /// HEAD moved while a commit was outstanding: the message is a commit now.
  void commitLanded() {
    if (state.pendingCommitFrom == null) return;
    reset();
  }

  /// The commit failed, or its outcome can no longer be told: stop waiting
  /// and keep the text, so a later checkout does not clear it.
  void commitAbandoned() {
    if (state.pendingCommitFrom == null) return;
    state = state.copyWith(clearPendingCommit: true);
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
