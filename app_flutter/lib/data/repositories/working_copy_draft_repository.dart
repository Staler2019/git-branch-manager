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

  /// The prepared-message episode, under its own key rather than inside the
  /// draft's list: an older build reading a longer list would drop the whole
  /// draft as malformed, while an unknown key it simply never reads.
  static String _episodeKey(RepoIdentity identity) =>
      'workingCopyPreparedEpisode:${identity.workDir}';

  /// `[prePreparedSummary, prePreparedDescription, hasAutofill ('1'/'0'),
  /// autofilledSummary, autofilledDescription, episodeHead, autofilledRaw]`.
  static const int _episodeLength = 7;

  /// A commit from this box is outstanding: `[headFrom, headKnown ('1'/'0')]`.
  /// Written **before** the commit is sent, so a crash after it lands -- but
  /// before the cleared draft reaches disk -- is told apart on reopen by HEAD
  /// having moved (Slice D R1). `headKnown` is '0' when refs had not loaded
  /// at submit: HEAD then read '' and cannot be compared.
  static String _pendingCommitKey(RepoIdentity identity) =>
      'workingCopyPendingCommit:${identity.workDir}';

  /// One list of exactly two entries rather than two keys: a message is one
  /// thing, and two `setString` calls can half-land, leaving a body with
  /// somebody else's subject.
  ///
  /// An episode stored beside it comes back marked
  /// [WorkingCopyDraft.needsRevalidation]: whether it is still the same merge
  /// is for git to say, not the disk. A malformed one reads as none.
  WorkingCopyDraft read(RepoIdentity identity) {
    final List<String>? stored = _prefs.getStringList(_key(identity));
    final WorkingCopyDraft draft = stored == null || stored.length != 2
        ? const WorkingCopyDraft()
        : WorkingCopyDraft(summary: stored[0], description: stored[1]);
    final List<String>? m = _prefs.getStringList(_pendingCommitKey(identity));
    final WorkingCopyDraft withCommit =
        m == null || m.length != 2 || (m[1] != '1' && m[1] != '0')
        ? draft
        : draft.copyWith(
            pendingCommitHead: m[0],
            pendingCommitHeadKnown: m[1] == '1',
            pendingCommitFromDisk: true,
          );
    return _withEpisode(identity, withCommit);
  }

  WorkingCopyDraft _withEpisode(RepoIdentity identity, WorkingCopyDraft draft) {
    final List<String>? e = _prefs.getStringList(_episodeKey(identity));
    if (e == null || e.length != _episodeLength) return draft;
    if (e[2] != '1' && e[2] != '0') return draft;
    return draft.copyWith(
      preparedEpisodeActive: true,
      preparedFilled: true,
      needsRevalidation: true,
      prePreparedSummary: e[0],
      prePreparedDescription: e[1],
      hasAutofill: e[2] == '1',
      autofilledSummary: e[3],
      autofilledDescription: e[4],
      episodeHead: e[5],
      autofilledRaw: e[6],
    );
  }

  /// An empty message removes the key: that is what a committed draft must
  /// leave behind ([WorkingCopyDraftController.reset]).
  Future<void> write(RepoIdentity identity, WorkingCopyDraft draft) {
    if (draft.summary.isEmpty && draft.description.isEmpty) {
      return clear(identity);
    }
    return _prefs.setStringList(_key(identity), <String>[
      draft.summary,
      draft.description,
    ]);
  }

  Future<void> writeEpisode(RepoIdentity identity, WorkingCopyDraft draft) {
    return _prefs.setStringList(_episodeKey(identity), <String>[
      draft.prePreparedSummary,
      draft.prePreparedDescription,
      draft.hasAutofill ? '1' : '0',
      draft.autofilledSummary,
      draft.autofilledDescription,
      draft.episodeHead,
      draft.autofilledRaw,
    ]);
  }

  Future<void> clearEpisode(RepoIdentity identity) =>
      _prefs.remove(_episodeKey(identity));

  /// Whether the episode key holds anything, well-formed or not: a
  /// malformed one is read as none and must still be deleted (Slice D A3).
  bool hasEpisode(RepoIdentity identity) =>
      _prefs.getStringList(_episodeKey(identity)) != null;

  /// Whether the marker key holds anything, well-formed or not: a malformed
  /// one is read as none and must still be deleted.
  bool hasPendingCommitMarker(RepoIdentity identity) =>
      _prefs.getStringList(_pendingCommitKey(identity)) != null;

  Future<void> writePendingCommit(
    RepoIdentity identity, {
    required String head,
    required bool headKnown,
  }) => _prefs.setStringList(_pendingCommitKey(identity), <String>[
    head,
    if (headKnown) '1' else '0',
  ]);

  Future<void> clearPendingCommit(RepoIdentity identity) =>
      _prefs.remove(_pendingCommitKey(identity));

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
    this.pendingCommitSeq,
    this.pendingCommitHead,
    this.pendingCommitHeadKnown = false,
    this.pendingCommitFromDisk = false,
    this.episodeHead = '',
    this.autofilledRaw = '',
    this.needsRevalidation = false,
    this.revalidationRequested = false,
    this.headCheckRequest,
    this.parentCheckHead,
    this.parentCheckSeq,
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

  /// `RepoSessionState.commitOutcomeSeq` when a commit from this box was
  /// submitted, or null when none is outstanding. The box is cleared when the
  /// count moves past it with a success, **not** when the commit is sent: a
  /// commit that failed -- nothing staged, a rejecting hook, a bad identity
  /// -- would otherwise take the message with it. A count rather than HEAD:
  /// HEAD read before refs load is '', and an unrelated error is not this
  /// commit failing (Slice D A1/A2). Memory only; one place sets it
  /// ([submitCommit]) for the button, the shortcut and the menu alike, and
  /// `WorkspaceScreen` settles it.
  final int? pendingCommitSeq;

  /// HEAD when the outstanding commit was submitted, and whether refs had
  /// loaded then. Persisted as the pending-commit marker; read back with
  /// [pendingCommitFromDisk] set, where [pendingCommitSeq] is meaningless
  /// (the session's count restarts) and HEAD is the only evidence left.
  final String? pendingCommitHead;
  final bool pendingCommitHeadKnown;
  final bool pendingCommitFromDisk;

  /// The episode's same-merge key: HEAD when it was filled, and git's message
  /// then ('' when that read failed). Persisted with the episode, so a
  /// reopen can tell the same merge from a new one (使用者 2026-10-10).
  final String episodeHead;
  final String autofilledRaw;

  /// Read back from disk and not yet checked against git; memory only.
  final bool needsRevalidation;
  final bool revalidationRequested;

  /// Slice D R2, memory only. The refresh request number
  /// (`RepoSessionController.refreshHistory()`) when the merge ended without
  /// an in-app commit and fresh refs were asked for -- refs decide only once
  /// `RepoSessionState.refsCoverRequest` reaches it, since a load already
  /// running then may predate the commit (Slice E D3); then the new HEAD
  /// whose commit was asked for, and `commitMetaReplySeq` at that moment. Here rather than in the view, so a wait survives Working Copy
  /// being unmounted. Cleared by the episode ending, or by a merge pending
  /// again.
  final int? headCheckRequest;
  final String? parentCheckHead;
  final int? parentCheckSeq;

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
    int? pendingCommitSeq,
    String? pendingCommitHead,
    bool? pendingCommitHeadKnown,
    bool? pendingCommitFromDisk,
    bool clearPendingCommit = false,
    String? episodeHead,
    String? autofilledRaw,
    bool? needsRevalidation,
    bool? revalidationRequested,
    int? headCheckRequest,
    String? parentCheckHead,
    int? parentCheckSeq,
    bool clearEndChecks = false,
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
      pendingCommitSeq: clearPendingCommit
          ? null
          : (pendingCommitSeq ?? this.pendingCommitSeq),
      pendingCommitHead: clearPendingCommit
          ? null
          : (pendingCommitHead ?? this.pendingCommitHead),
      pendingCommitHeadKnown: clearPendingCommit
          ? false
          : (pendingCommitHeadKnown ?? this.pendingCommitHeadKnown),
      pendingCommitFromDisk: clearPendingCommit
          ? false
          : (pendingCommitFromDisk ?? this.pendingCommitFromDisk),
      episodeHead: episodeHead ?? this.episodeHead,
      autofilledRaw: autofilledRaw ?? this.autofilledRaw,
      needsRevalidation: needsRevalidation ?? this.needsRevalidation,
      revalidationRequested:
          revalidationRequested ?? this.revalidationRequested,
      headCheckRequest: clearEndChecks
          ? null
          : (headCheckRequest ?? this.headCheckRequest),
      parentCheckHead: clearEndChecks
          ? null
          : (parentCheckHead ?? this.parentCheckHead),
      parentCheckSeq: clearEndChecks
          ? null
          : (parentCheckSeq ?? this.parentCheckSeq),
    );
  }
}

