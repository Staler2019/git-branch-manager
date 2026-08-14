// Tests for GbmSplitPane: extent mode (fixed pane), flex mode (weighted panes),
// drag/keyboard resizing, double-tap reset, hover color, and persistence.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/split_pane.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<(ProviderContainer, WidgetTester)> _pumpSplitPane(
  WidgetTester tester, {
  required Axis axis,
  required GbmSplitterSpec spec,
  required String storageId,
  ValueChanged<List<double>>? onFlexChanged,
  int? childCount,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
  );
  addTearDown(container.dispose);

  final List<Widget> children = List<Widget>.generate(
    childCount ?? (spec.flexRatio?.length ?? 2),
    (i) => Container(
      key: Key('pane-$i'),
      color: Colors.primaries[i],
      child: Text('Pane $i'),
    ),
  );

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 600,
              height: 400,
              child: GbmSplitPane(
                axis: axis,
                spec: spec,
                storageId: storageId,
                onFlexChanged: onFlexChanged,
                children: children,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  return (container, tester);
}

void main() {
  group('GbmSplitPane', () {
    // Test 1: Renders both children in order for extent mode and flex mode
    testWidgets('renders children in order (extent mode)', (tester) async {
      await _pumpSplitPane(
        tester,
        axis: Axis.horizontal,
        spec: GbmLayout.splitterMainSidebar,
        storageId: 'test.extent',
      );

      expect(find.byKey(const Key('pane-0')), findsOneWidget);
      expect(find.byKey(const Key('pane-1')), findsOneWidget);
      expect(find.text('Pane 0'), findsOneWidget);
      expect(find.text('Pane 1'), findsOneWidget);
    });

    testWidgets('renders children in order (flex mode)', (tester) async {
      await _pumpSplitPane(
        tester,
        axis: Axis.horizontal,
        spec: GbmLayout.splitterWcColumns,
        storageId: 'test.flex',
        childCount: 2,
      );

      expect(find.byKey(const Key('pane-0')), findsOneWidget);
      expect(find.byKey(const Key('pane-1')), findsOneWidget);
      expect(find.text('Pane 0'), findsOneWidget);
      expect(find.text('Pane 1'), findsOneWidget);
    });

    // Test 2: Dragging the single divider right increases pane 0's width
    testWidgets('extent mode: dragging right increases pane 0 extent', (
      tester,
    ) async {
      final List<List<double>> capturedFlexes = <List<double>>[];
      await _pumpSplitPane(
        tester,
        axis: Axis.horizontal,
        spec: GbmLayout.splitterMainSidebar,
        storageId: 'test.drag.extent',
        onFlexChanged: (flex) => capturedFlexes.add(flex.toList()),
      );

      final dividerFinder = find.byKey(const Key('gbm-split-divider-0'));
      expect(dividerFinder, findsOneWidget);

      // Drag right by 50 pixels
      await tester.drag(dividerFinder, const Offset(50, 0));
      await tester.pumpAndSettle();

      // Should have called onFlexChanged
      expect(capturedFlexes.isNotEmpty, true);
      // Final value should be ~= default + drag amount (accounting for slop)
      expect(capturedFlexes.last[0], greaterThan(250.0));
    });

    // Test 3: Dragging past minimum snaps to minExtent
    testWidgets('extent mode: dragging past minimum snaps to minExtent', (
      tester,
    ) async {
      final List<List<double>> capturedFlexes = <List<double>>[];
      await _pumpSplitPane(
        tester,
        axis: Axis.horizontal,
        spec: GbmLayout.splitterMainSidebar,
        storageId: 'test.drag.clamp',
        onFlexChanged: (flex) => capturedFlexes.add(flex.toList()),
      );

      final dividerFinder = find.byKey(const Key('gbm-split-divider-0'));

      // Drag far to the LEFT (past minimum, -150 should clamp to 180)
      await tester.drag(dividerFinder, const Offset(-150, 0));
      await tester.pumpAndSettle();

      // Should snap to minExtent = 180
      expect(capturedFlexes.isNotEmpty, true);
      expect(capturedFlexes.last[0], 180.0);
    });

    // Test 4: Flex mode dragging shifts weight while sum conserves
    testWidgets('flex mode: dragging shifts weight, sum conserves', (
      tester,
    ) async {
      final List<List<double>> capturedFlexes = <List<double>>[];
      await _pumpSplitPane(
        tester,
        axis: Axis.horizontal,
        spec: GbmLayout.splitterWcColumns,
        storageId: 'test.drag.flex',
        childCount: 2,
        onFlexChanged: (flex) => capturedFlexes.add(flex.toList()),
      );

      final dividerFinder = find.byKey(const Key('gbm-split-divider-0'));

      // Drag right by 40 pixels
      await tester.drag(dividerFinder, const Offset(40, 0));
      await tester.pumpAndSettle();

      // Should have changed flex weights
      expect(capturedFlexes.isNotEmpty, true);
      final flex = capturedFlexes.last;
      // Both weights should be positive
      expect(flex[0], greaterThan(0));
      expect(flex[1], greaterThan(0));
      // Sum should be conserved (approximately, 1+1=2)
      expect(flex[0] + flex[1], closeTo(2.0, 0.1));
    });

    // Test 5: Double-tap on divider resets to default
    testWidgets('extent mode: double-tap resets to defaultExtent', (
      tester,
    ) async {
      final List<List<double>> capturedFlexes = <List<double>>[];
      await _pumpSplitPane(
        tester,
        axis: Axis.horizontal,
        spec: GbmLayout.splitterMainSidebar,
        storageId: 'test.double.tap',
        onFlexChanged: (flex) => capturedFlexes.add(flex.toList()),
      );

      final dividerFinder = find.byKey(const Key('gbm-split-divider-0'));

      // First drag to non-default size
      await tester.drag(dividerFinder, const Offset(50, 0));
      await tester.pumpAndSettle();

      capturedFlexes.clear();

      // Double-tap to reset
      await tester.tap(dividerFinder);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(dividerFinder);
      await tester.pumpAndSettle();

      // Should reset to default 250
      expect(capturedFlexes.isNotEmpty, true);
      expect(capturedFlexes.last[0], 250.0);
    });

    // Test 6: Keyboard arrow keys move divider 16px normal, 64px with Shift
    testWidgets('extent mode: arrow key moves 16px, Shift+arrow 64px', (
      tester,
    ) async {
      final List<List<double>> capturedFlexes = <List<double>>[];
      await _pumpSplitPane(
        tester,
        axis: Axis.horizontal,
        spec: GbmLayout.splitterMainSidebar,
        storageId: 'test.keyboard',
        onFlexChanged: (flex) => capturedFlexes.add(flex.toList()),
      );

      final dividerFinder = find.byKey(const Key('gbm-split-divider-0'));
      final Focus focusWidget = tester.widget<Focus>(dividerFinder);
      focusWidget.focusNode?.requestFocus();
      await tester.pump();

      // Send ArrowRight (16px)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(capturedFlexes.isNotEmpty, true);
      expect(capturedFlexes.last[0], 266.0); // 250 + 16

      // Send Shift+ArrowRight (64px)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(capturedFlexes.last[0], 330.0); // 266 + 64
    });

    // Test 7: Restore persisted value on rebuild
    testWidgets('extent mode: restores persisted value on rebuild', (
      tester,
    ) async {
      // Pre-write a custom extent to SharedPreferences
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('panelLayout.test.persist.extent', '[350.0]');

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 600,
                  height: 400,
                  child: GbmSplitPane(
                    axis: Axis.horizontal,
                    spec: GbmLayout.splitterMainSidebar,
                    storageId: 'test.persist.extent',
                    children: <Widget>[
                      Container(
                        key: const Key('pane-0'),
                        color: Colors.red,
                        child: const Text('Pane 0'),
                      ),
                      Container(
                        key: const Key('pane-1'),
                        color: Colors.blue,
                        child: const Text('Pane 1'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Verify pane-0 width is 350 (the persisted value)
      final pane0Size = tester.getSize(find.byKey(const Key('pane-0')));
      expect(pane0Size.width, closeTo(350.0, 1.0));
    });

    // Test 8: Vertical extent mode renders panes in correct order
    testWidgets('vertical extent mode: renders main content above drawer', (
      tester,
    ) async {
      await _pumpSplitPane(
        tester,
        axis: Axis.vertical,
        spec: GbmLayout.splitterMainLog,
        storageId: 'test.vertical.extent',
      );

      // Both panes should be present
      expect(find.byKey(const Key('pane-0')), findsOneWidget);
      expect(find.byKey(const Key('pane-1')), findsOneWidget);

      // Verify pane-1 (main content) is above pane-0 (drawer):
      // pane-1's dy should be less than pane-0's dy
      final Offset pane1Offset = tester.getTopLeft(
        find.byKey(const Key('pane-1')),
      );
      final Offset pane0Offset = tester.getTopLeft(
        find.byKey(const Key('pane-0')),
      );
      expect(pane1Offset.dy, lessThan(pane0Offset.dy));

      // Verify pane-0 height is 0 (defaultExtent for splitterMainLog)
      final Size pane0Size = tester.getSize(find.byKey(const Key('pane-0')));
      expect(pane0Size.height, closeTo(0.0, 1.0));
    });

    // Test 9: collapsedByDefault starts with extent 0
    testWidgets('collapsedByDefault: initial extent is 0', (tester) async {
      // Use a synthetic spec with defaultExtent 200 but collapsedByDefault true
      const GbmSplitterSpec syntheticSpec = GbmSplitterSpec.extent(
        defaultExtent: 200,
        minExtent: 90,
        collapsedByDefault: true,
      );

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 600,
                  height: 400,
                  child: GbmSplitPane(
                    axis: Axis.horizontal,
                    spec: syntheticSpec,
                    storageId: 'test.collapsed.default',
                    children: <Widget>[
                      Container(
                        key: const Key('pane-0'),
                        color: Colors.red,
                        child: const Text('Pane 0'),
                      ),
                      Container(
                        key: const Key('pane-1'),
                        color: Colors.blue,
                        child: const Text('Pane 1'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      // Verify pane-0 width is 0 (collapsed by default, not 200)
      final pane0Size = tester.getSize(find.byKey(const Key('pane-0')));
      expect(pane0Size.width, closeTo(0.0, 1.0));
    });

    // Test 10: Vertical extent mode drag-down shrinks drawer (inverted delta)
    testWidgets('vertical extent mode: drag-down shrinks pane-0', (
      tester,
    ) async {
      final List<List<double>> capturedFlexes = <List<double>>[];
      // Start with a non-zero extent
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('panelLayout.test.vertical.drag', '[100.0]');

      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 600,
                  height: 400,
                  child: GbmSplitPane(
                    axis: Axis.vertical,
                    spec: GbmLayout.splitterMainLog,
                    storageId: 'test.vertical.drag',
                    onFlexChanged: (flex) => capturedFlexes.add(flex.toList()),
                    children: <Widget>[
                      Container(
                        key: const Key('pane-0'),
                        color: Colors.red,
                        child: const Text('Pane 0'),
                      ),
                      Container(
                        key: const Key('pane-1'),
                        color: Colors.blue,
                        child: const Text('Pane 1'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final dividerFinder = find.byKey(const Key('gbm-split-divider-0'));

      // Drag DOWN by 30 pixels (should SHRINK the drawer)
      await tester.drag(dividerFinder, const Offset(0, 30));
      await tester.pumpAndSettle();

      expect(capturedFlexes.isNotEmpty, true);
      // Initial was 100, drag-down should shrink it, so final should be < 100
      expect(capturedFlexes.last[0], lessThan(100.0));
    });

    // Test 11: GbmSplitPaneController.open() expands a collapsed pane
    testWidgets(
      'controller.open() expands a collapsed extent-mode pane to minExtent',
      (tester) async {
        final GbmSplitPaneController controller = GbmSplitPaneController();

        SharedPreferences.setMockInitialValues(<String, Object>{});
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final ProviderContainer container = ProviderContainer(
          overrides: <Override>[
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 600,
                    height: 400,
                    child: GbmSplitPane(
                      axis: Axis.vertical,
                      spec: GbmLayout.splitterMainLog,
                      storageId: 'test.controller.open',
                      controller: controller,
                      children: <Widget>[
                        Container(
                          key: const Key('pane-0'),
                          color: Colors.red,
                          child: const Text('Pane 0'),
                        ),
                        Container(
                          key: const Key('pane-1'),
                          color: Colors.blue,
                          child: const Text('Pane 1'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        // Starts collapsed (splitterMainLog defaults to 0 + collapsedByDefault).
        expect(
          tester.getSize(find.byKey(const Key('pane-0'))).height,
          closeTo(0.0, 1.0),
        );

        controller.open();
        await tester.pump();

        // Opens to at least minExtent (90 for splitterMainLog).
        expect(
          tester.getSize(find.byKey(const Key('pane-0'))).height,
          greaterThanOrEqualTo(GbmLayout.splitterMainLog.minExtent - 1.0),
        );
      },
    );

    testWidgets('controller.open() is a no-op when already open', (
      tester,
    ) async {
      final GbmSplitPaneController controller = GbmSplitPaneController();

      SharedPreferences.setMockInitialValues(<String, Object>{
        'panelLayout.test.controller.noop': '[150.0]',
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 600,
                  height: 400,
                  child: GbmSplitPane(
                    axis: Axis.vertical,
                    spec: GbmLayout.splitterMainLog,
                    storageId: 'test.controller.noop',
                    controller: controller,
                    children: <Widget>[
                      Container(
                        key: const Key('pane-0'),
                        color: Colors.red,
                        child: const Text('Pane 0'),
                      ),
                      Container(
                        key: const Key('pane-1'),
                        color: Colors.blue,
                        child: const Text('Pane 1'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      controller.open();
      await tester.pump();

      // Already above minExtent (150 > 90) -- open() must not shrink it.
      expect(
        tester.getSize(find.byKey(const Key('pane-0'))).height,
        closeTo(150.0, 1.0),
      );
    });

    // Regression test for a real bug caught in review: workspace_screen.dart
    // nests a vertical GbmSplitPane (main.log) whose children[1] toggles
    // between a horizontal GbmSplitPane (main.sidebar) and a bare widget,
    // depending on sidebar visibility. Since GbmSplitPane's extent-mode
    // Column branch already wraps children[1] in Expanded internally,
    // wrapping the "bare widget" branch in a second Expanded throws
    // Flutter's "Incorrect use of ParentDataWidget" error (two
    // ParentDataWidgets of the same type stacked with no intervening Flex).
    // Both branches -- with and without the nested inner GbmSplitPane --
    // must render without throwing.
    testWidgets(
      'a plain child alongside a nested GbmSplitPane renders without a '
      'ParentDataWidget error (regression)',
      (tester) async {
        Future<void> pumpOuter({required bool showInner}) async {
          SharedPreferences.setMockInitialValues(<String, Object>{});
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          final ProviderContainer container = ProviderContainer(
            overrides: <Override>[
              sharedPreferencesProvider.overrideWithValue(prefs),
            ],
          );
          addTearDown(container.dispose);

          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
                home: Scaffold(
                  body: SizedBox(
                    width: 600,
                    height: 400,
                    child: GbmSplitPane(
                      axis: Axis.vertical,
                      spec: GbmLayout.splitterMainLog,
                      storageId: 'test.regression.outer',
                      children: <Widget>[
                        const Text('drawer'),
                        if (showInner)
                          GbmSplitPane(
                            axis: Axis.horizontal,
                            spec: GbmLayout.splitterMainSidebar,
                            storageId: 'test.regression.inner',
                            children: const <Widget>[
                              Text('sidebar'),
                              Text('main content'),
                            ],
                          )
                        else
                          const Text('main content only'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        await pumpOuter(showInner: true);
        expect(tester.takeException(), isNull);
        expect(find.text('sidebar'), findsOneWidget);

        await pumpOuter(showInner: false);
        expect(tester.takeException(), isNull);
        expect(find.text('main content only'), findsOneWidget);
      },
    );
  });
}
