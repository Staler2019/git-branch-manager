// Does the hover background actually *paint*?
//
// The two hover tests catch different failures, and neither subsumes the
// other -- both mutations were run to check:
//
//   * `hoverColor: Colors.transparent` (paints nothing at all) -> only this
//     pixel test fails.
//   * no `hoverColor` at all, falling back to ThemeData's ~4% overlay --
//     which is the bug this round actually fixed -> only
//     branch_tree_item_row_chrome_test.dart's token-identity assertion
//     fails. The pixels *do* change, just imperceptibly, so this test stays
//     green.
//
// So: that test pins the colour, this one pins that a highlight reaches the
// screen at all. Neither on its own would have caught "no visible hover".
//
// `toImage()` never completes inside flutter_test's fake-async zone, so the
// capture runs under tester.runAsync() -- see CLAUDE.md's note on
// Picture.toImage.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_tree_item.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';

const Key _boundary = Key('hover-boundary');

RefInfo _localRef() => RefInfo(
  fullName: 'refs/heads/feature',
  shortName: 'feature',
  kind: RefKind.localBranch,
  target: 'abc123',
  isHead: false,
  isGone: false,
  upstream: '',
  ahead: 0,
  behind: 0,
  hasTrackingInfo: false,
  isSymbolic: false,
  worktreePath: '',
);

Future<Uint8List> _pixels(WidgetTester tester) async {
  final RenderRepaintBoundary boundary = tester
      .renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
  late Uint8List bytes;
  await tester.runAsync(() async {
    final ui.Image image = await boundary.toImage();
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    bytes = data!.buffer.asUint8List();
    image.dispose();
  });
  return bytes;
}

void main() {
  testWidgets('hovering a branch row changes what is painted', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: _boundary,
              child: SizedBox(
                width: 220,
                child: BranchTreeItem(ref: _localRef(), onCheckout: () {}),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final Uint8List before = await _pixels(tester);

    final TestGesture mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
    );
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(BranchTreeItem)));
    await tester.pumpAndSettle();

    final Uint8List after = await _pixels(tester);

    expect(
      after,
      isNot(equals(before)),
      reason:
          'the hover highlight must actually reach the screen -- a row that '
          'only stores the token paints nothing',
    );
  });
}