/// State notifier for mutable working copy draft state.
/// Updates are applied via copyWith() -- never in-place mutation.
class WorkingCopyDraftController extends StateNotifier<WorkingCopyDraft> {
  WorkingCopyDraftController(this._repo, this._identity)
    : super(_repo.read(_identity)) {
    _episodeOnDisk = _repo.hasEpisode(_identity);
    _markerOnDisk = _repo.hasPendingCommitMarker(_identity);
    _markerHead = state.pendingCommitHead;
    // A malformed episode or marker was read as none; the next round
    // deletes it rather than leaving it until something overwrites it.
    final bool malformedEpisode =
        _episodeOnDisk && !state.preparedEpisodeActive;
    final bool malformedMarker =
        _markerOnDisk && state.pendingCommitHead == null;
    if (malformedEpisode || malformedMarker) _persist();
  }

  final WorkingCopyDraftRepository _repo;
  final RepoIdentity _identity;

  Future<void>? _inFlight;
  bool _dirty = false;

  /// The episode key holds something, so ending an episode must delete it.
  bool _episodeOnDisk = false;

  /// Same for the pending-commit marker, and which HEAD it holds, so a round
  /// rewrites it only when a new commit was submitted.
  bool _markerOnDisk = false;
  String? _markerHead;

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
  /// [summary]/[description] are the reply's text and [raw] the whole of it,
  /// read only when it fills the box. [head] is `refs.head.target`, '' while
  /// refs have not arrived; [repoStateKnown] is false before RepoState has.
  PreparedMessageAction reconcilePreparedMessage({
    required bool pending,
    required PreparedReplyStatus reply,
    required String summary,
    required String description,
    required String raw,
    required String head,
    required bool overwrite,
    bool repoStateKnown = true,
    int refsCoverRequest = 0,
    int Function()? requestRefresh,
    int commitMetaReplySeq = 0,
    int commitMetaRequestSeq = 0,
    List<String>? Function(String oid)? parentsOf,
    bool lastErrorPresent = false,
    bool mounting = false,
  }) {
    // A merge pending again ends any wait on how the previous one ended.
    if (pending &&
        (state.headCheckRequest != null || state.parentCheckHead != null)) {
      state = state.copyWith(clearEndChecks: true);
    }
    final WorkingCopyDraft d = state;
    final int? checkRequest = d.headCheckRequest;
    final PreparedMessageAction action = decidePreparedMessageAction(
      PreparedMessageContext(
        pending: pending,
        episodeActive: d.preparedEpisodeActive,
        filled: d.preparedFilled,
        amending: d.amending,
        reply: reply,
        overwrite: overwrite,
        boxEmpty: d.summary.trim().isEmpty && d.description.trim().isEmpty,
        commitInFlight:
            d.pendingCommitSeq != null || d.pendingCommitHead != null,
        boxMatchesAutofill:
            d.hasAutofill &&
            d.summary == d.autofilledSummary &&
            d.description == d.autofilledDescription,
        headKnown: head.isNotEmpty,
        repoStateKnown: repoStateKnown,
        needsRevalidation: d.needsRevalidation,
        revalidationRequested: d.revalidationRequested,
        sameMerge: _isSameMerge(d, reply: reply, raw: raw, head: head),
        episodeHeadKnown: d.episodeHead.isNotEmpty,
        headCheckRequested: checkRequest != null,
        headCheckDone: checkRequest != null && refsCoverRequest >= checkRequest,
        headMoved: head != d.episodeHead,
        checkFailed: checkRequest != null && lastErrorPresent,
        parentCheckRequested: d.parentCheckHead != null,
        parent: _parentCheck(
          d,
          commitMetaReplySeq,
          commitMetaRequestSeq,
          parentsOf,
        ),
        mounting: mounting,
      ),
    );
    _apply(
      action,
      summary: summary,
      description: description,
      raw: raw,
      head: head,
      refsCoverRequest: refsCoverRequest,
      requestRefresh: requestRefresh,
      commitMetaReplySeq: commitMetaReplySeq,
    );
    return action;
  }

