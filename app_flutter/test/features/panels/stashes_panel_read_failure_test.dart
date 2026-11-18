// StashesPanel's failure states (read-failure-states-spec.html). The stash
// list is a refreshed list (R class): a failed refresh keeps the list it had
// and says so in the panel banner, with Open log.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/keyed_read_reply.dart';
import 'package:gbm_flutter/data/models/parsed_diff.dart';
import 'package:gbm_flutter/data/models/read_keys.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/stash_entry.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/stashes_panel.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';
import 'package:gbm_flutter/widgets/gbm_open_log_button.dart';

import '../../support/fake_repo_session.dart';
import '../../support/read_bindings.dart';
import 'panel_test_support.dart';

const StashEntry _stash0 = StashEntry(
  index: 0,
  message: 'WIP on main: 9be5523 tab row',
  oid: 'aaaaaaa',
  timestamp: 1755000000,
);

const GitError _listError = GitError(
  code: 2,
  codeName: 'CommandFailed',
  message: 'fatal: not a git repository',
  detail: '',
  argv: <String>['git', 'stash', 'list'],
  exitCode: 128,
);

const GitError _diffError = GitError(
  code: 2,
  codeName: 'CommandFailed',
  message: 'fatal: stash@{0} is not a valid reference',
  detail: '',
  argv: <String>['git', 'stash', 'show'],
  exitCode: 128,
);

typedef _StashDiff = KeyedReadReply<StashDiffKey, ParsedDiff>;

const ParsedDiff _emptyDiff = ParsedDiff(
  files: <DiffFile>[],
  truncated: false,
  inputBytes: 0,
);

class _NoopRecents extends FakeRecentsRepository {
  @override
  Future<void> recordOpen(String workDir) async {}
}

void main() {
  // (w1)
  testWidgets('a failed list refresh keeps the rows and shows the banner', (
    tester,
  ) async {
    final PumpedPanel pumped = await pumpPanel(
      tester,
      StashesPanel(identity: panelTestIdentity),
      state: const RepoSessionState(
        isOpen: true,
        stashes: <StashEntry>[_stash0],
      ),
    );
    expect(find.byType(GbmWarningBanner), findsNothing);

    pumped.fake.emit(pumped.fake.state.copyWith(stashesError: _listError));
    await tester.pumpAndSettle();

    expect(find.textContaining('WIP on main'), findsOneWidget);
    expect(find.text('無法載入 stash 清單。${_listError.message}'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GbmWarningBanner),
        matching: find.byType(GbmOpenLogButton),
      ),
      findsOneWidget,
    );
  });

  // (w3) The selected stash's diff failed: the wait ends and the banner
  // says why. A reply for another index is a request the selection has
  // moved past -- still waiting, nothing to say.
  testWidgets('a failed diff for the selected stash stops the spinner', (
    tester,
  ) async {
    final PumpedPanel pumped = await pumpPanel(
      tester,
      StashesPanel(identity: panelTestIdentity, initialSelectedIndex: 0),
      // Mounted answered: pumpPanel settles, which a spinner never does.
      state: const RepoSessionState(
        isOpen: true,
        stashes: <StashEntry>[_stash0],
        lastStashDiff: _StashDiff.succeeded(StashDiffKey(0), _emptyDiff),
      ),
    );

    pumped.fake.emit(
      pumped.fake.state.copyWith(
        lastStashDiff: const _StashDiff.failed(StashDiffKey(5), _diffError),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(GbmWarningBanner), findsNothing);

    pumped.fake.emit(
      pumped.fake.state.copyWith(
        lastStashDiff: const _StashDiff.failed(StashDiffKey(0), _diffError),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.text('無法載入 stash@{0} 的變更。${_diffError.message}'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(GbmWarningBanner),
        matching: find.byType(GbmOpenLogButton),
      ),
      findsOneWidget,
    );
  });

  // (w4) I1: one banner, and the list's failure covers the whole panel.
  testWidgets('a list failure wins over the selected stash\'s diff failure', (
    tester,
  ) async {
    final PumpedPanel pumped = await pumpPanel(
      tester,
      StashesPanel(identity: panelTestIdentity, initialSelectedIndex: 0),
      state: const RepoSessionState(
        isOpen: true,
        stashes: <StashEntry>[_stash0],
        lastStashDiff: _StashDiff.succeeded(StashDiffKey(0), _emptyDiff),
      ),
    );

    pumped.fake.emit(
      pumped.fake.state.copyWith(
        stashesError: _listError,
        lastStashDiff: const _StashDiff.failed(StashDiffKey(0), _diffError),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GbmWarningBanner), findsOneWidget);
    expect(find.text('無法載入 stash 清單。${_listError.message}'), findsOneWidget);
  });

  // (j-stash) Over the real controller: sidebar 「View diff」 on another
  // stash re-selects through didUpdateWidget, where a synchronous provider
  // write throws; the deferred request lands once.
  testWidgets('re-selecting from outside sends once, after the build', (
    tester,
  ) async {
    final ReadBindings bindings = ReadBindings();
    final ValueNotifier<int> index = ValueNotifier<int>(1);
    addTearDown(index.dispose);
    final PumpedPanel pumped = await pumpPanel(
      tester,
      ValueListenableBuilder<int>(
        valueListenable: index,
        builder: (BuildContext context, int value, Widget? child) =>
            StashesPanel(
              identity: panelTestIdentity,
              initialSelectedIndex: value,
            ),
      ),
      state: const RepoSessionState(isOpen: true),
      controllerFactory: () =>
          RepoSessionController(bindings, panelTestIdentity, _NoopRecents()),
    );
    await tester.pump();
    expect(bindings.stashDiffRequests, <int>[1]);

    index.value = 2;
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(bindings.stashDiffRequests, <int>[1, 2]);
    expect(pumped.controller.state.lastStashDiff?.key, const StashDiffKey(2));
    expect(pumped.controller.state.lastStashDiff?.value, isNull);
  });
}
