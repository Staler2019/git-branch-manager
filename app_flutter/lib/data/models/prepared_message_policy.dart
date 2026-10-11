/// What the Working Copy commit box does with the message git prepares for a
/// merge or squash (MERGE_MSG / SQUASH_MSG, comments already stripped by
/// core). Rulings ①②③⑨⑪ of `prepared-commit-message-spec.html` section 04.
///
/// An *episode* runs from the moment RepoState reports a prepared message
/// pending until it stops reporting one (a commit, an abort, a reset). The
/// box is filled at most once per episode, so switching tabs and coming back
/// does not fill it again over what the user typed since.
library;

/// The latest reply to `requestPreparedMessage()` for this episode.
enum PreparedReplyStatus {
  /// Not arrived yet (a request clears the previous reply).
  none,

  /// Arrived with text to fill the box with.
  message,

  /// The read failed, or git had nothing prepared. Either way there is no
  /// text, and the box must not be cleared for it.
  failed,
}

/// What the new HEAD's commit says about how a merge ended (Slice D R2).
enum ParentCheck {
  /// Not asked, or asked and not answered yet.
  none,

  /// Its first parent is the episode's HEAD: the merge was committed.
  commit,

  /// Any other first parent, or none (a root commit): a reset or an undo.
  notCommit,

  /// A reply came after the request without this commit in it: the read
  /// failed or was cancelled, and no answer is coming.
  noAnswer,
}

enum PreparedMessageAction {
  nothing,

  /// Open an episode and ask core for the prepared message.
  startAndRequest,

  /// Same as [startAndRequest], but amend mode is on: leave it first, putting
  /// back what the box held before it. The merge or squash wins -- git's
  /// state, not the app's mode, decides (使用者 2026-10-10).
  cancelAmendAndStart,

  /// Replace the box with the reply, remembering what it held.
  replace,

  /// Leave the box as it is and mark the episode filled.
  keep,

  /// The episode ended with the autofill untouched: put back what the box
  /// held before it (③⑨).
  restoreAndEnd,

  /// The episode ended after the user edited the autofill: keep their text.
  end,

  /// An episode read back from disk, still pending: ask git again, to tell
  /// the same merge from a new one. The box is left alone meanwhile.
  revalidate,

  /// The episode read back from disk is the same merge or squash as before:
  /// keep the box as it is (使用者 2026-10-10 「同筆，就沿用」).
  keepValidated,

  /// A different merge or squash than the one on disk: replace the box, with
  /// nothing to put back on Abort -- the earlier one ended while the app was
  /// closed.
  replaceAsNew,

  /// The episode on disk has ended (committed or aborted outside the app):
  /// clear the box (使用者 2026-10-10 「上次是優先狀態，這次沒有了，就清掉」).
  /// Also a merge committed outside the app while it is open (Slice D R2).
  clearAndEnd,

  /// The merge ended without an in-app commit: re-read refs before telling a
  /// commit from an Abort. RepoState is read synchronously and refs are not,
  /// so the pending flag drops while HEAD still shows the old commit.
  checkHead,

  /// HEAD moved: ask for its commit, to see whether its first parent is the
  /// episode's HEAD (使用者 2026-10-11 「分辨 commit，其他照 Abort」).
  checkParent,
}

class PreparedMessageContext {
  const PreparedMessageContext({
    required this.pending,
    required this.episodeActive,
    required this.filled,
    required this.amending,
    required this.reply,
    required this.overwrite,
    required this.boxEmpty,
    required this.boxMatchesAutofill,
    this.commitInFlight = false,
    this.headKnown = true,
    this.repoStateKnown = true,
    this.needsRevalidation = false,
    this.revalidationRequested = false,
    this.sameMerge = false,
    this.episodeHeadKnown = false,
    this.headCheckRequested = false,
    this.headCheckDone = false,
    this.headMoved = false,
    this.checkFailed = false,
    this.parentCheckRequested = false,
    this.parent = ParentCheck.none,
    this.mounting = false,
  });

  /// `RepoState.preparedMessagePending`.
  final bool pending;
  final bool episodeActive;

  /// The box was already replaced or deliberately kept in this episode.
  final bool filled;

  /// Amend mode holds HEAD's message; an episode starting cancels it.
  final bool amending;
  final PreparedReplyStatus reply;

  /// `AppPreferences.overwriteWithPreparedMessage` (⑪).
  final bool overwrite;
  final bool boxEmpty;

  /// The box still holds exactly what this episode filled it with.
  final bool boxMatchesAutofill;

  /// A commit from the box is outstanding. The merge then ends because it was
  /// committed, not aborted, so nothing is restored -- RepoState is re-read
  /// before refs, so the pending flag drops before HEAD visibly moves.
  final bool commitInFlight;

  /// `refs.head.target` has arrived. An episode records HEAD as half of its
  /// same-merge key, so nothing that would write one is decided before it --
  /// RepoState is read at open, refs only on a later event.
  final bool headKnown;