  /// The asked-for commit's first parent against the episode's HEAD. A
  /// root commit has none, and is not a commit of this merge. No answer is
  /// coming only once a reply arrived since the ask and every request sent
  /// so far is answered: replies are unordered and unlabelled, so a reply
  /// lacking the oid while any request is outstanding may be someone else's.
  static ParentCheck _parentCheck(
    WorkingCopyDraft d,
    int replySeq,
    int requestSeq,
    List<String>? Function(String oid)? parentsOf,
  ) {
    final String? asked = d.parentCheckHead;
    if (asked == null) return ParentCheck.none;
    final List<String>? parents = parentsOf?.call(asked);
    if (parents != null) {
      return parents.isNotEmpty && parents.first == d.episodeHead
          ? ParentCheck.commit
          : ParentCheck.notCommit;
    }
    return replySeq > (d.parentCheckSeq ?? replySeq) && replySeq >= requestSeq
        ? ParentCheck.noAnswer
        : ParentCheck.none;
  }

  /// Same HEAD, and the same message unless the stored one is empty (its
  /// read had failed) or this reply has none (使用者 2026-10-10: 「HEAD 沒變
  /// 就當同一筆」).
  static bool _isSameMerge(
    WorkingCopyDraft d, {
    required PreparedReplyStatus reply,
    required String raw,
    required String head,
  }) {
    if (head != d.episodeHead) return false;
    if (reply != PreparedReplyStatus.message) return true;
    return d.autofilledRaw.isEmpty || raw == d.autofilledRaw;
  }

