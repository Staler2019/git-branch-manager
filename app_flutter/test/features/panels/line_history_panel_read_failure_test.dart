// LineHistoryPanel's failure state and its render guard
// (read-failure-states-spec.html): a failed history shows one banner line
// with Open log and an empty list (ruling 4: never another range's steps),
// and the panel draws the session's history -- content and banner alike --
// only while it answers the range this panel last sent. The range is the one
// the panel *sent*, not what the fields say now: typing a new start line
// without submitting asks for nothing, so it hides nothing either.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/keyed_read_reply.dart';
import 'package:gbm_flutter/data/models/line_history_chunk.dart';
import 'package:gbm_flutter/data/models/read_keys.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/line_history_panel.dart';
import 'package:gbm_flutter/features/panels/panel_filter_field.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';
import 'package:gbm_flutter/widgets/gbm_open_log_button.dart';

import '../../support/fake_repo_session.dart';
import '../../support/read_bindings.dart';
import 'panel_test_support.dart';

const String _path = 'lib/main.dart';
const LineHistoryKey _mounted = LineHistoryKey(
  path: _path,
  startLine: 10,
  endLine: 12,
);

const LineHistoryChunk _step = LineHistoryChunk(
  oid: 'aaaaaaa',
  author: Signature(
    name: 'Ada',
    email: 'ada@example.com',
    when: 1755000000,
    tzOffsetMinutes: 0,
  ),
  subject: 'tidy the header',
  diffText: '@@ -10,3 +10,3 @@',
);

const GitError _error = GitError(
  code: 2,
  codeName: 'CommandFailed',
  message: 'fatal: file lib/main.dart has only 8 lines',
  detail: '',
  argv: <String>['git', 'log'],
  exitCode: 128,
);

typedef _Reply = KeyedReadReply<LineHistoryKey, List<LineHistoryChunk>>;

class _NoopRecents extends FakeRecentsRepository {
  @override
  Future<void> recordOpen(String workDir) async {}
}

Future<PumpedPanel> _pump(WidgetTester tester, {int from = 10, int to = 12}) =>
    pumpPanel(
      tester,
      LineHistoryPanel(
        identity: panelTestIdentity,
        path: _path,
        initialStartLine: from,
        initialEndLine: to,
      ),
      state: const RepoSessionState(
        isOpen: true,
        lastLineHistory: _Reply.succeeded(_mounted, <LineHistoryChunk>[_step]),
      ),
    );

Future<void> _emit(
  WidgetTester tester,
  PumpedPanel pumped,
  _Reply reply,
) async {
  pumped.fake.emit(pumped.fake.state.copyWith(lastLineHistory: reply));
  await tester.pumpAndSettle();
}

Finder _field(String key) => find.byKey(PageStorageKey<String>(key));

void main() {
  // (d)
  testWidgets('a failed range shows one banner line with Open log, no rows', (
    tester,
  ) async {
    final PumpedPanel pumped = await _pump(tester);
    expect(find.text('tidy the header'), findsOneWidget);

    await _emit(tester, pumped, const _Reply.failed(_mounted, _error));

    expect(
      find.text('無法載入 lib/main.dart 的 line history。${_error.message}'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(GbmWarningBanner),
        matching: find.byType(GbmOpenLogButton),
      ),
      findsOneWidget,
    );
    expect(find.text('tidy the header'), findsNothing);
  });

  // (k) The panel asked for lines 1-3; a reply for 10-12 is another range's,
  // content or failure.
  testWidgets('a reply for another range draws neither its rows nor a banner', (
    tester,
  ) async {
    final PumpedPanel pumped = await _pump(tester, from: 1, to: 3);
    expect(find.text('tidy the header'), findsNothing);

    await _emit(tester, pumped, const _Reply.failed(_mounted, _error));
    expect(find.byType(GbmWarningBanner), findsNothing);
  });

  // (l2) The filter field is the panel's one onChanged -> setState, so it
  // rebuilds with no send; the guard must compare against the range sent,
  // not the one now typed into the start field.
  testWidgets('typing a range without submitting keeps the content', (
    tester,
  ) async {
    await _pump(tester);
    await tester.enterText(_field('panel-field:start'), '40');
    await tester.enterText(
      find.descendant(
        of: find.byType(PanelFilterField),
        matching: find.byType(TextField),
      ),
      'tidy',
    );
    await tester.pumpAndSettle();

    expect(find.text('tidy the header'), findsOneWidget);
  });

  // Over the real controller: Widen sends the widened range once, and the
  // session is pending under it.
  testWidgets('Widen range sends the new range once and resets', (
    tester,
  ) async {
    final ReadBindings bindings = ReadBindings();
    final PumpedPanel pumped = await pumpPanel(
      tester,
      LineHistoryPanel(
        identity: panelTestIdentity,
        path: _path,
        initialStartLine: 20,
        initialEndLine: 22,
      ),
      state: const RepoSessionState(isOpen: true),
      controllerFactory: () =>
          RepoSessionController(bindings, panelTestIdentity, _NoopRecents()),
    );
    expect(bindings.lineHistoryRequests, hasLength(1));

    await tester.tap(find.text('Widen range'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      bindings.lineHistoryRequests.where((r) => r['startLine'] == 10).length,
      1,
    );
    expect(
      pumped.controller.state.lastLineHistory?.key,
      const LineHistoryKey(path: _path, startLine: 10, endLine: 32),
    );
    expect(pumped.controller.state.lastLineHistory?.value, isNull);
  });
}