  /// RepoState has been read at all. Unknown is not "nothing pending".
  final bool repoStateKnown;

  /// The episode was read back from disk and not yet checked against git.
  final bool needsRevalidation;

  /// That check's request has been sent.
  final bool revalidationRequested;

  /// The reply belongs to the same merge or squash as the episode on disk:
  /// same HEAD, and the same message unless the one on disk is empty (its
  /// read had failed -- then HEAD alone decides).
  final bool sameMerge;

  /// The episode recorded a HEAD when it was filled. Without one there is
  /// nothing to compare a new HEAD with (plan-verifier, Slice D epoch 1).
  final bool episodeHeadKnown;

  /// [PreparedMessageAction.checkHead] was sent, and refs have been published
  /// since: HEAD now is what git says after the merge ended.
  final bool headCheckRequested;
  final bool headCheckDone;

  /// That HEAD differs from the episode's.
  final bool headMoved;

  /// An error arrived while waiting on refs or on the commit: fall back to
  /// the Abort rule, which can only put the user's own text back.
  final bool checkFailed;

  /// [PreparedMessageAction.checkParent] was sent, and what came of it.
  final bool parentCheckRequested;
  final ParentCheck parent;

  /// The view's first pass after mounting: an unanswered parent check is
  /// asked again, since its reply may have come and gone while unmounted.
  final bool mounting;
}

PreparedMessageAction decidePreparedMessageAction(PreparedMessageContext c) {
  if (c.episodeActive && c.needsRevalidation) return _revalidating(c);
  if (!c.pending) {
    if (!c.episodeActive) return PreparedMessageAction.nothing;
    if (c.commitInFlight) return PreparedMessageAction.end;
    if (c.filled && c.episodeHeadKnown) return _endedWithoutAppCommit(c);
    return _abortRule(c);
  }
  if (!c.episodeActive) {
    return c.amending
        ? PreparedMessageAction.cancelAmendAndStart
        : PreparedMessageAction.startAndRequest;
  }
  if (c.filled) return PreparedMessageAction.nothing;
  if (c.reply != PreparedReplyStatus.none && !c.headKnown) {
    return PreparedMessageAction.nothing;
  }
  switch (c.reply) {
    case PreparedReplyStatus.none:
      return PreparedMessageAction.nothing;
    case PreparedReplyStatus.failed:
      return PreparedMessageAction.keep;
    case PreparedReplyStatus.message:
      return c.overwrite || c.boxEmpty
          ? PreparedMessageAction.replace
          : PreparedMessageAction.keep;
  }
}

/// ③⑨: untouched autofill → put back what the box held; edited → keep it.
PreparedMessageAction _abortRule(PreparedMessageContext c) =>
    c.boxMatchesAutofill
    ? PreparedMessageAction.restoreAndEnd
    : PreparedMessageAction.end;

/// Slice D R2: committed (HEAD moved onto a child of the episode's HEAD) →
/// clear; anything else → the Abort rule. Every wait has an exit: refs always
/// publish or raise an error, and a commit-meta reply without the commit
/// counts as no answer.
PreparedMessageAction _endedWithoutAppCommit(PreparedMessageContext c) {
  if (!c.headCheckRequested) return PreparedMessageAction.checkHead;
  if (c.checkFailed) return _abortRule(c);
  if (!c.headCheckDone) return PreparedMessageAction.nothing;
  if (!c.headMoved) return _abortRule(c);
  if (!c.parentCheckRequested) return PreparedMessageAction.checkParent;
  switch (c.parent) {
    case ParentCheck.none:
      return c.mounting
          ? PreparedMessageAction.checkParent
          : PreparedMessageAction.nothing;
    case ParentCheck.commit:
      return PreparedMessageAction.clearAndEnd;
    case ParentCheck.notCommit:
    case ParentCheck.noAnswer:
      return _abortRule(c);
  }
}

/// The reopen rules (使用者 2026-10-10), for an episode read back from disk.
PreparedMessageAction _revalidating(PreparedMessageContext c) {
  if (!c.repoStateKnown || !c.headKnown) return PreparedMessageAction.nothing;
  if (!c.pending) return PreparedMessageAction.clearAndEnd;
  if (!c.revalidationRequested) return PreparedMessageAction.revalidate;
  switch (c.reply) {
    case PreparedReplyStatus.none:
      return PreparedMessageAction.nothing;
    case PreparedReplyStatus.failed:
      return c.sameMerge
          ? PreparedMessageAction.keepValidated
          : PreparedMessageAction.keep;
    case PreparedReplyStatus.message:
      if (c.sameMerge) return PreparedMessageAction.keepValidated;
      return c.overwrite || c.boxEmpty
          ? PreparedMessageAction.replaceAsNew
          : PreparedMessageAction.keep;
  }
}
