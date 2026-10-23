// Covers promptNewRepository()/promptCloneRepository() in
// repo_switcher_popover.dart: File → New repository…/Clone repository… and
// the switcher popover footer's entries all funnel through these two
// functions. New reaches gbm_repo_init() directly via gbmBindingsProvider
// (there is no session yet for a RepoSessionController to dispatch
// through), so this drives a configurable fake GbmBindings. Clone only
// opens the routed Clone dialog; the dialog's own test covers the rest.
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
import 'package:gbm_flutter/data/models/operation_record.dart';
import 'package:go_router/go_router.dart';

class _FakeInitCloneBindings implements GbmBindings {
  int initResult = 0;
  String errorJson = '';
  String? lastInitPath;

  @override
  RepoInitDart get repoInit =>
      (Pointer<Utf8> path, Pointer<Utf8> initialBranch) {
        lastInitPath = path.toDartString();
        return initResult;
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
        path: RoutePaths.cloneRepositoryDialog,
        builder: (context, state) => Scaffold(
          body: Text(
            'clone dialog from ${state.uri.queryParameters['origin']}',
          ),
        ),
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
  const _NewRepoButton({this.lines});

  /// Every line [promptNewRepository]'s action logs.
  final List<AppLogEntry>? lines;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => promptNewRepository(context, ref, sink: lines?.add),
      child: const Text('New'),
    );
  }
}

class _CloneRepoButton extends StatelessWidget {
  const _CloneRepoButton({this.origin, this.onDismiss});

  final String? origin;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => promptCloneRepository(
        context,
        originWorkDir: origin,
        onDismiss: onDismiss,
      ),
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
      final List<AppLogEntry> lines = <AppLogEntry>[];
      final GoRouter router = await _pump(
        tester,
        _NewRepoButton(lines: lines),
        bindings,
      );

      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '/repos/new-project');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(bindings.lastInitPath, '/repos/new-project');
      // Ruling R4: a success is logged too.
      expect(lines.map((AppLogEntry e) => e.message), <String>[
        'Created a repository at /repos/new-project',
      ]);
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
      final List<AppLogEntry> lines = <AppLogEntry>[];
      final _FakeInitCloneBindings bindings = _FakeInitCloneBindings()
        ..initResult = -3
        ..errorJson =
            '{"code":2,"codeName":"InvalidArgument",'
            '"message":"A repository path is required","detail":"",'
            '"argv":[],"exitCode":0}';
      final GoRouter router = await _pump(
        tester,
        _NewRepoButton(lines: lines),
        bindings,
      );

      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '/repos/blocked');
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      expect(
        lines.map((AppLogEntry e) => (e.level, e.message)),
        <(OperationLogLevel, String)>[
          (
            OperationLogLevel.error,
            'Could not create a repository at /repos/blocked: '
                'A repository path is required',
          ),
        ],
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(router.routerDelegate.currentConfiguration.uri.toString(), '/');
    });
  });

  // DLGS: the dialog closes on Clone and the job runs in the background, so
  // there is nothing left here to drive -- only which dialog opens, from
  // which window (R13), and that the caller's popover is dismissed first.
  group('promptCloneRepository', () {
    testWidgets('opens the Clone dialog naming the window it came from', (
      tester,
    ) async {
      int dismissed = 0;
      await _pump(
        tester,
        _CloneRepoButton(origin: '/repos/here', onDismiss: () => dismissed++),
        _FakeInitCloneBindings(),
      );
      await tester.tap(find.text('Open Clone Prompt'));
      await tester.pumpAndSettle();
      expect(find.text('clone dialog from /repos/here'), findsOneWidget);
      expect(dismissed, 1);
    });

    testWidgets('from a window with no repository, it names none', (
      tester,
    ) async {
      await _pump(tester, const _CloneRepoButton(), _FakeInitCloneBindings());
      await tester.tap(find.text('Open Clone Prompt'));
      await tester.pumpAndSettle();
      expect(find.text('clone dialog from null'), findsOneWidget);
    });
  });
}
