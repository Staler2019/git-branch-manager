import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/file_tree.dart';
import 'package:gbm_flutter/theme/tokens.dart';
import 'package:gbm_flutter/widgets/file_tree_folder_row.dart';
import 'package:gbm_flutter/widgets/gbm_row.dart';

import '../support/pump_app.dart';

/// The variant [pumpGbmWidget] defaults to, so the tokens below are the ones
/// actually in effect.
final GbmColors _colors = tokensFor(GbmThemeVariant.darkTechnical);

void main() {
  group('FileTreeFolderRow', () {
    const FileTreeNode node = FileTreeNode(
      name: 'src',
      displayPath: 'src',
      isDirectory: true,
    );

    testWidgets('shows the folder name', (tester) async {
      await pumpGbmWidget(tester, child: const FileTreeFolderRow(node: node));

      expect(find.text('src'), findsOneWidget);
    });

    testWidgets('tapping invokes onToggle', (tester) async {
      int tapCount = 0;
      await pumpGbmWidget(
        tester,
        child: FileTreeFolderRow(node: node, onToggle: () => tapCount++),
      );

      await tester.tap(find.byType(FileTreeFolderRow));
      await tester.pump();

      expect(tapCount, 1);
    });

    testWidgets('renders without error when onToggle is null', (tester) async {
      await pumpGbmWidget(tester, child: const FileTreeFolderRow(node: node));

      expect(find.byType(FileTreeFolderRow), findsOneWidget);
    });

    // A folder row sits in the same list as file rows, which are GbmRows. It
    // hand-rolled its own InkWell, so it inherited ThemeData.hoverColor
    // (~4% black/white -- invisible on a real display) while the file rows
    // above and below it lit up properly. Exactly the defect the sidebar
    // shipped with for months; asserting the token by identity, because a
    // wrong hover colour throws no exception.
    testWidgets('is a GbmRow, so hover comes from the design system', (
      tester,
    ) async {
      await pumpGbmWidget(
        tester,
        child: FileTreeFolderRow(node: node, onToggle: () {}),
      );

      expect(find.byType(GbmRow), findsOneWidget);

      final InkWell ink = tester.widget<InkWell>(
        find
            .descendant(of: find.byType(GbmRow), matching: find.byType(InkWell))
            .first,
      );
      expect(ink.hoverColor, _colors.surfaceHover);
    });
  });
}
