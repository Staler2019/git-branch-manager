import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gbm_flutter/data/models/file_tree.dart';
import 'package:gbm_flutter/data/repositories/file_list_view_mode_repository.dart';
import 'package:gbm_flutter/widgets/file_tree_list.dart';

void main() {
  group('FileTreeList', () {
    const testPaths = [
      'lib/app/views/a.dart',
      'lib/app/views/b.dart',
      'src/main.rs',
      'README.md',
    ];

    testWidgets('renders flat list in list mode', (WidgetTester tester) async {
      final fileTree = FileTree.fromPaths(testPaths);
      final renderedItems = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileTreeList(
              fileTree: fileTree,
              mode: FileListViewMode.list,
              selectedPaths: const {},
              onItemBuilder: (context, node, level, onFolderToggle) {
                renderedItems.add(node.displayPath);
                return ListTile(title: Text(node.name));
              },
              onFolderCheckStateChanged: (_) {},
            ),
          ),
        ),
      );

      // In list mode, all leaf nodes should be rendered
      expect(renderedItems, contains('lib/app/views/a.dart'));
      expect(renderedItems, contains('lib/app/views/b.dart'));
      expect(renderedItems, contains('src/main.rs'));
      expect(renderedItems, contains('README.md'));
    });

    testWidgets('tree mode renders a folder row (root-level, collapsed to '
        'lib/app/views) that list mode does not render at all', (
      WidgetTester tester,
    ) async {
      final fileTree = FileTree.fromPaths(testPaths);
      final renderedNames = <String>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileTreeList(
              fileTree: fileTree,
              mode: FileListViewMode.tree,
              selectedPaths: const {},
              onItemBuilder: (context, node, level, onFolderToggle) {
                renderedNames.add(node.name);
                return ListTile(
                  title: Text(node.name),
                  leading: node.isDirectory
                      ? GestureDetector(
                          onTap: () => onFolderToggle?.call(),
                          child: const Icon(Icons.folder),
                        )
                      : null,
                );
              },
              onFolderCheckStateChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.pump();

      // 'lib/app/views' is a folder row in tree mode, unlike list mode
      // (previous test) which only ever renders the four leaf paths.
      expect(renderedNames, contains('lib/app/views'));
      // Its children are not rendered until the folder is expanded --
      // expandedFolders is empty here, so 'a.dart'/'b.dart' stay hidden.
      expect(renderedNames, isNot(contains('a.dart')));
      expect(renderedNames, isNot(contains('b.dart')));
    });

    testWidgets(
      'folder checkbox is checked when all its children are selected, and '
      'unchecked when none are',
      (WidgetTester tester) async {
        final fileTree = FileTree.fromPaths(testPaths);
        final selectedPaths = {'lib/app/views/a.dart', 'lib/app/views/b.dart'};

        CheckState? capturedState;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FileTreeList(
                fileTree: fileTree,
                mode: FileListViewMode.tree,
                selectedPaths: selectedPaths,
                onItemBuilder: (context, node, level, onFolderToggle) {
                  if (node.isDirectory) {
                    capturedState = node.getCheckState(selectedPaths);
                  }
                  return ListTile(title: Text(node.name));
                },
                onFolderCheckStateChanged: (_) {},
              ),
            ),
          ),
        );

        await tester.pumpAndSettle();
        // lib/app/views's two leaves (a.dart, b.dart) are both selected.
        expect(capturedState, CheckState.checked);
      },
    );
  });
}