  void _apply(
    PreparedMessageAction action, {
    required String summary,
    required String description,
    required String raw,
    required String head,
    required int refsCoverRequest,
    required int Function()? requestRefresh,
    required int commitMetaReplySeq,
  }) {
    final WorkingCopyDraft d = state;
    switch (action) {
      case PreparedMessageAction.nothing:
        break;
      case PreparedMessageAction.checkHead:
        // The request is sent here, not by the caller, so its number is in
        // hand when it is recorded. Without a sender (a caller with no
        // session), any refs published from now on are newer than these.
        state = d.copyWith(
          headCheckRequest: requestRefresh?.call() ?? refsCoverRequest + 1,
        );
      case PreparedMessageAction.checkParent:
        state = d.copyWith(
          parentCheckHead: head,
          parentCheckSeq: commitMetaReplySeq,
        );
      case PreparedMessageAction.startAndRequest:
        state = d.copyWith(preparedEpisodeActive: true, preparedFilled: false);
      case PreparedMessageAction.cancelAmendAndStart:
        cancelAmend();
        state = state.copyWith(
          preparedEpisodeActive: true,
          preparedFilled: false,
        );
      case PreparedMessageAction.revalidate:
        state = d.copyWith(revalidationRequested: true);
      case PreparedMessageAction.keepValidated:
        state = d.copyWith(
          needsRevalidation: false,
          revalidationRequested: false,
        );
      case PreparedMessageAction.replace:
      case PreparedMessageAction.replaceAsNew:
        final bool fresh = action == PreparedMessageAction.replaceAsNew;
        state = _filled(d, head: head, raw: raw).copyWith(
          prePreparedSummary: fresh ? '' : d.summary,
          prePreparedDescription: fresh ? '' : d.description,
          hasAutofill: true,
          autofilledSummary: summary,
          autofilledDescription: description,
          summary: summary,
          description: description,
        );
        _persist();
      case PreparedMessageAction.keep:
        state = _filled(d, head: head, raw: raw).copyWith(
          prePreparedSummary: '',
          prePreparedDescription: '',
          hasAutofill: false,
          autofilledSummary: '',
          autofilledDescription: '',
        );
        _persist();
      case PreparedMessageAction.restoreAndEnd:
        state = _endedEpisode(
          d.copyWith(
            summary: d.prePreparedSummary,
            description: d.prePreparedDescription,
          ),
        );
        _persist();
      case PreparedMessageAction.clearAndEnd:
        state = _endedEpisode(d.copyWith(summary: '', description: ''));
        _persist();
      case PreparedMessageAction.end:
        state = _endedEpisode(d);
        _persist();
    }
  }

  static WorkingCopyDraft _filled(
    WorkingCopyDraft d, {
    required String head,
    required String raw,
  }) => d.copyWith(
    preparedFilled: true,
    episodeHead: head,
    autofilledRaw: raw,
    needsRevalidation: false,
    revalidationRequested: false,
  );

  static WorkingCopyDraft _endedEpisode(WorkingCopyDraft d) => d.copyWith(
    preparedEpisodeActive: false,
    preparedFilled: false,
    prePreparedSummary: '',
    prePreparedDescription: '',
    hasAutofill: false,
    autofilledSummary: '',
    autofilledDescription: '',
    episodeHead: '',
    autofilledRaw: '',
    needsRevalidation: false,
    revalidationRequested: false,
    clearEndChecks: true,
  );

  /// A commit is about to be sent while the session's commit count stands
  /// at [seq] and HEAD at [head]. Completes once the marker is on disk;
  /// [submitCommit] sends the commit only then (Slice D R1).
  Future<void> commitSubmitted(
    int seq, {
    required String head,
    required bool headKnown,
  }) async {
    state = state.copyWith(
      pendingCommitSeq: seq,
      pendingCommitHead: head,
      pendingCommitHeadKnown: headKnown,
      pendingCommitFromDisk: false,
    );
    _persist();
    final Future<void>? writing = _inFlight;
    if (writing != null) await writing;
  }

