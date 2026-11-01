// 使用者裁定：「新增檔案為:+，刪除檔案為：-。其他檔案都是照目前這樣，沒有trailing
// icon，除非有移動屬性，就需要有move icon」，以及「+ and - use icon, not font」。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/working_copy_status.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/file_change_glyph.dart';
import 'package:gbm_flutter/widgets/lucide_icon.dart';

import '../support/pump_app.dart';

/// The variant [pumpGbmWidget] defaults to, so the tokens below are the ones
/// actually in effect.
final GbmColors _colors = tokensFor(GbmThemeVariant.darkTechnical);

Future<void> _pump(
  WidgetTester tester,
  FileChangeKind kind, {
  bool untracked = false,
}) => pumpGbmWidget(
  tester,
  child: Align(
    alignment: Alignment.topLeft,
    child: FileChangeGlyph(kind: kind, untracked: untracked),
  ),
);

LucideIcon _icon(WidgetTester tester) =>
    tester.widget<LucideIcon>(find.byType(LucideIcon));

void main() {
  group('FileChangeGlyph', () {
    testWidgets('an added file draws a green plus', (tester) async {
      await _pump(tester, FileChangeKind.added);

      expect(_icon(tester).name, 'plus');
      expect(_icon(tester).color, same(_colors.diffAddText));
    });

    testWidgets('an untracked file draws the same plus as an added one', (
      tester,
    ) async {
      // An untracked entry's worktreeStatus is not `added`; the flag is what
      // says the file is new.
      await _pump(tester, FileChangeKind.modified, untracked: true);

      expect(_icon(tester).name, 'plus');
      expect(_icon(tester).color, same(_colors.diffAddText));
    });

    testWidgets('a deleted file draws a red minus', (tester) async {
      await _pump(tester, FileChangeKind.deleted);

      expect(_icon(tester).name, 'minus');
      expect(_icon(tester).color, same(_colors.diffDelText));
    });

    testWidgets('a renamed file draws the move icon in the secondary text '
        'colour', (tester) async {
      await _pump(tester, FileChangeKind.renamed);

      expect(_icon(tester).name, 'move-right');
      expect(_icon(tester).color, same(_colors.textSecondary));
    });

    for (final FileChangeKind kind in <FileChangeKind>[
      FileChangeKind.modified,
      FileChangeKind.copied,
      FileChangeKind.typeChanged,
      FileChangeKind.modeChanged,
    ]) {
      testWidgets('a ${kind.name} file draws nothing and takes no space', (
        tester,
      ) async {
        await _pump(tester, kind);

        expect(find.byType(LucideIcon), findsNothing);
        expect(tester.getSize(find.byType(FileChangeGlyph)), Size.zero);
      });
    }

    testWidgets('every glyph is 14 across in a 14-wide box, then a 4 gap', (
      tester,
    ) async {
      for (final FileChangeKind kind in <FileChangeKind>[
        FileChangeKind.added,
        FileChangeKind.deleted,
        FileChangeKind.renamed,
      ]) {
        await _pump(tester, kind);

        expect(_icon(tester).size, 14, reason: kind.name);
        expect(
          tester.getSize(find.byType(FileChangeGlyph)).width,
          14 + GbmSpacing.space1,
          reason: kind.name,
        );
      }
    });
  });
}
