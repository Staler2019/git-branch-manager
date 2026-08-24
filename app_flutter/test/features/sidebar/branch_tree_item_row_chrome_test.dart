// The branch row's *chrome* -- hover and selected backgrounds -- as opposed to
// branch_tree_item_test.dart, which covers what the row does when clicked.
//
// These exist because the row used to hand-roll its own
// `Container` + `InkWell` instead of reaching for `GbmRow`, and a hand-rolled
// InkWell inherits `ThemeData.hoverColor` (~4% black/white) rather than the
// design system's `surfaceHover`. That is invisible on a real display, which
// is how the sidebar shipped with "no hover" while every other list in the app
// had it. Asserting the token by identity, not by eye.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/features/sidebar/widgets/branch_tree_item.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_row.dart';

const GbmThemeVariant _variant = GbmThemeVariant.darkTechnical;
final GbmColors _colors = tokensFor(_variant);

RefInfo _localRef({String shortName = 'feature', bool isHead = false}) =>
    RefInfo(
      fullName: 'refs/heads/$shortName',
      shortName: shortName,
      kind: RefKind.localBranch,
      target: 'abc123',
      isHead: isHead,
      isGone: false,
      upstream: '',
      ahead: 0,
      behind: 0,
      hasTrackingInfo: false,
      isSymbolic: false,
      worktreePath: '',
    );

Future<void> _pumpRow(
  WidgetTester tester, {
  required RefInfo ref,
  bool selected = false,
}) => tester.pumpWidget(
  MaterialApp(
    theme: buildGbmTheme(_variant),
    home: Scaffold(
      body: BranchTreeItem(ref: ref, onCheckout: () {}, selected: selected),
    ),
  ),
);

/// GbmRow's own background Container -- its first Container descendant, the
/// same handle `gbm_components_test.dart` uses.
BoxDecoration _rowDecoration(WidgetTester tester) {
  final Container container = tester.widget<Container>(
    find
        .descendant(of: find.byType(GbmRow), matching: find.byType(Container))
        .first,
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  testWidgets('the branch row is a GbmRow, not a hand-rolled Container', (
    tester,
  ) async {
    await _pumpRow(tester, ref: _localRef());
    expect(find.byType(GbmRow), findsOneWidget);
  });

  testWidgets('hover is wired to the surfaceHover token', (tester) async {
    await _pumpRow(tester, ref: _localRef());

    // `.first`: the trailing actions button has an InkWell too, and it sits
    // below GbmRow's own in tree order.
    final InkWell ink = tester.widget<InkWell>(
      find
          .descendant(of: find.byType(GbmRow), matching: find.byType(InkWell))
          .first,
    );

    // The whole point of the round: a null hoverColor means Material's
    // near-invisible default, which is what "hover color no show" was.
    expect(ink.hoverColor, _colors.surfaceHover);
  });

  testWidgets('a selected row paints surfaceSelected', (tester) async {
    await _pumpRow(tester, ref: _localRef(), selected: true);
    expect(_rowDecoration(tester).color, _colors.surfaceSelected);
  });

  testWidgets('an unselected, non-HEAD row paints no background', (
    tester,
  ) async {
    await _pumpRow(tester, ref: _localRef(), selected: false);
    expect(_rowDecoration(tester).color, isNull);
  });

  testWidgets('the current branch paints surfaceSelected', (tester) async {
    // BRANCH_STATES' 目前分支 row: 「名稱加粗、整列以 selected 底色標示」.
    await _pumpRow(tester, ref: _localRef(isHead: true), selected: false);
    expect(_rowDecoration(tester).color, _colors.surfaceSelected);
  });
}
