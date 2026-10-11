// The commit box's prepared-message rules (prepared-commit-message-spec.html
// section 04, rulings ①②③⑨⑪), one row of the plan's table per test.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/prepared_message_policy.dart';

PreparedMessageAction _decide({
  bool pending = true,
  bool episodeActive = true,
  bool filled = false,
  bool amending = false,
  PreparedReplyStatus reply = PreparedReplyStatus.none,
  bool overwrite = true,
  bool boxEmpty = false,
  bool boxMatchesAutofill = false,
  bool commitInFlight = false,
  bool headKnown = true,
  bool repoStateKnown = true,
  bool needsRevalidation = false,
  bool revalidationRequested = false,
  bool sameMerge = false,
  bool episodeHeadKnown = false,
  bool headCheckRequested = false,
  bool headCheckDone = false,
  bool headMoved = false,
  bool checkFailed = false,
  bool parentCheckRequested = false,
  ParentCheck parent = ParentCheck.none,
  bool mounting = false,
}) => decidePreparedMessageAction(
  PreparedMessageContext(
    pending: pending,
    episodeActive: episodeActive,
    filled: filled,
    amending: amending,
    reply: reply,
    overwrite: overwrite,
    boxEmpty: boxEmpty,
    boxMatchesAutofill: boxMatchesAutofill,
    commitInFlight: commitInFlight,
    headKnown: headKnown,
    repoStateKnown: repoStateKnown,
    needsRevalidation: needsRevalidation,
    revalidationRequested: revalidationRequested,
    sameMerge: sameMerge,
    episodeHeadKnown: episodeHeadKnown,
    headCheckRequested: headCheckRequested,
    headCheckDone: headCheckDone,
    headMoved: headMoved,
    checkFailed: checkFailed,
    parentCheckRequested: parentCheckRequested,
    parent: parent,
    mounting: mounting,
  ),
);

