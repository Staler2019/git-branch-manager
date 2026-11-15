// View > Theme cycles through GbmThemeVariant.values in declaration order.
// Driven through the macOS system menu item, which takes its callback
// straight out of WorkspaceScreen's actionHandlers map ([ACT-one-handler-map]),
// so the cycle is the real handler and not a hand-fed one.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/workspace/widgets/platform_menu_bar_host.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';

import '../support/pump_workspace.dart';

PlatformMenuItem? _findMenuItem(List<PlatformMenuItem> menus, String label) {
  for (final PlatformMenuItem item in menus) {
    if (item is PlatformMenu) {
      final PlatformMenuItem? found = _findMenuItem(item.menus, label);
      if (found != null) return found;
    } else if (item.label == label) {
      return item;
    }
  }
  return null;
}

void main() {
  final RepoIdentity identity = RepoIdentity(
    workDir: '/test/repo',
    gitDir: '/test/repo/.git',
  );

  testWidgets('View > Theme goes neutral -> dimGray -> darkTechnical', (
    WidgetTester tester,
  ) async {
    final PumpedWorkspace pumped = await pumpWorkspace(
      tester,
      identity: identity,
      isMacOS: true,
      initialPrefs: <String, Object>{'themeVariant': 'neutralProfessional'},
    );
    expect(
      pumped.container.read(themeVariantProvider),
      GbmThemeVariant.neutralProfessional,
    );

    PlatformMenuItem theme() => _findMenuItem(
      tester
          .widget<PlatformMenuBarHost>(find.byType(PlatformMenuBarHost))
          .platformMenus(),
      'Theme',
    )!;

    theme().onSelected!();
    await tester.pumpAndSettle();
    expect(
      pumped.container.read(themeVariantProvider),
      GbmThemeVariant.dimGray,
    );

    theme().onSelected!();
    await tester.pumpAndSettle();
    expect(
      pumped.container.read(themeVariantProvider),
      GbmThemeVariant.darkTechnical,
    );
  });
}
