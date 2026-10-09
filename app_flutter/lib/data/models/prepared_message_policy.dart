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
  clearAndEnd,
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
}

PreparedMessageAction decidePreparedMessageAction(PreparedMessageContext c) {
  if (c.episodeActive && c.needsRevalidation) return _revalidating(c);
  if (!c.pending) {
    if (!c.episodeActive) return PreparedMessageAction.nothing;
    if (c.commitInFlight) return PreparedMessageAction.end;
    return c.boxMatchesAutofill
        ? PreparedMessageAction.restoreAndEnd
        : PreparedMessageAction.end;
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
