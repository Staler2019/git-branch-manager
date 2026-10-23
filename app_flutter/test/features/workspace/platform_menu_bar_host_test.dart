import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/actions/gbm_action_id.dart';
import 'package:gbm_flutter/actions/gbm_menu_model.dart';
import 'package:gbm_flutter/features/workspace/widgets/platform_menu_bar_host.dart';

/// Runs [body] with the framework reporting macOS as the running platform.
///
/// `PlatformProvidedMenuItem.hasMenu` consults `defaultTargetPlatform`, not
/// `isMacOSOverride`, so the system-provided Quit item only appears under
/// this. The override is reset inside the body rather than in a
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

/// What the host sends the embedder.
List<PlatformMenuItem> _menus(WidgetTester tester) => tester
    .widget<PlatformMenuBarHost>(find.byType(PlatformMenuBarHost))
    .platformMenus();

/// Every ordinary item the built menu tree declares, flattened.
List<PlatformMenuItem> _items(WidgetTester tester) => <PlatformMenuItem>[
  for (final PlatformMenuItem menu in _menus(tester))
    if (menu is PlatformMenu)
      for (final PlatformMenuItem item in menu.menus) item,
];

PlatformMenuItem? _itemLabelled(WidgetTester tester, String label) {
  for (final PlatformMenuItem item in _items(tester)) {
    if (item.label == label) return item;
  }
  return null;
}

/// Records what reaches the embedder. Its lock always grants, so what is
/// under test is the order of `setMenus`/`clearMenus` -- the half a release
/// build keeps once the debug lock's asserts are compiled out.
class _RecordingDelegate extends PlatformMenuDelegate {
  final List<List<String>?> calls = <List<String>?>[];

  @override
  void setMenus(List<PlatformMenuItem> topLevelMenus) => calls.add(<String>[
    for (final PlatformMenuItem m in topLevelMenus) m.label,
  ]);

  @override
  void clearMenus() => calls.add(null);

  @override
  bool debugLockDelegate(BuildContext context) => true;

  @override
  bool debugUnlockDelegate(BuildContext context) => true;
}

/// One host per screen; [titles] tells them apart in what was sent.
Widget _host(String title) => PlatformMenuBarHost(
  menus: <GbmMenuModel>[
    GbmMenuModel(title: title, items: const <GbmMenuItemModel>[]),
  ],
  handlers: const <GbmActionId, VoidCallback?>{},
  isMacOSOverride: true,
  child: Text(title),
);

