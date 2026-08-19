import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/file_tree.dart';
import 'package:gbm_flutter/widgets/file_tree_folder_row.dart';

import '../support/pump_app.dart';

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
  });
}
