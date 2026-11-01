// View → Full file reaches the same preference from both menu paths --
// the in-window MenuBarRow and the macOS system menu, which both read
// `_buildActionHandlers()`'s map ([ACT-one-handler-map]). It has no
// shortcut (G1 ruling: the spec binds none), so there is no keyboard path.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/repositories/app_preferences_repository.dart';
import 'package:gbm_flutter/data/repositories/repo_identity.dart';
import 'package:gbm_flutter/features/workspace/widgets/platform_menu_bar_host.dart';

import '../support/pump_workspace.dart';

final RepoIdentity _identity = RepoIdentity(
  workDir: '/test/repo',
  gitDir: '/test/repo/.git',
);

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

bool _fullFile(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Scaffold).first))
        .read(appPreferencesProvider)
        .fullFileViewEnabled;

void main() {
  testWidgets('the in-window View > Full file toggles the preference', (
    WidgetTester tester,
  ) async {
    await pumpWorkspace(tester, identity: _identity);
    expect(_fullFile(tester), isFalse);

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full file'));
    await tester.pumpAndSettle();
    expect(_fullFile(tester), isTrue);

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full file'));
    await tester.pumpAndSettle();
    expect(_fullFile(tester), isFalse);
  });

  testWidgets('the macOS system menu item toggles it through the same map', (
    WidgetTester tester,
  ) async {
    await pumpWorkspace(tester, identity: _identity, isMacOS: true);
    final PlatformMenuItem? item = _findMenuItem(
      tester
          .widget<PlatformMenuBarHost>(find.byType(PlatformMenuBarHost))
          .platformMenus(),
      'Full file',
    );
    expect(item, isNotNull);
    expect(item!.onSelected, isNotNull, reason: 'null greys it out natively');

    item.onSelected!();
    await tester.pumpAndSettle();
    expect(_fullFile(tester), isTrue);
  });
}