void main() {
  // Welcome → workspace: the router mounts the new screen before the old one
  // is disposed. The old screen's teardown must not wipe the menus the new
  // one just sent, and two hosts alive at once must not trip the framework.
  testWidgets('a host disposed after a newer one mounted leaves the newer '
      'one\'s menus in place', (tester) async {
    final PlatformMenuDelegate original = tester.binding.platformMenuDelegate;
    final _RecordingDelegate delegate = _RecordingDelegate();
    tester.binding.platformMenuDelegate = delegate;
    addTearDown(() => tester.binding.platformMenuDelegate = original);

    Widget screens(List<String> titles) => MaterialApp(
      home: Column(
        children: <Widget>[
          for (final String t in titles)
            KeyedSubtree(key: ValueKey(t), child: _host(t)),
        ],
      ),
    );
    await tester.pumpWidget(screens(<String>['Welcome']));
    await tester.pumpWidget(screens(<String>['Welcome', 'Workspace']));
    await tester.pumpWidget(screens(<String>['Workspace']));

    expect(tester.takeException(), isNull);
    expect(delegate.calls.last, <String>['Workspace']);
  });

  testWidgets('when the owner goes first, the next newest host re-sends its '
      'own menus', (tester) async {
    final PlatformMenuDelegate original = tester.binding.platformMenuDelegate;
    final _RecordingDelegate delegate = _RecordingDelegate();
    tester.binding.platformMenuDelegate = delegate;
    addTearDown(() => tester.binding.platformMenuDelegate = original);

    Widget screens(List<String> titles) => MaterialApp(
      home: Column(
        children: <Widget>[
          for (final String t in titles)
            KeyedSubtree(key: ValueKey(t), child: _host(t)),
        ],
      ),
    );
    await tester.pumpWidget(screens(<String>['Welcome', 'Workspace']));
    await tester.pumpWidget(screens(<String>['Welcome']));

    expect(delegate.calls.last, <String>['Welcome']);
  });

  testWidgets('a host that is not the owner rebuilding sends nothing', (
    tester,
  ) async {
    final PlatformMenuDelegate original = tester.binding.platformMenuDelegate;
    final _RecordingDelegate delegate = _RecordingDelegate();
    tester.binding.platformMenuDelegate = delegate;
    addTearDown(() => tester.binding.platformMenuDelegate = original);

    // The same instance: Flutter does not update an identical widget, so
    // only the older host rebuilds on the second pump.
    final Widget newer = KeyedSubtree(
      key: const ValueKey('Workspace'),
      child: _host('Workspace'),
    );
    Widget screens() => MaterialApp(
      home: Column(
        children: <Widget>[
          KeyedSubtree(key: const ValueKey('Welcome'), child: _host('Welcome')),
          newer,
        ],
      ),
    );
    await tester.pumpWidget(screens());
    await tester.pumpWidget(screens());

    expect(delegate.calls.last, <String>['Workspace']);
  });

  testWidgets('the last host to go clears the menus', (tester) async {
    final PlatformMenuDelegate original = tester.binding.platformMenuDelegate;
    final _RecordingDelegate delegate = _RecordingDelegate();
    tester.binding.platformMenuDelegate = delegate;
    addTearDown(() => tester.binding.platformMenuDelegate = original);

    await tester.pumpWidget(MaterialApp(home: _host('Welcome')));
    await tester.pumpWidget(const MaterialApp(home: Text('none')));

    expect(delegate.calls, contains(equals(<String>['Welcome'])));
    expect(delegate.calls.last, isNull);
  });

  testWidgets('off macOS it is a passthrough that sends no menus', (
    tester,
  ) async {
    final PlatformMenuDelegate original = tester.binding.platformMenuDelegate;
    final _RecordingDelegate delegate = _RecordingDelegate();
    tester.binding.platformMenuDelegate = delegate;
    addTearDown(() => tester.binding.platformMenuDelegate = original);
    await _onMacOS(() async {
      await _pump(tester, isMacOS: false);
      await tester.pumpWidget(const SizedBox());

      expect(delegate.calls, isEmpty);
    });
  });

  testWidgets('on macOS it sends the menus and still renders the child', (
    tester,
  ) async {
    final PlatformMenuDelegate original = tester.binding.platformMenuDelegate;
    final _RecordingDelegate delegate = _RecordingDelegate();
    tester.binding.platformMenuDelegate = delegate;
    addTearDown(() => tester.binding.platformMenuDelegate = original);
    await _onMacOS(() async {
      await _pump(tester, isMacOS: true);

      expect(delegate.calls.last, <String>[
        for (final GbmMenuModel m in gbmMenus) m.title,
      ]);
      expect(find.text('workspace'), findsOneWidget);
    });
  });

  testWidgets('builds one PlatformMenu per menu, in spec order', (
    tester,
  ) async {
    await _onMacOS(() async {
      await _pump(tester, isMacOS: true);

      expect(
        _menus(tester).map((PlatformMenuItem m) => m.label).toList(),
        gbmMenus.map((GbmMenuModel m) => m.title).toList(),
      );
    });
  });

  testWidgets('Exit is the only system-provided item; About is an ordinary '
      'one', (tester) async {
    await _onMacOS(() async {
      await _pump(tester, isMacOS: true);
      final List<String> labels = <String>[
        for (final PlatformMenuItem i in _items(tester)) i.label,
      ];

      // The ordinary items are still there...
      expect(labels, contains('Open repository…'));
      expect(labels, contains('Keyboard shortcuts'));

      // ...macOS still owns Quit, which lives in the application menu, so it
      // must not be duplicated as a hand-rolled entry.
      expect(labels, isNot(contains('Exit')));

      // ...but About is *not* system-provided. A
      // PlatformProvidedMenuItem(about) opens the native About panel, which
      // is a different window from the `AboutDialogContent` Windows and
      // Linux get for the same action id -- and spec page 01 puts every
      // window's *contents* under Flutter on all three platforms. Only the
      // menu bar's position follows the OS.
      expect(labels, contains('About'));

      expect(
        <PlatformProvidedMenuItemType>{
          for (final PlatformMenuItem i in _items(tester))
            if (i is PlatformProvidedMenuItem) i.type,
        },
        <PlatformProvidedMenuItemType>{PlatformProvidedMenuItemType.quit},
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
