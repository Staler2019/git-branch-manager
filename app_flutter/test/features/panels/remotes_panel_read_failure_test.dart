// RemotesPanel's failure states (read-failure-states-spec.html). The remote
// list is a refreshed list (R class): a failed refresh keeps the list it had
// and says so in the panel banner, with Open log.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/remote_info.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/remotes_panel.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';
import 'package:gbm_flutter/widgets/gbm_open_log_button.dart';

import 'panel_test_support.dart';

const RemoteInfo _origin = RemoteInfo(
  name: 'origin',
  fetchUrl: 'https://example.com/repo.git',
  pushUrl: 'https://example.com/repo.git',
);

const GitError _listError = GitError(
  code: 2,
  codeName: 'CommandFailed',
  message: 'fatal: not a git repository',
  detail: '',
  argv: <String>['git', 'remote', '-v'],
  exitCode: 128,
);

void main() {
  // (w1)
  testWidgets('a failed list refresh keeps the rows and shows the banner', (
    tester,
  ) async {
    final PumpedPanel pumped = await pumpPanel(
      tester,
      RemotesPanel(identity: panelTestIdentity),
      state: const RepoSessionState(
        isOpen: true,
        remotes: <RemoteInfo>[_origin],
      ),
    );
    expect(find.byType(GbmWarningBanner), findsNothing);

    pumped.fake.emit(pumped.fake.state.copyWith(remotesError: _listError));
    await tester.pumpAndSettle();

    expect(find.text('origin'), findsWidgets);
    expect(find.text('無法載入 remote 清單。${_listError.message}'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GbmWarningBanner),
        matching: find.byType(GbmOpenLogButton),
      ),
      findsOneWidget,
    );
  });
}