  /// Settles an outstanding commit from what the session knows now.
  ///
  /// In-session: the commit count moved past [WorkingCopyDraft.pendingCommitSeq]
  /// → [lastSucceeded] decides. Read back from disk: refs must have loaded,
  /// then HEAD off the recorded one → it landed; on it, or unknown at submit
  /// → it failed or cannot be told, so the text stays.
  void settleCommit({
    required int outcomeSeq,
    required bool lastSucceeded,
    required bool refsLoaded,
    required String head,
  }) {
    final int? seq = state.pendingCommitSeq;
    if (seq != null) {
      if (outcomeSeq <= seq) return;
      lastSucceeded ? commitLanded() : commitAbandoned();
      return;
    }
    if (!state.pendingCommitFromDisk || state.pendingCommitHead == null) {
      return;
    }
    if (!refsLoaded) return;
    final bool moved =
        state.pendingCommitHeadKnown && head != state.pendingCommitHead;
    moved ? commitLanded() : commitAbandoned();
  }

  bool get _commitOutstanding =>
      state.pendingCommitSeq != null || state.pendingCommitHead != null;

  /// This commit's outcome said it succeeded: the message is a commit now.
  void commitLanded() {
    if (!_commitOutstanding) return;
    reset();
  }

  /// This commit's outcome said it failed: stop waiting and keep the text,
  /// so a later checkout does not clear it.
  void commitAbandoned() {
    if (!_commitOutstanding) return;
    state = state.copyWith(clearPendingCommit: true);
    // The marker too: left behind, a later checkout and a normal quit would
    // read as "landed" on the next launch (plan-verifier, Slice D epoch 1).
    _persist();
  }

  /// Resets all fields to their defaults, on disk as well as in memory.
  /// Called after a successful commit: the message has become a commit, and
  /// offering it again on the next launch would invite committing it twice.
  ///
  /// Through the same queue as every other write: written around it, a
  /// write already under way could land after the clear and bring the
  /// committed message back.
  void reset() {
    state = const WorkingCopyDraft();
    _persist();
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

  /// Two writes per round, the episode's first, and each reads [state] as it
  /// is *then* -- a reset between the two turns the second into a delete.
  /// The order makes every half-written state keep the user's text: an
  /// episode written without its draft leaves the old text, which no longer
  /// matches the autofill and so counts as theirs; an episode deleted without
  /// its draft leaves the autofill text in the box, never an empty one.
  /// Two functions on purpose (Slice E D2). The repository's writers are
  /// plain Future-returning methods, so one can throw synchronously, before
  /// any `await`. Inside one async function with a `try`/`finally`, that
  /// `finally` would run before [_drain] had even returned -- before
  /// [_persist]'s `_inFlight ??= _drain()` stored the future -- and the
  /// assignment would then keep the errored future forever. Here the throw is
  /// caught by [_drainRounds]'s own future, and `await` always suspends, so
  /// the `finally` runs after the assignment.
  Future<void> _drain() async {
    try {
      await _drainRounds();
    } finally {
      // A failed write must not leave every later [_persist] waiting on a
      // drain that will never run again. The error still reaches whoever
      // awaits this drain ([commitSubmitted]).
      _inFlight = null;
    }
  }

  Future<void> _drainRounds() async {
    while (_dirty) {
      _dirty = false;
      if (state.preparedEpisodeActive && state.preparedFilled) {
        _episodeOnDisk = true;
        await _repo.writeEpisode(_identity, state);
      } else if (_episodeOnDisk) {
        _episodeOnDisk = false;
        await _repo.clearEpisode(_identity);
      }
      // Disposed during the first write (the repository's provider went
      // away): [state] can no longer be read.
      if (!mounted) break;
      await _repo.write(_identity, state);
      if (!mounted) break;
      // Last, so a reset deletes the draft before the marker: a crash in
      // between leaves a marker that only resets an empty draft again.
      final String? head = state.pendingCommitHead;
      if (head != null && (!_markerOnDisk || _markerHead != head)) {
        _markerOnDisk = true;
        _markerHead = head;
        final bool headKnown = state.pendingCommitHeadKnown;
        await _repo.writePendingCommit(
          _identity,
          head: head,
          headKnown: headKnown,
        );
      } else if (head == null && _markerOnDisk) {
        _markerOnDisk = false;
        _markerHead = null;
        await _repo.clearPendingCommit(_identity);
      }
      if (!mounted) break;
    }
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
