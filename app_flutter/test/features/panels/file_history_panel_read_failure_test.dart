// FileHistoryPanel's failure state and its render guard
// (read-failure-states-spec.html): a failed history shows one banner line
// with Open log and an empty list (ruling 4: never the previous file's
// commits), and the panel draws the session's history -- content and banner
// alike -- only while it answers the request this panel last sent.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/file_history_entry.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/keyed_read_reply.dart';
import 'package:gbm_flutter/data/models/read_keys.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/file_history_panel.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';
import 'package:gbm_flutter/widgets/gbm_open_log_button.dart';

import '../../support/fake_repo_session.dart';
import '../../support/read_bindings.dart';
import 'panel_test_support.dart';

const String _path = 'lib/main.dart';

const FileHistoryEntry _entry = FileHistoryEntry(
  oid: 'aaaaaaa',
  author: Signature(
    name: 'Ada',
    email: 'ada@example.com',
    when: 1755000000,
    tzOffsetMinutes: 0,
  ),
  subject: 'tidy the header',
  status: 'M',
  renamedFrom: '',
  path: _path,
);

const GitError _error = GitError(
  code: 2,
  codeName: 'CommandFailed',
  message: "fatal: bad revision 'nope'",
  detail: '',
  argv: <String>['git', 'log'],
  exitCode: 128,
);

typedef _Reply = KeyedReadReply<FileHistoryKey, List<FileHistoryEntry>>;

class _NoopRecents extends FakeRecentsRepository {
  @override
  Future<void> recordOpen(String workDir) async {}
}

Future<PumpedPanel> _pump(WidgetTester tester, {required String path}) =>
    pumpPanel(
      tester,
      FileHistoryPanel(identity: panelTestIdentity, path: path),
      state: const RepoSessionState(
        isOpen: true,
        lastFileHistory: _Reply.succeeded(
          FileHistoryKey(path: _path),
          <FileHistoryEntry>[_entry],
        ),
      ),
    );

Future<void> _emit(
  WidgetTester tester,
  PumpedPanel pumped,
  _Reply reply,
) async {
  pumped.fake.emit(pumped.fake.state.copyWith(lastFileHistory: reply));
  await tester.pumpAndSettle();
}

void main() {
  // (d)
  testWidgets('a failed history shows one banner line with Open log, no rows', (
    tester,
  ) async {
    final PumpedPanel pumped = await _pump(tester, path: _path);
    expect(find.text('tidy the header'), findsOneWidget);

    await _emit(
      tester,
      pumped,
      const _Reply.failed(FileHistoryKey(path: _path), _error),
    );

    expect(
      find.text('無法載入 lib/main.dart 的 file history。${_error.message}'),
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

  // (k) The panel asked for lib/other.dart; a reply for lib/main.dart is
  // another file's, content or failure.
  testWidgets('a reply for another key draws neither its rows nor a banner', (
    tester,
  ) async {
    final PumpedPanel pumped = await _pump(tester, path: 'lib/other.dart');
    expect(find.text('tidy the header'), findsNothing);

    await _emit(
      tester,
      pumped,
      const _Reply.failed(FileHistoryKey(path: _path), _error),
    );
    expect(find.byType(GbmWarningBanner), findsNothing);
  });

  // (j) Over the real controller: a path change sends from didUpdateWidget,
  // where a synchronous provider write throws; the deferred send lands once.
  testWidgets('changing the path sends once, after the build, and resets', (
    tester,
  ) async {
    final ReadBindings bindings = ReadBindings();
    final ValueNotifier<String> path = ValueNotifier<String>('a.txt');
    addTearDown(path.dispose);
    final PumpedPanel pumped = await pumpPanel(
      tester,
      ValueListenableBuilder<String>(
        valueListenable: path,
        builder: (BuildContext context, String value, Widget? child) =>
            FileHistoryPanel(identity: panelTestIdentity, path: value),
      ),
      state: const RepoSessionState(isOpen: true),
      controllerFactory: () =>
          RepoSessionController(bindings, panelTestIdentity, _NoopRecents()),
    );
    expect(bindings.fileHistoryRequests.map((r) => r['path']), <Object?>[
      'a.txt',
    ]);

    path.value = 'b.txt';
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(
      bindings.fileHistoryRequests.where((r) => r['path'] == 'b.txt').length,
      1,
    );
    expect(
      pumped.controller.state.lastFileHistory?.key,
      const FileHistoryKey(path: 'b.txt'),
    );
    expect(pumped.controller.state.lastFileHistory?.value, isNull);
  });
}
