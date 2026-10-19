// Covers promptNewRepository()/promptCloneRepository() in
// repo_switcher_popover.dart: File → New repository…/Clone repository… and
// the switcher popover footer's Clone repository… all funnel through these
// two functions. Both reach gbm_repo_init()/gbm_repo_clone() directly via
// gbmBindingsProvider (there is no session yet for a RepoSessionController
// to dispatch through), so this drives a configurable fake GbmBindings
// rather than a FakeRepoSessionController.
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/ffi/gbm_bindings.dart';
import 'package:gbm_flutter/data/repositories/gbm_bindings_provider.dart';
import 'package:gbm_flutter/features/repo_switcher/repo_switcher_popover.dart';
import 'package:gbm_flutter/routing/route_paths.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:go_router/go_router.dart';

class _FakeInitCloneBindings implements GbmBindings {
  int initResult = 0;
  int cloneResult = 0;
  String errorJson = '';
  String? lastInitPath;
  String? lastCloneUrl;
  String? lastCloneDest;

  @override
  RepoInitDart get repoInit => (Pointer<Utf8> path) {
    lastInitPath = path.toDartString();
    return initResult;
  };

  @override
  RepoCloneDart get repoClone => (Pointer<Utf8> url, Pointer<Utf8> destPath) {
    lastCloneUrl = url.toDartString();
    lastCloneDest = destPath.toDartString();
    return cloneResult;
  };

  @override
  LastResultJsonLenDart get lastResultJsonLen =>
      () => utf8ByteLength(errorJson);

  @override
  LastResultJsonCopyDart get lastResultJsonCopy =>
      (Pointer<Uint8> out, int outLen) {
        final List<int> bytes = errorJson.codeUnits;
        for (int i = 0; i < outLen && i < bytes.length; i++) {
          out[i] = bytes[i];
        }
      };

  @override
  Never noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Not implemented for testing');
  }
}

int utf8ByteLength(String s) => s.codeUnits.length;

Future<GoRouter> _pump(
  WidgetTester tester,
  Widget child,
  _FakeInitCloneBindings bindings,
) async {
  final GoRouter router = GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (context, state) => Scaffold(body: child),
      ),
      GoRoute(
        path: RoutePaths.history,
        builder: (context, state) => Scaffold(
          body: Text('workspace: ${state.pathParameters['repoId']}'),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[gbmBindingsProvider.overrideWithValue(bindings)],
      child: MaterialApp.router(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

class _NewRepoButton extends ConsumerWidget {
  const _NewRepoButton({this.failures});

  /// Every `(path, message)` [promptNewRepository] reports as failed.
  final List<(String, String)>? failures;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => promptNewRepository(
        context,
        ref,
        onFailed: (String path, String message) =>
            failures?.add((path, message)),
      ),
      child: const Text('New'),
    );
  }
}

class _CloneRepoButton extends ConsumerWidget {
  const _CloneRepoButton({this.failures});

  /// When set, failures go to `onFailed` (the list footer's path); when
  /// null, the dialog shows them itself (File → Clone repository…).
  final List<String>? failures;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<String>? sink = failures;
    return ElevatedButton(
      onPressed: () => promptCloneRepository(context, ref, onFailed: sink?.add),
      child: const Text('Open Clone Prompt'),
    );
  }
}

