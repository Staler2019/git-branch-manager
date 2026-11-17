// InteractiveRebasePanel's failure state, its render guard, and its local
// todo (read-failure-states-spec.html). The panel edits a local copy of the
// plan and Start submits that copy, so a plan for one upstream must never
// survive while the panel waits on, or has failed to load, another: Start
// would replay the first upstream's commits onto the second. Whenever the
// reply for the sent upstream has no value -- pending, failed, or never
// queued -- the local todo is cleared and Start is disabled.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/keyed_read_reply.dart';
import 'package:gbm_flutter/data/models/read_keys.dart';
import 'package:gbm_flutter/data/models/rebase_todo_entry.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/interactive_rebase_panel.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';
import 'package:gbm_flutter/widgets/gbm_open_log_button.dart';

import '../../support/fake_repo_session.dart';
import '../../support/read_bindings.dart';
import 'panel_test_support.dart';

const RebaseTodoEntry _first = RebaseTodoEntry(
  action: RebaseTodoAction.pick,
  oid: 'aaaaaaa1111',
  shortOid: 'aaaaaaa',
  subject: 'add the guard',
);

const GitError _error = GitError(
  code: 2,
  codeName: 'CommandFailed',
  message: "fatal: invalid upstream 'x'",
  detail: '',
  argv: <String>['git', 'rev-list'],
  exitCode: 128,
);

typedef _Reply = KeyedReadReply<RebasePlanKey, List<RebaseTodoEntry>>;

class _NoopRecents extends FakeRecentsRepository {
  @override
  Future<void> recordOpen(String workDir) async {}
}

const String _emptyMessage = 'Load a plan to see the commits it would replay';

Finder get _upstreamField => find.ancestor(
  of: find.text('Upstream (e.g. main)'),
  matching: find.byType(TextField),
);

Future<void> _load(WidgetTester tester, String upstream) async {
  await tester.enterText(_upstreamField, upstream);
  await tester.tap(find.text('Load plan'));
  await tester.pumpAndSettle();
}

Future<void> _emit(
  WidgetTester tester,
  PumpedPanel pumped,
  _Reply? reply,
) async {
  pumped.fake.emit(pumped.fake.state.copyWith(lastRebasePlan: reply));
  await tester.pumpAndSettle();
}

/// `main` loaded and answered: the panel shows its plan and Start is live.
Future<PumpedPanel> _pumpWithMainLoaded(WidgetTester tester) async {
  final PumpedPanel pumped = await pumpPanel(
    tester,
    InteractiveRebasePanel(identity: panelTestIdentity),
    state: const RepoSessionState(isOpen: true),
  );
  await _load(tester, 'main');
  await _emit(
    tester,
    pumped,
    const _Reply.succeeded(RebasePlanKey('main'), <RebaseTodoEntry>[_first]),
  );
  expect(find.text('add the guard'), findsOneWidget);
  expect(panelButton(tester, 'Start').onPressed, isNotNull);
  return pumped;
}

