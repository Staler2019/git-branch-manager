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

  /// Replace the box with the reply, remembering what it held.
  replace,

  /// Leave the box as it is and mark the episode filled.
  keep,

  /// The episode ended with the autofill untouched: put back what the box
  /// held before it (③⑨).
  restoreAndEnd,

  /// The episode ended after the user edited the autofill: keep their text.
  end,
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
  });

  /// `RepoState.preparedMessagePending`.
  final bool pending;
  final bool episodeActive;

  /// The box was already replaced or deliberately kept in this episode.
  final bool filled;

  /// Amend mode holds HEAD's message; an episode never starts over it.
  final bool amending;
  final PreparedReplyStatus reply;

  /// `AppPreferences.overwriteWithPreparedMessage` (⑪).
  final bool overwrite;
  final bool boxEmpty;

  /// The box still holds exactly what this episode filled it with.
  final bool boxMatchesAutofill;
}

PreparedMessageAction decidePreparedMessageAction(PreparedMessageContext c) {
  if (!c.pending) {
    if (!c.episodeActive) return PreparedMessageAction.nothing;
    return c.boxMatchesAutofill
        ? PreparedMessageAction.restoreAndEnd
        : PreparedMessageAction.end;
  }
  if (!c.episodeActive) {
    return c.amending
        ? PreparedMessageAction.nothing
        : PreparedMessageAction.startAndRequest;
  }
  if (c.filled) return PreparedMessageAction.nothing;
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
