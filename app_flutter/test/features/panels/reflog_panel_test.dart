// ReflogPanel against spec page 19's PANELSPEC row for reflog:
//
//   list:    reflog 項目（時間 + 動作）
//   detail:  該 commit 的明細與可回得的 ref
//   toolbar: Restore branch、Checkout、Copy SHA
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/commit_meta.dart';
import 'package:gbm_flutter/data/models/reflog_entry.dart';
import 'package:gbm_flutter/data/models/signature.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/panel_filter_field.dart';
import 'package:gbm_flutter/features/panels/panel_widgets.dart';
import 'package:gbm_flutter/features/panels/reflog_panel.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_repo_session.dart';
import 'panel_test_support.dart';

const Signature _who = Signature(
  name: 'Ada',
  email: 'ada@example.com',
  when: 1755000000,
  tzOffsetMinutes: 0,
);

const ReflogEntry _reset = ReflogEntry(
  index: 0,
  oid: 'aaaaaaa1111',
  message: 'reset: moving to HEAD~1',
  who: _who,
);

const ReflogEntry _commit = ReflogEntry(
  index: 1,
  oid: 'bbbbbbb2222',
  message: 'commit: add tab row',
  who: _who,
);

const CommitMeta _meta = CommitMeta(
  oid: 'bbbbbbb2222',
  tree: 'ttt',
  parents: <String>['ccc'],
  author: _who,
  committer: _who,
  subject: 'add tab row',
  body: 'a longer explanation',
  signedCommit: false,
);

Future<PumpedPanel> _pump(
  WidgetTester tester, {
  List<ReflogEntry> entries = const <ReflogEntry>[_reset, _commit],
  Map<String, CommitMeta> meta = const <String, CommitMeta>{},
}) => pumpPanel(
  tester,
  ReflogPanel(identity: panelTestIdentity),
  state: RepoSessionState(
    isOpen: true,
    lastReflog: entries,
    commitMetaCache: meta,
  ),
  extraRoutes: <RouteBase>[
    GoRoute(
      path: RoutePaths.newBranchDialog,
      builder: (context, state) => Scaffold(
        body: Text('new-branch:${state.uri.queryParameters['startPoint']}'),
      ),
    ),
  ],
);

/// The ref-to-load field, told apart from the toolbar's filter by its own
/// hint rather than by position.
///
/// It was a bare `find.byType(TextField)`, which became ambiguous the moment
/// rule 2's filter slot was filled — the filter is a `TextField` too. A
/// predicate on the decoration is used instead of a label finder because
/// this field has only a hint, and a hint stops being rendered as soon as
/// the field has text in it ([TEST-design-system-swap-breaks-finders]).
final Finder _refField = find.byWidgetPredicate(
  (Widget w) => w is TextField && w.decoration?.hintText == 'HEAD',
);

Future<void> _filter(WidgetTester tester, String query) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(PanelFilterField),
      matching: find.byType(TextField),
    ),
    query,
  );
  await tester.pumpAndSettle();
}

