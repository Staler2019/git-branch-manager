// BisectPanel's failure states (read-failure-states-spec.html). The bisect
// status is a refreshed read (R class): a failed refresh keeps the status it
// had and says so in the panel banner, with Open log.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/bisect_status.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/bisect_panel.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';
import 'package:gbm_flutter/widgets/gbm_open_log_button.dart';

import 'panel_test_support.dart';

const BisectStatus _running = BisectStatus(
  active: true,
  currentOid: 'cccccccdddd',
  badOid: 'bbbbbbbaaaa',
  goodOids: <String>['9999999eeee'],
  skippedOids: <String>[],
  logText: '# bad: [bbbbbbbaaaa] broke it',
);

const GitError _statusError = GitError(
  code: 2,
  codeName: 'CommandFailed',
  message: 'fatal: could not read BISECT_LOG',
  detail: '',
  argv: <String>['git', 'bisect', 'log'],
  exitCode: 1,
);

void main() {
  // (w1)
  testWidgets('a failed status refresh keeps the steps and shows the banner', (
    tester,
  ) async {
    final PumpedPanel pumped = await pumpPanel(
      tester,
      BisectPanel(identity: panelTestIdentity),
      state: const RepoSessionState(isOpen: true, bisectStatus: _running),
    );
    expect(find.byType(GbmWarningBanner), findsNothing);
    final int stepsBefore = find.textContaining('bbbbbbb').evaluate().length;
    expect(stepsBefore, greaterThan(0));

    pumped.fake.emit(pumped.fake.state.copyWith(bisectError: _statusError));
    await tester.pumpAndSettle();

    expect(find.textContaining('bbbbbbb').evaluate().length, stepsBefore);
    expect(find.text('無法讀取 bisect 狀態。${_statusError.message}'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GbmWarningBanner),
        matching: find.byType(GbmOpenLogButton),
      ),
      findsOneWidget,
    );
  });
}
