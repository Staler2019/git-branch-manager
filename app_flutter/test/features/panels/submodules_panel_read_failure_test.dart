// SubmodulesPanel's failure states (read-failure-states-spec.html). The
// submodule list is a refreshed list (R class): a failed refresh keeps the
// list it had and says so in the panel banner, with Open log.
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/submodule_info.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/submodules_panel.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';
import 'package:gbm_flutter/widgets/gbm_open_log_button.dart';

import 'panel_test_support.dart';

const SubmoduleInfo _vendored = SubmoduleInfo(
  name: 'vendor/libgit',
  path: 'vendor/libgit',
  url: 'https://example.com/libgit.git',
  branch: 'main',
  headOid: 'a1b2c3d',
  state: SubmoduleState.modified,
);

const GitError _listError = GitError(
  code: 2,
  codeName: 'CommandFailed',
  message: 'fatal: not a git repository',
  detail: '',
  argv: <String>['git', 'submodule', 'status'],
  exitCode: 128,
);

void main() {
  // (w1)
  testWidgets('a failed list refresh keeps the rows and shows the banner', (
    tester,
  ) async {
    final PumpedPanel pumped = await pumpPanel(
      tester,
      SubmodulesPanel(identity: panelTestIdentity),
      state: const RepoSessionState(
        isOpen: true,
        submodules: <SubmoduleInfo>[_vendored],
      ),
    );
    expect(find.byType(GbmWarningBanner), findsNothing);

    pumped.fake.emit(pumped.fake.state.copyWith(submodulesError: _listError));
    await tester.pumpAndSettle();

    expect(find.textContaining('vendor/libgit'), findsWidgets);
    expect(
      find.text('無法載入 submodule 清單。${_listError.message}'),
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
}
