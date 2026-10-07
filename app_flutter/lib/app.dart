import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/repositories/git_timeout_multiplier_sync.dart';
import 'features/app_lifecycle/app_exit_session_cleanup.dart';
import 'features/update/auto_update_check.dart';
import 'features/update/update_leftover_sweep.dart';
import 'routing/app_router.dart';
import 'routing/route_paths.dart';
import 'theme/gbm_theme.dart';
import 'theme/theme_mode_provider.dart';
import 'routing/dialog_route.dart';

class GbmApp extends ConsumerWidget {
  const GbmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Above the router for the same reason as AutoUpdateCheck below: git
    // runs from the welcome screen too (clone), with no session to push the
    // user's timeout multiplier.
    ref.watch(gitTimeoutMultiplierSyncProvider);
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
        onUpdateAvailable: () => pushDialogRouteOn(
          ref.read(appRouterProvider),
          RoutePaths.updateDialog,
        ),
        // Nested rather than a second builder: the sweep is unconditional
        // where the check is not, so they are two jobs, not one.
        // AppExitSessionCleanup is innermost only because nesting order
        // does not matter here -- neither wraps the other's work, they
        // just both need to sit above the router for the same reason
        // AutoUpdateCheck does (see above).
        child: UpdateLeftoverSweep(
          child: AppExitSessionCleanup(child: child ?? const SizedBox.shrink()),
        ),
      ),
    );
  }
}
