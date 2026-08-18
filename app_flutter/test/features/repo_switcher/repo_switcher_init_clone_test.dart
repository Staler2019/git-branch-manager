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
  const _NewRepoButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => promptNewRepository(context, ref),
      child: const Text('New'),
    );
  }
}

class _CloneRepoButton extends ConsumerWidget {
  const _CloneRepoButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => promptCloneRepository(context, ref),
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

    testWidgets('shows the GitError message and stays put when init fails', (
      tester,
    ) async {
      final _FakeInitCloneBindings bindings = _FakeInitCloneBindings()
        ..initResult = -3
        ..errorJson =
            '{"code":2,"codeName":"InvalidArgument",'
            '"message":"A repository path is required","detail":"",'
            '"argv":[],"exitCode":0}';
      final GoRouter router = await _pump(
        tester,
        const _NewRepoButton(),
        bindings,
      );

      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '/repos/blocked');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(find.text('A repository path is required'), findsOneWidget);
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

    testWidgets('shows the GitError message and stays put when clone fails', (
      tester,
    ) async {
      final _FakeInitCloneBindings bindings = _FakeInitCloneBindings()
        ..cloneResult = -1
        ..errorJson =
            '{"code":1,"codeName":"NotFound",'
            '"message":"repository not found","detail":"",'
            '"argv":[],"exitCode":128}';
      final GoRouter router = await _pump(
        tester,
        const _CloneRepoButton(),
        bindings,
      );

      await tester.tap(find.text('Open Clone Prompt'));
      await tester.pumpAndSettle();
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

      expect(find.text('repository not found'), findsOneWidget);
      expect(router.routerDelegate.currentConfiguration.uri.toString(), '/');
    });
  });
}
