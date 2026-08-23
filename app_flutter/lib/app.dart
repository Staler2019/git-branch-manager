import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/update/auto_update_check.dart';
import 'routing/app_router.dart';
import 'routing/route_paths.dart';
import 'theme/gbm_theme.dart';
import 'theme/theme_mode_provider.dart';

class GbmApp extends ConsumerWidget {
  const GbmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'git-branch-manager',
      debugShowCheckedModeBanner: false,
      theme: buildGbmTheme(ref.watch(themeVariantProvider)),
      routerConfig: ref.watch(appRouterProvider),
      // Above the router rather than inside WorkspaceScreen: with no
      // repository open the app renders WelcomeScreen, which has no menu
      // bar, and a check hung off the workspace would never run there.
      builder: (BuildContext context, Widget? child) => AutoUpdateCheck(
        // Pushed through the router instance rather than `context.push`:
        // this builder sits above the Navigator the route resolves against,
        // so its context has no GoRouter of its own to reach.
        onUpdateAvailable: () =>
            ref.read(appRouterProvider).push(RoutePaths.updateDialog),
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