void main() {
  group('promptNewRepository', () {
    testWidgets('runs gbm_repo_init and switches to the new repository', (
      tester,
    ) async {
      final _FakeInitCloneBindings bindings = _FakeInitCloneBindings();
      final GoRouter router = await _pump(
        tester,
        const _NewRepoButton(),
        bindings,
      );

      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '/repos/new-project');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(bindings.lastInitPath, '/repos/new-project');
      expect(
        router.routerDelegate.currentConfiguration.uri.toString(),
        RoutePaths.workspaceFor(Uri.encodeComponent('/repos/new-project')),
      );
    });

    testWidgets('cancelling the prompt calls gbm_repo_init with nothing', (
      tester,
    ) async {
      final _FakeInitCloneBindings bindings = _FakeInitCloneBindings();
      await _pump(tester, const _NewRepoButton(), bindings);

      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(bindings.lastInitPath, isNull);
    });

    // A failure goes to the caller -- File → New repository… logs it as an
    // error line (open-with-apps-spec.html screen 3) -- never a toast.
    testWidgets('reports the GitError message and stays put when init fails', (
      tester,
    ) async {
      final List<(String, String)> failures = <(String, String)>[];
      final _FakeInitCloneBindings bindings = _FakeInitCloneBindings()
        ..initResult = -3
        ..errorJson =
            '{"code":2,"codeName":"InvalidArgument",'
            '"message":"A repository path is required","detail":"",'
            '"argv":[],"exitCode":0}';
      final GoRouter router = await _pump(
        tester,
        _NewRepoButton(failures: failures),
        bindings,
      );

      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '/repos/blocked');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(failures, <(String, String)>[
        ('/repos/blocked', 'A repository path is required'),
      ]);
      expect(find.byType(SnackBar), findsNothing);
      expect(router.routerDelegate.currentConfiguration.uri.toString(), '/');
    });
  });

  group('promptCloneRepository', () {
    testWidgets(
      'runs gbm_repo_clone with both fields and switches to the clone',
      (tester) async {
        final _FakeInitCloneBindings bindings = _FakeInitCloneBindings();
        final GoRouter router = await _pump(
          tester,
          const _CloneRepoButton(),
          bindings,
        );

        await tester.tap(find.text('Open Clone Prompt'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Repository URL'),
          'git@github.com:example/repo.git',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Destination path'),
          '/repos/cloned',
        );
        await tester.tap(find.text('Clone'));
        await tester.pumpAndSettle();

        expect(bindings.lastCloneUrl, 'git@github.com:example/repo.git');
        expect(bindings.lastCloneDest, '/repos/cloned');
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          RoutePaths.workspaceFor(Uri.encodeComponent('/repos/cloned')),
        );
      },
    );

    testWidgets('does not submit while the destination path is still empty', (
      tester,
    ) async {
      final _FakeInitCloneBindings bindings = _FakeInitCloneBindings();
      await _pump(tester, const _CloneRepoButton(), bindings);

      await tester.tap(find.text('Open Clone Prompt'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Repository URL'),
        'git@github.com:example/repo.git',
      );
      await tester.tap(find.text('Clone'));
      await tester.pumpAndSettle();

      expect(bindings.lastCloneUrl, isNull);
      // The dialog is still open with what was typed still in place.
      expect(find.text('git@github.com:example/repo.git'), findsOneWidget);
    });

    Future<void> fillAndClone(WidgetTester tester) async {
      await tester.enterText(
        find.widgetWithText(TextField, 'Repository URL'),
        'git@github.com:example/missing.git',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Destination path'),
        '/repos/cloned',
      );
      await tester.tap(find.text('Clone'));
      await tester.pumpAndSettle();
    }

    const String notFound =
        '{"code":1,"codeName":"NotFound",'
        '"message":"repository not found","detail":"",'
        '"argv":[],"exitCode":128}';

    // File → Clone repository… has no list footer to write under: the
    // dialog comes back with what was typed and the error in it (ruling Q8,
    // open-with-apps-spec.html screen 3). Never a toast, never the log --
    // git's message can quote the remote URL (Q4).
    testWidgets(
      'with no onFailed, a failure reopens the dialog with the error',
      (tester) async {
        final _FakeInitCloneBindings bindings = _FakeInitCloneBindings()
          ..cloneResult = -1
          ..errorJson = notFound;
        final GoRouter router = await _pump(
          tester,
          const _CloneRepoButton(),
          bindings,
        );

        await tester.tap(find.text('Open Clone Prompt'));
        await tester.pumpAndSettle();
        await fillAndClone(tester);

        expect(find.text('Clone Repository'), findsOneWidget);
        expect(find.text('git@github.com:example/missing.git'), findsOneWidget);
        expect(find.text('/repos/cloned'), findsOneWidget);
        final Text error = tester.widget<Text>(
          find.text('repository not found'),
        );
        expect(
          error.style!.color,
          tokensFor(GbmThemeVariant.darkTechnical).danger,
        );
        expect(error.style!.fontSize, GbmTypography.textXs);
        expect(find.byType(SnackBar), findsNothing);
        expect(router.routerDelegate.currentConfiguration.uri.toString(), '/');

        // Fixed and retried from the same dialog.
        bindings.cloneResult = 0;
        await tester.tap(find.text('Clone'));
        await tester.pumpAndSettle();
        expect(
          router.routerDelegate.currentConfiguration.uri.toString(),
          RoutePaths.workspaceFor(Uri.encodeComponent('/repos/cloned')),
        );
      },
    );

    testWidgets('with onFailed, the failure goes there and the dialog closes', (
      tester,
    ) async {
      final List<String> failures = <String>[];
      final _FakeInitCloneBindings bindings = _FakeInitCloneBindings()
        ..cloneResult = -1
        ..errorJson = notFound;
      await _pump(tester, _CloneRepoButton(failures: failures), bindings);

      await tester.tap(find.text('Open Clone Prompt'));
      await tester.pumpAndSettle();
      await fillAndClone(tester);

      expect(failures, <String>['repository not found']);
      expect(find.text('Clone Repository'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });
  });
}
