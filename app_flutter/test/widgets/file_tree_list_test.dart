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
              onItemBuilder: (context, node, level, onFolderToggle) {
                renderedItems.add(node.displayPath);
                return ListTile(title: Text(node.name));
              },
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

    // Two folders of the same name under different parents are two rows, and
    // expanding one must not expand the other. `_toggleFolder` keys on
    // `node.displayPath`, so this is really an assertion about that key being
    // root-anchored rather than the accumulated prefix from its own level.
    //
    // The fixture needs each parent to hold **more than one** child: a lone
    // `features` child would be collapsed into `lib/features` by
    // `_collapseIfSingleChild`, which anchors the prefix as a side effect and
    // hides the defect ([TEST-fixture-cannot-disagree]).
    testWidgets('expanding one folder does not expand a same-named folder '
        'under a different parent', (WidgetTester tester) async {
      final FileTree fileTree = FileTree.fromPaths(const <String>[
        'lib/main.dart',
        'lib/features/a.dart',
        'lib/features/b.dart',
        'test/main_test.dart',
        'test/features/c.dart',
        'test/features/d.dart',
      ]);

      final List<String> renderedNames = <String>[];
      final List<VoidCallback?> toggles = <VoidCallback?>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FileTreeList(
              fileTree: fileTree,
              mode: FileListViewMode.tree,
              expandedFolders: const <String>{'lib', 'test'},
              onItemBuilder: (context, node, level, onFolderToggle) {
                renderedNames.add(node.name);
                toggles.add(onFolderToggle);
                return ListTile(title: Text(node.displayPath));
              },
            ),
          ),
        ),
      );
      await tester.pump();

      // Both parents are open, so both `features` rows are on screen; the
      // first one in paint order is lib's.
      expect(
        renderedNames.where((String n) => n == 'features').length,
        2,
        reason: 'both same-named folder rows should be rendered',
      );
      final int libFeatures = renderedNames.indexOf('features');

      renderedNames.clear();
      toggles[libFeatures]!();
      await tester.pump();

      expect(renderedNames, containsAll(<String>['a.dart', 'b.dart']));
      expect(renderedNames, isNot(contains('c.dart')));
      expect(renderedNames, isNot(contains('d.dart')));
    });
  });
}
