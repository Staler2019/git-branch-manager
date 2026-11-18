// LfsPanel's failure states (read-failure-states-spec.html). The LFS
// listing is a refreshed read (R class): a failed refresh keeps what it had
// and says so in the panel banner, with Open log -- so an empty list after a
// failure no longer reads as "no LFS" (spec row 32).
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/git_error.dart';
import 'package:gbm_flutter/data/models/lfs_state.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/features/panels/lfs_panel.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';
import 'package:gbm_flutter/widgets/gbm_open_log_button.dart';

import 'panel_test_support.dart';

const LfsInstallation _installed = LfsInstallation(
  available: true,
  version: '3.4.0',
);

const GitError _listError = GitError(
  code: 2,
  codeName: 'CommandFailed',
  message: 'fatal: not a git repository',
  detail: '',
  argv: <String>['git', 'lfs', 'ls-files', '--long'],
  exitCode: 128,
);

void main() {
  // (w1)
  testWidgets('a failed refresh keeps the patterns and shows the banner', (
    tester,
  ) async {
    final PumpedPanel pumped = await pumpPanel(
      tester,
      LfsPanel(identity: panelTestIdentity),
      state: const RepoSessionState(
        isOpen: true,
        lfsInstallation: _installed,
        lfsPatterns: <String>['*.psd'],
      ),
    );
    expect(find.byType(GbmWarningBanner), findsNothing);

    pumped.fake.emit(pumped.fake.state.copyWith(lfsError: _listError));
    await tester.pumpAndSettle();

    expect(find.text('*.psd'), findsWidgets);
    expect(find.text('無法載入 LFS 清單。${_listError.message}'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GbmWarningBanner),
        matching: find.byType(GbmOpenLogButton),
      ),
      findsOneWidget,
    );
  });

  // O4: nothing listed yet and the read failed -- the banner says so, where
  // before the panel showed only 「No tracked patterns」.
  testWidgets('a failed first listing says it failed, not that there is none', (
    tester,
  ) async {
    final PumpedPanel pumped = await pumpPanel(
      tester,
      LfsPanel(identity: panelTestIdentity),
      state: const RepoSessionState(isOpen: true, lfsInstallation: _installed),
    );

    pumped.fake.emit(pumped.fake.state.copyWith(lfsError: _listError));
    await tester.pumpAndSettle();

    expect(find.text('無法載入 LFS 清單。${_listError.message}'), findsOneWidget);
  });
}