void main() {
  group('ReflogPanel (spec P19 PANELSPEC)', () {
    testWidgets('the toolbar carries PANELSPEC\'s three actions', (
      tester,
    ) async {
      await _pump(tester);

      for (final String label in const <String>[
        'Restore branch…',
        'Checkout',
        'Copy SHA',
      ]) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('the list shows each action over its time', (tester) async {
      await _pump(tester);

      expect(find.text('reset: moving to HEAD~1'), findsOneWidget);
      expect(find.text('commit: add tab row'), findsOneWidget);
    });

    testWidgets('the detail pane is empty until an entry is selected', (
      tester,
    ) async {
      await _pump(tester);

      expect(
        find.text('Select a reflog entry to see its commit'),
        findsOneWidget,
      );
    });

    // 可回得的 ref: `<ref>@{N}` is the revision string that gets this state
    // back, so it is the field this panel exists to produce.
    testWidgets('the detail shows the recoverable revision string', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('commit: add tab row'));
      await tester.pumpAndSettle();

      expect(find.text('Recoverable as'), findsOneWidget);
      expect(find.text('HEAD@{1}'), findsOneWidget);
    });

    testWidgets('selecting an entry requests its commit meta', (tester) async {
      final PumpedPanel pumped = await _pump(tester);
      await tester.tap(find.text('commit: add tab row'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'requestCommitMeta',
      );
      expect(cmd.args['oids'], <String>['bbbbbbb2222']);
    });

    testWidgets('cached commit meta fills in subject, body and author', (
      tester,
    ) async {
      await _pump(
        tester,
        meta: const <String, CommitMeta>{'bbbbbbb2222': _meta},
      );
      await tester.tap(find.text('commit: add tab row'));
      await tester.pumpAndSettle();

      expect(find.text('add tab row'), findsOneWidget);
      expect(find.text('a longer explanation'), findsOneWidget);
      expect(find.text('Ada <ada@example.com>'), findsWidgets);
    });

    // A reflog entry can outlive its commit -- saying which of the two
    // causes it is beats a blank pane.
    testWidgets('a missing commit meta says loading-or-gone', (tester) async {
      await _pump(tester);
      await tester.tap(find.text('commit: add tab row'));
      await tester.pumpAndSettle();

      expect(
        find.text('Loading, or no longer in the object database'),
        findsOneWidget,
      );
    });

    testWidgets('all three actions are disabled with no selection', (
      tester,
    ) async {
      await _pump(tester);

      for (final String label in const <String>[
        'Restore branch…',
        'Checkout',
        'Copy SHA',
      ]) {
        expect(panelButton(tester, label).onPressed, isNull, reason: label);
      }
    });

    // There is no branch at a reflog entry -- that is the whole reason this
    // panel exists -- so the checkout must detach rather than silently
    // failing to find a branch.
    testWidgets('Checkout detaches at the selected oid', (tester) async {
      final PumpedPanel pumped = await _pump(tester);
      await tester.tap(find.text('reset: moving to HEAD~1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Checkout'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'checkout',
      );
      expect(cmd.args['target'], 'aaaaaaa1111');
      expect(cmd.args['detach'], isTrue);
    });

    testWidgets('Restore branch… opens new-branch with that oid', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('reset: moving to HEAD~1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Restore branch…'));
      await tester.pumpAndSettle();

      expect(find.text('new-branch:aaaaaaa1111'), findsOneWidget);
    });

    testWidgets('Copy SHA puts the oid on the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') {
            copied =
                (call.arguments as Map<Object?, Object?>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await _pump(tester);
      await tester.tap(find.text('reset: moving to HEAD~1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy SHA'));
      await tester.pumpAndSettle();

      expect(copied, 'aaaaaaa1111');
    });

    testWidgets('the toolbar follows P19 rule 2\'s four segments', (
      tester,
    ) async {
      await _pump(tester);
      await tester.tap(find.text('reset: moving to HEAD~1'));
      await tester.pumpAndSettle();

      expectPanelTemplate(
        tester,
        // `Restore branch…` is the only action here that creates anything.
        primary: const <String>['Restore branch…'],
        // Checking out a reflog entry acts on this repository, which is
        // maintenance; only `Copy SHA` leaves the app at all.
        maintenance: const <String>['Checkout'],
        external: const <String>['Copy SHA'],
        listHeader: 'Reflog · 2',
        statusBar: RegExp(r'^2 entries$'),
      );
    });

    testWidgets('the filter narrows the list, the header and the status line', (
      tester,
    ) async {
      await _pump(tester);
      expect(find.byType(PanelListRow), findsNWidgets(2));

      await _filter(tester, 'reset');

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('reset: moving to HEAD~1'), findsOneWidget);
      expect(find.text('Reflog · 1'), findsOneWidget);
      expect(find.text('2 entries · 命中 1'), findsOneWidget);
    });

    // The discriminating case. A row draws its *message* and its date, never
    // its oid — so 「bbbbbbb」 is in no rendered text at all, and it is the
    // only kind of query that tells a message-only filter apart from one
    // that also reads the oid ([TEST-fixture-cannot-disagree]). Looking up
    // a reflog entry by SHA is the case this exists for: a user who has the
    // hash from `git reflog` output has nothing else to paste.
    testWidgets('an entry is findable by an oid the row never draws', (
      tester,
    ) async {
      await _pump(tester);

      await _filter(tester, 'bbbbbbb');

      expect(find.byType(PanelListRow), findsOneWidget);
      expect(find.text('commit: add tab row'), findsOneWidget);
    });

    testWidgets('a filter that hides everything says so, not "no entries"', (
      tester,
    ) async {
      await _pump(tester);

      await _filter(tester, 'zzz');

      expect(find.text('No reflog entry matches the filter'), findsOneWidget);
      expect(find.text('No reflog entries'), findsNothing);
    });

    // Loading another ref re-scopes the list, so a selection from the old
    // ref must not survive into the new one.
    testWidgets('loading a different ref requests it and clears selection', (
      tester,
    ) async {
      final PumpedPanel pumped = await _pump(tester);
      await tester.tap(find.text('reset: moving to HEAD~1'));
      await tester.pumpAndSettle();

      await tester.enterText(_refField, 'refs/heads/main');
      await tester.tap(find.text('Load'));
      await tester.pumpAndSettle();

      final FakeCommand cmd = pumped.fake.commandLog.lastWhere(
        (FakeCommand c) => c.name == 'requestReflog',
      );
      expect(cmd.args['ref'], 'refs/heads/main');
      expect(panelButton(tester, 'Checkout').onPressed, isNull);
    });

    testWidgets('an empty reflog says so', (tester) async {
      await _pump(tester, entries: const <ReflogEntry>[]);

      expect(find.text('No reflog entries'), findsOneWidget);
    });
  });
}
