// ReflogPanel's failure state and its render guard
// (read-failure-states-spec.html): a failed reflog shows one banner line
// with Open log and an empty list (ruling 4: never another ref's entries),
// and the panel draws the session's reflog -- content and banner alike --
// only while it answers the ref this panel last sent. The ref is the one the
// panel *sent*: typing into the ref field without Load asks for nothing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/keyed_read_reply.dart';
import 'package:gbm_flutter/data/models/read_keys.dart';
import 'package:gbm_flutter/data/models/reflog_entry.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/panel_filter_field.dart';
import 'package:gbm_flutter/features/panels/reflog_panel.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';
import 'package:gbm_flutter/widgets/gbm_open_log_button.dart';

import '../../support/fake_repo_session.dart';
import '../../support/read_bindings.dart';
import 'panel_test_support.dart';

const ReflogEntry _entry = ReflogEntry(
  index: 0,
  oid: 'aaaaaaa1111',
  message: 'reset: moving to HEAD~1',
  who: Signature(
    name: 'Ada',
    email: 'ada@example.com',
    when: 1755000000,
    tzOffsetMinutes: 0,
  ),
);

const GitError _error = GitError(
  code: 2,
  codeName: 'CommandFailed',
  message: "fatal: ambiguous argument 'nope'",
  detail: '',
  argv: <String>['git', 'reflog'],
  exitCode: 128,
);

typedef _Reply = KeyedReadReply<ReflogKey, List<ReflogEntry>>;

class _NoopRecents extends FakeRecentsRepository {
  @override
  Future<void> recordOpen(String workDir) async {}
}

final Finder _refField = find.byWidgetPredicate(
  (Widget w) => w is TextField && w.decoration?.hintText == 'HEAD',
);

/// Mounted, the panel has sent `''` (HEAD); the session holds that reply.
Future<PumpedPanel> _pump(WidgetTester tester) => pumpPanel(
  tester,
  ReflogPanel(identity: panelTestIdentity),
  state: const RepoSessionState(
    isOpen: true,
    lastReflog: _Reply.succeeded(ReflogKey(''), <ReflogEntry>[_entry]),
  ),
);

Future<void> _emit(
  WidgetTester tester,
  PumpedPanel pumped,
  _Reply reply,
) async {
  pumped.fake.emit(pumped.fake.state.copyWith(lastReflog: reply));
  await tester.pumpAndSettle();
}

void main() {
  // (d)
  testWidgets('a failed reflog shows one banner line with Open log, no rows', (
    tester,
  ) async {
    final PumpedPanel pumped = await _pump(tester);
    expect(find.text('reset: moving to HEAD~1'), findsOneWidget);

    await _emit(tester, pumped, const _Reply.failed(ReflogKey(''), _error));

    expect(find.text('無法載入 HEAD 的 reflog。${_error.message}'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GbmWarningBanner),
        matching: find.byType(GbmOpenLogButton),
      ),
      findsOneWidget,
    );
    expect(find.text('reset: moving to HEAD~1'), findsNothing);
  });

  // (k) The panel asked for HEAD; a reply for `main` is another ref's,
  // content or failure.
  testWidgets('a reply for another ref draws neither its rows nor a banner', (
    tester,
  ) async {
    final PumpedPanel pumped = await _pump(tester);

    await _emit(tester, pumped, const _Reply.failed(ReflogKey('main'), _error));
    expect(find.byType(GbmWarningBanner), findsNothing);

    await _emit(
      tester,
      pumped,
      const _Reply.succeeded(ReflogKey('main'), <ReflogEntry>[_entry]),
    );
    expect(find.text('reset: moving to HEAD~1'), findsNothing);
  });

  // (l2) for the ref field: the filter's setState rebuilds with no send.
  testWidgets('typing a ref without Load keeps the content', (tester) async {
    await _pump(tester);
    await tester.enterText(_refField, 'refs/heads/main');
    await tester.enterText(
      find.descendant(
        of: find.byType(PanelFilterField),
        matching: find.byType(TextField),
      ),
      'reset',
    );
    await tester.pumpAndSettle();

    expect(find.text('reset: moving to HEAD~1'), findsOneWidget);
  });

  // Over the real controller: Load sends the typed ref once, and the session
  // is pending under it.
  testWidgets('Load sends the typed ref once and resets', (tester) async {
    final ReadBindings bindings = ReadBindings();
    final PumpedPanel pumped = await pumpPanel(
      tester,
      ReflogPanel(identity: panelTestIdentity),
      state: const RepoSessionState(isOpen: true),
      controllerFactory: () =>
          RepoSessionController(bindings, panelTestIdentity, _NoopRecents()),
    );
    expect(bindings.reflogRequests, <String>['']);

    await tester.enterText(_refField, ' main ');
    await tester.tap(find.text('Load'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(bindings.reflogRequests, <String>['', 'main']);
    expect(pumped.controller.state.lastReflog?.key, const ReflogKey('main'));
    expect(pumped.controller.state.lastReflog?.value, isNull);
  });
}
