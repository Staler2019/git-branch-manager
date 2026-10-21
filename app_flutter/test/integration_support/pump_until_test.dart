// `pumpUntil` is the device tier's only wait-for-a-condition helper. It used
// to give up silently after `maxAttempts`, so a slow machine surfaced as a
// wrong value at some later, unrelated `expect` (prepared_message_flow_test:
// once a missing `Merge`, once an empty description after Abort). Pinned here
// on the host so the contract does not depend on a device run to be seen.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/real_repo_harness.dart';

void main() {
  testWidgets('returns once the condition holds', (WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    int polls = 0;

    await pumpUntil(tester, () => ++polls >= 3);

    expect(polls, 3);
  });

  testWidgets('fails at the wait, not later, when the condition never holds', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const SizedBox());

    // Not `expectLater`: it is guarded too, and would overlap `pump`.
    TestFailure? failure;
    try {
      await pumpUntil(tester, () => false, maxAttempts: 5);
    } on TestFailure catch (e) {
      failure = e;
    }

    expect(failure?.message, contains('pumpUntil'));
  });
}
