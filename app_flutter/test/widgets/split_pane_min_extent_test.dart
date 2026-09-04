// A persisted extent below the spec's `minExtent` must be clamped up on
// restore -- otherwise raising a minimum does nothing for anyone who has
// already dragged the splitter, which is precisely the population the raise
// is for.
//
// The clamp belongs in `initState`, not in `_clampedFixedExtent()`: the
// latter runs every build, so clamping there would force a
// `collapsedByDefault` drawer (extent 0) open to `minExtent` on every frame.
// Case 2 below is the assertion that catches that mistake.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/theme_mode_provider.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/split_pane.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pumps a split pane whose stored extent is seeded *before* the widget
/// mounts, since the restore happens once in `initState`.
Future<void> _pumpWithStored(
  WidgetTester tester, {
  required GbmSplitterSpec spec,
  required String storageId,
  required String storedJson,
  required Axis axis,
  double width = 800,
  double height = 600,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'panelLayout.$storageId': storedJson,
  });
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[sharedPreferencesProvider.overrideWithValue(prefs)],
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
              width: width,
              height: height,
              child: GbmSplitPane(
                axis: axis,
                spec: spec,
                storageId: storageId,
                children: <Widget>[
                  Container(key: const Key('pane-0'), color: Colors.blue),
                  Container(key: const Key('pane-1'), color: Colors.green),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('GbmSplitPane restore honours minExtent', () {
    // A spec whose minimum was raised past a width the user had already
    // dragged to. Declared locally rather than reusing GbmLayout's, so this
    // test does not depend on the token change that motivated it.
    const GbmSplitterSpec raisedMinimum = GbmSplitterSpec.extent(
      defaultExtent: 280,
      minExtent: 220,
    );

    testWidgets('a stored extent below minExtent is clamped up to it', (
      tester,
    ) async {
      await _pumpWithStored(
        tester,
        spec: raisedMinimum,
        storageId: 'test.raised.min',
        storedJson: '[190.0]',
        axis: Axis.horizontal,
      );

      final Size pane0 = tester.getSize(find.byKey(const Key('pane-0')));
      expect(
        pane0.width,
        220,
        reason:
            'a persisted 190 predates the raise to 220; leaving it there '
            'makes the new minimum invisible to exactly the users it is for',
      );
    });

    testWidgets('a collapsedByDefault drawer stored at 0 stays collapsed', (
      tester,
    ) async {
      // splitterMainLog is the real instance of this: defaultExtent 0,
      // minExtent 90, collapsedByDefault. A clamp applied on every build
      // rather than on restore would force this open to 90.
      await _pumpWithStored(
        tester,
        spec: GbmLayout.splitterMainLog,
        storageId: 'test.collapsed.drawer',
        storedJson: '[0.0]',
        axis: Axis.vertical,
      );

      final Size pane0 = tester.getSize(find.byKey(const Key('pane-0')));
      expect(
        pane0.height,
        0,
        reason:
            'an explicit collapse is a user decision, not a value below the '
            'minimum to be repaired',
      );
    });

    testWidgets('a stored extent above minExtent is left alone', (
      tester,
    ) async {
      await _pumpWithStored(
        tester,
        spec: raisedMinimum,
        storageId: 'test.above.min',
        storedJson: '[350.0]',
        axis: Axis.horizontal,
      );

      final Size pane0 = tester.getSize(find.byKey(const Key('pane-0')));
      expect(pane0.width, 350);
    });
  });
}