void main() {
  group('decidePreparedMessageAction', () {
    test('a merge starting opens an episode and asks for the message', () {
      expect(
        _decide(episodeActive: false),
        PreparedMessageAction.startAndRequest,
      );
    });

    // 使用者 2026-10-10:「以merge為優先，也就是以git狀態為主」 -- the merge
    // takes the box; amend mode is cancelled, not waited out.
    test('a merge starting in amend mode cancels amend and starts', () {
      expect(
        _decide(episodeActive: false, amending: true),
        PreparedMessageAction.cancelAmendAndStart,
      );
    });

    test('waiting for the reply does nothing', () {
      expect(_decide(), PreparedMessageAction.nothing);
    });

    test('with overwrite on, a reply replaces typed text', () {
      expect(
        _decide(reply: PreparedReplyStatus.message),
        PreparedMessageAction.replace,
      );
    });

    test('with overwrite off, a reply fills an empty box', () {
      expect(
        _decide(
          reply: PreparedReplyStatus.message,
          overwrite: false,
          boxEmpty: true,
        ),
        PreparedMessageAction.replace,
      );
    });

    test('with overwrite off, a reply leaves typed text alone', () {
      expect(
        _decide(reply: PreparedReplyStatus.message, overwrite: false),
        PreparedMessageAction.keep,
      );
    });

    test('once filled, a later reply changes nothing', () {
      expect(
        _decide(filled: true, reply: PreparedReplyStatus.message),
        PreparedMessageAction.nothing,
      );
    });

    // The reason already reached the banner and the Log; retrying would
    // loop on the same failure, and clearing the box would lose the text.
    test('a failed reply keeps the box and stops asking', () {
      expect(
        _decide(reply: PreparedReplyStatus.failed),
        PreparedMessageAction.keep,
      );
    });

    test('the merge ending with the autofill untouched restores', () {
      expect(
        _decide(pending: false, filled: true, boxMatchesAutofill: true),
        PreparedMessageAction.restoreAndEnd,
      );
    });

    // A commit from the box concluded the merge: not an Abort, so nothing
    // is put back (使用者 2026-10-10).
    test('the merge ending under an outstanding commit restores nothing', () {
      expect(
        _decide(
          pending: false,
          filled: true,
          boxMatchesAutofill: true,
          commitInFlight: true,
        ),
        PreparedMessageAction.end,
      );
    });

    test('the merge ending after the user edited keeps their text', () {
      expect(_decide(pending: false, filled: true), PreparedMessageAction.end);
    });

    test('nothing pending and no episode does nothing', () {
      expect(
        _decide(pending: false, episodeActive: false),
        PreparedMessageAction.nothing,
      );
    });
  });

  // The same-merge key is HEAD; an episode decided before refs arrive would
  // be stored with an empty one and misjudged on the next reopen.
  group('HEAD not loaded yet', () {
    test('a reply waits instead of replacing', () {
      expect(
        _decide(reply: PreparedReplyStatus.message, headKnown: false),
        PreparedMessageAction.nothing,
      );
    });

    test('a failed reply waits instead of keeping', () {
      expect(
        _decide(reply: PreparedReplyStatus.failed, headKnown: false),
        PreparedMessageAction.nothing,
      );
    });
  });

  // 使用者 2026-10-10: on reopening the repository, the same merge or squash
  // keeps the box; a different one fetches again; none any more clears it.
  group('an episode read back from disk', () {
    PreparedMessageAction reopened({
      bool pending = true,
      bool requested = true,
      PreparedReplyStatus reply = PreparedReplyStatus.none,
      bool sameMerge = false,
      bool overwrite = true,
      bool boxEmpty = false,
      bool headKnown = true,
      bool repoStateKnown = true,
    }) => _decide(
      pending: pending,
      filled: true,
      needsRevalidation: true,
      revalidationRequested: requested,
      reply: reply,
      sameMerge: sameMerge,
      overwrite: overwrite,
      boxEmpty: boxEmpty,
      headKnown: headKnown,
      repoStateKnown: repoStateKnown,
    );

    test('waits while RepoState is unknown, even with no pending flag', () {
      expect(
        reopened(pending: false, repoStateKnown: false),
        PreparedMessageAction.nothing,
      );
    });

    test('waits while HEAD is unknown', () {
      // Not "nothing pending" either: without HEAD there is no telling.
      expect(
        reopened(pending: false, headKnown: false),
        PreparedMessageAction.nothing,
      );
      expect(
        reopened(requested: false, headKnown: false),
        PreparedMessageAction.nothing,
      );
    });

    test('nothing pending any more clears the box', () {
      expect(reopened(pending: false), PreparedMessageAction.clearAndEnd);
    });

    test('still pending asks git once', () {
      expect(reopened(requested: false), PreparedMessageAction.revalidate);
      expect(reopened(), PreparedMessageAction.nothing);
    });

    test('the same merge keeps the box', () {
      expect(
        reopened(reply: PreparedReplyStatus.message, sameMerge: true),
        PreparedMessageAction.keepValidated,
      );
    });

    test('a different merge fetches again and overwrites', () {
      expect(
        reopened(reply: PreparedReplyStatus.message),
        PreparedMessageAction.replaceAsNew,
      );
    });

    test('a different merge with the switch off keeps a non-empty box', () {
      expect(
        reopened(reply: PreparedReplyStatus.message, overwrite: false),
        PreparedMessageAction.keep,
      );
    });

    test('a different merge with the switch off fills an empty box', () {
      expect(
        reopened(
          reply: PreparedReplyStatus.message,
          overwrite: false,
          boxEmpty: true,
        ),
        PreparedMessageAction.replaceAsNew,
      );
    });

    test('a failed read on the same merge keeps the box', () {
      expect(
        reopened(reply: PreparedReplyStatus.failed, sameMerge: true),
        PreparedMessageAction.keepValidated,
      );
    });

    test('a failed read on a different merge keeps the box too', () {
      expect(
        reopened(reply: PreparedReplyStatus.failed),
        PreparedMessageAction.keep,
      );
    });
  });

  // Slice D R2: the merge ending outside an in-app commit. A commit (new
  // HEAD's first parent is the episode's HEAD) clears the box; any other
  // HEAD move, or none, follows the Abort rule (使用者 2026-10-11 「分辨
  // commit，其他照 Abort」).
  group('a filled episode ending without an in-app commit', () {
    PreparedMessageAction ended({
      bool boxMatchesAutofill = true,
      bool episodeHeadKnown = true,
      bool filled = true,
      bool headCheckRequested = true,
      bool headCheckDone = true,
      bool headMoved = true,
      bool checkFailed = false,
      bool parentCheckRequested = true,
      ParentCheck parent = ParentCheck.none,
      bool mounting = false,
      bool commitInFlight = false,
    }) => _decide(
      pending: false,
      filled: filled,
      boxMatchesAutofill: boxMatchesAutofill,
      episodeHeadKnown: episodeHeadKnown,
      headCheckRequested: headCheckRequested,
      headCheckDone: headCheckDone,
      headMoved: headMoved,
      checkFailed: checkFailed,
      parentCheckRequested: parentCheckRequested,
      parent: parent,
      mounting: mounting,
      commitInFlight: commitInFlight,
    );

    test('first asks for fresh refs', () {
      expect(ended(headCheckRequested: false), PreparedMessageAction.checkHead);
    });

    test('waits for them', () {
      expect(ended(headCheckDone: false), PreparedMessageAction.nothing);
    });

    test('HEAD unchanged is an Abort: untouched restores, edited ends', () {
      expect(ended(headMoved: false), PreparedMessageAction.restoreAndEnd);
      expect(
        ended(headMoved: false, boxMatchesAutofill: false),
        PreparedMessageAction.end,
      );
    });

    test('HEAD moved asks for its parent, then waits', () {
      expect(
        ended(parentCheckRequested: false),
        PreparedMessageAction.checkParent,
      );
      expect(ended(), PreparedMessageAction.nothing);
    });

    test('a remount while the parent is unanswered asks again', () {
      expect(ended(mounting: true), PreparedMessageAction.checkParent);
    });

    test('a commit clears the box', () {
      expect(
        ended(parent: ParentCheck.commit),
        PreparedMessageAction.clearAndEnd,
      );
      expect(
        ended(parent: ParentCheck.commit, boxMatchesAutofill: false),
        PreparedMessageAction.clearAndEnd,
      );
    });

    test('a reset, an undo, a root commit or no answer is an Abort', () {
      for (final ParentCheck p in <ParentCheck>[
        ParentCheck.notCommit,
        ParentCheck.noAnswer,
      ]) {
        expect(ended(parent: p), PreparedMessageAction.restoreAndEnd);
        expect(
          ended(parent: p, boxMatchesAutofill: false),
          PreparedMessageAction.end,
        );
      }
    });

    test('an error while waiting is an Abort', () {
      expect(
        ended(headCheckDone: false, checkFailed: true),
        PreparedMessageAction.restoreAndEnd,
      );
      expect(ended(checkFailed: true), PreparedMessageAction.restoreAndEnd);
    });

    // plan-verifier epoch 1: an unfilled episode has no HEAD recorded, and
    // "HEAD differs from ''" would always read as a move.
    test('an unfilled episode or one with no HEAD is not checked', () {
      expect(
        ended(
          filled: false,
          headCheckRequested: false,
          boxMatchesAutofill: false,
        ),
        PreparedMessageAction.end,
      );
      expect(
        ended(episodeHeadKnown: false, headCheckRequested: false),
        PreparedMessageAction.restoreAndEnd,
      );
    });

    test('an in-app commit still just ends', () {
      expect(
        ended(commitInFlight: true, headCheckRequested: false),
        PreparedMessageAction.end,
      );
    });
  });
}
