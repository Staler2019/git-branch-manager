// appLogSinkFor: the window an action started in decides which Log its
// lines go to -- the repository's when one is open, otherwise the window's
// own (ruling R13). Shared by every surface that can open in either.
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:gbm_flutter/data/repositories/app_log_sink.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/data/repositories/repo_session_repository.dart';
import 'package:gbm_flutter/data/repositories/window_log_repository.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../support/fake_repo_session.dart';

const AppLogEntry _line = AppLogEntry(
  whenEpochMs: 1,
  level: OperationLogLevel.info,
  message: 'hello',
);

Future<(ProviderContainer, FakeRepoSessionController, WidgetRef)> _pump(
  WidgetTester tester,
) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final RepoIdentity identity = RepoIdentity.forWorkDir('/r');
  final FakeRepoSessionController session = FakeRepoSessionController(
    identity,
    const RepoSessionState(isOpen: true),
  );
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      sharedPreferencesProvider.overrideWithValue(prefs),
      repoSessionProvider(identity).overrideWith((ref) => session),
    ],
  );
  addTearDown(container.dispose);
  late WidgetRef scope;
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: Consumer(
        builder: (context, ref, _) {
          scope = ref;
          return const SizedBox();
        },
      ),
    ),
  );
  return (container, session, scope);
}

void main() {
  testWidgets('no work dir writes to the window Log', (tester) async {
    final (ProviderContainer c, FakeRepoSessionController s, WidgetRef ref) =
        await _pump(tester);
    appLogSinkFor(ref, null)(_line);
    expect(c.read(windowLogProvider).entries, <GbmLogEntry>[_line]);
    expect(s.state.operationLog, isEmpty);
  });

  testWidgets('a work dir writes to that repository\'s Log', (tester) async {
    final (ProviderContainer c, FakeRepoSessionController s, WidgetRef ref) =
        await _pump(tester);
    appLogSinkFor(ref, '/r')(_line);
    expect(s.state.operationLog, <GbmLogEntry>[_line]);
    expect(c.read(windowLogProvider).entries, isEmpty);
  });
}
