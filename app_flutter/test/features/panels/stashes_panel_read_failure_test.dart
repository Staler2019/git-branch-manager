// StashesPanel's failure states (read-failure-states-spec.html). The stash
// list is a refreshed list (R class): a failed refresh keeps the list it had
// and says so in the panel banner, with Open log.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/stash_entry.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/stashes_panel.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';
import 'package:gbm_flutter/widgets/gbm_open_log_button.dart';

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
}
