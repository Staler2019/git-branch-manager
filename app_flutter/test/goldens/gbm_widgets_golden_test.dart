// Golden tests for design-system components across all theme variants.
// Pixel goldens run on macOS only (ci.yml's macos-26 leg); the source scan at
// the end of main() runs everywhere.
import 'dart:io' show Directory, File, FileSystemEntity, Platform;

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
import 'package:gbm_flutter/widgets/lucide_icon.dart';

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

  // GbmIconButton goldens. The icons are LucideIcon SVGs, as in production,
  // not `Icon(Icons.*)`: flutter_test loads no Material Icons font, so a
  // glyph renders as a placeholder box whose anti-aliased edge differed by
  // 2/255 between a local macOS 27 and CI's macos-26 (#151). SVG paths are
  // rasterised like the other components' borders, which matched on both.
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
                  GbmIconButton(
                    icon: const LucideIcon('columns-3'),
                    onPressed: () {},
                  ),
                  GbmIconButton(
                    icon: const LucideIcon('columns-3'),
                    active: true,
                    onPressed: () {},
                  ),
                  GbmIconButton(
                    icon: const LucideIcon('refresh-cw'),
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

  // Not skipped off macOS: it reads source, not pixels. A golden that paints
  // a Material icon compares a placeholder box, not the icon, and that box's
  // anti-aliasing is what broke the GbmIconButton goldens above (#151).
  test('no golden test paints a Material Icons glyph', () {
    final RegExp iconGlyph = RegExp(r'\bIcons\.');
    final List<String> offenders = <String>[];
    for (final FileSystemEntity entity in Directory(
      'test',
    ).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final List<String> lines = entity.readAsLinesSync();
      if (!lines.any((String l) => l.contains('matchesGoldenFile'))) continue;
      for (int i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (iconGlyph.hasMatch(lines[i])) {
          offenders.add('${entity.path}:${i + 1}');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'use LucideIcon (SVG paths, what production paints) in a golden:\n'
          '${offenders.join('\n')}',
    );
  });
}
