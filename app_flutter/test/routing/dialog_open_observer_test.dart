import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/routing/dialog_open_observer.dart';
import 'package:go_router/go_router.dart';
import 'package:gbm_flutter/routing/dialog_route.dart';

void main() {
  testWidgets('showDialog counts as a dialog until it is popped', (
    WidgetTester tester,
  ) async {
    final DialogOpenObserver observer = DialogOpenObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const Text('dialog'),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    expect(observer.dialogOpen, isFalse);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(observer.dialogOpen, isTrue);

    Navigator.of(tester.element(find.text('dialog'))).pop();
    await tester.pumpAndSettle();
    expect(observer.dialogOpen, isFalse);
  });

  testWidgets('a context menu is not a dialog', (WidgetTester tester) async {
    final DialogOpenObserver observer = DialogOpenObserver();
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: <NavigatorObserver>[observer],
        home: Builder(
          builder: (BuildContext context) => TextButton(
            onPressed: () => showMenu<void>(
              context: context,
              position: RelativeRect.fill,
              items: const <PopupMenuEntry<void>>[
                PopupMenuItem<void>(child: Text('item')),
              ],
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('item'), findsOneWidget);
    expect(observer.dialogOpen, isFalse);
  });

  testWidgets('a routed dialogRoute counts, and so does a second one above '
      'it until both are gone', (WidgetTester tester) async {
    final DialogOpenObserver observer = DialogOpenObserver();
    final GoRouter router = GoRouter(
      observers: <NavigatorObserver>[observer],
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        dialogRoute(path: '/a', builder: (_, _) => const Text('a')),
        dialogRoute(path: '/b', builder: (_, _) => const Text('b')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    router.push<void>('/a');
    await tester.pumpAndSettle();
    router.push<void>('/b');
    await tester.pumpAndSettle();
    expect(observer.dialogOpen, isTrue);

    router.pop();
    await tester.pumpAndSettle();
    expect(observer.dialogOpen, isTrue);

    router.pop();
    await tester.pumpAndSettle();
    expect(observer.dialogOpen, isFalse);
  });

  testWidgets('an opaque page is not a dialog', (WidgetTester tester) async {
    final DialogOpenObserver observer = DialogOpenObserver();
    final GoRouter router = GoRouter(
      observers: <NavigatorObserver>[observer],
      routes: <RouteBase>[
        GoRoute(path: '/', builder: (_, _) => const Text('home')),
        GoRoute(path: '/page', builder: (_, _) => const Text('page')),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    router.push<void>('/page');
    await tester.pumpAndSettle();
    expect(find.text('page'), findsOneWidget);
    expect(observer.dialogOpen, isFalse);
  });

  testWidgets('a dialog removed without a pop stops counting', (
    WidgetTester tester,
  ) async {
    final DialogOpenObserver observer = DialogOpenObserver();
    final GlobalKey<NavigatorState> navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        navigatorObservers: <NavigatorObserver>[observer],
        home: const Text('home'),
      ),
    );
    final DialogRoute<void> route = DialogRoute<void>(
      context: navigator.currentContext!,
      builder: (_) => const Text('dialog'),
    );
    unawaited(navigator.currentState!.push<void>(route));
    await tester.pumpAndSettle();
    expect(observer.dialogOpen, isTrue);

    navigator.currentState!.removeRoute(route);
    await tester.pumpAndSettle();
    expect(observer.dialogOpen, isFalse);
  });
}
