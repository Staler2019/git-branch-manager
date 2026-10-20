// The app-wide half of a clone job (P3-J3, R10): its credential prompt opens
// a dialog wherever the user is, a stale one closes when the job ends, and a
// successful clone opens the new repository.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/repositories/clone_job_repository.dart';
import 'package:gbm_flutter/data/repositories/window_log_repository.dart';
import 'package:gbm_flutter/features/app_lifecycle/clone_job_listener.dart';
import 'package:gbm_flutter/features/dialogs/credential/clone_credential_dialog.dart';
import 'package:gbm_flutter/routing/app_router.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_clone_job_native.dart';

class _Harness {
  _Harness(this.native, this.container, this.router);
  final FakeCloneJobNative native;
  final ProviderContainer container;
  final GoRouter router;

  void start() => container
      .read(cloneJobsProvider.notifier)
      .start(
        url: 'https://h/r.git',
        destPath: '/src/r',
        recurseSubmodules: false,
        shallow: false,
        origin: CloneLogTarget.window(
          container.read(windowLogProvider.notifier),
        ),
      );

  void ask(String prompt) => native.emit(
    0,
    GbmEventType.credentialRequested,
    <String, Object>{'prompt': prompt},
  );

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();
}

Future<_Harness> _pump(WidgetTester tester) async {
  final FakeCloneJobNative native = FakeCloneJobNative();
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(body: Text('home')),
      ),
      GoRoute(
        path: RoutePaths.history,
        builder: (context, state) =>
            Scaffold(body: Text('repo ${state.pathParameters['repoId']}')),
      ),
      cloneCredentialDialogRoute(),
    ],
  );
  addTearDown(router.dispose);
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      cloneJobNativeProvider.overrideWithValue(native),
      appRouterProvider.overrideWithValue(router),
      windowLogProvider.overrideWith(
        (ref) => WindowLogController(maxEntries: 100),
      ),
      // R12's move into the new repository's Log is the controller's own
      // test; here the target only has to exist.
      cloneRepositoryLogProvider.overrideWithValue(
        (String dest) => CloneLogTarget(record: (_) {}, retract: (_) {}),
      ),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: router,
        builder: (context, child) => CloneJobListener(child: child!),
      ),
    ),
  );
  return _Harness(native, container, router);
}

void main() {
  testWidgets('a prompt opens the dialog; Submit answers that job', (
    tester,
  ) async {
    final _Harness h = await _pump(tester);
    h.start();
    h.ask("Password for 'https://h': ");
    await tester.pumpAndSettle();
    expect(find.byType(CloneCredentialDialogContent), findsOneWidget);
    expect(find.text("Password for 'https://h': "), findsOneWidget);
    final TextField field = tester.widget<TextField>(
      find.byKey(const Key('credential-secret-field')),
    );
    expect(field.obscureText, isTrue);

    await tester.enterText(
      find.byKey(const Key('credential-secret-field')),
      's3cret',
    );
    await tester.tap(find.widgetWithText(GbmButton, 'Submit'));
    await tester.pumpAndSettle();
    expect(h.native.jobs.single.calls, <String>['provide:s3cret']);
    expect(find.byType(CloneCredentialDialogContent), findsNothing);
  });

  testWidgets('Cancel, and Esc, both cancel the prompt', (tester) async {
    final _Harness h = await _pump(tester);
    h.start();
    h.ask('Username for x');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(GbmButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(h.native.jobs.single.calls, <String>['cancelCredential']);

    h.ask('Password for x');
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CloneCredentialDialogContent), findsNothing);
    expect(h.native.jobs.single.calls, <String>[
      'cancelCredential',
      'cancelCredential',
    ]);
  });

  testWidgets('a job that ends closes its stale dialog without answering', (
    tester,
  ) async {
    final _Harness h = await _pump(tester);
    h.start();
    h.ask('Password for x');
    await tester.pumpAndSettle();
    h.native.emit(0, GbmEventType.cloneFinished, <String, Object>{'ok': false});
    await tester.pumpAndSettle();
    expect(find.byType(CloneCredentialDialogContent), findsNothing);
    expect(h.native.jobs.single.calls, <String>['close']);
  });

  testWidgets('a successful clone opens the new repository (R10)', (
    tester,
  ) async {
    final _Harness h = await _pump(tester);
    h.start();
    h.native.emit(0, GbmEventType.cloneFinished, <String, Object>{'ok': true});
    await tester.pumpAndSettle();
    expect(h.location, RoutePaths.workspaceFor(repoIdFor('/src/r')));
  });

  testWidgets('a failed one stays where the user is', (tester) async {
    final _Harness h = await _pump(tester);
    h.start();
    h.native.emit(0, GbmEventType.cloneFinished, <String, Object>{'ok': false});
    await tester.pumpAndSettle();
    expect(h.location, '/');
  });
}
