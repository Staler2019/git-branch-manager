// BlamePanel's failure state and its render guard (read-failure-states-spec.html):
// a failed blame shows one banner line with Open log and an empty list
// (ruling 4: never the previous subject's lines), and the panel draws the
// session's blame -- content and banner alike -- only while it answers the
// request this panel last sent.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/blame_result.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/keyed_read_reply.dart';
import 'package:gbm_flutter/data/models/read_keys.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/blame_panel.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';
import 'package:gbm_flutter/widgets/gbm_open_log_button.dart';

import '../../support/fake_repo_session.dart';
import '../../support/read_bindings.dart';
import 'panel_test_support.dart';

const String _path = 'lib/main.dart';

const BlameLine _line = BlameLine(
  commitOid: 'bbbbbbb',
  authorName: 'Grace',
  authorEmail: 'grace@example.com',
  authorTime: 1754000000,
  summary: 'tidy imports',
  finalLine: 1,
  originalLine: 1,
  content: 'import bar;',
  boundary: false,
);

const BlameLine _olderLine = BlameLine(
  commitOid: '9999999',
  authorName: 'Ada',
  authorEmail: 'ada@example.com',
  authorTime: 1753000000,
  summary: 'first',
  finalLine: 1,
  originalLine: 1,
  content: 'import foo;',
  boundary: false,
);

const CommitMeta _metaOfLine = CommitMeta(
  oid: 'bbbbbbb',
  tree: 'ttt',
  parents: <String>['9999999'],
  author: Signature(
    name: 'Grace',
    email: 'grace@example.com',
    when: 1754000000,
    tzOffsetMinutes: 0,
  ),
  committer: Signature(
    name: 'Grace',
    email: 'grace@example.com',
    when: 1754000000,
    tzOffsetMinutes: 0,
  ),
  subject: 'tidy imports',
  body: '',
  signedCommit: false,
);

const GitError _error = GitError(
  code: 2,
  codeName: 'CommandFailed',
  message: "fatal: no such path 'lib/main.dart' in HEAD",
  detail: '',
  argv: <String>['git', 'blame'],
  exitCode: 128,
);

KeyedReadReply<BlameKey, BlameResult> _ok(BlameKey key, BlameLine line) =>
    KeyedReadReply<BlameKey, BlameResult>.succeeded(
      key,
      BlameResult(lines: <BlameLine>[line], truncated: false),
    );

class _NoopRecents extends FakeRecentsRepository {
  @override
  Future<void> recordOpen(String workDir) async {}
}

Future<PumpedPanel> _pump(WidgetTester tester, {required String path}) =>
    pumpPanel(
      tester,
      BlamePanel(identity: panelTestIdentity, path: path),
      state: RepoSessionState(
        isOpen: true,
        lastBlame: _ok(const BlameKey(path: _path), _line),
        commitMetaCache: const <String, CommitMeta>{'bbbbbbb': _metaOfLine},
      ),
    );

Future<void> _emitBlame(
  WidgetTester tester,
  PumpedPanel pumped,
  KeyedReadReply<BlameKey, BlameResult> reply,
) async {
  pumped.fake.emit(pumped.fake.state.copyWith(lastBlame: reply));
  await tester.pumpAndSettle();
}

void main() {
  // (d)
  testWidgets('a failed blame shows one banner line with Open log, no lines', (
    tester,
  ) async {
    final PumpedPanel pumped = await _pump(tester, path: _path);
    expect(find.text('import bar;'), findsOneWidget);

    await _emitBlame(
      tester,
      pumped,
      const KeyedReadReply<BlameKey, BlameResult>.failed(
        BlameKey(path: _path),
        _error,
      ),
    );

    expect(
      find.text("無法載入 lib/main.dart 的 blame。${_error.message}"),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(GbmWarningBanner),
        matching: find.byType(GbmOpenLogButton),
      ),
      findsOneWidget,
    );
    expect(find.text('import bar;'), findsNothing);
    expect(find.text('No blame information'), findsOneWidget);
  });

  // (k) The panel asked for lib/other.dart; a reply for lib/main.dart is
  // another subject's, content or failure.
  testWidgets('a reply for another key draws neither its lines nor a banner', (
    tester,
  ) async {
    final PumpedPanel pumped = await _pump(tester, path: 'lib/other.dart');
    expect(find.text('import bar;'), findsNothing);

    await _emitBlame(
      tester,
      pumped,
      const KeyedReadReply<BlameKey, BlameResult>.failed(
        BlameKey(path: _path),
        _error,
      ),
    );
    expect(find.byType(GbmWarningBanner), findsNothing);
    expect(find.text('No blame information'), findsOneWidget);
  });

  // (l1) Previous revision sends a key with the parent revision; its reply
  // is this panel's.
  testWidgets('the reply to Previous revision is drawn', (tester) async {
    final PumpedPanel pumped = await _pump(tester, path: _path);
    await tester.tap(find.text('import bar;'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Previous revision'));
    await tester.pumpAndSettle();

    await _emitBlame(
      tester,
      pumped,
      _ok(const BlameKey(path: _path, revision: '9999999'), _olderLine),
    );

    expect(find.text('import foo;'), findsOneWidget);
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
            BlamePanel(identity: panelTestIdentity, path: value),
      ),
      state: const RepoSessionState(isOpen: true),
      controllerFactory: () =>
          RepoSessionController(bindings, panelTestIdentity, _NoopRecents()),
    );
    expect(bindings.blameRequests.map((r) => r['path']), <Object?>['a.txt']);

    path.value = 'b.txt';
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(bindings.blameRequests.where((r) => r['path'] == 'b.txt').length, 1);
    expect(
      pumped.controller.state.lastBlame?.key,
      const BlameKey(path: 'b.txt'),
    );
    expect(pumped.controller.state.lastBlame?.value, isNull);
  });
}
