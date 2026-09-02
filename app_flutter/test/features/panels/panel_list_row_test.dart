// Spec page 19's list row: the mockup draws icon + (name over branch) +
// right-hand badge.
//
// The asset test at the bottom is the one that matters most, because a
// missing SVG fails *silently*: LucideIcon is a bare
// `SvgPicture.asset('assets/icons/$name.svg')`, so a name with no file
// behind it renders blank while `find.byType(LucideIcon)` stays green.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/features/panels/panel_widgets.dart';
import 'package:gbm_flutter/theme/gbm_theme.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/gbm_badge.dart';
import 'package:gbm_flutter/widgets/lucide_icon.dart';

Future<void> _pumpRow(
  WidgetTester tester, {
  Widget? icon,
  Widget? badge,
  double width = 300,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildGbmTheme(GbmThemeVariant.darkTechnical),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: PanelListRow(
              title: 'gbm-lfs',
              subtitle: 'main · locked',
              selected: false,
              onTap: () {},
              icon: icon,
              badge: badge,
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('PanelListRow icon and badge', () {
    testWidgets('lays out icon, then the text block, then the badge', (
      tester,
    ) async {
      await _pumpRow(
        tester,
        icon: const LucideIcon('folder-git-2'),
        badge: const GbmBadge(label: 'current'),
      );

      final Rect row = tester.getRect(find.byType(PanelListRow));
      final Rect icon = tester.getRect(find.byType(LucideIcon));
      final Rect title = tester.getRect(find.text('gbm-lfs'));
      final Rect badge = tester.getRect(find.byType(GbmBadge));

      expect(icon.right, lessThanOrEqualTo(title.left));
      expect(title.right, lessThanOrEqualTo(badge.left));
      expect(
        row.right - badge.right,
        GbmSpacing.space2,
        reason: 'the badge sits at the row right edge, less the row padding',
      );
    });

    testWidgets('adding an icon and badge does not change the row height', (
      tester,
    ) async {
      await _pumpRow(tester);
      final double bare = tester.getSize(find.byType(PanelListRow)).height;

      await _pumpRow(
        tester,
        icon: const LucideIcon('folder-git-2'),
        badge: const GbmBadge(label: 'current'),
      );
      final double decorated = tester.getSize(find.byType(PanelListRow)).height;

      expect(
        decorated,
        bare,
        reason:
            'the row height is P19 rule 3 and belongs to the two-line text '
            'block, not to whatever decoration sits beside it',
      );
    });

    testWidgets('both are optional and absent by default', (tester) async {
      await _pumpRow(tester);

      expect(find.byType(LucideIcon), findsNothing);
      expect(find.byType(GbmBadge), findsNothing);
      expect(find.text('gbm-lfs'), findsOneWidget);
    });

    testWidgets('a long title does not overflow the row', (tester) async {
      await _pumpRow(
        tester,
        icon: const LucideIcon('folder-git-2'),
        badge: const GbmBadge(label: '路徑不存在'),
        width: 200,
      );

      expect(tester.takeException(), isNull);
    });
  });

  group('the icons P19 names actually ship', () {
    // Read from disk, not through `rootBundle`. That was tried first and
    // **came back green with the file moved away**: `flutter test` builds
    // its asset bundle once and caches it against pubspec.yaml, which does
    // not change when a file inside a declared directory disappears. A
    // fixture that cannot disagree with the code proves nothing
    // ([TEST-fixture-cannot-disagree]).
    //
    // pubspec.yaml declares `assets/icons/` as a whole directory, so
    // present-on-disk is what "ships" means here.
    for (final String name in <String>[
      'folder-git-2', // an ordinary worktree
      'git-commit-horizontal', // a detached HEAD
      'alert-triangle', // a path that no longer exists
    ]) {
      test('$name.svg is in assets/icons/ and is normalised Lucide', () {
        final File file = File('assets/icons/$name.svg');
        expect(
          file.existsSync(),
          isTrue,
          reason:
              'LucideIcon is a bare SvgPicture.asset, so a missing file '
              'renders blank rather than throwing -- nothing else notices',
        );

        final String svg = file.readAsStringSync();
        expect(svg, contains('<svg'));
        expect(
          svg,
          contains('stroke="#000000"'),
          reason:
              'the repo normalises Lucide\'s currentColor so LucideIcon\'s '
              'colorFilter has something to replace',
        );
        expect(
          svg,
          isNot(contains('@license')),
          reason: 'the vendored copies drop the license comment',
        );
      });
    }
  });
}
