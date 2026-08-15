import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/actions/gbm_menu_model.dart';
import 'package:gbm_flutter/features/workspace/widgets/platform_menu_bar_host.dart';

/// Runs [body] with the framework reporting macOS as the running platform.
///
/// `PlatformProvidedMenuItem.hasMenu` consults `defaultTargetPlatform`, not
/// `isMacOSOverride`, so the system-provided Quit/About items only appear
/// under this. The override is reset inside the body rather than in a
/// `tearDown`, because the test binding asserts all foundation debug
/// variables are unset at the end of the body, before tearDowns run.
Future<void> _onMacOS(Future<void> Function() body) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  try {
    await body();
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required bool isMacOS,
  Map<GbmActionId, VoidCallback?> handlers =
      const <GbmActionId, VoidCallback?>{},
}) {
  return tester.pumpWidget(
    MaterialApp(
      home: PlatformMenuBarHost(
        menus: gbmMenus,
        handlers: handlers,
        isMacOSOverride: isMacOS,
        child: const Scaffold(body: Text('workspace')),
      ),
    ),
  );
}

PlatformMenuBar _bar(WidgetTester tester) =>
    tester.widget<PlatformMenuBar>(find.byType(PlatformMenuBar));

/// Every ordinary item the built menu tree declares, flattened.
List<PlatformMenuItem> _items(WidgetTester tester) => <PlatformMenuItem>[
  for (final PlatformMenuItem menu in _bar(tester).menus)
    if (menu is PlatformMenu)
      for (final PlatformMenuItem item in menu.menus) item,
];

PlatformMenuItem? _itemLabelled(WidgetTester tester, String label) {
  for (final PlatformMenuItem item in _items(tester)) {
    if (item.label == label) return item;
  }
  return null;
}

void main() {
  testWidgets('off macOS it is a passthrough, adding no menu bar', (
    tester,
  ) async {
    await _onMacOS(() async {
      await _pump(tester, isMacOS: false);

      expect(find.byType(PlatformMenuBar), findsNothing);
      expect(
        find.text('workspace'),
        findsOneWidget,
        reason: 'the child must still render',
      );
    });
  });

  testWidgets('on macOS it wraps the child in a PlatformMenuBar', (
    tester,
  ) async {
    await _onMacOS(() async {
      await _pump(tester, isMacOS: true);

      expect(find.byType(PlatformMenuBar), findsOneWidget);
      expect(find.text('workspace'), findsOneWidget);
    });
  });

  testWidgets('builds one PlatformMenu per menu, in spec order', (
    tester,
  ) async {
    await _onMacOS(() async {
      await _pump(tester, isMacOS: true);

      expect(
        _bar(tester).menus.map((PlatformMenuItem m) => m.label).toList(),
        gbmMenus.map((GbmMenuModel m) => m.title).toList(),
      );
    });
  });

  testWidgets('Exit and About become system-provided items, not plain ones', (
    tester,
  ) async {
    await _onMacOS(() async {
      await _pump(tester, isMacOS: true);
      final List<String> labels = <String>[
        for (final PlatformMenuItem i in _items(tester)) i.label,
      ];

      // The ordinary items are still there...
      expect(labels, contains('Open repository…'));
      expect(labels, contains('Keyboard shortcuts'));

      // ...but macOS owns Quit and About, so they must not be duplicated as
      // hand-rolled entries.
      expect(labels, isNot(contains('Exit')));
      expect(labels, isNot(contains('About')));

      expect(
        <PlatformProvidedMenuItemType>{
          for (final PlatformMenuItem i in _items(tester))
            if (i is PlatformProvidedMenuItem) i.type,
        },
        <PlatformProvidedMenuItemType>{
          PlatformProvidedMenuItemType.quit,
          PlatformProvidedMenuItemType.about,
        },
      );
    });
  });

  testWidgets('a handler is attached to the matching item', (tester) async {
    await _onMacOS(() async {
      int pushed = 0;
      await _pump(
        tester,
        isMacOS: true,
        handlers: <GbmActionId, VoidCallback?>{
          GbmActionId.repositoryPush: () => pushed++,
        },
      );

      final PlatformMenuItem? push = _itemLabelled(tester, 'Push');
      expect(push, isNotNull);
      expect(push!.onSelected, isNotNull);
      push.onSelected!();
      expect(pushed, 1);
    });
  });

  testWidgets('an unmapped action produces an inert item', (tester) async {
    await _onMacOS(() async {
      await _pump(tester, isMacOS: true);

      final PlatformMenuItem? push = _itemLabelled(tester, 'Push');
      expect(push, isNotNull);
      expect(
        push!.onSelected,
        isNull,
        reason: 'no handler passed means macOS renders the item disabled',
      );
    });
  });

  testWidgets('bound actions carry their macOS key equivalent', (tester) async {
    await _onMacOS(() async {
      await _pump(tester, isMacOS: true);

      final SingleActivator activator =
          _itemLabelled(tester, 'Push')!.shortcut! as SingleActivator;
      expect(activator.meta, isTrue, reason: 'Cmd, not Ctrl, on macOS');
      expect(activator.control, isFalse);
    });
  });
}
