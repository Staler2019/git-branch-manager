import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'routing/app_router.dart';
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
    );
  }
}
