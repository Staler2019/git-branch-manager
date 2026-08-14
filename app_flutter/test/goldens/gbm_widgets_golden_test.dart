// Golden tests for design-system components across all theme variants.
// Only runs on macOS (flutter test CI runs on Ubuntu and skips these).
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/ref_snapshot.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_badge.dart';
import 'package:gbm_flutter/widgets/gbm_banner.dart';
import 'package:gbm_flutter/widgets/gbm_button.dart';
import 'package:gbm_flutter/widgets/gbm_icon_button.dart';
import 'package:gbm_flutter/widgets/gbm_panel.dart';
import 'package:gbm_flutter/widgets/gbm_row.dart';
import 'package:gbm_flutter/widgets/gbm_tag_chip.dart';

void main() {
  // GbmBadge goldens across all kinds and variants
  for (final variant in GbmThemeVariant.values) {
    testWidgets('GbmBadge golden ($variant)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(variant),
          home: Scaffold(
            body: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: const [
                  GbmBadge(label: '+12', kind: GbmBadgeKind.added),
                  GbmBadge(label: '-3', kind: GbmBadgeKind.removed),
                  GbmBadge(label: '5', kind: GbmBadgeKind.neutral),
                ],
              ),
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(Row),
        matchesGoldenFile('goldens/gbm_badge_$variant.png'),
      );
    }, skip: !Platform.isMacOS);
  }

  // GbmButton goldens across all kinds and sizes
  for (final variant in GbmThemeVariant.values) {
    testWidgets('GbmButton golden ($variant)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(variant),
          home: Scaffold(
            body: Center(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  GbmButton(
                    label: 'Primary',
                    kind: GbmButtonKind.primary,
                    onPressed: () {},
                  ),
                  GbmButton(
                    label: 'Secondary',
                    kind: GbmButtonKind.secondary,
                    onPressed: () {},
                  ),
                  GbmButton(
                    label: 'Ghost',
                    kind: GbmButtonKind.ghost,
                    onPressed: () {},
                  ),
                  GbmButton(
                    label: 'Danger',
                    kind: GbmButtonKind.danger,
                    onPressed: () {},
                  ),
                  GbmButton(
                    label: 'Sm',
                    size: GbmButtonSize.sm,
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(Wrap),
        matchesGoldenFile('goldens/gbm_button_$variant.png'),
      );
    }, skip: !Platform.isMacOS);
  }

  // GbmIconButton goldens
  for (final variant in GbmThemeVariant.values) {
    testWidgets('GbmIconButton golden ($variant)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(variant),
          home: Scaffold(
            body: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  GbmIconButton(icon: const Icon(Icons.add), onPressed: () {}),
                  GbmIconButton(
                    icon: const Icon(Icons.add),
                    active: true,
                    onPressed: () {},
                  ),
                  GbmIconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(Row),
        matchesGoldenFile('goldens/gbm_icon_button_$variant.png'),
      );
    }, skip: !Platform.isMacOS);
  }

  // GbmBanner (GbmWarningBanner) golden
  for (final variant in GbmThemeVariant.values) {
    testWidgets('GbmWarningBanner golden ($variant)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(variant),
          home: const Scaffold(
            body: GbmWarningBanner(message: 'Something went wrong'),
          ),
        ),
      );

      await expectLater(
        find.byType(GbmWarningBanner),
        matchesGoldenFile('goldens/gbm_warning_banner_$variant.png'),
      );
    }, skip: !Platform.isMacOS);
  }

  // GbmPanel golden
  for (final variant in GbmThemeVariant.values) {
    testWidgets('GbmPanel golden ($variant)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(variant),
          home: const Scaffold(
            body: Center(
              child: GbmPanel(
                child: SizedBox(
                  width: 200,
                  height: 100,
                  child: Center(child: Text('Panel')),
                ),
              ),
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(GbmPanel),
        matchesGoldenFile('goldens/gbm_panel_$variant.png'),
      );
    }, skip: !Platform.isMacOS);
  }

  // GbmRow goldens
  for (final variant in GbmThemeVariant.values) {
    testWidgets('GbmRow golden ($variant)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(variant),
          home: const Scaffold(
            body: Column(
              children: [
                GbmRow(child: Text('Unselected row')),
                GbmRow(selected: true, child: Text('Selected row')),
              ],
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(Column),
        matchesGoldenFile('goldens/gbm_row_$variant.png'),
      );
    }, skip: !Platform.isMacOS);
  }

  // GbmTagChip goldens
  for (final variant in GbmThemeVariant.values) {
    testWidgets('GbmTagChip golden ($variant)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildGbmTheme(variant),
          home: Scaffold(
            body: Center(
              child: Wrap(
                spacing: 12,
                children: [
                  GbmTagChip(label: 'feature', kind: RefKind.localBranch),
                  GbmTagChip(label: 'v1.0', kind: RefKind.tag),
                  GbmTagChip(
                    label: 'main',
                    kind: RefKind.localBranch,
                    isCurrent: true,
                  ),
                  GbmTagChip(label: 'upstream', kind: RefKind.remoteBranch),
                  GbmTagChip(label: 'stale', kind: RefKind.localBranch),
                ],
              ),
            ),
          ),
        ),
      );

      await expectLater(
        find.byType(Wrap),
        matchesGoldenFile('goldens/gbm_tag_chip_$variant.png'),
      );
    }, skip: !Platform.isMacOS);
  }
}
