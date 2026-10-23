// Covers promptNewRepository()/promptCloneRepository() in
// repo_switcher_popover.dart: File → New repository…/Clone repository… and
// the switcher popover footer's entries all funnel through these two
// functions. Both only open their routed dialog; each dialog's own test
// covers the rest.

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

/// Neither function reaches the bindings any more; this only fails loudly
/// if one starts to.
class _FakeInitCloneBindings implements GbmBindings {
  @override
  Never noSuchMethod(Invocation invocation) {
    throw UnsupportedError('Not implemented for testing');
  }
}

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
        path: RoutePaths.newRepositoryDialog,
        builder: (context, state) => Scaffold(
          body: Text('new dialog from ${state.uri.queryParameters['origin']}'),
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

class _NewRepoButton extends StatelessWidget {
  const _NewRepoButton({this.origin, this.onDismiss});

  final String? origin;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: () => promptNewRepository(
        context,
        originWorkDir: origin,
        onDismiss: onDismiss,
      ),
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
  // N-D5: the dialog runs init itself (its own test covers that), so only
  // which dialog opens, from which window (R13), and the dismiss are here.
  group('promptNewRepository', () {
    testWidgets('opens the New repository dialog naming the window it came '
        'from', (tester) async {
      int dismissed = 0;
      await _pump(
        tester,
        _NewRepoButton(origin: '/repos/here', onDismiss: () => dismissed++),
        _FakeInitCloneBindings(),
      );
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      expect(find.text('new dialog from /repos/here'), findsOneWidget);
      expect(dismissed, 1);
    });

    testWidgets('from a window with no repository, it names none', (
      tester,
    ) async {
      await _pump(tester, const _NewRepoButton(), _FakeInitCloneBindings());
      await tester.tap(find.text('New'));
      await tester.pumpAndSettle();
      expect(find.text('new dialog from null'), findsOneWidget);
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