void main() {
  // (i) The pending window, reloading the same upstream: the guard passes
  // throughout (the reply's key is the one sent), so only the local-todo
  // clear decides what Start would submit. Switching to another upstream
  // would not do -- the guard clears on the key change first and masks it.
  testWidgets('while main reloads, its old plan is gone', (tester) async {
    final PumpedPanel pumped = await _pumpWithMainLoaded(tester);

    await _load(tester, 'main');
    await _emit(tester, pumped, const _Reply.pending(RebasePlanKey('main')));

    expect(find.text('add the guard'), findsNothing);
    expect(find.text(_emptyMessage), findsOneWidget);
    expect(panelButton(tester, 'Start').onPressed, isNull);
  });

  // (g) The same, for a failed reload.
  testWidgets('a failed reload of main clears its todo and Start is off', (
    tester,
  ) async {
    final PumpedPanel pumped = await _pumpWithMainLoaded(tester);

    await _load(tester, 'main');
    await _emit(
      tester,
      pumped,
      const _Reply.failed(RebasePlanKey('main'), _error),
    );

    expect(find.text('add the guard'), findsNothing);
    expect(find.text(_emptyMessage), findsOneWidget);
    expect(panelButton(tester, 'Start').onPressed, isNull);
  });

  // Switching upstream: whatever the session holds, main's plan is gone the
  // moment x is sent.
  testWidgets('while another upstream is pending, main\'s plan is gone', (
    tester,
  ) async {
    final PumpedPanel pumped = await _pumpWithMainLoaded(tester);

    await _load(tester, 'x');
    await _emit(tester, pumped, const _Reply.pending(RebasePlanKey('x')));

    expect(find.text(_emptyMessage), findsOneWidget);
    expect(panelButton(tester, 'Start').onPressed, isNull);
  });

  // (d)
  testWidgets('a failed plan clears the todo, shows the banner, and Start is '
      'off', (tester) async {
    final PumpedPanel pumped = await _pumpWithMainLoaded(tester);

    await _load(tester, 'x');
    await _emit(
      tester,
      pumped,
      const _Reply.failed(RebasePlanKey('x'), _error),
    );

    expect(find.text(_emptyMessage), findsOneWidget);
    expect(panelButton(tester, 'Start').onPressed, isNull);
    expect(find.text('無法載入 x 的 rebase plan。${_error.message}'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GbmWarningBanner),
        matching: find.byType(GbmOpenLogButton),
      ),
      findsOneWidget,
    );
  });

  // (k) The panel asked for x; a reply for main is another upstream's.
  testWidgets('a reply for another upstream draws neither its plan nor a '
      'banner', (tester) async {
    final PumpedPanel pumped = await pumpPanel(
      tester,
      InteractiveRebasePanel(identity: panelTestIdentity),
      state: const RepoSessionState(isOpen: true),
    );
    await _load(tester, 'x');

    await _emit(
      tester,
      pumped,
      const _Reply.succeeded(RebasePlanKey('main'), <RebaseTodoEntry>[_first]),
    );
    expect(find.text('add the guard'), findsNothing);
    expect(panelButton(tester, 'Start').onPressed, isNull);

    await _emit(
      tester,
      pumped,
      const _Reply.failed(RebasePlanKey('main'), _error),
    );
    expect(find.byType(GbmWarningBanner), findsNothing);
  });

  // A plan that arrives after a clear is always adopted, even when it is
  // the very list the panel last published.
  testWidgets('the same plan reloaded after a failure is shown again', (
    tester,
  ) async {
    final PumpedPanel pumped = await _pumpWithMainLoaded(tester);
    final _Reply loaded = pumped.fake.state.lastRebasePlan!;

    await _emit(
      tester,
      pumped,
      const _Reply.failed(RebasePlanKey('main'), _error),
    );
    expect(find.text('add the guard'), findsNothing);

    await _emit(tester, pumped, loaded);
    expect(find.text('add the guard'), findsOneWidget);
    expect(panelButton(tester, 'Start').onPressed, isNotNull);
  });

  // Over the real controller: Load plan sends the typed upstream once, and
  // the session is pending under it.
  testWidgets('Load plan sends the upstream once and resets', (tester) async {
    final ReadBindings bindings = ReadBindings();
    final PumpedPanel pumped = await pumpPanel(
      tester,
      InteractiveRebasePanel(identity: panelTestIdentity),
      state: const RepoSessionState(isOpen: true),
      controllerFactory: () =>
          RepoSessionController(bindings, panelTestIdentity, _NoopRecents()),
    );
    expect(bindings.rebasePlanRequests, isEmpty);

    await tester.enterText(_upstreamField, ' main ');
    await tester.tap(find.text('Load plan'));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(bindings.rebasePlanRequests, <String>['main']);
    expect(
      pumped.controller.state.lastRebasePlan?.key,
      const RebasePlanKey('main'),
    );
    expect(pumped.controller.state.lastRebasePlan?.value, isNull);
  });
}
