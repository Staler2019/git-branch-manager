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
}
